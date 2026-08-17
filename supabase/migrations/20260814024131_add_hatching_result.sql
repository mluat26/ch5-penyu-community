-- The final hatching accounting for a nest.
--
-- Reached from the Hatchling details screen when a nest has hatched. It splits
-- the outcome three ways -- hatched, rotten, unhatched -- where the schema so
-- far had only two. Rotten (spoiled) and unhatched (intact but never developed)
-- are different results and conservation reporting needs them apart.
--
-- One row per nest for now: this is a single terminal tally whose counts sum to
-- the clutch. Partial emergence continues to be recorded as inspections, and if
-- that ever needs its own hatching rows the unique constraint is what to drop.
--
-- Inspections keep tracking progress; this table is the last word. Where both
-- exist, the nest summary follows this one.

alter table public.nest add column eggs_unhatched bigint;

create table public.hatching (
  id             uuid        primary key default gen_random_uuid(),
  nest_id        uuid        not null unique references public.nest(id) on delete cascade,
  -- When the eggs actually hatched, which may predate writing it down.
  hatched_on     date        not null,
  eggs_hatched   bigint      not null,
  eggs_rotten    bigint      not null,
  eggs_unhatched bigint      not null,
  created_at     timestamptz not null default now(),

  constraint hatching_counts_non_negative
    check (eggs_hatched >= 0 and eggs_rotten >= 0 and eggs_unhatched >= 0)
);

-- 2. One place that decides what a nest reports.
--
--    Two things now write the nest summary, so they must not fight. A hatching
--    row is the final accounting and wins outright; without one the summary is
--    the running total from inspections.
create or replace function public.refresh_nest_summary(target_nest uuid)
returns void
language plpgsql
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

-- 3. Counts cannot exceed the clutch. A cross-table rule, so it cannot be a
--    CHECK constraint. Catches a transposed digit before it becomes a
--    conservation statistic.
create or replace function public.hatching_within_clutch()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
declare
  clutch_size bigint;
  counted     bigint;
begin
  select number_of_eggs into clutch_size
    from public.nest where id = new.nest_id;

  if not found then
    raise exception 'nest % does not exist', new.nest_id;
  end if;

  counted := new.eggs_hatched + new.eggs_rotten + new.eggs_unhatched;

  if counted > clutch_size then
    raise exception
      'hatching counts total % but nest % holds only % eggs',
      counted, new.nest_id, clutch_size;
  end if;

  return new;
end;
$$;

create trigger hatching_within_clutch
  before insert or update on public.hatching
  for each row
  execute function public.hatching_within_clutch();

create or replace function public.apply_hatching_to_nest()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  if tg_op = 'DELETE' then
    perform public.refresh_nest_summary(old.nest_id);
    return old;
  end if;

  perform public.refresh_nest_summary(new.nest_id);
  return new;
end;
$$;

create trigger apply_hatching_to_nest
  after insert or update or delete on public.hatching
  for each row
  execute function public.apply_hatching_to_nest();

-- 4. Point the existing inspection trigger at the shared function, so a visit
--    can no longer overwrite a final tally.
create or replace function public.apply_inspection_to_nest()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  if tg_op = 'DELETE' then
    perform public.refresh_nest_summary(old.nest_id);
    return old;
  end if;

  perform public.refresh_nest_summary(new.nest_id);
  return new;
end;
$$;

-- 5. Inspection totals are bounded by the clutch for the same reason.
create or replace function public.inspection_within_clutch()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
declare
  clutch_size bigint;
  counted     bigint;
begin
  select number_of_eggs into clutch_size
    from public.nest where id = new.nest_id;

  if not found then
    raise exception 'nest % does not exist', new.nest_id;
  end if;

  select coalesce(sum(eggs_hatched), 0) + coalesce(sum(eggs_rotten), 0)
    into counted
    from public.inspection
   where nest_id = new.nest_id
     and id <> new.id;

  counted := counted
           + coalesce(new.eggs_hatched, 0)
           + coalesce(new.eggs_rotten, 0);

  if counted > clutch_size then
    raise exception
      'inspection counts total % but nest % holds only % eggs',
      counted, new.nest_id, clutch_size;
  end if;

  return new;
end;
$$;

create trigger inspection_within_clutch
  before insert or update on public.inspection
  for each row
  execute function public.inspection_within_clutch();

-- 6. TEMPORARY / DEV ONLY, matching the other tables. Replace with reviewed
--    ownership policies once authentication exists.
alter table public.hatching enable row level security;

create policy "dev: anon full access" on public.hatching
  for all to anon using (true) with check (true);

grant all on public.hatching to anon, authenticated, service_role;
