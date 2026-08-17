-- Behaviour check for 20260816020000_allow_rescan_with_existing_nests.
--
--   docker exec -i supabase_db_ch5-penyu-community \
--     psql -U postgres -d postgres -v ON_ERROR_STOP=1 \
--     < supabase/tests/rescan_with_nests_test.sql
--
-- This drives `finalize_hatchery_layout` itself, which is the function the
-- migration changed. Testing the `hatchery_grid_change_is_safe` trigger
-- instead would prove nothing about it.
--
-- Both directions matter. Re-photographing a hatchery that has nests must now
-- succeed, and shrinking the grid past one of those nests must still be
-- refused — a test that only checked the first would pass just as happily if
-- the guard had been deleted outright.
--
-- Pending layout rows are inserted directly, using the same
-- `app.hatchery_layout_finalizing` escape hatch that `finalize` sets, because
-- `begin_hatchery_layout` validates full quadrilateral geometry that is beside
-- the point here. `finalize` does not re-validate the payload.

begin;

create or replace function pg_temp.check(condition boolean, label text)
returns void language plpgsql as $$
begin
  if not condition then
    raise exception 'FAILED: %', label;
  end if;
  raise notice 'ok: %', label;
end;
$$;

-- Staging writes directly to a table RLS protects, so it runs as the owning
-- role; `finalize` reads auth.uid(), so it runs as the member.
create or replace function pg_temp.become(user_id uuid)
returns void language plpgsql as $$
begin
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims', json_build_object('sub', user_id)::text, true);
end;
$$;

create or replace function pg_temp.become_admin()
returns void language plpgsql as $$
begin
  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
end;
$$;

-- Stages a pending layout for `hatchery` at the given grid size. `marker`
-- varies the boundary so a rescan looks genuinely different from what is
-- current, which is exactly what the old guard refused.
create or replace function pg_temp.stage_layout(
  layout_id uuid,
  hatchery uuid,
  actor uuid,
  rev bigint,
  rows_count bigint,
  cols_count bigint,
  marker double precision
)
returns void language plpgsql as $$
begin
  perform set_config('app.hatchery_layout_finalizing', 'true', true);

  insert into public.hatchery_layout (
    id, hatchery_id, revision, created_by, state, is_current, capture_mode,
    name, length_m, width_m, grid_rows, grid_columns,
    boundary_json, sand_region_json, grid_json,
    layout_schema_version, processing_version
  )
  values (
    layout_id, hatchery, rev, actor, 'uploading', false, 'skipped',
    'Hatch_01', 5, 5, rows_count, cols_count,
    -- Coordinates are normalized to 0..1. `marker` insets the quad slightly so
    -- each staged layout is genuinely different from the current one, which is
    -- what the old guard refused.
    jsonb_build_object(
      'topLeft',     jsonb_build_object('x', marker,     'y', marker),
      'topRight',    jsonb_build_object('x', 1 - marker, 'y', marker),
      'bottomRight', jsonb_build_object('x', 1 - marker, 'y', 1 - marker),
      'bottomLeft',  jsonb_build_object('x', marker,     'y', 1 - marker)
    ),
    jsonb_build_array(
      jsonb_build_object('x', 0.1 + marker, 'y', 0.1),
      jsonb_build_object('x', 0.9,          'y', 0.1),
      jsonb_build_object('x', 0.9,          'y', 0.9)
    ),
    jsonb_build_object(
      'schema_version', 1,
      'rows', rows_count,
      'columns', cols_count,
      'section_width_m', 1,
      'section_height_m', 1,
      -- Every cell active, so a nest may sit anywhere in the grid.
      'active_cells', (
        select jsonb_agg(jsonb_build_object('row', r, 'column', c))
        from generate_series(0, rows_count - 1) as r,
             generate_series(0, cols_count - 1) as c
      )
    ),
    1, 'test'
  );

  perform set_config('app.hatchery_layout_finalizing', 'false', true);
end;
$$;

do $$
declare
  owner_id uuid := gen_random_uuid();
  v_hatchery_id uuid := gen_random_uuid();
  first_layout uuid := gen_random_uuid();
  rescan_layout uuid := gen_random_uuid();
  shrink_layout uuid := gen_random_uuid();
  nest_total integer;
begin
  insert into auth.users (id, instance_id, aud, role, email, created_at, updated_at)
  values (owner_id, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'owner@test.local', now(), now());

  insert into public.hatchery
    (id, name, shape, number_of_row, number_of_collumn, length_m, width_m, layout_status, owner_id)
  values
    (v_hatchery_id, 'Hatch_01', 'rectangle', 5, 5, 5, 5, 'ready', owner_id);

  -- Establish a current layout at 5x5.
  perform pg_temp.stage_layout(first_layout, v_hatchery_id, owner_id, 1, 5, 5, 0.00);
  perform pg_temp.become(owner_id);
  perform public.finalize_hatchery_layout(first_layout);
  perform pg_temp.become_admin();
  perform pg_temp.check(
    (select is_current from public.hatchery_layout where id = first_layout),
    'the first layout becomes current'
  );

  -- A nest at row 4 / col 4 sits on the edge of a 5x5 grid (0-based).
  insert into public.nest (id, hatchery_id, placement_row, placement_col, number_of_eggs, date_eggs_laid)
  values (gen_random_uuid(), v_hatchery_id, 4, 4, 10, current_date);

  select count(*) into nest_total from public.nest where public.nest.hatchery_id = v_hatchery_id;
  perform pg_temp.check(nest_total = 1, 'the hatchery has a nest at the grid edge');

  -- 1. Re-photographing: same grid, different boundary and sand region.
  --    This is what the old guard refused and the migration now permits.
  perform pg_temp.stage_layout(rescan_layout, v_hatchery_id, owner_id, 2, 5, 5, 0.02);
  perform pg_temp.become(owner_id);
  perform public.finalize_hatchery_layout(rescan_layout);
  perform pg_temp.become_admin();
  perform pg_temp.check(
    (select is_current from public.hatchery_layout where id = rescan_layout),
    're-scanning a hatchery that contains nests is allowed'
  );
  perform pg_temp.check(
    (select count(*) from public.nest where public.nest.hatchery_id = v_hatchery_id) = 1,
    'the existing nest survives the rescan'
  );

  -- 2. Shrinking to 3x3 would put the nest at row 4 outside the grid.
  perform pg_temp.stage_layout(shrink_layout, v_hatchery_id, owner_id, 3, 3, 3, 0.04);
  begin
    perform pg_temp.become(owner_id);
    perform public.finalize_hatchery_layout(shrink_layout);
    raise exception 'FAILED: a grid shrink past an existing nest was allowed';
  exception when others then
    if sqlerrm like 'FAILED:%' then raise; end if;
    -- Assert it failed *because of the nest*, not for some unrelated reason.
    if sqlerrm not ilike '%nest%' then
      raise exception 'FAILED: shrink was refused, but not because of a nest: %', sqlerrm;
    end if;
    raise notice 'ok: a grid shrink past an existing nest is still refused (%)', sqlerrm;
  end;
  perform pg_temp.become_admin();

  perform pg_temp.check(
    (select is_current from public.hatchery_layout where id = rescan_layout),
    'the refused shrink left the rescanned layout current'
  );

  raise notice 'ALL CHECKS PASSED';
end
$$;

rollback;
