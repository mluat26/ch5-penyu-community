-- Let an organization work one hatchery together.
--
-- 20260816010000 made hatcheries and nests readable by everyone in the owning
-- organization -- that is what invite codes are for -- but it only ever added
-- `for select` policies, and it stopped at the two parent tables. Everything
-- hanging off a nest stayed on owns_nest(), which is strictly
-- `hatchery.owner_id = auth.uid()`.
--
-- The result was a half-shared record. refresh_nest_summary() denormalises the
-- tallies onto public.nest, so a teammate could already read
-- success_eggs_hatch, fail_eggs_hatch and eggs_unhatched -- but not the
-- hatching row those numbers came from, not the inspections, and not a single
-- temperature reading. They saw the answer with no working.
--
-- Worse for the flow being built: hatching's policy is `for all` with no
-- WITH CHECK, so USING governs inserts too. A teammate could not record a
-- hatch at all. The design has Made Sari (Officer) recording a hatch on a nest
-- Pak Wayan (Manager) collected, which the schema simply did not permit.
--
-- Reading, recording and correcting now follow the organization. Deleting does
-- not: see below.

-- ---------------------------------------------------------------------------
-- 1. "May I touch this nest's records?"
-- ---------------------------------------------------------------------------
--
-- owns_nest() is deliberately left exactly as it is rather than widened.
-- A function called owns_nest that answers true for someone who does not own
-- the nest is the kind of thing that reads fine in a diff and is a trap at 3am.
-- It also still has a caller with genuinely stricter intent -- see note 4.

create or replace function public.may_access_nest(p_nest_id uuid)
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

