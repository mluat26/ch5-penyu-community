-- A bucket ID that behaves like a real logger, for testing before hardware
-- exists.
--
-- Creating a nest with bucket ID `PN-DEMO` registers a logger for it, assigns
-- it, and backfills a week of readings — so the section list, dashboard, and
-- nest detail chart all have data the moment the nest is saved. Any other
-- bucket ID behaves exactly as before.
--
-- This is deliberately keyed to one reserved string rather than seeding every
-- nest: once real loggers report, a nest created with its true bucket ID must
-- stay empty until that hardware speaks for itself.

create or replace function public.seed_demo_logger_readings(
  p_nest_id uuid,
  p_owner_id uuid,
  p_device_name text default 'PN-DEMO'
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  sensor uuid;
  day_offset integer;
  slot integer;
  hour_of_day double precision;
  reading_time timestamptz;
  temperature double precision;
  voltage double precision;
  inserted integer := 0;
begin
  -- Reuse this owner's demo logger if they already have one, so repeated test
  -- nests do not each register another device.
  select id into sensor
  from public.device
  where name = p_device_name
    and owner_id is not distinct from p_owner_id
  limit 1;

  if sensor is null then
    insert into public.device (id, name, installed_at, owner_id)
    values (gen_random_uuid(), p_device_name, now() - interval '7 days', p_owner_id)
    returning id into sensor;
  end if;

  insert into public.device_assignment (id, device_id, nest_id, assigned_at, assigned_by)
  values (gen_random_uuid(), sensor, p_nest_id, now(), p_owner_id)
  on conflict do nothing;

  -- 28 slots a day matches the bar count the detail chart draws. Sand
  -- temperature lags air and swings little, peaking mid-afternoon.
  for day_offset in reverse 6..0 loop
    for slot in 0..27 loop
      hour_of_day := slot * 24.0 / 28.0;
      reading_time := date_trunc('day', now())
        - make_interval(days => day_offset)
        + make_interval(secs => (hour_of_day * 3600)::int);

      continue when reading_time > now();

      temperature := 29.6
        + 1.9 * sin((hour_of_day - 9.0) / 24.0 * 2 * pi())
        + (random() - 0.5) * 0.35;

      voltage := 4.15 - (6 - day_offset) * 0.055 + (random() - 0.5) * 0.02;

      insert into public.iotdata (
        id, nest_id, sensor_id, temperature, timestamp,
        battery_voltage, sensor_status, depth_cm, signal_rssi_dbm
      )
      values (
        gen_random_uuid(), p_nest_id, sensor,
        round(temperature::numeric, 2), reading_time,
        round(greatest(voltage, 3.02)::numeric, 3),
        'online', 45, -67
      );

      inserted := inserted + 1;
    end loop;
  end loop;

  return inserted;
end;
$$;

create or replace function public.attach_demo_logger()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_owner_id uuid;
begin
  if upper(btrim(coalesce(new.bucket_id, ''))) <> 'PN-DEMO' then
    return new;
  end if;

  select owner_id into v_owner_id
  from public.hatchery
  where id = new.hatchery_id;

  if v_owner_id is null then
    return new;
  end if;

  perform public.seed_demo_logger_readings(new.id, v_owner_id);
  return new;
end;
$$;

drop trigger if exists nest_attach_demo_logger on public.nest;

create trigger nest_attach_demo_logger
  after insert on public.nest
  for each row
  execute function public.attach_demo_logger();

revoke all on function public.seed_demo_logger_readings(uuid, uuid, text) from public;
grant execute on function public.seed_demo_logger_readings(uuid, uuid, text) to authenticated;
