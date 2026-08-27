-- Covers organization-member nest deletion and its device lifecycle.
--
-- Deleting the nest is permanent working-data deletion: assignments,
-- telemetry, inspections and hatch results cascade away. The physical device
-- is an organization asset, so it survives unassigned and can be installed in
-- another nest without changing the UUID stored in its firmware/NFC tag.

begin;

create or replace function pg_temp.become(user_id uuid)
returns void language plpgsql as $$
begin
  perform set_config('role', 'authenticated', true);
  perform set_config(
    'request.jwt.claims',
    json_build_object('sub', user_id, 'role', 'authenticated')::text,
    true
  );
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
  member uuid := gen_random_uuid();
  hatchery_id uuid := gen_random_uuid();
  active_nest uuid := gen_random_uuid();
  next_nest uuid := gen_random_uuid();
  hatched_nest uuid := gen_random_uuid();
  device_id uuid := gen_random_uuid();
  v_organization_id uuid;
  deleted_id uuid;
  landed_on uuid;
begin
  insert into auth.users (
    id, instance_id, aud, role, email, created_at, updated_at
  ) values
    (founder, '00000000-0000-0000-0000-000000000000',
      'authenticated', 'authenticated', 'delete-founder@test.local', now(), now()),
    (member, '00000000-0000-0000-0000-000000000000',
      'authenticated', 'authenticated', 'delete-member@test.local', now(), now());

  insert into public.hatchery (
    id, name, shape, number_of_row, number_of_collumn,
    length_m, width_m, layout_status, owner_id
  ) values (
    hatchery_id, 'Delete lifecycle', 'rectangle', 3, 3,
    3, 3, 'ready', founder
  );

  select hatchery.organization_id into v_organization_id
  from public.hatchery as hatchery
  where hatchery.id = hatchery_id;

  update public.profile
  set organization_id = v_organization_id,
      role = 'officer'
  where id = member;

  insert into public.nest (
    id, hatchery_id, placement_row, placement_col,
    number_of_eggs, date_eggs_laid
  ) values
    (active_nest, hatchery_id, 0, 0, 100, current_date),
    (next_nest, hatchery_id, 0, 1, 90, current_date),
    (hatched_nest, hatchery_id, 0, 2, 80, current_date - 56);

  insert into public.device (
    id, name, installed_at, owner_id, organization_id
  ) values (
    device_id, 'Lifecycle logger', now() - interval '1 day',
    founder, v_organization_id
  );

  insert into public.device_assignment (
    device_id, nest_id, assigned_at, assigned_by
  ) values (
    device_id, active_nest, now() - interval '1 day', founder
  );

  insert into public.iotdata (
    sensor_id, temperature, timestamp, sensor_status
  ) values (
    device_id, 29.5, now() - interval '1 hour', 'online'
  );

  insert into public.inspection (
    nest_id, inspected_on, outcome, next_inspection_date
  ) values (
    active_nest, current_date, 'not_hatched', current_date + 7
  );

  insert into public.hatching (
    nest_id, hatched_on, eggs_hatched, eggs_rotten, eggs_unhatched
  ) values (
    hatched_nest, current_date, 70, 5, 5
  );

  -- An ordinary organization member, not the hatchery owner or a manager.
  perform pg_temp.become(member);
  delete from public.nest
  where id = active_nest
  returning id into deleted_id;
  perform pg_temp.check(deleted_id = active_nest, 'an organization member deletes the nest');

  perform pg_temp.become_admin();
  perform pg_temp.check(
    not exists (select 1 from public.nest where id = active_nest),
    'the nest row is gone'
  );
  perform pg_temp.check(
    not exists (select 1 from public.device_assignment where nest_id = active_nest),
    'its current assignment is gone'
  );
  perform pg_temp.check(
    not exists (select 1 from public.iotdata where nest_id = active_nest),
    'its telemetry is gone'
  );
  perform pg_temp.check(
    not exists (select 1 from public.inspection where nest_id = active_nest),
    'its inspections are gone'
  );
  perform pg_temp.check(
    exists (select 1 from public.device where id = device_id),
    'the physical device survives'
  );
  perform pg_temp.check(
    (select nest_id is null from public.device_current_assignment where id = device_id),
    'the surviving device is unassigned'
  );

  -- The same organization member can install that surviving device again.
  perform pg_temp.become(member);
  perform public.save_device('Lifecycle logger', next_nest, device_id);
  perform pg_temp.become_admin();

  insert into public.iotdata (sensor_id, temperature, sensor_status)
  values (device_id, 30.1, 'online')
  returning nest_id into landed_on;
  perform pg_temp.check(
    landed_on = next_nest,
    'new readings follow the replacement assignment'
  );

  -- Hatch results are part of the permanent nest deletion too.
  perform pg_temp.become(member);
  delete from public.nest where id = hatched_nest;
  perform pg_temp.become_admin();
  perform pg_temp.check(
    not exists (select 1 from public.hatching where nest_id = hatched_nest),
    'the hatch result cascades with its deleted nest'
  );

  raise notice 'ALL CHECKS PASSED';
end
$$;

rollback;
