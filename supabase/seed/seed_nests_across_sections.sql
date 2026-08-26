-- Seed nests spread across the sections of Andrian Ang's hatchery.
--
-- Run in the SQL editor. Resolves the account and the hatchery itself, so
-- there are no ids to paste and no chance of seeding into the wrong one.
--
-- Every lookup raises rather than defaulting. A seed that silently picks a
-- different account is worse than one that stops and says why.

do $$
declare
  v_owner_id     uuid;
  v_hatchery_id  uuid;
  v_cell         record;
  v_seeded       integer := 0;
  v_target       constant integer := 8;
begin
  -- 1. The account, by the name on the profile.
  select p.id
  into v_owner_id
  from public.profile p
  where p.display_name ilike '%andrian%'
  order by p.created_at
  limit 1;

  if v_owner_id is null then
    raise exception
      'No profile whose display_name looks like "Andrian". Run: select id, display_name, apple_email from public.profile;'
      using hint = 'Apple Sign In only returns a name on first authorization, so this can be blank after a reinstall.';
  end if;

  -- 2. Their newest hatchery that the app will actually open. `layout_status`
  --    must be ready or `may_access_hatchery` hides it, and nests seeded into
  --    a hatchery nobody can open look like the seed silently failed.
  select h.id
  into v_hatchery_id
  from public.hatchery h
  where h.owner_id = v_owner_id
    and h.layout_status = 'ready'
  order by h.created_at desc nulls last
  limit 1;

  if v_hatchery_id is null then
    raise exception 'That account owns no hatchery with layout_status = ''ready''.';
  end if;

  -- 3. One nest per active cell, spread over distinct sections.
  --
  --    Placements come from the layout's own `active_cells` rather than from
  --    counting rows and columns: `validate_nest_placement` refuses anything
  --    outside the traced sand, so a generated grid position would be rejected
  --    for exactly the cells that fall outside an irregular hatchery.
  for v_cell in
    select cell."row" as r, cell."column" as c
    from public.hatchery_layout layout,
         jsonb_to_recordset(layout.grid_json -> 'active_cells')
           as cell("row" bigint, "column" bigint)
    where layout.hatchery_id = v_hatchery_id
      and layout.is_current
      -- Skip cells that already hold a nest, so re-running tops up rather
      -- than stacking duplicates on the same square.
      and not exists (
        select 1 from public.nest n
        where n.hatchery_id = v_hatchery_id
          and n.placement_row = cell."row"
          and n.placement_col = cell."column"
      )
    order by cell."row", cell."column"
    limit v_target
  loop
    insert into public.nest (
      hatchery_id,
      founder_id,
      number_of_eggs,
      placement_row,
      placement_col,
      bucket_id,
      date_eggs_laid,
      date_predicted_hatch,
      next_inspection_date
    )
    values (
      v_hatchery_id,
      v_owner_id,
      -- A spread rather than one number, so the egg totals and the hatching
      -- soon count are not obviously synthetic.
      80 + (v_seeded * 7) % 45,
      v_cell.r,
      v_cell.c,
      -- Deliberately not 'PN-DEMO': that string triggers attach_demo_logger,
      -- which registers a second device and backfills a week of invented
      -- readings next to any real ones.
      'SEED-' || lpad((v_seeded + 1)::text, 3, '0'),
      current_date - ((v_seeded * 5) % 40),
      current_date + 55 - ((v_seeded * 5) % 40),
      current_date + 3 + (v_seeded % 6)
    );

    v_seeded := v_seeded + 1;
  end loop;

  if v_seeded = 0 then
    raise exception 'Every active cell in that hatchery already holds a nest.';
  end if;

  raise notice 'Seeded % nests into hatchery %', v_seeded, v_hatchery_id;
end $$;

-- What landed, and where.
select
  p.display_name                                                as owner,
  h.name                                                        as hatchery,
  chr(65 + n.placement_col::int) || (n.placement_row + 1)::text as section,
  n.nest_number,
  n.bucket_id,
  n.number_of_eggs,
  n.date_predicted_hatch
from public.nest n
join public.hatchery h on h.id = n.hatchery_id
join public.profile p on p.id = h.owner_id
where n.bucket_id like 'SEED-%'
order by n.placement_row, n.placement_col;
