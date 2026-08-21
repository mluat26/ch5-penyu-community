-- Behaviour check for 20260820030000_share_nest_records_across_the_organization.
--
--   docker exec -i supabase_db_ch5-penyu-community \
--     psql -U postgres -d postgres -v ON_ERROR_STOP=1 \
--     < supabase/tests/organization_nest_access_test.sql
--
-- Four people, so each branch is proved on its own rather than by accident:
--
--   A  hatchery owner, left as 'agent' -- see below
--   B  same organization, 'officer' -- the Made Sari case from the design
--   M  same organization, 'manager', owns nothing
--   C  'manager' of a different organization entirely
--
-- A is an agent on purpose, and it is not a contrivance. attach_hatchery_
-- organization only promotes the owner to manager when it has to create the
-- organization; someone who joined an existing one by invite code keeps the
-- 'agent' role redeem_organization_invite gave them and still owns whatever
-- hatchery they create next. If A stayed a manager, "the owner may delete"
-- would pass even with the owner branch of may_delete_nest_record deleted.
--
-- The check that matters most is not any single permission. It is that a
-- teammate recording a hatch actually moves the numbers on public.nest. The
-- tally goes into a table they may now write; the summary lands on one they
-- still may not, via refresh_nest_summary inside an AFTER trigger. Before that
-- function was made security definer this failed silently -- no error, just
-- four figures that never changed on the screen the whole team reads.

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

-- Stands in for what PostgREST does per request.
create or replace function pg_temp.become(p_user uuid)
returns void language plpgsql as $$
begin
  perform set_config(
    'request.jwt.claims',
    json_build_object('sub', p_user, 'role', 'authenticated')::text,
    true
  );
  perform set_config('role', 'authenticated', true);
end;
$$;

do $$
declare
  v_owner     uuid := gen_random_uuid();  -- A
  v_member    uuid := gen_random_uuid();  -- B
  v_manager   uuid := gen_random_uuid();  -- M
  v_outsider  uuid := gen_random_uuid();  -- C
  v_org       uuid;
  v_other_org uuid := gen_random_uuid();
  v_hatchery  uuid := gen_random_uuid();
  v_nest      uuid := gen_random_uuid();
  v_hatching  uuid := gen_random_uuid();
  v_visit_one uuid := gen_random_uuid();
  v_visit_two uuid := gen_random_uuid();
  v_device    uuid := gen_random_uuid();
  v_avg       double precision;
  v_refused   boolean;
