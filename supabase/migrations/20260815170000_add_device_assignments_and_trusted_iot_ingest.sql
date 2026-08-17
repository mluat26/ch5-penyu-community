-- Device-to-nest assignment history and trusted IoT ingestion.
--
-- `device.nest_id` made the current connection convenient to query, but it
-- lost assignment history and forced the hardware to know a database nest ID.
-- A device now reports only its own `device.id` as `iotdata.sensor_id`; the
-- trusted ingest path resolves the current assignment and writes the nest ID.

-- ---------------------------------------------------------------------------
-- 1. Give a physical device an owner independent of its current assignment.
-- ---------------------------------------------------------------------------

alter table public.device
  add column if not exists owner_id uuid references auth.users(id) on delete restrict;

-- Existing assigned devices inherit the owner of the hatchery containing their
-- nest. Legacy/unassigned devices with no trustworthy owner intentionally stay
-- NULL and remain service-role-only until a future administrative adoption
-- workflow assigns them.
update public.device as device
set owner_id = hatchery.owner_id
from public.nest as nest
join public.hatchery as hatchery on hatchery.id = nest.hatchery_id
where device.nest_id = nest.id
  and device.owner_id is null;

create or replace function public.assign_device_owner()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  if tg_op = 'INSERT' and new.owner_id is null then
    new.owner_id := auth.uid();
  end if;

  if new.owner_id is null then
    raise exception 'An authenticated user is required to register a device';
  end if;

  if tg_op = 'UPDATE'
     and new.owner_id is distinct from old.owner_id
     and current_setting('app.device_owner_transferring', true) is distinct from 'true' then
    raise exception 'A device owner cannot be changed through the client API';
  end if;

  return new;
end;
$$;

drop trigger if exists assign_device_owner on public.device;

create trigger assign_device_owner
before insert or update of owner_id on public.device
for each row execute function public.assign_device_owner();

-- ---------------------------------------------------------------------------
-- 2. Replace the mutable direct link with an assignment history.
-- ---------------------------------------------------------------------------

create table public.device_assignment (
  id uuid primary key default gen_random_uuid(),
  device_id uuid not null references public.device(id) on delete restrict,
  nest_id uuid not null references public.nest(id) on delete cascade,
  assigned_at timestamptz not null default now(),
  unassigned_at timestamptz,
  assigned_by uuid references auth.users(id) on delete set null,
  unassigned_by uuid references auth.users(id) on delete set null,
  constraint device_assignment_time_order
    check (unassigned_at is null or unassigned_at >= assigned_at)
);

-- Preserve every existing current connection before dropping device.nest_id.
-- The old unique device.nest_id constraint guarantees this cannot create two
-- active assignments for the same nest during the backfill.
insert into public.device_assignment (
  device_id,
  nest_id,
  assigned_at,
  assigned_by
)
select
  device.id,
  device.nest_id,
  device.installed_at,
  device.owner_id
from public.device as device
where device.nest_id is not null;

create unique index device_assignment_one_active_device_idx
  on public.device_assignment(device_id)
  where unassigned_at is null;

create unique index device_assignment_one_active_nest_idx
  on public.device_assignment(nest_id)
  where unassigned_at is null;

create index device_assignment_device_history_idx
  on public.device_assignment(device_id, assigned_at desc);

create index device_assignment_nest_history_idx
  on public.device_assignment(nest_id, assigned_at desc);

-- A device may only be actively installed into a nest owned by the same user.
-- This trigger protects the invariant even if a future server workflow writes
-- assignment rows without using the client-facing save_device RPC.
create or replace function public.validate_active_device_assignment()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
declare
  device_owner uuid;
  nest_owner uuid;
begin
  if new.unassigned_at is not null then
    return new;
  end if;

  select device.owner_id into device_owner
  from public.device as device
  where device.id = new.device_id;

  select hatchery.owner_id into nest_owner
  from public.nest as nest
  join public.hatchery as hatchery on hatchery.id = nest.hatchery_id
  where nest.id = new.nest_id;

  if device_owner is null
     or nest_owner is null
     or device_owner is distinct from nest_owner then
    raise exception 'A device can only be assigned to a nest owned by the same user';
  end if;

  return new;
end;
$$;

create trigger validate_active_device_assignment
before insert or update of device_id, nest_id, unassigned_at
on public.device_assignment
for each row execute function public.validate_active_device_assignment();

-- Assignment rows inherit access from the device owner. They are read-only to
-- clients; save_device below owns reassignment so closing one assignment and
-- opening the next happens atomically.
alter table public.device_assignment enable row level security;

revoke all on public.device_assignment from public, anon, authenticated;
grant select on public.device_assignment to authenticated;

create policy "Device owners read their assignment history"
  on public.device_assignment for select
  to authenticated
  using (
    exists (
      select 1
      from public.device
      where device.id = device_assignment.device_id
        and device.owner_id = auth.uid()
    )
  );

drop policy if exists "Nest owners manage their devices" on public.device;

create policy "Device owners manage their devices"
  on public.device for all
  to authenticated
  using (owner_id = auth.uid())
  with check (owner_id = auth.uid());

-- Device creation, rename, and reassignment must go through `save_device` so
-- the physical device and its assignment history cannot drift apart. Keep
-- read/delete access for the existing app API; a device with assignments or
-- readings naturally cannot be deleted because those records preserve history.
revoke all on public.device from anon;
revoke insert, update on public.device from authenticated;
grant select, delete on public.device to authenticated;

