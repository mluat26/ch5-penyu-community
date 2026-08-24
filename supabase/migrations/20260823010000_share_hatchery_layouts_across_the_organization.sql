-- Let organization members see the hatchery photo and grid their manager scanned.
--
-- 20260816010000 gave members read access to `hatchery`, and 20260820030000
-- widened nests, inspections, hatching results and readings. Both stopped at
-- the table boundary: `hatchery_layout` and the private `hatchery-layouts`
-- Storage bucket are still gated on `is_hatchery_owner`, which is strictly
-- `owner_id = auth.uid()` with no organization clause.
--
-- The consequence is not a visible error. A member reads zero layout rows, and
-- `HatcheryListController.session(for:)` cannot tell RLS filtering apart from
-- "this hatchery has no layout", so it silently falls back to the legacy
-- placeholder: a generated grid and a default photo. The member loses the real
-- geometry too, not just the picture.
--
-- Read only. Scanning, rescanning and deletion stay with the owner, because
-- the layout lifecycle RPCs and the immutable revision history are built
-- around a single writer.

-- ---------------------------------------------------------------------------
-- 1. "May I look at this hatchery?"
-- ---------------------------------------------------------------------------

-- The hatchery-level twin of `may_access_nest`, and deliberately the same
-- shape: owner, or a member of the organization the hatchery belongs to.
--
-- Unlike `may_access_nest` this does NOT require `layout_status = 'ready'`.
-- A layout row is exactly what a caller needs while the status is still
-- settling, and the owner policies already refuse an `uploading` hatchery.
create or replace function public.may_access_hatchery(p_hatchery_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select auth.uid() is not null
    and exists (
      select 1
      from public.hatchery
      where hatchery.id = p_hatchery_id
        and (
          hatchery.owner_id = auth.uid()
          or (
            hatchery.organization_id is not null
            and hatchery.organization_id = public.current_organization_id()
          )
        )
    );
$$;

revoke all on function public.may_access_hatchery(uuid) from public, anon, authenticated;
grant execute on function public.may_access_hatchery(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 2. The layout revisions.
-- ---------------------------------------------------------------------------

-- An additional policy rather than a replacement: the owner policy from
-- 20260814093000 still applies and the two combine with OR, so single-owner
-- access is unchanged.
drop policy if exists "Organization members read layout revisions" on public.hatchery_layout;

create policy "Organization members read layout revisions"
  on public.hatchery_layout for select
  to authenticated
  using (public.may_access_hatchery(hatchery_layout.hatchery_id));

-- ---------------------------------------------------------------------------
-- 3. The private photo behind those revisions.
-- ---------------------------------------------------------------------------

-- Scoped through `hatchery_layout` rather than by parsing the object path.
-- `source_photo_path` is pinned by a CHECK constraint to
-- `<hatchery_id>/<layout_id>/source.jpg`, but joining the row that claims the
-- object keeps the rule in one place: if a path shape ever changes, this
-- policy follows it instead of silently opening the wrong objects.
drop policy if exists "Organization members read layout photos" on storage.objects;

create policy "Organization members read layout photos"
  on storage.objects for select
  to authenticated
  using (
    bucket_id = 'hatchery-layouts'
    and exists (
      select 1
      from public.hatchery_layout layout
      where layout.source_photo_path = storage.objects.name
        and public.may_access_hatchery(layout.hatchery_id)
    )
  );

-- Upload and delete are intentionally NOT widened. A member who could write
-- into this bucket could replace the photo underneath a committed, immutable
-- revision, which the layout lifecycle has no way to detect or undo.
