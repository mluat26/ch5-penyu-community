-- Behaviour check for 20260826010000_share_devices_across_the_organization.
--
-- Run against a local stack:
--   docker exec -i supabase_db_ch5-penyu-community \
--     psql -U postgres -d postgres -v ON_ERROR_STOP=1 \
--     < supabase/tests/organization_device_access_test.sql
--
-- A member registers the device, a teammate operates it, an outsider cannot
-- discover it, and the device remains with the organization when its original
-- registrant deletes their account. Rolled back, so no test rows remain.

begin;

create or replace function pg_temp.become(user_id uuid)
returns void language plpgsql as $$
begin
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims', json_build_object('sub', user_id)::text, true);
end;
$$;

create or replace function pg_temp.become_admin()
returns void language plpgsql as $$
begin
  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
end;
$$;

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
  founder uuid := gen_random_uuid();
  registrant uuid := gen_random_uuid();
  teammate uuid := gen_random_uuid();
  outsider uuid := gen_random_uuid();
  team_hatchery uuid := gen_random_uuid();
  outsider_hatchery uuid := gen_random_uuid();
  team_nest uuid := gen_random_uuid();
  outsider_nest uuid := gen_random_uuid();
  team_organization uuid;
  shared_device uuid;
  invite_code text;
  visible_count integer;
begin
  insert into auth.users (id, instance_id, aud, role, email, created_at, updated_at)
  values
    (founder,    '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'device-founder@test.local',    now(), now()),
    (registrant, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'device-registrant@test.local', now(), now()),
    (teammate,   '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'device-teammate@test.local',   now(), now()),
    (outsider,   '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'device-outsider@test.local',   now(), now());

  insert into public.hatchery
    (id, name, shape, number_of_row, number_of_collumn, length_m, width_m, layout_status, owner_id)
  values
    (team_hatchery, 'Device team', 'rectangle', 4, 4, 5, 4, 'ready', founder),
    (outsider_hatchery, 'Other team', 'rectangle', 4, 4, 5, 4, 'ready', outsider);

  select organization_id into team_organization
  from public.hatchery
  where id = team_hatchery;

  insert into public.nest
    (id, hatchery_id, placement_row, placement_col, number_of_eggs, date_eggs_laid)
  values
    (team_nest, team_hatchery, 0, 0, 100, current_date),
    (outsider_nest, outsider_hatchery, 0, 0, 80, current_date);

  perform pg_temp.become(founder);
  select code into invite_code from public.generate_organization_invite();
  perform pg_temp.become(registrant);
  perform public.redeem_organization_invite(invite_code);

  perform pg_temp.become(founder);
  select code into invite_code from public.generate_organization_invite();
  perform pg_temp.become(teammate);
  perform public.redeem_organization_invite(invite_code);

  -- 1. A member registers the logger for the organization.
  perform pg_temp.become(registrant);
  select id into shared_device
  from public.save_device('Shared logger', null, null)
  limit 1;

  perform pg_temp.become_admin();
  perform pg_temp.check(
    exists (
      select 1 from public.device
      where id = shared_device
        and owner_id = registrant
        and organization_id = team_organization
    ),
    'registration records its member and canonical organization'
  );

  -- 2. A teammate can discover, rename, assign, and inspect the same device.
  perform pg_temp.become(teammate);
  select count(*) into visible_count
  from public.device_current_assignment
  where id = shared_device;
  perform pg_temp.check(visible_count = 1, 'a teammate sees the shared device');

  perform public.save_device('Renamed by teammate', team_nest, shared_device);
  perform pg_temp.check(
    exists (
      select 1 from public.device_current_assignment
      where id = shared_device
        and name = 'Renamed by teammate'
        and nest_id = team_nest
    ),
    'a teammate can rename and assign the shared device'
  );
  perform pg_temp.check(
    exists (
      select 1 from public.device_assignment
      where device_id = shared_device
        and nest_id = team_nest
        and unassigned_at is null
    ),
    'a teammate can read the device assignment history'
  );

  -- 3. A different organization cannot even discover the device.
  perform pg_temp.become(outsider);
  select count(*) into visible_count
  from public.device_current_assignment
  where id = shared_device;
  perform pg_temp.check(visible_count = 0, 'an outsider cannot see the shared device');

  begin
    perform public.save_device('Stolen logger', outsider_nest, shared_device);
    raise exception 'FAILED: an outsider changed or assigned the shared device';
  exception when others then
    if sqlerrm like 'FAILED:%' then raise; end if;
    raise notice 'ok: an outsider cannot change or assign the shared device';
  end;

  -- 4. The database invariant also refuses a cross-organization assignment,
  -- even if a future privileged workflow bypasses save_device.
  perform pg_temp.become(teammate);
  perform public.save_device('Renamed by teammate', null, shared_device);
  perform pg_temp.become_admin();

  begin
    insert into public.device_assignment (device_id, nest_id, assigned_by)
    values (shared_device, outsider_nest, founder);
    raise exception 'FAILED: a cross-organization assignment was inserted';
  exception when others then
    if sqlerrm like 'FAILED:%' then raise; end if;
    raise notice 'ok: the assignment trigger refuses a different organization';
  end;

  -- 5. Leaving the organization closes access immediately.
  perform pg_temp.become(founder);
  perform public.remove_organization_member(teammate);
  perform pg_temp.become(teammate);
  select count(*) into visible_count
  from public.device_current_assignment
  where id = shared_device;
  perform pg_temp.check(visible_count = 0, 'a removed teammate loses device access');

  -- 6. Registration provenance is not ownership of the shared asset. The
  -- device stays with the organization when its registrant deletes the account.
  perform pg_temp.become(registrant);
  perform public.delete_my_account();
  perform pg_temp.become_admin();
  perform pg_temp.check(
    exists (
      select 1 from public.device
      where id = shared_device
        and owner_id is null
        and organization_id = team_organization
    ),
    'the organization keeps a device after its registrant deletes their account'
  );

  perform pg_temp.become(founder);
  select count(*) into visible_count
  from public.device_current_assignment
  where id = shared_device;
  perform pg_temp.check(visible_count = 1, 'the remaining organization owner still sees it');

  perform pg_temp.become_admin();
  raise notice 'ALL CHECKS PASSED';
end
$$;

rollback;
