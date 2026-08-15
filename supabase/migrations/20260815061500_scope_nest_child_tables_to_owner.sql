-- Owner-scoped access for the tables that hang off a nest.
--
-- 20260814093000 replaced the temporary anon policies on hatchery and nest with
-- owner policies, but inspection, device and hatching were left on
-- "dev: anon full access" and iotdata was never given a read policy at all.
-- The app's publishable key is public by design, so until this lands those
-- three tables are readable and writable by anyone who has it.
--
-- Every table here is a child of a nest, so the rule is the same for all of
-- them: you may touch a row exactly when you may touch its nest. That is one
-- predicate, so it lives in one function rather than being copied per table
-- and per command, where the copies would eventually drift apart.

-- Mirrors the nest policies from 20260814093000 -- owner match plus a ready
-- layout -- so a child row is never visible when its nest is not. SECURITY
-- DEFINER for the same reason is_hatchery_owner is: the lookup must see the
-- nest and hatchery rows regardless of the caller's own policies, and it
-- returns only a caller-owned boolean.
--
-- Returns false for a null nest id, which is what makes the device case below
-- deny rather than error.
create or replace function public.owns_nest(p_nest_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select auth.uid() is not null
    and exists (
      select 1
      from public.nest
      join public.hatchery on hatchery.id = nest.hatchery_id
      where nest.id = p_nest_id
        and hatchery.owner_id = auth.uid()
        and hatchery.layout_status = 'ready'
    );
$$;

revoke all on function public.owns_nest(uuid) from public, anon, authenticated;
grant execute on function public.owns_nest(uuid) to authenticated;

-- Permissive policies combine with OR, so the development ones must be removed
-- rather than supplemented.
drop policy if exists "dev: anon full access" on public.inspection;
drop policy if exists "dev: anon full access" on public.device;
drop policy if exists "dev: anon full access" on public.hatching;

-- `for all` covers select, insert, update and delete. Omitting WITH CHECK makes
-- Postgres reuse the USING expression for the write side, which is what we want
-- here: the same nest test governs reading a row and creating one.
create policy "Nest owners manage their inspections"
  on public.inspection for all
  to authenticated
  using (public.owns_nest(nest_id));

create policy "Nest owners manage their hatching results"
  on public.hatching for all
  to authenticated
  using (public.owns_nest(nest_id));

-- device.nest_id is nullable: a spare or recalled device sits unassigned. An
-- unassigned device has no nest, therefore no hatchery, therefore no owner this
-- schema can derive, so owns_nest(null) denies it and only service_role can see
-- it. Assigning it to a nest hands it to that nest's owner.
--
-- ponytail: unassigned hardware is service_role-only; give device its own
-- owner_id if field staff ever need to manage a shelf of spare sensors.
create policy "Nest owners manage their devices"
  on public.device for all
  to authenticated
  using (public.owns_nest(nest_id));

-- iotdata had RLS enabled with a single anon INSERT policy and no SELECT
-- policy, so every read returned zero rows no matter what was stored --
-- IoTDataRepository.fetchReadings could not work even once a sensor wrote.
-- Readings are owner-scoped like every other child of a nest.
create policy "Nest owners read their readings"
  on public.iotdata for select
  to authenticated
  using (public.owns_nest(nest_id));

-- The existing "Allow anon inserts" policy stays: sensors post readings with
-- the publishable key and no user session. It is INSERT-only and the foreign
-- key added in 20260813151652 forces nest_id to name a real nest, so it cannot
-- be used to read anything or to accumulate rows against nests that do not
-- exist.
