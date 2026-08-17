-- Give every existing user a profile, and every existing hatchery an
-- organization.
--
-- `hatchery_attach_organization` fires `before insert`, so it only ever ran
-- for hatcheries created after the membership migration. Anyone whose
-- hatchery predated it was left with no profile row at all, which the app
-- surfaced as Role "Agent", Organization ID "—", and a profile that silently
-- refused to save: the update matched zero rows because there was no row.
--
-- This backfills what the trigger would have done, and adds a matching
-- `auth.users` trigger so a profile now exists from the moment an account
-- does, rather than only once its owner creates a hatchery.

-- ---------------------------------------------------------------------------
-- 1. A profile exists as soon as an account does
-- ---------------------------------------------------------------------------

create or replace function public.create_profile_for_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profile (id)
  values (new.id)
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;

create trigger on_auth_user_created
  after insert on auth.users
  for each row
  execute function public.create_profile_for_new_user();

-- Existing accounts, including the anonymous sessions already in the wild.
insert into public.profile (id)
select u.id
from auth.users u
where not exists (select 1 from public.profile p where p.id = u.id)
on conflict (id) do nothing;

-- ---------------------------------------------------------------------------
-- 2. Existing hatchery owners get their organization
-- ---------------------------------------------------------------------------

do $$
declare
  owner_record record;
  v_organization_id uuid;
begin
  -- One organization per owner, named after their earliest hatchery so it
  -- matches what the insert trigger would have produced.
  for owner_record in
    select distinct on (owner_id) owner_id, name
    from public.hatchery
    where owner_id is not null
    order by owner_id, created_at asc nulls last
  loop
    select organization_id into v_organization_id
    from public.profile
    where id = owner_record.owner_id;

    if v_organization_id is null then
      insert into public.organization (name, owner_id, code, date_created)
      values (
        coalesce(nullif(btrim(owner_record.name), ''), 'My hatchery') || ' organization',
        owner_record.owner_id,
        public.generate_organization_code(),
        current_date
      )
      returning id into v_organization_id;

      insert into public.profile (id, organization_id, role)
      values (owner_record.owner_id, v_organization_id, 'manager')
      on conflict (id) do update
        set organization_id = excluded.organization_id,
            role = 'manager';
    end if;
  end loop;
end
$$;

-- ---------------------------------------------------------------------------
-- 3. Every hatchery points at its owner's organization
-- ---------------------------------------------------------------------------

update public.hatchery h
set organization_id = p.organization_id
from public.profile p
where h.owner_id = p.id
  and h.organization_id is null
  and p.organization_id is not null;