-- security definer for the same reason current_organization_id() is one:
-- reading public.profile from inside a policy that is itself evaluating a read
-- would re-enter RLS. 20260817020000 fixed exactly that recursion once already.
revoke all on function public.may_access_nest(uuid) from public, anon, authenticated;
grant execute on function public.may_access_nest(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 2. "May I destroy this nest's records?"
-- ---------------------------------------------------------------------------
--
-- Narrower on purpose. A hatch tally is a conservation figure that gets
-- reported upward, and nothing here keeps a copy: hatching has no soft delete
-- and no audit trail, so a deletion is silent and final. Recording and
-- correcting are field work that any member does; destroying the record is
-- not.
--
-- Manager is the role that already carries privileged actions in this schema
-- (it is the only one that may issue invite codes), so the line is drawn in
-- the same place rather than in a new one.

create or replace function public.may_delete_nest_record(p_nest_id uuid)
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
        and hatchery.layout_status = 'ready'
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

revoke all on function public.may_delete_nest_record(uuid) from public, anon, authenticated;
grant execute on function public.may_delete_nest_record(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 3. Split the `for all` policies.
-- ---------------------------------------------------------------------------
--
-- `for all` cannot express this: it takes one USING for reads and deletes and
-- reuses it for writes. Delete needs a different answer from the other three,
-- so each verb gets its own policy.
--
-- The WITH CHECK on insert and update is now explicit rather than inherited
-- from USING. On update that matters: without it a member could move a row to
-- a nest outside the organization, which USING alone does not prevent because
-- USING tests the row as it was, not as it will be.

drop policy if exists "Nest owners manage their inspections" on public.inspection;

create policy "Organization members read inspections"
  on public.inspection for select
  to authenticated
  using (public.may_access_nest(nest_id));

create policy "Organization members record inspections"
  on public.inspection for insert
  to authenticated
  with check (public.may_access_nest(nest_id));

create policy "Organization members correct inspections"
  on public.inspection for update
  to authenticated
  using (public.may_access_nest(nest_id))
  with check (public.may_access_nest(nest_id));

create policy "Managers and hatchery owners delete inspections"
  on public.inspection for delete
  to authenticated
  using (public.may_delete_nest_record(nest_id));

drop policy if exists "Nest owners manage their hatching results" on public.hatching;

create policy "Organization members read hatching results"
  on public.hatching for select
  to authenticated
  using (public.may_access_nest(nest_id));

create policy "Organization members record hatching results"
  on public.hatching for insert
  to authenticated
  with check (public.may_access_nest(nest_id));

create policy "Organization members correct hatching results"
  on public.hatching for update
  to authenticated
  using (public.may_access_nest(nest_id))
  with check (public.may_access_nest(nest_id));

create policy "Managers and hatchery owners delete hatching results"
  on public.hatching for delete
  to authenticated
  using (public.may_delete_nest_record(nest_id));

-- iotdata gets read only, because no user role may write it at all:
-- 20260815170000 dropped the anon insert policy and revoked insert, update and
-- delete from anon and authenticated, leaving service-role ingest_iot_reading()
-- as the only way in. Widening the read is the whole change here.
drop policy if exists "Nest owners read their readings" on public.iotdata;

create policy "Organization members read readings"
  on public.iotdata for select
  to authenticated
  using (public.may_access_nest(nest_id));

-- ---------------------------------------------------------------------------
-- 4. The summary writer needs rights the writer does not have.
-- ---------------------------------------------------------------------------
--
-- Without this the rest of the migration is worse than useless.
--
-- refresh_nest_summary() is called from the AFTER triggers on hatching and
-- inspection, and it does `update public.nest set success_eggs_hatch = ...`.
-- It was never marked security definer, so it runs as whoever wrote the row --
-- and public.nest's UPDATE policy is still hatchery-owner-only.
--
-- So the moment a teammate records a hatch: the hatching row inserts fine, the
-- trigger fires fine, and the UPDATE inside it matches zero rows. No error, no
-- warning. The tally is stored but the four figures the detail screen reads off
-- public.nest never change. That is silent data corruption, and it is caused by
-- widening the child tables without widening nest -- which is exactly what
-- sections 1 to 3 do.
--
-- Definer is right here regardless of the policy question: this function is an
-- internal invariant maintainer, not a user action. It writes nothing the
-- caller chose -- it recomputes nest from the rows that already exist and are
-- already policy-checked on their own tables. Giving the app UPDATE on nest to
-- work around it would hand every member the ability to write those columns
-- directly, which is far more than they need.
--
-- The body is unchanged from 20260814024131; only the security context moves.

create or replace function public.refresh_nest_summary(target_nest uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  final_result   public.hatching%rowtype;
  visit_hatched  bigint;
  visit_rotten   bigint;
  visit_next_due date;
begin
  select * into final_result
    from public.hatching
   where nest_id = target_nest;

  if found then
    update public.nest
       set success_eggs_hatch   = final_result.eggs_hatched,
           fail_eggs_hatch      = final_result.eggs_rotten,
           eggs_unhatched       = final_result.eggs_unhatched,
           -- hatched is terminal: nothing further is expected
           next_inspection_date = null
     where id = target_nest;
    return;
  end if;

  select sum(eggs_hatched), sum(eggs_rotten)
    into visit_hatched, visit_rotten
    from public.inspection
   where nest_id = target_nest;

  select next_inspection_date
    into visit_next_due
    from public.inspection
   where nest_id = target_nest
   order by inspected_on desc, created_at desc
   limit 1;

  update public.nest
     set success_eggs_hatch   = visit_hatched,
         fail_eggs_hatch      = visit_rotten,
         eggs_unhatched       = null,
         next_inspection_date = visit_next_due
   where id = target_nest;
end;
$$;

-- ---------------------------------------------------------------------------
-- 5. Deliberately unchanged
-- ---------------------------------------------------------------------------
--
-- owns_nest() keeps its one remaining caller: the guard in save_device()
-- (20260815170000) that refuses to attach a sensor to a nest you do not own.
-- That is hardware assignment, not field record-keeping -- device rows carry
-- their own owner_id and travel independently of any hatchery -- so it is a
-- separate decision from this one and is left where it was.
--
-- public.nest itself is also untouched. Creating, editing and deleting a nest
-- remain hatchery-owner-only (20260814093000). A teammate may now record the
-- hatch on a nest, but not create the nest. If the Add Nest flow is meant to be
-- shared too, that is another policy set and another decision.
--
-- No grants needed: `grant all on public.inspection/hatching to authenticated`
-- and the iotdata grants already exist. Policies decide the rows; the grants
-- were never the thing standing in the way.
