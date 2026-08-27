-- Stage per-device authentication for IoT telemetry without interrupting the
-- ESP32s that still use the temporary anonymous insert policy.
--
-- Rollout order:
--   1. Apply this migration and deploy the ingest-iot Edge Function.
--   2. Rotate a unique secret for one device and install it in that logger.
--   3. Verify authenticated readings in production, then migrate the rest.
--   4. Only after every logger has moved, remove the anonymous insert policy.

create schema if not exists private;

revoke all on schema private from public, anon, authenticated;

create table if not exists private.device_ingest_credential (
  device_id uuid primary key
    references public.device(id) on delete cascade,
  secret_hash text not null,
  created_at timestamptz not null default now(),
  rotated_at timestamptz not null default now(),
  disabled_at timestamptz
);

alter table private.device_ingest_credential enable row level security;
revoke all on table private.device_ingest_credential
  from public, anon, authenticated;

comment on table private.device_ingest_credential is
  'Server-only bcrypt hashes for unique device ingestion secrets. Raw secrets are returned once when rotated and are never stored.';

create or replace function public.rotate_device_ingest_secret(
  p_device_id uuid
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  raw_secret text;
begin
  if auth.role() is distinct from 'service_role'
     and session_user <> 'postgres' then
    raise exception 'Only a trusted service may rotate device credentials';
  end if;

  if not exists (
    select 1 from public.device where id = p_device_id
  ) then
    raise exception 'The device was not found';
  end if;

  raw_secret := encode(extensions.gen_random_bytes(32), 'hex');

  insert into private.device_ingest_credential (
    device_id,
    secret_hash,
    rotated_at,
    disabled_at
  ) values (
    p_device_id,
    extensions.crypt(raw_secret, extensions.gen_salt('bf', 12)),
    now(),
    null
  )
  on conflict (device_id) do update
  set secret_hash = excluded.secret_hash,
      rotated_at = excluded.rotated_at,
      disabled_at = null;

  -- The caller must transfer this value to the logger securely. It cannot be
  -- recovered from the bcrypt hash later; rotating creates a new value.
  return raw_secret;
end;
$$;

revoke all on function public.rotate_device_ingest_secret(uuid)
  from public, anon, authenticated;
grant execute on function public.rotate_device_ingest_secret(uuid)
  to service_role;

create or replace function public.disable_device_ingest_secret(
  p_device_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.role() is distinct from 'service_role'
     and session_user <> 'postgres' then
    raise exception 'Only a trusted service may disable device credentials';
  end if;

  update private.device_ingest_credential
  set disabled_at = now()
  where device_id = p_device_id;

  if not found then
    raise exception 'The device has no ingestion credential';
  end if;
end;
$$;

revoke all on function public.disable_device_ingest_secret(uuid)
  from public, anon, authenticated;
grant execute on function public.disable_device_ingest_secret(uuid)
  to service_role;

create or replace function public.ingest_iot_reading_authenticated(
  p_sensor_id uuid,
  p_device_secret text,
  p_temperature double precision,
  p_timestamp timestamptz default null,
  p_position text default null,
  p_depth_cm double precision default null,
  p_alert text default null,
  p_sensor_status text default null,
  p_battery_voltage double precision default null,
  p_signal_rssi_dbm integer default null
)
returns public.iotdata
language plpgsql
security definer
set search_path = ''
as $$
declare
  stored_hash text;
  reading public.iotdata;
begin
  if auth.role() is distinct from 'service_role'
     and session_user <> 'postgres' then
    raise exception 'Only a trusted IoT ingestion service may submit readings';
  end if;

  select credential.secret_hash into stored_hash
  from private.device_ingest_credential as credential
  where credential.device_id = p_sensor_id
    and credential.disabled_at is null;

  if stored_hash is null
     or p_device_secret is null
     or length(p_device_secret) <> 64
     or extensions.crypt(p_device_secret, stored_hash) <> stored_hash then
    raise exception 'Invalid device credential' using errcode = '28000';
  end if;

  reading := public.ingest_iot_reading(
    p_sensor_id,
    p_temperature,
    p_timestamp,
    p_position,
    p_depth_cm,
    p_alert,
    p_sensor_status,
    p_battery_voltage,
    p_signal_rssi_dbm
  );

  return reading;
end;
$$;

revoke all on function public.ingest_iot_reading_authenticated(
  uuid, text, double precision, timestamptz, text, double precision, text,
  text, double precision, integer
) from public, anon, authenticated;
grant execute on function public.ingest_iot_reading_authenticated(
  uuid, text, double precision, timestamptz, text, double precision, text,
  text, double precision, integer
) to service_role;
