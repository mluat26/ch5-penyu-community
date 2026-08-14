-- The columns a reading needs to be usable.
--
-- public.iotdata held only id, nest_id, sensor_id, temperature and alert, while
-- the domain model needs eleven fields. IoTDataDTO therefore had no toEntity()
-- mapper at all, so no Supabase repository could exist and AppContainer still
-- runs an in-memory fake in production -- which is why every nest shows "--"
-- for temperature no matter what a sensor writes.
--
-- The blocking one is `timestamp`. Without it there is no ordering, so "the
-- latest reading for this nest" is unanswerable and any average would mix old
-- and new values indiscriminately.

alter table public.iotdata
  add column if not exists "timestamp"      timestamptz not null default now(),
  add column if not exists position         text,
  add column if not exists depth_cm         double precision,
  add column if not exists sensor_status    text,
  add column if not exists battery_voltage  double precision,
  add column if not exists signal_rssi_dbm  integer;

-- Matches the SensorStatus cases the app maps into. Left nullable: a reading
-- from firmware that does not report status is still a valid temperature.
alter table public.iotdata add constraint iotdata_sensor_status_known
  check (sensor_status is null
      or sensor_status in ('online', 'offline', 'faulty'));

-- Matches AlertLevel. Same reasoning.
alter table public.iotdata add constraint iotdata_alert_known
  check (alert is null
      or alert in ('none', 'low', 'high', 'critical'));

-- Temperature is the reason this table exists; a reading without one is noise.
-- Not NOT NULL, because rows predating this migration may lack it.
alter table public.iotdata add constraint iotdata_temperature_sane
  check (temperature is null
      or (temperature > -50 and temperature < 100));

-- Every query is "the readings for these nests, newest first". Without this
-- index that is a full scan, and this table grows unbounded: one row per
-- sensor per interval, forever.
create index if not exists iotdata_nest_id_timestamp_idx
  on public.iotdata (nest_id, "timestamp" desc);
