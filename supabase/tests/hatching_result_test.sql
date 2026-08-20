-- Behaviour check for 20260814024131_add_hatching_result.
--
--   docker exec -i supabase_db_ch5-penyu-community \
--     psql -U postgres -d postgres -v ON_ERROR_STOP=1 \
--     < supabase/tests/hatching_result_test.sql
--
-- The Hatchling details flow inserts one row into public.hatching and nothing
-- else -- SupabaseHatchingRepository.create() never touches public.nest. Every
-- number the post-hatch nest detail screen shows is therefore written by the
-- apply_hatching_to_nest trigger, with no Swift code in between. If that
-- trigger is wrong the app reports wrong conservation figures and nothing on
-- the client side can reveal it.
--
-- The precedence rule is the half worth testing hardest. Two things write the
-- nest summary -- inspections and this final tally -- and refresh_nest_summary
-- exists to stop them fighting. A test that only checked "hatching writes the
-- summary" would pass just as happily if the inspection trigger could still
-- overwrite it afterwards, which is the actual failure mode.
--
-- The in-memory fake makes this worse, not better: InMemoryNestRepository sets
-- successEggsHatch by hand, so the Swift tests exercise a hand-written
-- imitation of the trigger rather than the trigger. Only SQL catches a drift
-- between the two.

begin;

create or replace function pg_temp.check(condition boolean, label text)
returns void language plpgsql as $$
begin
  if not condition then
    raise exception 'FAILED: %', label;
  end if;
  raise notice 'ok: %', label;
end;
$$;

do $$
declare
  v_owner_id     uuid := gen_random_uuid();
  v_hatchery     uuid := gen_random_uuid();
  v_nest         uuid := gen_random_uuid();
  v_hatching     uuid := gen_random_uuid();
  v_inspection   uuid := gen_random_uuid();
  v_next_visit   date := current_date + 14;
  v_collected    date := current_date - 56;
  v_refused      boolean;
  v_message      text;
