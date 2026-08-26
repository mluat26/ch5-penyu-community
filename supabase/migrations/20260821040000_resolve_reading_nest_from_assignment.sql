-- Let the current assignment decide which nest a reading belongs to, and end
-- that assignment when the nest finishes hatching.
--
-- `ingest_iot_reading` already does the first half, but it refuses anything
-- that is not `service_role`, so it needs a trusted server in front of it.
-- There isn't one: the hardware posts to PostgREST with the anon key, and a
-- policy added outside migrations (`with check (true)`) lets it. That policy
-- is captured here so a `db reset` stops silently breaking the devices.
--
-- Under `with check (true)` the device's own `nest_id` is taken on trust, so
-- `device_assignment` -- the table whose whole purpose is to record which nest
-- a logger sits in -- is consulted by nothing. A stale ID writes readings onto
-- the wrong nest, and moving a logger means reflashing it.
--
-- A BEFORE INSERT trigger resolves `nest_id` from the active assignment
-- instead. The hardware then only has to know its own device ID, which is what
-- the assignment design intended.

-- ---------------------------------------------------------------------------
-- 1. Keep the ingest grant the hardware currently depends on.
-- ---------------------------------------------------------------------------

grant insert on public.iotdata to anon;

drop policy if exists "ESP32 can insert IoT data" on public.iotdata;

-- Authenticity is still unsolved: anything holding the anon key may post as
-- any device. The trigger below fixes *which nest* a reading lands on, not
-- *who* sent it. Signing readings needs a per-device secret, which needs
-- somewhere to verify it -- revisit when a backend exists.
create policy "ESP32 can insert IoT data"
  on public.iotdata for insert
  to anon
  with check (true);

-- ---------------------------------------------------------------------------
-- 2. The assignment decides the nest, not the payload.
-- ---------------------------------------------------------------------------

create or replace function public.resolve_reading_nest()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  assigned_nest_id uuid;
begin
  if new.sensor_id is null then
    raise exception 'A reading must name the device that produced it';
  end if;

  select nest_id into assigned_nest_id
  from public.device_assignment
  where device_id = new.sensor_id
    and unassigned_at is null;

  -- Refuse rather than guess. A logger that is not in a nest has nothing
  -- meaningful to say, and writing the row anyway would attach real
  -- temperatures to whichever nest the firmware last happened to know.
  if assigned_nest_id is null then
    raise exception
      'Device % is not currently assigned to a nest', new.sensor_id
      using hint = 'Assign it by saving a nest with this device, then retry.';
  end if;

  new.nest_id := assigned_nest_id;
  return new;
end;
$$;

drop trigger if exists resolve_reading_nest on public.iotdata;

create trigger resolve_reading_nest
  before insert on public.iotdata
  for each row execute function public.resolve_reading_nest();

-- ---------------------------------------------------------------------------
-- 3. A hatched nest releases its logger.
-- ---------------------------------------------------------------------------

-- Recording a hatching is the explicit "this nest is finished" event, so it is
-- the honest place to end the assignment -- rather than inferring completion by
-- adding up egg counts, which would release the logger early on a partially
-- entered inspection.
--
-- Readings posted after this point are refused by the trigger above until the
-- logger is assigned to its next nest, which is the intended behaviour: the
-- device has been lifted out of the sand.
create or replace function public.release_logger_after_hatching()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  update public.device_assignment
  set unassigned_at = now(),
      unassigned_by = auth.uid()
  where nest_id = new.nest_id
    and unassigned_at is null;

  return new;
end;
$$;

drop trigger if exists release_logger_after_hatching on public.hatching;

create trigger release_logger_after_hatching
  after insert on public.hatching
  for each row execute function public.release_logger_after_hatching();
