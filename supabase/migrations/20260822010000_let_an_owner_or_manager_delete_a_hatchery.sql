-- Let an owner, or a manager in the owning organization, delete a hatchery.
--
-- `20260814093000` dropped the hatchery delete policy and did not replace it,
-- for a reason it wrote down: "safe deletion needs a privileged Storage cleanup
-- path for immutable photos". The table still carries `grant all` to
-- `authenticated`, so a client delete has not been failing -- it has been
-- matching zero rows and quietly doing nothing, which the app then reports as
-- "not found". This closes that, and supplies the cleanup path the comment
-- asked for.
--
-- Nothing here deletes nests. `nest_hatchery_id_fkey` is `on delete no action`
-- on purpose (`20260813151652`), and that stays the backstop: a hatchery
-- holding nests is refused by the database, not merely by HatcheryService.

-- ---------------------------------------------------------------------------
-- 1. "May I delete this hatchery?"
-- ---------------------------------------------------------------------------
--
-- The same line `may_delete_nest_record` already draws, one table up. A hatch
-- tally is a conservation figure with no audit trail behind it; a hatchery is
-- every tally it ever held. Recording is field work that any member does,
-- destroying the container is not.
--
-- `layout_status <> 'uploading'` keeps this away from a scan still in flight.
-- That row belongs to `abandon_hatchery_layout` / `purge_failed_hatchery_layout`
-- until the revision settles, and those two already know how to unwind it.

create or replace function public.may_delete_hatchery(p_hatchery_id uuid)
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
        and hatchery.layout_status <> 'uploading'
        and (
          hatchery.owner_id = auth.uid()
          or exists (
            select 1
            from public.profile
            where profile.id = auth.uid()
              and profile.organization_id = hatchery.organization_id
              and profile.role = 'manager'
          )
        )
    );
$$;

-- security definer for the same reason current_organization_id() is one:
-- reading public.profile from inside a policy that is itself evaluating a read
-- would re-enter RLS. 20260817020000 fixed exactly that recursion once already.
revoke all on function public.may_delete_hatchery(uuid) from public, anon, authenticated;
grant execute on function public.may_delete_hatchery(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 2. The delete policy the table has been missing
-- ---------------------------------------------------------------------------
--
-- The drops are not decoration. A permissive policy added outside migrations --
-- the way the iotdata anon insert policy lived in no file at all until
-- 20260821040000 captured it -- would OR itself with this one rather than be
-- replaced by it, and the whole point here is that a non-manager cannot delete.

drop policy if exists "Owners and managers delete hatcheries" on public.hatchery;
drop policy if exists "Hatchery owners can delete their hatcheries" on public.hatchery;

create policy "Owners and managers delete hatcheries"
  on public.hatchery for delete
  to authenticated
  using (public.may_delete_hatchery(id));

-- ---------------------------------------------------------------------------
-- 3. The photographs
-- ---------------------------------------------------------------------------
--
-- `hatchery_layout.hatchery_id` is `on delete cascade`, so the rows go with the
-- hatchery -- but the source photographs live in the private `hatchery-layouts`
-- bucket, and Postgres refuses a direct delete on `storage.objects` from any
-- role. So the client has to remove them through the Storage API first, and
-- once the layout rows are gone it can never do so again: the bucket's delete
-- policy is written against a layout row that would no longer exist.
-- 20260819020000 hit this exact wall for account deletion. Same shape here.
--
-- The client cannot list the paths for itself. `hatchery_layout`'s select policy
-- is owner-only (`Hatchery owners can read layout revisions`), so a manager
-- deleting a colleague's hatchery would read nothing and silently orphan every
-- object. Hence a definer function, gated on the same question as the delete.

create or replace function public.hatchery_layout_photo_paths(p_hatchery_id uuid)
returns setof text
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select layout.source_photo_path
  from public.hatchery_layout layout
  where layout.hatchery_id = p_hatchery_id
    and layout.source_photo_path is not null
    and public.may_delete_hatchery(p_hatchery_id);
$$;

revoke all on function public.hatchery_layout_photo_paths(uuid) from public, anon, authenticated;
grant execute on function public.hatchery_layout_photo_paths(uuid) to authenticated;

-- The bucket policy has to answer to the same person. `may_delete_hatchery` is
-- added to the existing arms rather than replacing them: the owner arm is what
-- lets the abandon/purge flow clear a failed photo while `layout_status` is
-- still 'uploading', which is precisely the state `may_delete_hatchery` refuses.

drop policy if exists "Hatchery owners can remove settled layout photos" on storage.objects;

create policy "Hatchery owners can remove settled layout photos"
  on storage.objects for delete
  to authenticated
  using (
    bucket_id = 'hatchery-layouts'
    and exists (
      select 1
      from public.hatchery_layout layout
      where layout.source_photo_path = storage.objects.name
        and layout.state <> 'uploading'
        and (
          public.is_hatchery_owner(layout.hatchery_id)
          or layout.created_by = (select auth.uid())
          or public.may_delete_hatchery(layout.hatchery_id)
        )
    )
  );
