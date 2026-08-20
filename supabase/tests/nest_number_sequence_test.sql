-- Behaviour check for 20260818010000_number_nests_per_hatchery.
--
--   docker exec -i supabase_db_ch5-penyu-community \
--     psql -U postgres -d postgres -v ON_ERROR_STOP=1 \
--     < supabase/tests/nest_number_sequence_test.sql
--
-- Bucket IDs are the deliberate exception: they may repeat freely, because a
-- bucket is physical and gets reused, so check 8 must NOT behave like the
-- nest-number checks around it.
--
-- The important half is that a clash is *corrected*, not rejected: the app
-- numbers nests client-side, so two rangers offline in the same hatchery will
-- propose the same number, and neither of them should lose a filled-in form.
-- A test that only checked "no duplicates exist" would pass just as happily
-- if the trigger raised an exception instead.

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
  v_owner_id  uuid := gen_random_uuid();
  hatchery_a  uuid := gen_random_uuid();
  hatchery_b  uuid := gen_random_uuid();
  first_nest  uuid := gen_random_uuid();
  second_nest uuid := gen_random_uuid();
  third_nest  uuid := gen_random_uuid();
  other_nest  uuid := gen_random_uuid();
  padded_nest uuid := gen_random_uuid();
  tagged_nest uuid := gen_random_uuid();
  shared_bucket_nest uuid := gen_random_uuid();
  blank_nest  uuid := gen_random_uuid();
begin
  insert into auth.users (id, instance_id, aud, role, email, created_at, updated_at)
  values (v_owner_id, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'numbering@test.local', now(), now());

  insert into public.hatchery
    (id, name, shape, number_of_row, number_of_collumn, length_m, width_m, layout_status, owner_id)
  values
    (hatchery_a, 'Hatch_A', 'rectangle', 5, 5, 5, 5, 'ready', v_owner_id),
    (hatchery_b, 'Hatch_B', 'rectangle', 5, 5, 5, 5, 'ready', v_owner_id);

  -- 1. The first nest keeps the number the app proposed.
  insert into public.nest (id, hatchery_id, placement_row, placement_col, number_of_eggs, date_eggs_laid, nest_number, bucket_id)
  values (first_nest, hatchery_a, 0, 0, 100, current_date, '007', '007');

  perform pg_temp.check(
    (select nest_number from public.nest where id = first_nest) = '007',
    'the first nest keeps the number it asked for'
  );

  -- 2. A second nest proposing the same number is moved on; the earlier one
  --    is left exactly as it was.
  insert into public.nest (id, hatchery_id, placement_row, placement_col, number_of_eggs, date_eggs_laid, nest_number, bucket_id)
  values (second_nest, hatchery_a, 0, 1, 100, current_date, '007', '007');

  perform pg_temp.check(
    (select nest_number from public.nest where id = first_nest) = '007',
    'the earlier nest still owns 007'
  );
  perform pg_temp.check(
    (select nest_number from public.nest where id = second_nest) = '008',
    'the later nest is moved on to the next free number'
  );
  perform pg_temp.check(
    (select bucket_id from public.nest where id = second_nest) = '007',
    'a supplied bucket ID survives the renumbering untouched'
  );

  -- 3. Numbering is per hatchery: B is unaffected by anything in A.
  insert into public.nest (id, hatchery_id, placement_row, placement_col, number_of_eggs, date_eggs_laid, nest_number, bucket_id)
  values (other_nest, hatchery_b, 0, 0, 100, current_date, '007', '007');

  perform pg_temp.check(
    (select nest_number from public.nest where id = other_nest) = '007',
    'another hatchery may hold its own 007'
  );

  -- 4. A deleted nest does not hand its number back out.
  delete from public.nest where id = second_nest;

  insert into public.nest (id, hatchery_id, placement_row, placement_col, number_of_eggs, date_eggs_laid, nest_number, bucket_id)
  values (third_nest, hatchery_a, 0, 2, 100, current_date, '008', '008');

  perform pg_temp.check(
    (select nest_number from public.nest where id = third_nest) = '008',
    'a freed number is reusable while nothing else holds it'
  );

  -- 5. Numbers are stored in one canonical shape, so 0007 cannot sit beside
  --    007 looking distinct.
  insert into public.nest (id, hatchery_id, placement_row, placement_col, number_of_eggs, date_eggs_laid, nest_number, bucket_id)
  values (padded_nest, hatchery_a, 0, 3, 100, current_date, '0007', '0007');

  perform pg_temp.check(
    (select nest_number from public.nest where id = padded_nest) = '009',
    '0007 is recognised as 007 and moved on rather than duplicated'
  );

  -- 6. No number at all still gets one.
  insert into public.nest (id, hatchery_id, placement_row, placement_col, number_of_eggs, date_eggs_laid)
  values (blank_nest, hatchery_a, 0, 4, 100, current_date);

  perform pg_temp.check(
    (select nest_number from public.nest where id = blank_nest) = '010',
    'a nest saved without a number is given the next one'
  );

  -- 7. A bucket ID the client set independently is its own value, not a
  --    mirror, and survives a correction untouched. This is the NFC case.
  insert into public.nest (id, hatchery_id, placement_row, placement_col, number_of_eggs, date_eggs_laid, nest_number, bucket_id)
  values (tagged_nest, hatchery_a, 1, 0, 100, current_date, '007', '04:A2:24:B1');

  perform pg_temp.check(
    (select nest_number from public.nest where id = tagged_nest) = '011',
    'a tagged nest is renumbered like any other'
  );
  perform pg_temp.check(
    (select bucket_id from public.nest where id = tagged_nest) = '04:A2:24:B1',
    'an independently set bucket ID is left alone'
  );

  -- 8. Two nests may share a bucket: it is a physical container, emptied and
  --    reused, so a repeat is a fact rather than a clash. This is the case
  --    that must NOT behave like the nest number above.
  insert into public.nest (id, hatchery_id, placement_row, placement_col, number_of_eggs, date_eggs_laid, nest_number, bucket_id)
  values (shared_bucket_nest, hatchery_a, 1, 1, 100, current_date, '020', '04:A2:24:B1');

  perform pg_temp.check(
    (select count(*) from public.nest
      where hatchery_id = hatchery_a and bucket_id = '04:A2:24:B1') = 2,
    'one bucket may hold two different nests'
  );
  perform pg_temp.check(
    (select nest_number from public.nest where id = shared_bucket_nest) = '020',
    'sharing a bucket does not renumber the nest'
  );

  -- 9. Editing a nest without touching its number is not a clash with itself.
  update public.nest set number_of_eggs = 120 where id = first_nest;

  perform pg_temp.check(
    (select nest_number from public.nest where id = first_nest) = '007',
    'an unrelated edit leaves the number where it was'
  );

  raise notice 'ALL CHECKS PASSED';
end
$$;

rollback;
