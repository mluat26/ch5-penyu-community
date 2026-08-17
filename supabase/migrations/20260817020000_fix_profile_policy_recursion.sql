-- Fix infinite recursion in the profile read policy.
--
-- `20260817010000_org_members_read_profiles` let organization members read
-- each other by looking up the reader's own `organization_id` — with a
-- subquery against `public.profile`. That subquery is itself subject to the
-- policy being evaluated, so Postgres recursed and every profile read failed
-- with "infinite recursion detected in policy for relation profile".
--
-- Because `profile` gates hatchery visibility, that broke loading hatcheries
-- too, not just the profile screen.
--
-- The lookup now goes through a `security definer` function, which runs as its
-- owner and therefore does not re-enter the policy.

create or replace function public.current_organization_id()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select organization_id from public.profile where id = auth.uid();
$$;

revoke all on function public.current_organization_id() from public;
grant execute on function public.current_organization_id() to authenticated;

drop policy if exists "Organization members can read each other" on public.profile;

create policy "Organization members can read each other"
  on public.profile for select
  to authenticated
  using (
    organization_id is not null
    and organization_id = public.current_organization_id()
  );
