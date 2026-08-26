-- Share physical devices with the organization that registered them.
--
-- `device.owner_id` was originally both provenance and authorization. That
-- made a logger invisible to everybody except the person who registered it,
-- even though the hatchery and nests it serves are organization resources.
-- Keep owner_id as registration provenance, but make organization_id the
-- durable access boundary. Personal devices remain owner-only as a fallback.

-- ---------------------------------------------------------------------------
-- 1. Give every organization device a durable tenant key.
-- ---------------------------------------------------------------------------

alter table public.device
  add column if not exists organization_id uuid
    references public.organization(id) on delete restrict;

create index if not exists device_organization_id_idx
  on public.device(organization_id);

update public.device as device
set organization_id = profile.organization_id
from public.profile as profile
where profile.id = device.owner_id
  and device.organization_id is null
  and profile.organization_id is not null;

-- A shared device must survive if the person who first registered it deletes
-- their account. The organization remains canonical; owner_id may then become
-- NULL without erasing the logger or its history.
alter table public.device drop constraint if exists device_owner_id_fkey;
alter table public.device
  add constraint device_owner_id_fkey
  foreign key (owner_id) references auth.users(id) on delete set null;

create or replace function public.assign_device_owner()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
declare
  owner_organization_id uuid;
begin
  if tg_op = 'INSERT'
     and new.owner_id is null
     and new.organization_id is null then
    new.owner_id := auth.uid();
  end if;

  if new.owner_id is not null then
    select profile.organization_id into owner_organization_id
    from public.profile as profile
    where profile.id = new.owner_id;

    if new.organization_id is null then
      new.organization_id := owner_organization_id;
    end if;
  end if;

  if new.owner_id is null and new.organization_id is null then
    raise exception 'An authenticated user or organization is required to register a device';
  end if;

  if tg_op = 'UPDATE'
     and (
       new.owner_id is distinct from old.owner_id
       or new.organization_id is distinct from old.organization_id
     )
     and current_setting('app.device_owner_transferring', true) is distinct from 'true'
     -- ON DELETE SET NULL and delete_my_account intentionally clear only the
     -- provenance owner while retaining the canonical organization.
     and not (
       new.owner_id is null
       and old.owner_id is not null
       and new.organization_id is not distinct from old.organization_id
     ) then
    raise exception 'A device owner or organization cannot be changed through the client API';
  end if;

  return new;
end;
$$;

drop trigger if exists assign_device_owner on public.device;

create trigger assign_device_owner
before insert or update of owner_id, organization_id on public.device
for each row execute function public.assign_device_owner();

-- ---------------------------------------------------------------------------
-- 2. Organization-aware authorization helpers and policies.
-- ---------------------------------------------------------------------------

