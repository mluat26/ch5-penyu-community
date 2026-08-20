-- Organizations, membership profiles, and single-use invite codes.
--
-- Creating a hatchery now also gives its owner an organization and a profile,
-- so every hatchery belongs to exactly one organization from the moment it
-- exists. Other people join that organization by redeeming a short-lived
-- invite code, which is what makes a hatchery visible to more than one device.
--
-- The pre-existing `public.organiztion` table is misspelled and no repository
-- ever selected it, so this renames it rather than carrying the typo into
-- every new foreign key.

-- ---------------------------------------------------------------------------
-- 1. Organization
-- ---------------------------------------------------------------------------

do $$
begin
  if exists (select 1 from pg_tables where schemaname = 'public' and tablename = 'organiztion')
     and not exists (select 1 from pg_tables where schemaname = 'public' and tablename = 'organization')
  then
    alter table public.organiztion rename to organization;
  end if;
end
$$;

create table if not exists public.organization (
  id uuid primary key default gen_random_uuid(),
  name text,
  date_created date
);

alter table public.organization
  add column if not exists owner_id uuid references auth.users(id) on delete restrict;

-- The Figma profile screen shows a human-readable organization id
-- ("ORG-0000000"), which is not the primary key. Keep both: the uuid for
-- foreign keys, this for anything a person has to read or type.
alter table public.organization
  add column if not exists code text;

alter table public.organization
  alter column date_created set default current_date;

alter table public.organization enable row level security;

create unique index if not exists organization_code_key
  on public.organization(code);

create index if not exists organization_owner_id_idx
  on public.organization(owner_id);

-- ---------------------------------------------------------------------------
-- 2. Roles and profiles
-- ---------------------------------------------------------------------------

do $$
begin
  if not exists (select 1 from pg_type where typname = 'org_role') then
    create type public.org_role as enum ('manager', 'coordinator', 'officer', 'agent');
  end if;
end
$$;

-- One row per authenticated user. `role` lives here rather than in a separate
-- roles table, so a permission check is a column read instead of a join.
create table if not exists public.profile (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text,
  apple_email text,
  organization_id uuid references public.organization(id) on delete set null,
  role public.org_role not null default 'agent',
  created_at timestamptz not null default now()
);

alter table public.profile enable row level security;

create index if not exists profile_organization_id_idx
  on public.profile(organization_id);

-- ---------------------------------------------------------------------------
-- 3. Invite codes
-- ---------------------------------------------------------------------------

create table if not exists public.organization_invite (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organization(id) on delete cascade,
  code text not null,
  created_by uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,
  redeemed_at timestamptz,
  redeemed_by uuid references auth.users(id) on delete set null
);

alter table public.organization_invite enable row level security;

-- A four-character code is only safe because it is single-use and expires in
-- minutes. Uniqueness therefore only has to hold among codes that are still
-- live; expired and redeemed codes may repeat.
create unique index if not exists organization_invite_live_code_key
  on public.organization_invite(code)
  where redeemed_at is null;

create index if not exists organization_invite_organization_id_idx
  on public.organization_invite(organization_id);

-- ---------------------------------------------------------------------------
-- 4. Hatchery -> organization
-- ---------------------------------------------------------------------------

alter table public.hatchery
  add column if not exists organization_id uuid references public.organization(id) on delete restrict;

create index if not exists hatchery_organization_id_idx
  on public.hatchery(organization_id);

-- ---------------------------------------------------------------------------
-- 5. Code generation helpers
-- ---------------------------------------------------------------------------

-- Excludes 0/O/1/I so a code read aloud in the field cannot be transcribed
-- into a different valid code.
create or replace function public.generate_invite_code_text()
returns text
language plpgsql
volatile
as $$
declare
  alphabet constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  result text := '';
  i integer;
begin
  for i in 1..4 loop
    result := result || substr(alphabet, 1 + floor(random() * length(alphabet))::int, 1);
  end loop;
  return result;
end;
$$;

create or replace function public.generate_organization_code()
returns text
language plpgsql
volatile
as $$
declare
  candidate text;
  attempt integer := 0;
begin
  loop
    candidate := 'ORG-' || lpad(floor(random() * 10000000)::bigint::text, 7, '0');
    exit when not exists (select 1 from public.organization where code = candidate);

    attempt := attempt + 1;
    if attempt >= 50 then
      raise exception 'Could not allocate a unique organization code';
    end if;
  end loop;

  return candidate;
end;
$$;

-- ---------------------------------------------------------------------------
-- 6. Creating a hatchery creates its owner's organization
-- ---------------------------------------------------------------------------

