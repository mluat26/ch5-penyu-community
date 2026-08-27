-- Keep the reserved PN-DEMO path compatible with assignment-routed ingestion.
-- One physical logger cannot be active in two nests, so every demo nest gets
-- its own clearly synthetic device. Its assignment begins before the oldest
-- backfilled reading, preserving a truthful assignment timeline.

create or replace function public.seed_demo_logger_readings(
  p_nest_id uuid,
  p_owner_id uuid,
  p_device_name text default 'PN-DEMO'
)
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  sensor uuid;
  hatchery_owner uuid;
  unique_device_name text;
  first_reading_time timestamptz;
  day_offset integer;
  slot integer;
  hour_of_day double precision;
  reading_time timestamptz;
  temperature double precision;
  voltage double precision;
  inserted integer := 0;
begin
  select hatchery.owner_id into hatchery_owner
  from public.nest
  join public.hatchery on hatchery.id = nest.hatchery_id
  where nest.id = p_nest_id;

  if hatchery_owner is null then
    raise exception 'Cannot seed a logger for missing nest %', p_nest_id;
  end if;

  if hatchery_owner is distinct from p_owner_id then
    raise exception 'Demo logger owner does not match nest % hatchery owner', p_nest_id;
  end if;

  if session_user <> 'postgres' and not public.may_access_nest(p_nest_id) then
    raise exception 'The nest is not available to this organization';
  end if;

  if exists (select 1 from public.hatching where nest_id = p_nest_id) then
    raise exception 'Cannot attach a demo logger to a hatched nest';
  end if;

  unique_device_name := btrim(p_device_name) || '-' ||
    upper(left(replace(p_nest_id::text, '-', ''), 8));
  first_reading_time := date_trunc('day', now()) - interval '6 days';

  select id into sensor
  from public.device
  where name = unique_device_name
    and owner_id is not distinct from p_owner_id
  limit 1;

  if sensor is null then
    insert into public.device (name, installed_at, owner_id)
    values (unique_device_name, first_reading_time, p_owner_id)
    returning id into sensor;
  end if;

  insert into public.device_assignment (
    device_id,
    nest_id,
    assigned_at,
    assigned_by
  ) values (
    sensor,
    p_nest_id,
    first_reading_time,
    p_owner_id
  ) on conflict do nothing;

  if not exists (
    select 1
    from public.device_assignment
    where device_id = sensor
      and nest_id = p_nest_id
      and unassigned_at is null
  ) then
    raise exception 'Demo logger % could not be assigned to nest %', sensor, p_nest_id;
  end if;

  -- Re-running the helper must not duplicate a week's telemetry.
  if exists (
    select 1 from public.iotdata
    where sensor_id = sensor and nest_id = p_nest_id
  ) then
    return 0;
  end if;

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

      voltage := 4.15 - (6 - day_offset) * 0.055
        + (random() - 0.5) * 0.02;

      -- nest_id is intentionally omitted. resolve_reading_nest() derives it
      -- from the active assignment, exactly like live device ingestion.
      insert into public.iotdata (
        sensor_id,
        temperature,
        timestamp,
        battery_voltage,
        sensor_status,
        depth_cm,
        signal_rssi_dbm
      ) values (
        sensor,
        round(temperature::numeric, 2),
        reading_time,
        round(greatest(voltage, 3.02)::numeric, 3),
        'online',
        45,
        -67
      );

      inserted := inserted + 1;
    end loop;
  end loop;

  return inserted;
end;
$$;

revoke all on function public.seed_demo_logger_readings(uuid, uuid, text)
  from public, anon, authenticated;