create or replace function public.may_access_device(p_device_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select auth.uid() is not null
    and exists (
      select 1
      from public.device
      where device.id = p_device_id
        and (
          (
            device.organization_id is not null
            and device.organization_id = public.current_organization_id()
          )
          or (
            device.organization_id is null
            and device.owner_id = auth.uid()
          )
        )
    );
$$;

revoke all on function public.may_access_device(uuid)
  from public, anon, authenticated;
grant execute on function public.may_access_device(uuid) to authenticated;

create or replace function public.may_delete_device(p_device_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select auth.uid() is not null
    and exists (
      select 1
      from public.device
      where device.id = p_device_id
        and (
          (
            device.organization_id is null
            and device.owner_id = auth.uid()
          )
          or (
            device.organization_id is not null
            and device.organization_id = public.current_organization_id()
            and exists (
              select 1
              from public.organization
              left join public.profile
                on profile.id = auth.uid()
               and profile.organization_id = organization.id
              where organization.id = device.organization_id
                and (
                  organization.owner_id = auth.uid()
                  or profile.role = 'manager'
                )
            )
          )
        )
    );
$$;

revoke all on function public.may_delete_device(uuid)
  from public, anon, authenticated;
grant execute on function public.may_delete_device(uuid) to authenticated;

drop policy if exists "dev: anon full access" on public.device;
drop policy if exists "Nest owners manage their devices" on public.device;
drop policy if exists "Device owners manage their devices" on public.device;
drop policy if exists "Organization members read devices" on public.device;
drop policy if exists "Owners and managers delete devices" on public.device;

create policy "Organization members read devices"
  on public.device for select
  to authenticated
  using (public.may_access_device(id));

create policy "Owners and managers delete devices"
  on public.device for delete
  to authenticated
  using (public.may_delete_device(id));

drop policy if exists "Device owners read their assignment history"
  on public.device_assignment;
drop policy if exists "Organization members read device assignment history"
  on public.device_assignment;

create policy "Organization members read device assignment history"
  on public.device_assignment for select
  to authenticated
  using (public.may_access_device(device_id));

-- ---------------------------------------------------------------------------
-- 3. Assignment integrity follows the organization.
-- ---------------------------------------------------------------------------

create or replace function public.validate_active_device_assignment()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  device_owner uuid;
  device_organization uuid;
  nest_owner uuid;
  nest_organization uuid;
begin
  if new.unassigned_at is not null then
    return new;
  end if;

  select device.owner_id, device.organization_id
    into device_owner, device_organization
  from public.device as device
  where device.id = new.device_id;

  select hatchery.owner_id, hatchery.organization_id
    into nest_owner, nest_organization
  from public.nest as nest
  join public.hatchery as hatchery on hatchery.id = nest.hatchery_id
  where nest.id = new.nest_id;

  if device_organization is not null
     and nest_organization is not null
     and device_organization = nest_organization then
    return new;
  end if;

  -- Legacy/personal devices without an organization retain the original
  -- owner-to-owner rule.
  if device_organization is null
     and device_owner is not null
     and device_owner = nest_owner then
    return new;
  end if;

  raise exception 'A device can only be assigned to a nest in the same organization';
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. Registration, rename, assignment, and unassignment are shared work.
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
    insert into public.device (name, owner_id, organization_id)
    values (
      btrim(p_name),
      auth.uid(),
      public.current_organization_id()
    )
    returning * into saved_device;
  else
    select * into saved_device
    from public.device
    where id = p_device_id
    for update;

    if not found or not public.may_access_device(p_device_id) then
      raise exception 'The device was not found or is not available to this organization';
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
    if p_nest_id is not null and not public.may_access_nest(p_nest_id) then
      raise exception 'The requested nest was not found or is not available to this organization';
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
-- 5. Account deletion preserves devices belonging to a surviving team.
-- ---------------------------------------------------------------------------

create or replace function public.delete_my_account()
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  uid uuid := auth.uid();
  org record;
  other_member_count integer;
begin
  if uid is null then
    raise exception 'An authenticated user is required to delete an account';
  end if;

  for org in select id from public.organization where owner_id = uid loop
    select count(*) into other_member_count
    from public.profile
    where organization_id = org.id
      and id <> uid;

    if other_member_count > 0 then
      raise exception
        'Your organization still has % other member(s). Remove them before deleting your account.',
        other_member_count;
    end if;
  end loop;

  delete from public.iotdata
  where nest_id in (
    select nest.id from public.nest as nest
    join public.hatchery as hatchery on hatchery.id = nest.hatchery_id
    where hatchery.owner_id = uid
  );

  delete from public.inspection
  where nest_id in (
    select nest.id from public.nest as nest
    join public.hatchery as hatchery on hatchery.id = nest.hatchery_id
    where hatchery.owner_id = uid
  );

  delete from public.hatching
  where nest_id in (
    select nest.id from public.nest as nest
    join public.hatchery as hatchery on hatchery.id = nest.hatchery_id
    where hatchery.owner_id = uid
  );

  delete from public.device_assignment
  where nest_id in (
    select nest.id from public.nest as nest
    join public.hatchery as hatchery on hatchery.id = nest.hatchery_id
    where hatchery.owner_id = uid
  );

  delete from public.nest
  where hatchery_id in (
    select id from public.hatchery where owner_id = uid
  );

  delete from public.hatchery_layout
  where hatchery_id in (
          select id from public.hatchery where owner_id = uid
        )
     or created_by = uid;

  delete from public.hatchery where owner_id = uid;

  -- Personal devices still belong to the individual. Shared devices belong to
  -- the organization and merely lose their registration provenance.
  delete from public.device
  where owner_id = uid
    and organization_id is null;

  update public.device
  set owner_id = null
  where owner_id = uid
    and organization_id is not null;

  for org in select id from public.organization where owner_id = uid loop
    -- No members remain (checked above), so the entire organization and its
    -- hardware history are being removed together.
    delete from public.iotdata
    where sensor_id in (
      select id from public.device where organization_id = org.id
    );

    delete from public.device_assignment
    where device_id in (
      select id from public.device where organization_id = org.id
    );

    delete from public.device where organization_id = org.id;
    delete from public.organization_invite where organization_id = org.id;
    update public.profile set organization_id = null where organization_id = org.id;
    delete from public.organization where id = org.id;
  end loop;

  delete from auth.users where id = uid;
end;
$$;

revoke all on function public.delete_my_account() from public;
grant execute on function public.delete_my_account() to authenticated;

comment on column public.device.organization_id is
  'Canonical tenant that may see and assign this device; owner_id records who registered it.';