begin
  insert into auth.users (id, instance_id, aud, role, email, created_at, updated_at)
  values (v_owner_id, '00000000-0000-0000-0000-000000000000',
          'authenticated', 'authenticated', 'hatching@test.local', now(), now());

  insert into public.hatchery
    (id, name, shape, number_of_row, number_of_collumn, length_m, width_m, layout_status, owner_id)
  values
    (v_hatchery, 'Hatch_Result', 'rectangle', 5, 5, 5, 5, 'ready', v_owner_id);

  -- A 100-egg clutch, so every count below reads as a percentage too.
  insert into public.nest
    (id, hatchery_id, placement_row, placement_col, number_of_eggs, date_eggs_laid, nest_number)
  values
    (v_nest, v_hatchery, 0, 0, 100, v_collected, '001');

  -- ---------------------------------------------------------------------
  -- 1. Before anything is recorded the nest reports nothing.
  -- ---------------------------------------------------------------------
  perform pg_temp.check(
    (select success_eggs_hatch is null and fail_eggs_hatch is null
            and eggs_unhatched is null
       from public.nest where id = v_nest),
    'a fresh nest has no hatching figures'
  );

  -- ---------------------------------------------------------------------
  -- 2. An inspection writes the running total, and keeps the nest on the
  --    work queue. This is the state a real nest is in when someone taps
  --    Hatched, so the precedence check below starts from it rather than
  --    from an untouched row.
  -- ---------------------------------------------------------------------
  insert into public.inspection
    (id, nest_id, inspected_on, outcome, eggs_hatched, eggs_rotten, next_inspection_date)
  values
    (v_inspection, v_nest, current_date - 3, 'partially_hatched', 10, 2, v_next_visit);

  perform pg_temp.check(
    (select success_eggs_hatch = 10 and fail_eggs_hatch = 2
       from public.nest where id = v_nest),
    'an inspection writes the running total to the nest'
  );
  perform pg_temp.check(
    (select next_inspection_date = v_next_visit from public.nest where id = v_nest),
    'a partially hatched nest stays on the work queue'
  );
  perform pg_temp.check(
    (select eggs_unhatched is null from public.nest where id = v_nest),
    'an inspection cannot report unhatched eggs -- only the final tally can'
  );

  -- ---------------------------------------------------------------------
  -- 3. The final tally overrides the inspection total outright.
  --
  --    Not "adds to": 90 hatched is the whole clutch's outcome, not 90 more
  --    on top of the 10 an earlier visit counted. Summing here would report
  --    100 hatched out of 100 and overstate the hatch rate.
  -- ---------------------------------------------------------------------
  insert into public.hatching
    (id, nest_id, hatched_on, eggs_hatched, eggs_rotten, eggs_unhatched)
  values
    (v_hatching, v_nest, current_date, 90, 5, 5);

  perform pg_temp.check(
    (select success_eggs_hatch = 90 from public.nest where id = v_nest),
    'the final tally replaces the inspection hatched count, it does not add to it'
  );
  perform pg_temp.check(
    (select fail_eggs_hatch = 5 from public.nest where id = v_nest),
    'the final tally replaces the inspection rotten count'
  );
  perform pg_temp.check(
    (select eggs_unhatched = 5 from public.nest where id = v_nest),
    'unhatched eggs reach the nest only once a hatching row exists'
  );

  -- ---------------------------------------------------------------------
  -- 4. Hatched is terminal: nothing further is scheduled.
  --
  --    This is what takes the nest off the home screen work queue, so a
  --    regression here means rangers keep being sent back to a finished nest.
  -- ---------------------------------------------------------------------
  perform pg_temp.check(
    (select next_inspection_date is null from public.nest where id = v_nest),
    'recording a hatch clears the next inspection date'
  );

  -- ---------------------------------------------------------------------
  -- 5. A later inspection must not undo the final tally.
  --
  --    The failure mode the shared refresh_nest_summary() exists to prevent:
  --    before it, apply_inspection_to_nest wrote the nest summary directly and
  --    a stray visit row would silently overwrite a finished nest.
  -- ---------------------------------------------------------------------
  insert into public.inspection
    (nest_id, inspected_on, outcome, eggs_hatched, eggs_rotten, next_inspection_date)
  values
    (v_nest, current_date, 'not_hatched', null, null, current_date + 7);

  perform pg_temp.check(
    (select success_eggs_hatch = 90 and fail_eggs_hatch = 5 and eggs_unhatched = 5
       from public.nest where id = v_nest),
    'an inspection recorded after the hatch cannot overwrite the final tally'
  );
  perform pg_temp.check(
    (select next_inspection_date is null from public.nest where id = v_nest),
    'an inspection recorded after the hatch cannot put the nest back on the queue'
  );

  -- ---------------------------------------------------------------------
  -- 6. A correction re-applies. The Review screen offers "Edit details", so
  --    this is a path the UI actually takes, not a hypothetical.
  -- ---------------------------------------------------------------------
  update public.hatching
     set eggs_hatched = 80, eggs_rotten = 10, eggs_unhatched = 10
   where id = v_hatching;

  perform pg_temp.check(
    (select success_eggs_hatch = 80 and fail_eggs_hatch = 10 and eggs_unhatched = 10
       from public.nest where id = v_nest),
    'correcting the tally rewrites the nest summary'
  );

  -- ---------------------------------------------------------------------
  -- 7. Counts may not exceed the clutch. A cross-table rule, so it lives in
  --    a trigger rather than a CHECK -- this is what catches a transposed
  --    digit before it becomes a conservation statistic.
  -- ---------------------------------------------------------------------
  v_refused := false;
  begin
    update public.hatching
       set eggs_hatched = 90, eggs_rotten = 30, eggs_unhatched = 5
     where id = v_hatching;
  exception when others then
    v_refused  := true;
    v_message  := sqlerrm;
  end;

  perform pg_temp.check(v_refused, '125 eggs accounted for in a 100-egg nest is refused');
  perform pg_temp.check(
    v_message like '%holds only%',
    'the refusal is the clutch-size trigger, not some unrelated error'
  );
  perform pg_temp.check(
    (select success_eggs_hatch = 80 from public.nest where id = v_nest),
    'a refused correction leaves the stored tally untouched'
  );

  -- ---------------------------------------------------------------------
  -- 8. Accounting for exactly the clutch is allowed. The boundary matters:
  --    the auto-calculated hatched count on the Hatchling details screen
  --    makes the three numbers sum to exactly this by default, so an
  --    off-by-one here would refuse the app's own happy path.
  -- ---------------------------------------------------------------------
  update public.hatching
     set eggs_hatched = 98, eggs_rotten = 1, eggs_unhatched = 1
   where id = v_hatching;

  perform pg_temp.check(
    (select success_eggs_hatch = 98 from public.nest where id = v_nest),
    'accounting for exactly the clutch is allowed'
  );

  -- ---------------------------------------------------------------------
  -- 9. Under-accounting is allowed on purpose. Eggs go missing on a beach,
  --    and the total is what was actually seen, not what subtraction implies.
  -- ---------------------------------------------------------------------
  update public.hatching
     set eggs_hatched = 50, eggs_rotten = 1, eggs_unhatched = 1
   where id = v_hatching;

  perform pg_temp.check(
    (select success_eggs_hatch = 50 from public.nest where id = v_nest),
    'accounting for fewer eggs than the clutch is allowed'
  );

  -- ---------------------------------------------------------------------
  -- 10. One tally per nest. SupabaseHatchingRepository maps this unique
  --     violation onto DomainValidationError.nestAlreadyHatched, so the
  --     constraint is what makes that error reachable.
  -- ---------------------------------------------------------------------
  v_refused := false;
  begin
    insert into public.hatching
      (nest_id, hatched_on, eggs_hatched, eggs_rotten, eggs_unhatched)
    values
      (v_nest, current_date, 1, 1, 1);
  exception when unique_violation then
    v_refused := true;
  end;

  perform pg_temp.check(v_refused, 'a nest cannot be hatched twice');

  -- ---------------------------------------------------------------------
  -- 11. Deleting the tally falls back to the inspection record rather than
  --     leaving the nest reporting figures with nothing behind them.
  -- ---------------------------------------------------------------------
  delete from public.hatching where id = v_hatching;

  perform pg_temp.check(
    (select success_eggs_hatch = 10 and fail_eggs_hatch = 2
       from public.nest where id = v_nest),
    'deleting the tally falls back to the inspection totals'
  );
  perform pg_temp.check(
    (select eggs_unhatched is null from public.nest where id = v_nest),
    'deleting the tally clears the unhatched count, which only it could set'
  );
  perform pg_temp.check(
    (select next_inspection_date = current_date + 7 from public.nest where id = v_nest),
    'deleting the tally puts the nest back on the queue at the latest visit date'
  );

  raise notice 'ALL CHECKS PASSED';
end
$$;

rollback;
