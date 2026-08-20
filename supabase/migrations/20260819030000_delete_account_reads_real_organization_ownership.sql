-- Read organization ownership from the organization, not from the profile.
--
-- `delete_my_account` asked `profile.organization_id` which organization the
-- caller belonged to, then checked whether they owned *that* one. Ownership is
-- not recorded there, though -- it lives in `organization.owner_id` -- and the
-- two can disagree. A profile whose `organization_id` is null, or points at a
-- different organization from the one the person owns, made `owns_organization`
-- false, so the whole organization branch was skipped and the final delete hit:
--
--   ERROR: update or delete on table "users" violates foreign key constraint
--          "organization_owner_id_fkey" on table "organization"
--
-- and the account could not be deleted at all. The membership question and the
-- ownership question were being answered from the same column, and only one of
-- them lives there.
--
-- Ownership is now read from `organization.owner_id` directly, and as a loop:
-- nothing constrains a person to owning exactly one organization, and the
-- previous shape could only ever see one. The "still has other members" refusal
-- moves to the front for the same reason -- it now has to hold for every
-- organization involved before anything is deleted, rather than being decided
-- against a single organization halfway through.

create or replace function public.delete_my_account()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  org record;
  other_member_count integer;
begin
  if uid is null then
    raise exception 'An authenticated user is required to delete an account';
  end if;

  -- Deleting the owner takes the organization's hatcheries with it, so refuse
  -- while anybody else still depends on them. Leaving as a member is always
  -- fine; only the owner is blocked. Checked for every organization they own,
  -- and checked before the first delete, so a refusal cannot leave a
  -- half-dismantled account behind.
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
  --
  -- The photographs these rows name are removed by the client through the
  -- Storage API before this function is called: Postgres refuses a direct
  -- delete on `storage.objects` from any role, so it cannot be done here.
  delete from public.hatchery_layout
  where hatchery_id in (select id from public.hatchery where owner_id = uid)
     or created_by = uid;

  delete from public.hatchery where owner_id = uid;
  delete from public.device where owner_id = uid;

  -- Every organization this person owns, found by ownership rather than by
  -- what their own profile row happens to point at.
  for org in select id from public.organization where owner_id = uid loop
    delete from public.organization_invite where organization_id = org.id;
    -- Nothing should still point at the organization by now, but a member who
    -- left their row behind would block the delete.
    update public.profile set organization_id = null where organization_id = org.id;
    delete from public.organization where id = org.id;
  end loop;

  -- profile.id cascades from auth.users.
  delete from auth.users where id = uid;
end;
$$;

revoke all on function public.delete_my_account() from public;
grant execute on function public.delete_my_account() to authenticated;