begin
  -- -------------------------------------------------------------------
  -- Setup, as postgres.
  -- -------------------------------------------------------------------
  insert into auth.users (id, instance_id, aud, role, email, created_at, updated_at)
  values
    (v_owner,    '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'a@test.local', now(), now()),
    (v_member,   '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'b@test.local', now(), now()),
    (v_manager,  '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'm@test.local', now(), now()),
    (v_outsider, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'c@test.local', now(), now());

  -- attach_hatchery_organization creates the organization and makes its
  -- creator a manager, so the org id is read back rather than invented here.
  insert into public.hatchery
    (id, name, shape, number_of_row, number_of_collumn, length_m, width_m, layout_status, owner_id)
  values
    (v_hatchery, 'Shared_Hatch', 'rectangle', 5, 5, 5, 5, 'ready', v_owner);

  select organization_id into v_org from public.hatchery where id = v_hatchery;
  perform pg_temp.check(v_org is not null, 'the hatchery was given an organization');

  update public.profile set role = 'agent' where id = v_owner;

  insert into public.profile (id, organization_id, role)
  values (v_member, v_org, 'officer'), (v_manager, v_org, 'manager')
  on conflict (id) do update
    set organization_id = excluded.organization_id, role = excluded.role;

  insert into public.organization (id, name, owner_id, code, date_created)
  values (v_other_org, 'Other org', v_outsider, 'ORG-TEST9', current_date);

  insert into public.profile (id, organization_id, role)
  values (v_outsider, v_other_org, 'manager')
  on conflict (id) do update
    set organization_id = excluded.organization_id, role = excluded.role;

  insert into public.nest
    (id, hatchery_id, placement_row, placement_col, number_of_eggs, date_eggs_laid, nest_number)
  values
    (v_nest, v_hatchery, 0, 0, 100, current_date - 56, '001');

  -- Readings arrive through the service-role ingest path, never from a user,
  -- and must name the device that produced them (iotdata_sensor_id_required).
  insert into public.device (id, name, owner_id)
  values (v_device, 'Logger_Shared', v_owner);

  insert into public.iotdata (nest_id, sensor_id, "timestamp", temperature)
  values
    (v_nest, v_device, now() - interval '2 hours', 28),
    (v_nest, v_device, now() - interval '1 hour',  32);

  -- -------------------------------------------------------------------
  -- B: an officer in the organization, owning nothing.
  -- -------------------------------------------------------------------
  perform pg_temp.become(v_member);

  perform pg_temp.check(
    (select count(*) from public.iotdata where nest_id = v_nest) = 2,
    'a teammate can read the nest''s readings'
  );

  select avg_c into v_avg
    from public.nest_temperature_stats(v_nest, now() - interval '1 day', now() + interval '1 day');
  perform pg_temp.check(
    v_avg = 30,
    'a teammate gets real numbers out of nest_temperature_stats'
  );

  insert into public.inspection
    (id, nest_id, inspected_on, outcome, next_inspection_date)
  values
    (v_visit_one, v_nest, current_date - 5, 'not_hatched', current_date + 7),
    (v_visit_two, v_nest, current_date - 4, 'not_hatched', current_date + 9);

  perform pg_temp.check(
    (select count(*) from public.inspection where nest_id = v_nest) = 2,
    'a teammate can record an inspection'
  );

  -- The insert this whole migration exists to allow.
  insert into public.hatching
    (id, nest_id, hatched_on, eggs_hatched, eggs_rotten, eggs_unhatched)
  values
    (v_hatching, v_nest, current_date, 90, 5, 5);

  perform pg_temp.check(
    (select recorded_by from public.hatching where id = v_hatching) = v_member,
    'a teammate can record the hatch, and it is attributed to them'
  );

  -- The silent-failure check.
  perform pg_temp.check(
    (select success_eggs_hatch = 90 and fail_eggs_hatch = 5 and eggs_unhatched = 5
       from public.nest where id = v_nest),
    'the summary reaches public.nest even though the recorder cannot update nest'
  );
  perform pg_temp.check(
    (select next_inspection_date is null from public.nest where id = v_nest),
    'and the nest still comes off the work queue'
  );

  update public.hatching
     set eggs_hatched = 88, eggs_rotten = 6, eggs_unhatched = 6
   where id = v_hatching;

  perform pg_temp.check(
    (select success_eggs_hatch = 88 from public.nest where id = v_nest),
    'a teammate can correct the tally, and the summary follows the correction'
  );

  -- Deleting is not theirs. RLS filters the row out instead of raising, so the
  -- check is that it survived, not that an error came back.
  delete from public.inspection where id = v_visit_one;
  perform pg_temp.check(
    exists (select 1 from public.inspection where id = v_visit_one),
    'an officer cannot delete an inspection'
  );

  delete from public.hatching where id = v_hatching;
  perform pg_temp.check(
    exists (select 1 from public.hatching where id = v_hatching),
    'an officer cannot delete the hatch record'
  );

  -- -------------------------------------------------------------------
  -- M: manager of the organization, owner of nothing.
  -- -------------------------------------------------------------------
  perform pg_temp.become(v_manager);

  delete from public.inspection where id = v_visit_one;
  perform pg_temp.check(
    not exists (select 1 from public.inspection where id = v_visit_one),
    'a manager can delete on a hatchery they do not own'
  );

  -- -------------------------------------------------------------------
  -- A: hatchery owner, and only an agent.
  -- -------------------------------------------------------------------
  perform pg_temp.become(v_owner);

  perform pg_temp.check(
    (select role from public.profile where id = v_owner) = 'agent',
    'the owner really is only an agent, so the next check tests the owner branch'
  );

  delete from public.inspection where id = v_visit_two;
  perform pg_temp.check(
    not exists (select 1 from public.inspection where id = v_visit_two),
    'the hatchery owner can delete without holding any rank'
  );

  -- -------------------------------------------------------------------
  -- C: a manager, but of somewhere else. Rank does not travel.
  -- -------------------------------------------------------------------
  perform pg_temp.become(v_outsider);

  perform pg_temp.check(
    not exists (select 1 from public.hatching where id = v_hatching),
    'an outsider cannot read the hatch record'
  );
  perform pg_temp.check(
    (select count(*) from public.iotdata where nest_id = v_nest) = 0,
    'an outsider cannot read the readings'
  );

  select avg_c into v_avg
    from public.nest_temperature_stats(v_nest, now() - interval '1 day', now() + interval '1 day');
  perform pg_temp.check(
    v_avg is null,
    'an outsider gets an empty window out of the stats function'
  );

  -- Refused, but not by RLS. inspection_within_clutch is a BEFORE trigger, and
  -- BEFORE triggers run ahead of the policy's WITH CHECK -- so it looks up the
  -- nest first, cannot see it under the outsider's own policy, and raises
  -- 'nest ... does not exist'. The row is still rejected either way; the point
  -- of recording it here is that the message a client sees is the trigger's,
  -- not a permission error, which is confusing to debug from the app side.
  v_refused := false;
  begin
    insert into public.inspection (nest_id, inspected_on, outcome, next_inspection_date)
    values (v_nest, current_date, 'not_hatched', current_date + 7);
  exception when others then
    v_refused := true;
  end;
  perform pg_temp.check(v_refused, 'an outsider cannot record an inspection');
  perform pg_temp.check(
    not exists (select 1 from public.inspection where nest_id = v_nest),
    'and nothing of theirs was written'
  );

  delete from public.hatching where id = v_hatching;

  -- Verified from outside the outsider's session on purpose. They cannot SELECT
  -- this row either, so asking them whether it survived returns false whether
  -- the delete worked or not -- the check would pass for the wrong reason and
  -- keep passing if the delete policy were removed entirely.
  perform set_config('role', 'postgres', true);

  perform pg_temp.check(
    exists (select 1 from public.hatching where id = v_hatching),
    'a manager of another organization cannot delete this hatch record'
  );

  raise notice 'ALL CHECKS PASSED';
end
$$;

rollback;
