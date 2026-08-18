-- Let a person delete their own layout photographs, so deleting an account
-- takes them with it.
--
-- `delete_my_account` cleared every table that referenced the person but left
-- their photographs in the private `hatchery-layouts` bucket -- and left them
-- unreachable, because the bucket's delete policy only ever matched an object
-- whose `hatchery_layout` row still existed in state `failed`. Once the layout
-- row was gone that test could never be true again, so nothing could remove the
-- object afterwards even in principle.
--
-- The obvious fix -- deleting from `storage.objects` inside the account
-- deletion function -- is not available: Postgres refuses it outright with
-- "Direct deletion from storage tables is not allowed. Use the Storage API
-- instead.", regardless of role, so a `security definer` function cannot do it
-- either. The removal therefore has to come from the client, through the
-- Storage API, before it calls the RPC.
--
-- Two things are needed for that, and both are here.

-- ---------------------------------------------------------------------------
-- 1. A photo may be removed once its revision is settled
-- ---------------------------------------------------------------------------

-- The `failed`-only restriction was protecting one specific race, described
-- where it was written: an upload is abandoned, its object is removed, and a
-- late finalization then commits a layout whose photo has already vanished.
-- That race exists only while a revision is still `uploading`, which is the
-- window the abandonment RPC closes by moving it to `failed` first.
--
-- So the guard is now "not `uploading`" rather than "is `failed`". Every state
-- the original policy protected is still protected, and a settled revision --
-- `ready`, `superseded`, or `failed` -- can have its photo removed by the
-- person whose photo it is. Tearing down an account is exactly that, done to
-- every revision at once.
--
-- `created_by` is included alongside hatchery ownership to match what
-- `delete_my_account` already deletes: layouts this person authored on someone
-- else's hatchery go too, and their photos would otherwise be orphaned by the
-- very mechanism this migration exists to close.

drop policy if exists "Hatchery owners can remove failed layout photos" on storage.objects;

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
        )
    )
  );

-- ---------------------------------------------------------------------------
-- 2. The paths to remove
-- ---------------------------------------------------------------------------

-- The client cannot work these out for itself without reproducing the account
-- deletion function's selection rules, which would then be free to drift from
-- it. This returns exactly the set `delete_my_account` is about to delete the
-- rows for, from the same predicate, so the two cannot disagree.
--
-- `security definer` for the same reason the deletion function is: the caller
-- is only ever `auth.uid()`, and the read has to see layouts on hatcheries
-- whose visibility rules are not worth re-deriving here.

create or replace function public.my_layout_photo_paths()
returns setof text
language sql
stable
security definer
set search_path = public
as $$
  select layout.source_photo_path
  from public.hatchery_layout layout
  where layout.source_photo_path is not null
    and (
      layout.hatchery_id in (
        select id from public.hatchery where owner_id = (select auth.uid())
      )
      or layout.created_by = (select auth.uid())
    );
$$;

revoke all on function public.my_layout_photo_paths() from public;
grant execute on function public.my_layout_photo_paths() to authenticated;
