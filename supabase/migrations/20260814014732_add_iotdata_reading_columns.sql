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
--
-- NOT VALID for the same reason as iotdata_nest_id_fkey in 20260813151652:
-- this table already holds junk rows that predate every rule the app relies
-- on, and one of them carries an alert string outside this set. Adding the
-- constraint plainly fails with SQLSTATE 23514 and takes the whole migration
-- down with it. NOT VALID still enforces the check on every future insert and
-- update; it only declines to re-check rows written before now. Those rows are
-- unreachable from the app, whose policy on this table grants INSERT and
-- nothing else. Once they are cleaned up, promote this with:
--     alter table public.iotdata validate constraint iotdata_alert_known;
alter table public.iotdata add constraint iotdata_alert_known
  check (alert is null
      or alert in ('none', 'low', 'high', 'critical'))
  not valid;

-- Temperature is the reason this table exists; a reading without one is noise.
-- Not NOT NULL, because rows predating this migration may lack it.
--
-- NOT VALID as well: temperature is the other column those junk rows already
-- populate, so it carries the same risk of holding a value this rejects.
--     alter table public.iotdata validate constraint iotdata_temperature_sane;
alter table public.iotdata add constraint iotdata_temperature_sane
  check (temperature is null
      or (temperature > -50 and temperature < 100))
  not valid;

-- Every query is "the readings for these nests, newest first". Without this
-- index that is a full scan, and this table grows unbounded: one row per
-- sensor per interval, forever.
create index if not exists iotdata_nest_id_timestamp_idx
  on public.iotdata (nest_id, "timestamp" desc);
