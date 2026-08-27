-- Apply the delete rule that already governs a nest's child records to the
-- nest row itself. Without this, a manager can delete inspections and a hatch
-- result but the final DELETE on public.nest matches zero rows unless that
-- manager also happens to be the hatchery's original owner.

drop policy if exists "Owners and managers delete nests" on public.nest;
drop policy if exists "Hatchery owners can delete their nests" on public.nest;

create policy "Owners and managers delete nests"
  on public.nest for delete
  to authenticated
  using (public.may_delete_nest_record(id));