-- The mobile app preserves its existing DeviceEntity shape by reading this
-- current-assignment projection rather than the history table directly.
create or replace view public.device_current_assignment
with (security_invoker = true)
as
select
  d.id,
  d.name,
  assignment.nest_id,
  d.installed_at
from public.device as d
left join lateral (
  select da.nest_id
  from public.device_assignment as da
  where da.device_id = d.id
    and da.unassigned_at is null
  limit 1
) as assignment on true;

revoke all on public.device_current_assignment from public, anon;
grant select on public.device_current_assignment to authenticated;

-- The old column is now redundant and would allow two competing sources of
-- truth. Assignment history is canonical from this point onward.
alter table public.device drop constraint if exists device_nest_id_key;
alter table public.device drop column if exists nest_id;

-- ---------------------------------------------------------------------------
-- 3. Client-facing device registration and reassignment.
-- ---------------------------------------------------------------------------

create or replace function public.save_device(
  p_name text,
  p_nest_id uuid,
  p_device_id uuid default null
)
returns setof public.device
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  saved_device public.device;
  current_nest_id uuid;
begin
  if auth.uid() is null then
    raise exception 'An authenticated user is required to save a device';
  end if;

  if p_name is null or btrim(p_name) = '' then
    raise exception 'A device name is required';
  end if;

  if p_device_id is null then
    insert into public.device (name, owner_id)
    values (btrim(p_name), auth.uid())
    returning * into saved_device;
  else
    select * into saved_device
    from public.device
    where id = p_device_id
    for update;

    if not found or saved_device.owner_id is distinct from auth.uid() then
      raise exception 'The device was not found or is not owned by this user';
    end if;

    update public.device
    set name = btrim(p_name)
    where id = saved_device.id
    returning * into saved_device;
  end if;

  select nest_id into current_nest_id
  from public.device_assignment
  where device_id = saved_device.id
    and unassigned_at is null
  for update;

  if current_nest_id is distinct from p_nest_id then
    if p_nest_id is not null and not public.owns_nest(p_nest_id) then
      raise exception 'The requested nest was not found or is not owned by this user';
    end if;

    update public.device_assignment
    set unassigned_at = now(),
        unassigned_by = auth.uid()
    where device_id = saved_device.id
      and unassigned_at is null;

    if p_nest_id is not null then
      insert into public.device_assignment (
        device_id,
        nest_id,
        assigned_by
      ) values (
        saved_device.id,
        p_nest_id,
        auth.uid()
      );
    end if;
  end if;

  return next saved_device;
  return;
end;
$$;

revoke all on function public.save_device(text, uuid, uuid)
  from public, anon, authenticated;
grant execute on function public.save_device(text, uuid, uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 4. Trusted telemetry ingestion.
-- ---------------------------------------------------------------------------

-- `sensor_id` is now a required reference to the physical device. NOT VALID
-- preserves historical orphan readings while rejecting every new bad row.
--
-- The original foreign key used `ON DELETE SET NULL`, which would erase the
-- source identity from historical telemetry as soon as a device was removed.
-- A physical device with readings is now retained instead; recall/unassign it
-- through `save_device` rather than deleting its audit trail.
alter table public.iotdata
  drop constraint if exists iotdata_sensor_id_fkey;

alter table public.iotdata
  add constraint iotdata_sensor_id_fkey
  foreign key (sensor_id) references public.device(id) on delete restrict
  not valid;

alter table public.iotdata drop constraint if exists iotdata_sensor_id_required;
alter table public.iotdata
  add constraint iotdata_sensor_id_required
  check (sensor_id is not null)
  not valid;

comment on column public.iotdata.sensor_id is
  'The immutable public.device.id that produced this reading.';

-- Devices/gateways must not write readings directly. A trusted server or Edge
-- Function calls ingest_iot_reading with a service-role credential after it
-- authenticates the hardware; this database function resolves nest_id itself.
drop policy if exists "Allow anon inserts" on public.iotdata;
revoke insert, update, delete on public.iotdata from anon, authenticated;

create or replace function public.ingest_iot_reading(
  p_sensor_id uuid,
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
set search_path = public, pg_temp
as $$
declare
  assignment public.device_assignment;
  reading public.iotdata;
begin
  if auth.role() is distinct from 'service_role' then
    raise exception 'Only a trusted IoT ingestion service may submit readings';
  end if;

  if p_sensor_id is null or p_temperature is null then
    raise exception 'A device ID and temperature are required';
  end if;

  select * into assignment
  from public.device_assignment
  where device_id = p_sensor_id
    and unassigned_at is null
  for share;

  if not found then
    raise exception 'The device is not currently assigned to a nest';
  end if;

  insert into public.iotdata (
    nest_id,
    sensor_id,
    position,
    depth_cm,
    temperature,
    "timestamp",
    alert,
    sensor_status,
    battery_voltage,
    signal_rssi_dbm
  ) values (
    assignment.nest_id,
    p_sensor_id,
    p_position,
    p_depth_cm,
    p_temperature,
    coalesce(p_timestamp, now()),
    p_alert,
    p_sensor_status,
    p_battery_voltage,
    p_signal_rssi_dbm
  )
  returning * into reading;

  return reading;
end;
$$;

revoke all on function public.ingest_iot_reading(
  uuid, double precision, timestamptz, text, double precision, text, text,
  double precision, integer
) from public, anon, authenticated;
grant execute on function public.ingest_iot_reading(
  uuid, double precision, timestamptz, text, double precision, text, text,
  double precision, integer
) to service_role;

create index if not exists iotdata_sensor_id_timestamp_idx
  on public.iotdata(sensor_id, "timestamp" desc);
