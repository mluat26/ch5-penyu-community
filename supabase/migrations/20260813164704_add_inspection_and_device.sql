-- Inspection history and sensor devices.
--
-- Inspection: when a nest reaches its inspection date someone checks whether it
-- has hatched. Hatched means recording how many hatched and how many were
-- rotten, and no further visit is scheduled. Not hatched means scheduling the
-- next one. Until now only a single success_eggs_hatch number existed, with no
-- record of when it was found or what came before it.
--
-- Device: one sensor per nest supplies the IoT readings. iotdata.sensor_id was
-- a bare uuid referencing nothing, so a reading could not be traced to hardware.
--
-- Out of scope: the six telemetry columns iotdata still lacks, and anything
-- needing authentication (users, organizations, ownership policies).

-- 1. Columns nest is missing.
--
--    fail_eggs_hatch never existed, which is why NestDTO.toEntity() hardcodes
--    nil for it and RecordHatchResultInput.toDTO() throws whenever it is
--    non-zero. The inspection trigger needs somewhere to put the rotten count.
alter table public.nest add column fail_eggs_hatch      bigint;

--    next_inspection_date drives the work queue: the nests due today are the
--    ones whose date has arrived. Null means nothing further is expected,
--    which is the terminal state after hatching.
alter table public.nest add column next_inspection_date date;

-- 2. Inspection history. Rows record completed visits only; a visit that has
--    not happened yet is represented by nest.next_inspection_date, so there is
--    no such thing as a half-filled inspection row.
--
--    Counts are per visit, not running totals: a field worker counts what they
--    find that day. The nest summary is the sum across visits.
--
--    Hatching is not one moment. A clutch emerges over days, so a visit can
--    find some hatched and some rotten with eggs still incubating. Only
--    'complete' ends the schedule; 'partially_hatched' still needs a follow-up.
create table public.inspection (
  id                   uuid        primary key default gen_random_uuid(),
  nest_id              uuid        not null references public.nest(id) on delete cascade,
  inspected_on         date        not null default current_date,
  outcome              text        not null,
  eggs_hatched         bigint,
  eggs_rotten          bigint,
  next_inspection_date date,
  created_at           timestamptz not null default now(),

  constraint inspection_outcome_known
    check (outcome in ('not_hatched', 'partially_hatched', 'complete')),

  constraint inspection_counts_non_negative
    check (coalesce(eggs_hatched, 0) >= 0 and coalesce(eggs_rotten, 0) >= 0),

  -- Only a finished nest stops being scheduled. Anything else must name the
  -- next visit, otherwise the nest silently drops out of the work queue.
  constraint inspection_schedule_matches_outcome
    check ((outcome = 'complete' and next_inspection_date is null)
        or (outcome <> 'complete' and next_inspection_date is not null)),

  -- Reporting hatching without saying how many is not a usable record.
  constraint inspection_hatching_requires_counts
    check (outcome = 'not_hatched'
        or (eggs_hatched is not null and eggs_rotten is not null)),

  -- "Partially hatched" means something actually hatched.
  constraint inspection_partial_requires_hatchlings
    check (outcome <> 'partially_hatched' or eggs_hatched > 0)
);

-- An inspection describes a nest and is meaningless without it.
create index inspection_nest_id_idx on public.inspection (nest_id);

-- 3. The nest summary follows the inspection record, so a row written by curl,
--    a script, or a future service cannot leave the two inconsistent.
--
--    Totals are recomputed from every inspection rather than patched, which
--    makes the function correct for inserts, corrections, and deletions alike:
--    whatever the inspections currently say is what the nest reports.
create or replace function public.apply_inspection_to_nest()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
declare
  target_nest uuid;
begin
  if tg_op = 'DELETE' then
    target_nest := old.nest_id;
  else
    target_nest := new.nest_id;
  end if;

  update public.nest n
     set success_eggs_hatch = totals.hatched,
         fail_eggs_hatch    = totals.rotten,
         -- the schedule is whatever the most recent visit decided
         next_inspection_date = (
           select i.next_inspection_date
             from public.inspection i
            where i.nest_id = target_nest
            order by i.inspected_on desc, i.created_at desc
            limit 1
         )
    from (
      select sum(eggs_hatched) as hatched,
             sum(eggs_rotten)  as rotten
        from public.inspection
       where nest_id = target_nest
    ) as totals
   where n.id = target_nest;

  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

create trigger apply_inspection_to_nest
  after insert or update or delete on public.inspection
  for each row
  execute function public.apply_inspection_to_nest();

-- 4. Devices. nest_id is nullable-unique: Postgres permits many NULLs under a
--    unique constraint, so spare and recalled devices can sit unassigned while
--    a nest still holds at most one. ON DELETE SET NULL because the physical
--    device outlives the nest it was measuring.
create table public.device (
  id           uuid        primary key default gen_random_uuid(),
  name         text        not null,
  nest_id      uuid        unique references public.nest(id) on delete set null,
  installed_at timestamptz not null default now()
);

-- Readings become traceable to hardware.
--
-- NOT VALID because iotdata already holds at least one orphan row (see
-- 20260813151652) whose sensor_id was never a real device. It is invisible to
-- the app behind that table's INSERT-only policy. The constraint is still
-- enforced on every future write; once the orphans are cleared, promote it:
--     alter table public.iotdata validate constraint iotdata_sensor_id_fkey;
alter table public.iotdata
  add constraint iotdata_sensor_id_fkey
  foreign key (sensor_id) references public.device(id) on delete set null
  not valid;

-- 5. TEMPORARY / DEV ONLY, matching 20260813132557.
--
--    RLS is enabled by default on new tables, and a table with no policy denies
--    everything -- the same trap that made hatchery and nest unusable. These
--    grant anon full access so the app can exercise the tables before
--    authentication exists. They must be replaced, not supplemented, by the
--    reviewed ownership policies described in supabase/README.md.
alter table public.inspection enable row level security;
alter table public.device     enable row level security;

create policy "dev: anon full access" on public.inspection
  for all to anon using (true) with check (true);

create policy "dev: anon full access" on public.device
  for all to anon using (true) with check (true);

grant all on public.inspection to anon, authenticated, service_role;
grant all on public.device     to anon, authenticated, service_role;
