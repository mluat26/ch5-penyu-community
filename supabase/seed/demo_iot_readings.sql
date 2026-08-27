-- Demo sensor data, for use before real loggers are deployed.
--
--   supabase db query --linked -f supabase/seed/demo_iot_readings.sql
--
-- Generates a week of readings for every nest that has none, so the dashboard,
-- section list, and nest detail chart all have something truthful-looking to
-- draw. Re-runnable: nests that already carry readings are skipped, so this
-- will never duplicate or overwrite real logger data once it arrives.
--
-- The shape is deliberately plausible rather than random. Sand temperature
-- lags air temperature and swings far less than it does above ground, so each
-- nest sits on its own baseline and moves a couple of degrees across the day,
-- peaking mid-afternoon.

do $$
declare
  nest_record record;
  reading_time timestamptz;
  day_offset integer;
  slot integer;
  baseline double precision;
  hour_of_day double precision;
  temperature double precision;
  voltage double precision;
  sensor uuid;
  inserted integer := 0;
  seeded_nests integer := 0;
begin
  for nest_record in
    select n.id, n.hatchery_id, h.owner_id,
           row_number() over (order by n.id) as ordinal
    from public.nest n
    join public.hatchery h on h.id = n.hatchery_id
    where not exists (select 1 from public.iotdata d where d.nest_id = n.id)
      -- Completed nests have already released their logger. Seeding an active
      -- assignment afterwards would put a finished nest back into service.
      and not exists (
        select 1 from public.hatching hatching where hatching.nest_id = n.id
      )
      -- Registering a logger runs as its owner, so hatcheries predating
      -- owner_id have nobody to attribute one to. They are left alone rather
      -- than attributed to an arbitrary account.
      and h.owner_id is not null
  loop
    -- `assign_device_owner` reads auth.uid(), so registering a device has to
    -- happen as the hatchery's owner rather than as the seeding superuser.
    perform set_config(
      'request.jwt.claims',
      json_build_object('sub', nest_record.owner_id)::text,
      true
    );

    -- `iotdata.sensor_id` is required, so each nest needs a logger to have
    -- reported its readings. One per nest, owned by whoever owns the hatchery.
    insert into public.device (id, name, installed_at, owner_id)
    values (
      gen_random_uuid(),
      'PN' || lpad(nest_record.ordinal::text, 3, '0'),
      now() - interval '7 days',
      nest_record.owner_id
    )
    returning id into sensor;

    -- The resolver ignores a payload nest ID and trusts this assignment. Start
    -- it before the oldest generated reading so the synthetic history is also
    -- temporally valid rather than merely foreign-key valid.
    insert into public.device_assignment (
      device_id,
      nest_id,
      assigned_at,
      assigned_by
    ) values (
      sensor,
      nest_record.id,
      date_trunc('day', now()) - interval '6 days',
      nest_record.owner_id
    );

    -- Spread nests across the incubation band so the UI shows its cold,
    -- healthy, and hot states rather than one flat colour. 29-31°C is the
    -- healthy window; either side of it skews the sex ratio.
    baseline := 28.4 + ((nest_record.ordinal - 1) % 4) * 1.35;

    for day_offset in reverse 6..0 loop
      -- 28 slots a day matches the bar count the detail chart draws.
      for slot in 0..27 loop
        hour_of_day := slot * 24.0 / 28.0;

        reading_time :=
          date_trunc('day', now())
          - make_interval(days => day_offset)
          + make_interval(secs => (hour_of_day * 3600)::int);

        -- Skip anything in the future on today's partial day.
        continue when reading_time > now();

        -- Peaks around 15:00, troughs before dawn.
        temperature := baseline
          + 1.9 * sin((hour_of_day - 9.0) / 24.0 * 2 * pi())
          + (random() - 0.5) * 0.35;

        -- A slow drain from full over the week, plus a little noise.
        voltage := 4.15
          - (6 - day_offset) * 0.055
          - ((nest_record.ordinal - 1) % 4) * 0.18
          + (random() - 0.5) * 0.02;

        insert into public.iotdata (
          id, sensor_id, temperature, timestamp, battery_voltage,
          sensor_status, depth_cm, signal_rssi_dbm
        )
        values (
          gen_random_uuid(),
          sensor,
          round(temperature::numeric, 2),
          reading_time,
          round(greatest(voltage, 3.02)::numeric, 3),
          'online',
          45,
          -60 - ((nest_record.ordinal * 7) % 25)
        );

        inserted := inserted + 1;
      end loop;
    end loop;

    seeded_nests := seeded_nests + 1;
  end loop;

  raise notice 'seeded % readings across % nests', inserted, seeded_nests;
end
$$;

-- A short inspection history per nest, so the detail screen's list is not
-- empty. Only for nests with none, for the same re-run safety.
do $$
declare
  nest_record record;
  visit integer;
  inserted integer := 0;
begin
  for nest_record in
    select n.id
    from public.nest n
    where not exists (select 1 from public.inspection i where i.nest_id = n.id)
  loop
    for visit in 1..3 loop
      insert into public.inspection (id, nest_id, inspected_on, outcome, next_inspection_date)
      values (
        gen_random_uuid(),
        nest_record.id,
        (current_date - (30 - visit * 10)),
        'not_hatched',
        current_date + 7
      );
      inserted := inserted + 1;
    end loop;
  end loop;

  raise notice 'seeded % inspections', inserted;
end
$$;
