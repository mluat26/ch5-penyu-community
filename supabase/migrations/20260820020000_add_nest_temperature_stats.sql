-- Temperature summary for one nest over one window.
--
-- Two screens want this, with different windows:
--
--   Hatch recorded!   whole incubation      "Average temperature  30°C"
--   Temperature tab   one calendar day      "Avg (daily) / Highest / Lowest"
--
-- One function with caller-supplied bounds rather than two with the windows
-- baked in.
--
-- Why this is not done in Swift. NestDetailController already fetches raw
-- readings, so the daily figures could be averaged on device -- but it caps
-- itself at seven days on purpose, and the success screen needs the whole
-- incubation. This table takes one row per sensor per interval, so a 56-day
-- window is thousands of rows shipped to a phone on a beach to produce one
-- number. Three doubles is the cheaper answer.

create or replace function public.nest_temperature_stats(
  p_nest_id uuid,
  p_from    timestamptz,
  p_to      timestamptz
)
returns table (
  avg_c double precision,
  max_c double precision,
  min_c double precision
)
language sql
stable
security invoker
set search_path = public, pg_temp
as $$
  select avg(temperature), max(temperature), min(temperature)
  from public.iotdata
  where nest_id = p_nest_id
    and "timestamp" >= p_from
    and "timestamp" <  p_to;
$$;

-- The bounds are half-open on purpose. `between` is inclusive at both ends, so
-- a reading landing exactly on midnight would be counted in both the day that
-- ends and the day that begins, and would pull two daily averages at once.
--
-- They are timestamptz rather than a date, so the caller decides where the day
-- starts. A ranger's "20th June" is a window in their own timezone; picking a
-- server timezone here and truncating would silently shift every daily figure
-- for anyone not standing in it.
--
-- No reading count in the result. avg() already returns NULL when the window
-- holds nothing, which is the "--" state the designs show, and no screen
-- currently distinguishes an average of two readings from one of two thousand.

-- security invoker, not definer: the function runs as the caller, so the
-- iotdata SELECT policy added in 20260815061500 -- which routes through
-- owns_nest() -- still applies. Passing someone else's nest_id returns an
-- empty window rather than their data. A definer function would run with the
-- creator's rights, bypass RLS, and force an ownership check to be rewritten
-- by hand inside the body.
--
-- stable: reads, never writes, and returns the same answer within a statement,
-- so the planner may cache and reorder it.

-- Explicit grant. config.toml leaves auto_expose_new_tables unset, which is
-- the current cloud default: functions created in public are NOT reachable
-- through the Data API roles without one. Without this the app gets a 404 on
-- /rest/v1/rpc/nest_temperature_stats.
--
-- anon is deliberately omitted. An anonymous caller owns no nest, so the
-- policy would return an empty window anyway; there is no reason to publish
-- the endpoint to it.
grant execute on function public.nest_temperature_stats(uuid, timestamptz, timestamptz)
  to authenticated, service_role;

-- The window scan is already indexed: iotdata_nest_id_timestamp_idx from
-- 20260814014732 is (nest_id, "timestamp" desc), which is exactly this
-- predicate. Nothing further to add.
