-- Let a signed-in person delete their own account and data.
--
-- This cannot be done from the app directly: removing an `auth.users` row is
-- an admin operation, and the key that permits it must never ship inside an
-- iOS binary. So the privileged work lives here, and the function only ever
-- touches `auth.uid()` — the caller's own rows, never anybody else's.
--
-- Four foreign keys to auth.users are ON DELETE RESTRICT (device.owner_id,
-- hatchery.owner_id, hatchery_layout.created_by, organization.owner_id), so a
-- plain delete fails. Everything below is ordered to clear those first.

create or replace function public.delete_my_account()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  v_organization_id uuid;
  other_member_count integer := 0;
  owns_organization boolean := false;
begin
  if uid is null then
    raise exception 'An authenticated user is required to delete an account';
  end if;

  select organization_id into v_organization_id
  from public.profile
  where id = uid;

  if v_organization_id is not null then
    select exists (
      select 1 from public.organization
      where id = v_organization_id and owner_id = uid
    ) into owns_organization;

    select count(*) into other_member_count
    from public.profile
    where organization_id = v_organization_id
      and id <> uid;

    -- Deleting the owner takes the organization's hatcheries with it, so
    -- refuse while anybody else still depends on them. Leaving as a member is
    -- always fine; only the owner is blocked.
    if owns_organization and other_member_count > 0 then
      raise exception
        'Your organization still has % other member(s). Remove them before deleting your account.',
        other_member_count;
    end if;
  end if;

  -- Nest children first.
  delete from public.iotdata
  where nest_id in (
    select n.id from public.nest n
    join public.hatchery h on h.id = n.hatchery_id
    where h.owner_id = uid
  );

  delete from public.inspection
  where nest_id in (
    select n.id from public.nest n
    join public.hatchery h on h.id = n.hatchery_id
    where h.owner_id = uid
  );

  delete from public.hatching
  where nest_id in (
    select n.id from public.nest n
    join public.hatchery h on h.id = n.hatchery_id
    where h.owner_id = uid
  );

  delete from public.device_assignment
  where nest_id in (
    select n.id from public.nest n
    join public.hatchery h on h.id = n.hatchery_id
    where h.owner_id = uid
  );

  delete from public.nest
  where hatchery_id in (select id from public.hatchery where owner_id = uid);

  -- `created_by` is RESTRICT, so layouts this person authored on any hatchery
  -- have to go too, not only those on hatcheries they own.
  delete from public.hatchery_layout
  where hatchery_id in (select id from public.hatchery where owner_id = uid)
     or created_by = uid;

  delete from public.hatchery where owner_id = uid;
  delete from public.device where owner_id = uid;

  if owns_organization then
    delete from public.organization_invite where organization_id = v_organization_id;
    -- Nothing should still point at the organization by now, but a member who
    -- left their row behind would block the delete.
    update public.profile set organization_id = null where organization_id = v_organization_id;
    delete from public.organization where id = v_organization_id;
  end if;

  -- profile.id cascades from auth.users.
  delete from auth.users where id = uid;
end;
$$;

revoke all on function public.delete_my_account() from public;
grant execute on function public.delete_my_account() to authenticated;