create or replace function public.attach_hatchery_organization()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_organization_id uuid;
begin
  if new.owner_id is null then
    return new;
  end if;

  select organization_id into v_organization_id
  from public.profile
  where id = new.owner_id;

  if v_organization_id is null then
    insert into public.organization (name, owner_id, code, date_created)
    values (
      coalesce(nullif(btrim(new.name), ''), 'My hatchery') || ' organization',
      new.owner_id,
      public.generate_organization_code(),
      current_date
    )
    returning id into v_organization_id;

    -- The person who creates the organization runs it.
    insert into public.profile (id, organization_id, role)
    values (new.owner_id, v_organization_id, 'manager')
    on conflict (id) do update
      set organization_id = excluded.organization_id,
          role = 'manager';
  end if;

  new.organization_id := v_organization_id;
  return new;
end;
$$;

drop trigger if exists hatchery_attach_organization on public.hatchery;

create trigger hatchery_attach_organization
  before insert on public.hatchery
  for each row
  execute function public.attach_hatchery_organization();

-- ---------------------------------------------------------------------------
-- 7. Invite generation and redemption
-- ---------------------------------------------------------------------------

-- Ten minutes, single use. Both properties are what make a four-character
-- code defensible; shortening the alphabet or lengthening this window without
-- revisiting the other is what would make it guessable.
create or replace function public.generate_organization_invite()
returns table (code text, expires_at timestamptz)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_organization_id uuid;
  v_role public.org_role;
  v_code text;
  v_expires_at timestamptz;
  attempt integer := 0;
begin
  if auth.uid() is null then
    raise exception 'An authenticated user is required to generate an invite code';
  end if;

  select organization_id, role into v_organization_id, v_role
  from public.profile
  where id = auth.uid();

  if v_organization_id is null then
    raise exception 'Create a hatchery before inviting people to your organization';
  end if;

  if v_role <> 'manager' then
    raise exception 'Only a manager can generate an invite code';
  end if;

  v_expires_at := now() + interval '10 minutes';

  loop
    v_code := public.generate_invite_code_text();

    begin
      insert into public.organization_invite (organization_id, code, created_by, expires_at)
      values (v_organization_id, v_code, auth.uid(), v_expires_at);
      exit;
    exception when unique_violation then
      attempt := attempt + 1;
      if attempt >= 50 then
        raise exception 'Could not allocate a unique invite code';
      end if;
    end;
  end loop;

  return query select v_code, v_expires_at;
end;
$$;

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
  values (auth.uid(), v_invite.organization_id, 'agent')
  on conflict (id) do update
    set organization_id = excluded.organization_id;

  return v_invite.organization_id;
end;
$$;

revoke all on function public.generate_organization_invite() from public;
revoke all on function public.redeem_organization_invite(text) from public;
grant execute on function public.generate_organization_invite() to authenticated;
grant execute on function public.redeem_organization_invite(text) to authenticated;

-- ---------------------------------------------------------------------------
-- 8. Row level security
-- ---------------------------------------------------------------------------

drop policy if exists "Members can read their own profile" on public.profile;
create policy "Members can read their own profile"
  on public.profile for select
  to authenticated
  using (id = (select auth.uid()));

drop policy if exists "Members can update their own profile" on public.profile;
create policy "Members can update their own profile"
  on public.profile for update
  to authenticated
  using (id = (select auth.uid()))
  with check (id = (select auth.uid()));

drop policy if exists "Members can read their organization" on public.organization;
create policy "Members can read their organization"
  on public.organization for select
  to authenticated
  using (
    exists (
      select 1
      from public.profile
      where profile.id = (select auth.uid())
        and profile.organization_id = organization.id
    )
  );

-- Invites are only ever created and consumed through the security-definer
-- functions above, so no direct write policy exists. Managers may still list
-- what they issued.
drop policy if exists "Managers can read their organization invites" on public.organization_invite;
create policy "Managers can read their organization invites"
  on public.organization_invite for select
  to authenticated
  using (
    exists (
      select 1
      from public.profile
      where profile.id = (select auth.uid())
        and profile.organization_id = organization_invite.organization_id
        and profile.role = 'manager'
    )
  );

-- Organization members can reach the organization's hatcheries. This is an
-- additional policy: the owner policies still apply and combine with OR, so
-- existing single-owner access is unchanged.
drop policy if exists "Organization members can read hatcheries" on public.hatchery;
create policy "Organization members can read hatcheries"
  on public.hatchery for select
  to authenticated
  using (
    layout_status <> 'uploading'
    and organization_id is not null
    and exists (
      select 1
      from public.profile
      where profile.id = (select auth.uid())
        and profile.organization_id = hatchery.organization_id
    )
  );

drop policy if exists "Organization members can read nests" on public.nest;
create policy "Organization members can read nests"
  on public.nest for select
  to authenticated
  using (
    exists (
      select 1
      from public.hatchery
      join public.profile on profile.organization_id = hatchery.organization_id
      where hatchery.id = nest.hatchery_id
        and hatchery.layout_status = 'ready'
        and profile.id = (select auth.uid())
    )
  );
