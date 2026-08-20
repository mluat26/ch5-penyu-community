-- Let organization members see each other's names.
--
-- `profile` could only ever be read by its own owner, so a nest's founder
-- resolved to nothing but a uuid — the detail screen had no way to turn
-- `founder_id` into "Pak Wayan". A shared hatchery is a team record; who
-- collected a nest is part of it.
--
-- Scoped to the reader's own organization: this exposes a display name and
-- role to colleagues, never to the whole table.

drop policy if exists "Organization members can read each other" on public.profile;

create policy "Organization members can read each other"
  on public.profile for select
  to authenticated
  using (
    organization_id is not null
    and organization_id = (
      select p.organization_id
      from public.profile p
      where p.id = (select auth.uid())
    )
  );
