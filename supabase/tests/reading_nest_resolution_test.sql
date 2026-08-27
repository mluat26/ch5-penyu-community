-- Covers 20260821040000: the assignment decides a reading's nest, and a
-- hatching record releases the logger.
--
-- (20260820010000 is `record_who_logged_the_hatch`, which this does not test.)

begin;

do $$
declare
  v_owner uuid := gen_random_uuid();
  v_hatchery uuid;
  v_nest_a uuid;
  v_nest_b uuid;
  v_device uuid;
  v_landed_on uuid;
  v_count integer;
  v_failed boolean;
begin
  insert into auth.users (id, instance_id, aud, role, email)
  values (v_owner, '00000000-0000-0000-0000-000000000000', 'authenticated',
          'authenticated', 'reading-resolution@example.test');

  insert into public.hatchery (
    name, shape, number_of_row, number_of_collumn,
    length_m, width_m, layout_status, owner_id
  ) values (
    'Resolution test', 'rectangle', 1, 2,
    1, 2, 'ready', v_owner
  )
  returning id into v_hatchery;

  insert into public.nest (
    hatchery_id, placement_row, placement_col,
    number_of_eggs, date_eggs_laid
  ) values (
    v_hatchery, 0, 0, 100, current_date
  ) returning id into v_nest_a;

  insert into public.nest (
    hatchery_id, placement_row, placement_col,
    number_of_eggs, date_eggs_laid
  ) values (
    v_hatchery, 0, 1, 80, current_date
  ) returning id into v_nest_b;

  insert into public.device (name, owner_id)
  values ('Resolution logger', v_owner) returning id into v_device;

  -- 1. With no assignment, a reading is refused rather than guessed at.
  v_failed := false;
  begin
    insert into public.iotdata (nest_id, sensor_id, temperature)
    values (v_nest_a, v_device, 29.5);
  exception when others then
    v_failed := true;
  end;
  assert v_failed, 'an unassigned device must not be able to post readings';

  -- 2. Assigned to nest A, a reading lands on nest A.
  insert into public.device_assignment (device_id, nest_id, assigned_by)
  values (v_device, v_nest_a, v_owner);

  insert into public.iotdata (nest_id, sensor_id, temperature)
  values (v_nest_a, v_device, 29.5)
  returning nest_id into v_landed_on;
  assert v_landed_on = v_nest_a, 'reading should land on the assigned nest';

  -- 3. The payload's nest_id is ignored: the assignment wins. This is the
  --    point of the change -- stale firmware cannot write onto another nest.
  insert into public.iotdata (nest_id, sensor_id, temperature)
  values (v_nest_b, v_device, 30.1)
  returning nest_id into v_landed_on;
  assert v_landed_on = v_nest_a,
    format('assignment should override the payload, landed on %s', v_landed_on);

  -- 4. Recording a hatching releases the logger.
  insert into public.hatching (
    nest_id, hatched_on, eggs_hatched, eggs_rotten, eggs_unhatched
  ) values (
    v_nest_a, current_date, 100, 0, 0
  );

  select count(*) into v_count
  from public.device_assignment
  where device_id = v_device and unassigned_at is null;
  assert v_count = 0, 'hatching should close the active assignment';

  -- 5. Once released, readings are refused again until it is reassigned.
  v_failed := false;
  begin
    insert into public.iotdata (nest_id, sensor_id, temperature)
    values (v_nest_a, v_device, 28.9);
  exception when others then
    v_failed := true;
  end;
  assert v_failed, 'a released logger must not keep writing to its old nest';

  -- 6. Reassigned to nest B, it writes again -- no firmware change involved.
  insert into public.device_assignment (device_id, nest_id, assigned_by)
  values (v_device, v_nest_b, v_owner);

  insert into public.iotdata (nest_id, sensor_id, temperature)
  values (v_nest_a, v_device, 27.4)
  returning nest_id into v_landed_on;
  assert v_landed_on = v_nest_b, 'reassignment should redirect later readings';

  raise notice 'reading_nest_resolution_test: all checks passed';
end;
$$;

rollback;
