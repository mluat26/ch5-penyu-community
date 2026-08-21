-- A nest's inspection date vanished the moment it hatched.
--
-- The ranger types an inspection date into the Add Nest form, sees it on the
-- nest's Timeline for weeks, taps Hatched, and the row goes to "—". Nothing on
-- that screen changed except the tally, so the date reads as lost -- and it is:
-- refresh_nest_summary's hatched branch ends with
--
--     next_inspection_date = null
--
-- commented "hatched is terminal: nothing further is expected". That is a true
-- statement about the work queue and a false one about the record.
--
-- next_inspection_date is carrying two meanings at once:
--
--   1. a queue signal -- "somebody should visit this nest on this date", which
--      is what isDueForInspection() and the home screen's due list read, and
--   2. a record -- "this is the inspection date entered for this nest", which
--      is what the Timeline section displays.
--
-- Nulling on hatch serves the first by destroying the second. It also encodes
-- a boolean that is already derivable: a hatched nest is exactly one with a
-- hatching row, which is what eggs_unhatched (set in the same statement, two
-- lines up) already records and what NestEntity.hasHatched already reads.
-- Overwriting a person's data to store a fact the schema knows twice over is
-- the wrong trade in any direction.
--
-- So the column stops being a state flag and goes back to meaning one thing.
-- The queue asks the question it actually means -- "has this hatched?" --
-- which is a client-side filter, not a stored null.
--
-- The inspection branch below is untouched. There, next_inspection_date is
-- genuinely derived: the latest inspection says when the next visit is due,
-- and a `complete` outcome says there is none. That is the column being a
-- queue signal legitimately, because an inspection is the thing that schedules
-- the next one.
--
-- Not recoverable: nests already hatched under the old function have had their
-- date overwritten with NULL, and nothing else in the schema kept a copy. A
-- nest with inspections can be re-derived from its latest one; a nest hatched
-- without any -- the common case, and the one in the bug report -- cannot. Only
-- nests hatched from here on keep their date.

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
    -- next_inspection_date is deliberately absent: a hatched nest is
    -- identified by eggs_unhatched, and the date is the ranger's record of
    -- what was planned, not a flag for this function to clear.
    update public.nest
       set success_eggs_hatch   = final_result.eggs_hatched,
           fail_eggs_hatch      = final_result.eggs_rotten,
           eggs_unhatched       = final_result.eggs_unhatched
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
