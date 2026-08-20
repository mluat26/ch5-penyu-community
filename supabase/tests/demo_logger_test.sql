-- Behaviour check for 20260816050000_add_demo_logger_bucket_id.
--
--   docker exec -i supabase_db_ch5-penyu-community \
--     psql -U postgres -d postgres -v ON_ERROR_STOP=1 \
--     < supabase/tests/demo_logger_test.sql
--
-- The important half is the negative: a nest created with a real bucket ID
-- must stay empty, or the demo rig would fabricate readings for hardware that
-- has not reported yet.

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
  v_owner_id uuid := gen_random_uuid();
  hatchery_id uuid := gen_random_uuid();
  demo_nest uuid := gen_random_uuid();
  real_nest uuid := gen_random_uuid();
  lower_nest uuid := gen_random_uuid();
  demo_readings integer;
begin
  insert into auth.users (id, instance_id, aud, role, email, created_at, updated_at)
  values (v_owner_id, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'demo@test.local', now(), now());

  insert into public.hatchery
    (id, name, shape, number_of_row, number_of_collumn, length_m, width_m, layout_status, owner_id)
  values
    (hatchery_id, 'Hatch_01', 'rectangle', 5, 5, 5, 5, 'ready', v_owner_id);

  -- 1. The reserved bucket ID seeds a week of readings.
  insert into public.nest (id, hatchery_id, placement_row, placement_col, number_of_eggs, date_eggs_laid, bucket_id)
  values (demo_nest, hatchery_id, 0, 0, 100, current_date, 'PN-DEMO');

  select count(*) into demo_readings from public.iotdata where nest_id = demo_nest;
  perform pg_temp.check(demo_readings > 150, 'PN-DEMO seeds a week of readings');

  perform pg_temp.check(
    exists (select 1 from public.device_assignment where nest_id = demo_nest),
    'the demo logger is assigned to the nest'
  );

  perform pg_temp.check(
    (select count(distinct date_trunc('day', timestamp)) from public.iotdata where nest_id = demo_nest) = 7,
    'the readings span seven days'
  );

  perform pg_temp.check(
    (select max(temperature) from public.iotdata where nest_id = demo_nest) < 32.5
      and (select min(temperature) from public.iotdata where nest_id = demo_nest) > 27,
    'the readings sit in a plausible incubation band'
  );

  perform pg_temp.check(
    (select count(*) from public.iotdata where nest_id = demo_nest and battery_voltage is null) = 0,
    'every reading carries a battery voltage'
  );

  -- 2. Case and padding are forgiving, and a second demo nest reuses the
  --    same logger rather than registering another.
  insert into public.nest (id, hatchery_id, placement_row, placement_col, number_of_eggs, date_eggs_laid, bucket_id)
  values (lower_nest, hatchery_id, 0, 1, 100, current_date, '  pn-demo ');

  perform pg_temp.check(
    (select count(*) from public.iotdata where nest_id = lower_nest) > 150,
    'the bucket ID is matched case- and space-insensitively'
  );
  perform pg_temp.check(
    (select count(*) from public.device where owner_id = v_owner_id and name = 'PN-DEMO') = 1,
    'a second demo nest reuses the same logger'
  );

  -- 3. A real bucket ID is left completely alone.
  insert into public.nest (id, hatchery_id, placement_row, placement_col, number_of_eggs, date_eggs_laid, bucket_id)
  values (real_nest, hatchery_id, 0, 2, 100, current_date, 'PN124');

  perform pg_temp.check(
    (select count(*) from public.iotdata where nest_id = real_nest) = 0,
    'a real bucket ID gets no fabricated readings'
  );
  perform pg_temp.check(
    not exists (select 1 from public.device_assignment where nest_id = real_nest),
    'a real bucket ID gets no logger assigned'
  );

  raise notice 'ALL CHECKS PASSED';
end
$$;

rollback;
