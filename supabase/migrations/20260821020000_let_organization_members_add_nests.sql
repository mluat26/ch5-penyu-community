-- "hatchery <uuid> does not exist", reported by a member who can see that
-- hatchery on every other screen.
--
-- Two separate faults, stacked. The message is the second one wearing the
-- first one's clothes.
--
-- ---------------------------------------------------------------------------
-- Fault 1: the integrity trigger reads the hatchery with a lock.
-- ---------------------------------------------------------------------------
--
-- nest_placement_within_hatchery is `security invoker`, and its first
-- statement is
--
--     select number_of_row, number_of_collumn from public.hatchery
--      where id = new.hatchery_id for share;
--
-- Under RLS a locking read is not an ordinary read. `SELECT ... FOR SHARE`
-- applies the table's UPDATE policy USING clause on top of its SELECT policy,
-- because a row you have locked is a row you are claiming the right to change.
-- public.hatchery's update policy is `auth.uid() = owner_id` (20260814093000)
-- and has no organization branch, so for anybody but the owner the row is
-- filtered out, `found` is false, and the trigger reports the hatchery as
-- missing. It is not missing. The plain SELECT policy added by 20260816010000
-- returns it perfectly well, which is why it is on screen.
--
-- The same trigger then asks hatchery_layout whether a current layout exists.
-- That table is owner-only too (is_hatchery_owner), so for a member the answer
-- is silently "no" and the active-sand-area guard below it never runs. A
-- member's nest could be placed outside the sand entirely. That one has never
-- been reachable, only because fault 2 refused the insert first.
--
-- Both are the same mistake: an internal invariant check was left running as
-- the caller, so it sees the caller's slice of the tables rather than the
-- truth it is supposed to be checking against. It writes nothing, returns
-- nothing, and every value it reads is a fact about the hatchery rather than
-- anything the caller chose -- exactly the argument that made
-- refresh_nest_summary a definer in 20260820030000.
--
-- ---------------------------------------------------------------------------
-- Fault 2: members genuinely cannot create a nest.
-- ---------------------------------------------------------------------------
--
-- 20260820030000 shared inspections, hatchings and readings across the
-- organization and said so in its own closing note: "public.nest itself is
-- also untouched ... A teammate may now record the hatch on a nest, but not
-- create the nest. If the Add Nest flow is meant to be shared too, that is
-- another policy set and another decision."
--
-- It is meant to be shared. An organization exists so that a hatchery can be
-- worked by more than one person, and collecting a nest is the most routine
-- field work there is -- more routine than recording a hatch, which members
-- can already do. A member who may write the tally but not register the nest
-- it belongs to is a half-shared hatchery again.
--
-- So insert and update follow the organization, on the same terms as
-- 20260820030000: recording and correcting are field work, destroying a record
-- is not. Deleting a nest stays with the hatchery owner exactly as it is --
-- deleting a nest cascades its inspections, its hatch and its readings, which
-- is a larger act than deleting any one of them, and nothing here asked for it
-- to be shared.

-- ---------------------------------------------------------------------------
-- 1. The trigger checks the hatchery, not the caller's view of it.
-- ---------------------------------------------------------------------------
--
-- Body unchanged from 20260814093000; only the security context moves. The
-- `for share` stays: it is what stops a concurrent grid resize from landing
-- between this check and the insert, and it pairs with
-- hatchery_grid_change_is_safe going the other way.

create or replace function public.nest_placement_within_hatchery()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  grid_rows bigint;
  grid_cols bigint;
  has_current_layout boolean;
begin
  select number_of_row, number_of_collumn
    into grid_rows, grid_cols
  from public.hatchery
   where id = new.hatchery_id
   for share;

  if not found then
    raise exception 'hatchery % does not exist', new.hatchery_id;
  end if;

  if new.placement_row >= grid_rows or new.placement_col >= grid_cols then
    raise exception
      'nest placement (%, %) is outside the % x % grid of hatchery %',
      new.placement_row, new.placement_col, grid_rows, grid_cols,
      new.hatchery_id;
  end if;

  select exists (
    select 1 from public.hatchery_layout
    where hatchery_id = new.hatchery_id
      and is_current
  ) into has_current_layout;

  if has_current_layout and not exists (
    select 1
    from public.hatchery_layout layout,
         jsonb_to_recordset(layout.grid_json -> 'active_cells')
           as cell("row" bigint, "column" bigint)
    where layout.hatchery_id = new.hatchery_id
      and layout.is_current
      and cell."row" = new.placement_row
      and cell."column" = new.placement_col
  ) then
    raise exception 'nest placement (%, %) is outside the active sand area',
      new.placement_row, new.placement_col;
  end if;

  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- 2. "May I work this hatchery?"
-- ---------------------------------------------------------------------------
--
-- may_access_nest() answers this for a nest that already exists. Creating one
-- has no nest to ask about yet, so the same question is asked of the hatchery.
-- Deliberately a sibling rather than a rewrite: the two are read side by side
-- in policies and should look alike.

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
        and hatchery.layout_status = 'ready'
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
-- 3. Registering and correcting a nest follow the organization.
-- ---------------------------------------------------------------------------
--
-- The owner-only policies are replaced rather than supplemented.
-- may_access_hatchery already returns true for the owner, so keeping the old
-- ones alongside would leave two policies saying the same thing about the same
-- person, and one of them would be the one somebody edits by mistake later.
--
-- Update keeps its own WITH CHECK for the reason 20260820030000 spelled out:
-- USING tests the row as it was, so without a WITH CHECK a member could move a
-- nest to a hatchery outside the organization.

drop policy if exists "Hatchery owners can create nests" on public.nest;

create policy "Organization members can create nests"
  on public.nest for insert
  to authenticated
  with check (public.may_access_hatchery(hatchery_id));

drop policy if exists "Hatchery owners can update their nests" on public.nest;

create policy "Organization members can update nests"
  on public.nest for update
  to authenticated
  using (public.may_access_hatchery(hatchery_id))
  with check (public.may_access_hatchery(hatchery_id));

-- ---------------------------------------------------------------------------
-- 4. Deliberately unchanged
-- ---------------------------------------------------------------------------
--
-- "Hatchery owners can delete their nests" stays exactly as it is. So does
-- "Hatchery owners can read their nests", which 20260816010000 already
-- supplemented with an organization read that combines with it via OR.
--
-- public.hatchery's own update policy also stays owner-only. Fault 1 was the
-- trigger asking the wrong question, not that policy being too narrow --
-- resizing a hatchery's grid, or renaming it, is not field work, and widening
-- it here to make a lock succeed would be fixing the symptom in the one place
-- guaranteed to have consequences elsewhere.
