-- Fills a hatchery with nests covering every state the dashboard, section
-- list and nest detail can show, so those screens can be exercised without
-- entering five nests by hand after each account reset.
--
-- Usage: set v_hatchery_id below and run against the linked project:
--   supabase db query --linked --file supabase/seed/demo_nests.sql
--
-- Safe to re-run: nests are keyed by nest_number within the hatchery, and
-- one that already exists is left alone rather than duplicated.
--
-- Dates are relative to current_date, so the states stay true whenever this
-- runs -- "due today" is due today, not on the day it was written. Predicted
-- hatch is collection + 56, the infobook's 30C reference duration.

do $$
declare
  -- CHANGE ME: the hatchery to fill. Find it with
  --   select id, name from public.hatchery where owner_id = '<your profile id>';
  v_hatchery_id uuid := '00000000-0000-0000-0000-000000000000';

  v_founder_id uuid;
  v_columns integer;
  v_rows integer;
  v_inserted integer := 0;
  v_skipped integer := 0;
  r record;
begin
  -- The founder is whoever owns the hatchery, so Data logger resolves to a
  -- real name instead of sitting blank.
  select owner_id into v_founder_id
  from public.hatchery
  where id = v_hatchery_id;

  if v_founder_id is null then
    raise exception 'No hatchery %', v_hatchery_id;
  end if;

  select grid_columns, grid_rows into v_columns, v_rows
  from public.hatchery_layout
  where hatchery_id = v_hatchery_id and is_current
  limit 1;

  if v_columns is null then
    raise exception 'Hatchery % has no current layout, so nests have no grid to sit on', v_hatchery_id;
  end if;

  for r in
    select * from (values
      -- PN-DEMO is reserved: a trigger registers a logger and backfills a
      -- week of readings, which is what gives the detail chart its data.
      ('N-101', 'PN-DEMO',   112, 0, 0, 12, 2,   null::int, null::int, null::int, 'Kuta Beach, Bali',     -8.7350, 115.1740),
      ('N-102', 'PN-2024-A',  96, 0, 3, 30, 0,   null,      null,      null,      'Kuta Beach, Bali',     -8.7361, 115.1752),
      ('N-103', 'PN-2024-B', 134, 1, 5, 44, -3,  null,      null,      null,      'Legian Beach, Bali',   -8.7372, 115.1765),
      ('N-104', 'PN-2024-C',  88, 2, 1, 52, 1,   null,      null,      null,      'Legian Beach, Bali',   -8.7384, 115.1778),
      ('N-105', 'PN-2023-Z', 120, 2, 7, 70, -8,  104,       11,        5,         'Seminyak Beach, Bali', -8.7395, 115.1790)
    ) as v(nest_number, bucket_id, eggs, prow, pcol,
           laid_days_ago, inspect_in_days, ok, fail, unhatched, addr, lat, lon)
  loop
    if r.prow >= v_rows or r.pcol >= v_columns then
      raise notice 'Skipping % — section (%, %) is outside this % x % grid',
        r.nest_number, r.prow, r.pcol, v_columns, v_rows;
      v_skipped := v_skipped + 1;
      continue;
    end if;

    if exists (
      select 1 from public.nest
      where hatchery_id = v_hatchery_id and nest_number = r.nest_number
    ) then
      v_skipped := v_skipped + 1;
      continue;
    end if;

    insert into public.nest (
      hatchery_id, founder_id, nest_number, bucket_id,
      number_of_eggs, placement_row, placement_col,
      date_eggs_laid, date_predicted_hatch, next_inspection_date,
      success_eggs_hatch, fail_eggs_hatch, eggs_unhatched,
      latitude, longitude, location_address
    )
    values (
      v_hatchery_id, v_founder_id, r.nest_number, r.bucket_id,
      r.eggs, r.prow, r.pcol,
      current_date - r.laid_days_ago,
      current_date - r.laid_days_ago + 56,
      current_date + r.inspect_in_days,
      r.ok, r.fail, r.unhatched,
      r.lat, r.lon, r.addr
    );
    v_inserted := v_inserted + 1;
  end loop;

  raise notice 'Seeded % nest(s), skipped %', v_inserted, v_skipped;
end;
$$;

select n.nest_number,
       n.number_of_eggs                                as eggs,
       n.date_eggs_laid                                as collected,
       n.date_predicted_hatch                          as predicted,
       n.next_inspection_date                          as inspect,
       coalesce(n.success_eggs_hatch::text, '-')       as hatched,
       (select count(*) from public.iotdata i where i.nest_id = n.id) as readings
from public.nest n
where n.hatchery_id = '00000000-0000-0000-0000-000000000000'
order by n.nest_number;
