-- A nest is shared working data for the hatchery's organization. The app
-- already lets every organization member read, create and update that nest,
-- and it presents the Delete action to those same members. Keeping DELETE
-- owner/manager-only made PostgREST hide the row from an ordinary member, so
-- `.delete().select()` returned an empty array and the app reported the visible
-- nest as "not found".
--
-- Scope only the parent nest policy to organization access. Direct deletion of
-- individual inspection and hatching records remains guarded by
-- may_delete_nest_record(), while deleting the nest still removes its dependent
-- records through their foreign-key cascades.

drop policy if exists "Organization members delete nests" on public.nest;
drop policy if exists "Owners and managers delete nests" on public.nest;
drop policy if exists "Hatchery owners can delete their nests" on public.nest;

create policy "Organization members delete nests"
  on public.nest for delete
  to authenticated
  using (public.may_access_nest(id));
