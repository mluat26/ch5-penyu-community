-- Let an organization's owner manage who is in it.
--
-- Three things, all decided together:
--
-- 1. Invitees join as `officer`, not `agent`. `agent` was only ever the default
--    on a fresh profile row -- what create_profile_for_new_user() produces for
--    somebody signed in with no organization -- and 20260816010000 reused it as
--    the joined-member role too, so one value meant two different things.
--    After this migration `agent` means exactly one thing: no organization.
--
--    That also settles a question 20260820030000 left open. may_access_nest()
--    is organization-scoped and never consults `role`, which looked like an
--    oversight while `agent` was a role inside the organization. It is not:
--    every member of an organization is at least an officer, and officers are
--    meant to record field work. Nothing inside an organization is an agent.
--
-- 2. The owner may change a member's role. Nothing could: `profile` has
--    `select own`, `select org members` and `update own` -- no policy lets
--    anyone write another person's row, and deliberately so (see
--    ProfileUpdateDTO, which omits `role` for the same reason). A definer
--    function is the way in, not a new update policy.
--
-- 3. "Removing" a member means removing them from the organization, not
--    deleting their account. `organization_id = null`, role back to `agent`.
--    Deleting the auth user would cascade their profile away and null
--    `hatching.recorded_by` (20260820010000), destroying the audit trail on
--    every hatch they recorded. Reversible matters when the button sits next
--    to "change role".
--
-- Owner throughout is `organization.owner_id`, not a role. Ownership is
-- per-organization and already recorded there; 20260819030000 established it
-- as the authoritative answer after `profile.organization_id` was asked the
-- ownership question and got it wrong.

-- ---------------------------------------------------------------------------
-- 1. Invitees join as officers
-- ---------------------------------------------------------------------------

create or replace function public.redeem_organization_invite(invite_code text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_invite public.organization_invite;
  v_normalized text;
begin
  if auth.uid() is null then
    raise exception 'An authenticated user is required to redeem an invite code';
  end if;

  v_normalized := upper(btrim(invite_code));

  -- Lock the row so two people racing the same code cannot both join.
  select * into v_invite
  from public.organization_invite
  where code = v_normalized
    and redeemed_at is null
  for update;

  if v_invite.id is null then
    raise exception 'That invite code is not valid';
  end if;

  if v_invite.expires_at <= now() then
    raise exception 'That invite code has expired';
  end if;

  update public.organization_invite
  set redeemed_at = now(),
      redeemed_by = auth.uid()
  where id = v_invite.id;

  insert into public.profile (id, organization_id, role)
  values (auth.uid(), v_invite.organization_id, 'officer')
  on conflict (id) do update
    set organization_id = excluded.organization_id,
        -- Joining an organization starts you as an officer. Redeeming a code
        -- for the organization you are already in does not demote you, which
        -- would otherwise let a manager strip their own invite rights by
        -- scanning their own code.
        role = case
                 when profile.organization_id = excluded.organization_id
                   then profile.role
                 else 'officer'
               end;

  return v_invite.organization_id;
end;
$$;

revoke all on function public.redeem_organization_invite(text) from public;
grant execute on function public.redeem_organization_invite(text) to authenticated;

-- Everyone who joined under the old default. Members only: a profile with no
-- organization is an agent by definition and stays one.
update public.profile
set role = 'officer'
where organization_id is not null
  and role = 'agent';

-- ---------------------------------------------------------------------------
-- 2. Shared owner check
-- ---------------------------------------------------------------------------
--
-- Answers "is the caller the owner of the organization this member belongs
-- to?", which is the single condition both functions below turn on. Returns
-- the organization so the caller can also refuse a member who has none.

create or replace function public.owned_organization_of_member(p_member_id uuid)
returns uuid
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select organization.id
  from public.profile
  join public.organization on organization.id = profile.organization_id
  where profile.id = p_member_id
    and organization.owner_id = auth.uid()
    and auth.uid() is not null;
$$;

revoke all on function public.owned_organization_of_member(uuid) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 3. Change a member's role
-- ---------------------------------------------------------------------------

create or replace function public.set_organization_member_role(
  member_id uuid,
  new_role public.org_role
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if auth.uid() is null then
    raise exception 'An authenticated user is required to change a role';
  end if;

  if member_id = auth.uid() then
    raise exception 'You cannot change your own role';
  end if;

  -- `agent` means "belongs to no organization". Setting it here would leave a
  -- member in the organization holding the role that says they are not,
  -- which is what remove_organization_member is for.
  if new_role = 'agent' then
    raise exception 'Remove the member from the organization instead of making them an agent';
  end if;

  if public.owned_organization_of_member(member_id) is null then
    raise exception 'Only the organization owner can change a member''s role';
  end if;

  update public.profile
  set role = new_role
  where id = member_id;
end;
$$;

revoke all on function public.set_organization_member_role(uuid, public.org_role) from public;
grant execute on function public.set_organization_member_role(uuid, public.org_role) to authenticated;

-- ---------------------------------------------------------------------------
-- 4. Remove a member from the organization
-- ---------------------------------------------------------------------------

create or replace function public.remove_organization_member(member_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_organization_id uuid;
begin
  if auth.uid() is null then
    raise exception 'An authenticated user is required to remove a member';
  end if;

  if member_id = auth.uid() then
    raise exception 'You cannot remove yourself from your own organization';
  end if;

  v_organization_id := public.owned_organization_of_member(member_id);

  if v_organization_id is null then
    raise exception 'Only the organization owner can remove a member';
  end if;

  -- Their profile row survives, so `hatching.recorded_by` and `nest.founder_id`
  -- still resolve to a name for the team that keeps working the hatchery.
  -- What they lose is the organization, and with it every RLS path into it.
  update public.profile
  set organization_id = null,
      role = 'agent'
  where id = member_id;

  -- Any invite this person issued goes with them. A live code created by
  -- somebody who is no longer a member would still let a stranger in.
  delete from public.organization_invite
  where organization_id = v_organization_id
    and created_by = member_id
    and redeemed_at is null;
end;
$$;

revoke all on function public.remove_organization_member(uuid) from public;
grant execute on function public.remove_organization_member(uuid) to authenticated;
