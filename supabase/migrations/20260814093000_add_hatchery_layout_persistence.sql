-- Persisted hatchery scan layouts
--
-- A hatchery's photographed area is private user data. The image itself lives
-- in the private `hatchery-layouts` Storage bucket; this migration stores only
-- immutable object keys plus the normalized geometry required to recreate the
-- map. It also replaces the temporary anon hatchery/nest policies with owner
-- policies. The iOS app creates an anonymous Supabase Auth session on first
-- launch, so every installation has a stable `auth.uid()` without exposing a
-- shared anonymous data set.
--
-- Existing rows deliberately keep a NULL owner. There is no safe way to guess
-- which user owns legacy dev data, so they become inaccessible until a trusted
-- administrator explicitly backfills `owner_id`.

-- ---------------------------------------------------------------------------
-- 1. Authenticated hatchery ownership.
-- ---------------------------------------------------------------------------

alter table public.hatchery
  add column if not exists owner_id uuid references auth.users(id) on delete restrict;

-- Existing rows predate scan persistence and remain readable as `legacy`.
-- New direct inserts start hidden in `uploading`; the first-layout RPC changes
-- that only when a ready immutable revision exists.
alter table public.hatchery
  add column if not exists layout_status text;

update public.hatchery
set layout_status = 'legacy'
where layout_status is null;

alter table public.hatchery
  alter column layout_status set default 'uploading',
  alter column layout_status set not null,
  add constraint hatchery_layout_status_valid
    check (layout_status in ('legacy', 'uploading', 'ready'));

create index if not exists hatchery_owner_id_idx
  on public.hatchery(owner_id);

create or replace function public.assign_hatchery_owner()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  if tg_op = 'INSERT' and new.owner_id is null then
    new.owner_id := auth.uid();
  end if;

  if new.owner_id is null then
    raise exception 'An authenticated user is required to create a hatchery';
  end if;

  -- Owner changes are otherwise immutable. The only exception is the
  -- service-role-only legacy-adoption RPC below, which sets this transaction-
  -- local flag immediately before its audited update.
  if tg_op = 'UPDATE'
     and new.owner_id is distinct from old.owner_id
     and current_setting('app.hatchery_owner_adopting', true) is distinct from 'true' then
    raise exception 'A hatchery owner cannot be changed through the client API';
  end if;

  return new;
end;
$$;

drop trigger if exists assign_hatchery_owner on public.hatchery;
create trigger assign_hatchery_owner
  before insert or update on public.hatchery
  for each row execute function public.assign_hatchery_owner();

-- This helper intentionally bypasses table RLS so a pending *first* layout can
-- authorize its Storage upload even though its parent hatchery is hidden from
-- ordinary SELECTs until finalization. It exposes only a caller-owned boolean.
create or replace function public.is_hatchery_owner(p_hatchery_id uuid)
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
      where id = p_hatchery_id
        and owner_id = auth.uid()
    );
$$;

revoke all on function public.is_hatchery_owner(uuid) from public, anon, authenticated;
grant execute on function public.is_hatchery_owner(uuid) to authenticated;

-- Legacy rows predate owner-scoped access. Their owner must be adopted by a
-- trusted backend only after a human has identified the correct Auth user;
-- this audit trail deliberately survives future hatchery deletion.
create table public.hatchery_legacy_owner_adoption_audit (
  id uuid primary key default gen_random_uuid(),
  hatchery_id uuid not null,
  adopted_owner_id uuid not null references auth.users(id) on delete restrict,
  adoption_reason text not null
    check (char_length(btrim(adoption_reason)) between 1 and 500),
  adopted_by_role text not null,
  adopted_by_subject text,
  adopted_at timestamptz not null default now()
);

create index hatchery_legacy_owner_adoption_hatchery_idx
  on public.hatchery_legacy_owner_adoption_audit(hatchery_id, adopted_at desc);

alter table public.hatchery_legacy_owner_adoption_audit enable row level security;
revoke all on public.hatchery_legacy_owner_adoption_audit from public, anon, authenticated, service_role;
grant select on public.hatchery_legacy_owner_adoption_audit to service_role;

-- `service_role` is deliberately the only caller granted this RPC. It cannot
-- adopt a non-legacy row, cannot overwrite a previously assigned owner, and
-- requires a bounded human-readable audit reason. The transaction-local flag
-- is consumed by `assign_hatchery_owner`, preserving owner immutability for
-- every normal client/API update.
create or replace function public.adopt_legacy_hatchery_owner(
  p_hatchery_id uuid,
  p_owner_id uuid,
  p_adoption_reason text
)
returns public.hatchery
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  legacy_hatchery public.hatchery;
  caller_role text;
  caller_subject text;
begin
  caller_role := auth.role();
  if caller_role is distinct from 'service_role' then
    raise exception 'Only the service role may adopt a legacy hatchery owner';
  end if;

  if p_hatchery_id is null
     or p_owner_id is null
     or p_adoption_reason is null
     or char_length(btrim(p_adoption_reason)) not between 1 and 500 then
    raise exception 'A hatchery ID, owner ID, and 1-500 character adoption reason are required';
  end if;

  perform 1 from auth.users where id = p_owner_id;
  if not found then
    raise exception 'The requested legacy hatchery owner does not exist';
  end if;

  select * into legacy_hatchery
  from public.hatchery
  where id = p_hatchery_id
  for update;

  if not found then
    raise exception 'The requested legacy hatchery does not exist';
  end if;

  if legacy_hatchery.owner_id is not null
     or legacy_hatchery.layout_status <> 'legacy' then
    raise exception 'Only an unowned legacy hatchery can be adopted';
  end if;

  caller_subject := nullif(current_setting('request.jwt.claim.sub', true), '');
  perform set_config('app.hatchery_owner_adopting', 'true', true);

  update public.hatchery
  set owner_id = p_owner_id
  where id = p_hatchery_id
  returning * into legacy_hatchery;

  insert into public.hatchery_legacy_owner_adoption_audit (
    hatchery_id,
    adopted_owner_id,
    adoption_reason,
    adopted_by_role,
    adopted_by_subject
  ) values (
    p_hatchery_id,
    p_owner_id,
    btrim(p_adoption_reason),
    caller_role,
    caller_subject
  );

  return legacy_hatchery;
end;
$$;

revoke all on function public.adopt_legacy_hatchery_owner(uuid, uuid, text)
  from public, anon, authenticated;
grant execute on function public.adopt_legacy_hatchery_owner(uuid, uuid, text)
  to service_role;

-- The development policy is permissive and combines with future policies via
-- OR, so it must be removed rather than supplemented.
drop policy if exists "dev: anon full access" on public.hatchery;
drop policy if exists "dev: anon full access" on public.nest;
drop policy if exists "Hatchery owners can create hatcheries" on public.hatchery;
drop policy if exists "Hatchery owners can delete their hatcheries" on public.hatchery;

create policy "Hatchery owners can read their hatcheries"
  on public.hatchery for select
  to authenticated
  using (
    (select auth.uid()) = owner_id
    and layout_status <> 'uploading'
  );

create policy "Hatchery owners can update their hatcheries"
  on public.hatchery for update
  to authenticated
  using ((select auth.uid()) = owner_id)
  with check ((select auth.uid()) = owner_id);

-- Hatchery creation and deletion are intentionally not exposed as direct
-- table writes. Creation goes through the begin/finalize layout lifecycle;
-- safe deletion needs a privileged Storage cleanup path for immutable photos.

create policy "Hatchery owners can read their nests"
  on public.nest for select
  to authenticated
  using (
    exists (
      select 1
      from public.hatchery
      where hatchery.id = nest.hatchery_id
        and hatchery.owner_id = (select auth.uid())
        and hatchery.layout_status = 'ready'
    )
  );

create policy "Hatchery owners can create nests"
  on public.nest for insert
  to authenticated
  with check (
    exists (
      select 1
      from public.hatchery
      where hatchery.id = nest.hatchery_id
        and hatchery.owner_id = (select auth.uid())
        and hatchery.layout_status = 'ready'
    )
  );

create policy "Hatchery owners can update their nests"
  on public.nest for update
  to authenticated
  using (
    exists (
      select 1
      from public.hatchery
      where hatchery.id = nest.hatchery_id
        and hatchery.owner_id = (select auth.uid())
        and hatchery.layout_status = 'ready'
    )
  )
  with check (
    exists (
      select 1
      from public.hatchery
      where hatchery.id = nest.hatchery_id
        and hatchery.owner_id = (select auth.uid())
        and hatchery.layout_status = 'ready'
    )
  );

create policy "Hatchery owners can delete their nests"
  on public.nest for delete
  to authenticated
  using (
    exists (
      select 1
      from public.hatchery
      where hatchery.id = nest.hatchery_id
        and hatchery.owner_id = (select auth.uid())
        and hatchery.layout_status = 'ready'
    )
  );

-- Guard direct PostgREST hatchery edits too. The original nest trigger checks
-- placement on nest writes; this prevents a raw hatchery resize from making an
-- existing nest disappear outside the new grid.
create or replace function public.hatchery_grid_change_is_safe()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  if new.number_of_row < old.number_of_row
     or new.number_of_collumn < old.number_of_collumn then
    if exists (
      select 1
      from public.nest
      where hatchery_id = old.id
        and (
          placement_row >= new.number_of_row
          or placement_col >= new.number_of_collumn
        )
    ) then
      raise exception 'Cannot shrink a hatchery grid while it contains nests outside the new grid';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists hatchery_grid_change_is_safe on public.hatchery;
create trigger hatchery_grid_change_is_safe
  before update of number_of_row, number_of_collumn on public.hatchery
  for each row execute function public.hatchery_grid_change_is_safe();

-- Once a hatchery has a saved layout, raw PostgREST updates may only rename
-- it. Dimensions/grid counts must change through `finalize_hatchery_layout`,
-- otherwise `hatchery` and its current immutable revision could disagree.
create or replace function public.hatchery_layout_edit_is_managed()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  if new.shape is distinct from old.shape
     or new.number_of_row is distinct from old.number_of_row
     or new.number_of_collumn is distinct from old.number_of_collumn
     or new.length_m is distinct from old.length_m
     or new.width_m is distinct from old.width_m
     or new.layout_status is distinct from old.layout_status then
    if current_setting('app.hatchery_layout_finalizing', true) is distinct from 'true' then
      raise exception 'Change hatchery dimensions and grid through a new layout revision';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists hatchery_layout_edit_is_managed on public.hatchery;
create trigger hatchery_layout_edit_is_managed
  before update of shape, number_of_row, number_of_collumn, length_m, width_m, layout_status
  on public.hatchery
  for each row execute function public.hatchery_layout_edit_is_managed();

-- ---------------------------------------------------------------------------
-- 2. Immutable scan-layout revisions and their private image bucket.
-- ---------------------------------------------------------------------------

create type public.hatchery_capture_mode as enum ('captured', 'skipped');
create type public.hatchery_layout_state as enum (
  'uploading',
  'ready',
  'superseded',
  'failed'
);

-- JSONB is intentionally used for portable geometry, but the server still
-- validates the whole payload. RLS protects ownership; this function protects
-- the data model from a malformed or hand-crafted RPC request.
create or replace function public.hatchery_layout_payload_is_valid(
  p_boundary_json jsonb,
  p_sand_region_json jsonb,
  p_grid_json jsonb,
  p_grid_rows bigint,
  p_grid_columns bigint
)
returns boolean
language plpgsql
immutable
set search_path = public, pg_temp
as $$
declare
  point jsonb;
  cell jsonb;
  boundary_points jsonb[];
  sand_points jsonb[];
  boundary_x double precision[] := array[]::double precision[];
  boundary_y double precision[] := array[]::double precision[];
  sand_x double precision[] := array[]::double precision[];
  sand_y double precision[] := array[]::double precision[];
  x_value double precision;
  y_value double precision;
  grid_schema_version double precision;
  grid_rows_value double precision;
  grid_columns_value double precision;
  section_width_value double precision;
  section_height_value double precision;
  row_number double precision;
  column_number double precision;
  row_value bigint;
  column_value bigint;
  seen_cells text[] := array[]::text[];
  cell_key text;
  point_count integer;
  previous_index integer;
  next_index integer;
  first_edge_end integer;
  second_edge_end integer;
  boundary_orientation integer := 0;
  cross_value double precision;
  dot_value double precision;
  area_value double precision := 0;
  first_cross_start double precision;
  first_cross_end double precision;
  second_cross_start double precision;
  second_cross_end double precision;
  geometry_epsilon constant double precision := 0.000001;
  boundary_turn_epsilon constant double precision := 0.0005;
begin
  if p_grid_rows is null or p_grid_columns is null
     or p_grid_rows < 1 or p_grid_columns < 1
     or p_grid_rows > 100 or p_grid_columns > 100 then
    return false;
  end if;

  if p_grid_rows * p_grid_columns > 2500 then
    return false;
  end if;

  if p_boundary_json is null
     or p_sand_region_json is null
     or p_grid_json is null
     or jsonb_typeof(p_boundary_json) <> 'object'
     or not (p_boundary_json ?& array['topLeft', 'topRight', 'bottomRight', 'bottomLeft'])
     or jsonb_typeof(p_sand_region_json) <> 'array'
     or jsonb_typeof(p_grid_json) <> 'object'
     or jsonb_typeof(p_grid_json -> 'active_cells') <> 'array'
     or jsonb_typeof(p_grid_json -> 'schema_version') <> 'number'
     or jsonb_typeof(p_grid_json -> 'rows') <> 'number'
     or jsonb_typeof(p_grid_json -> 'columns') <> 'number'
     or jsonb_typeof(p_grid_json -> 'section_width_m') <> 'number'
     or jsonb_typeof(p_grid_json -> 'section_height_m') <> 'number' then
    return false;
  end if;

  if jsonb_array_length(p_sand_region_json) not between 3 and 12 then
    return false;
  end if;

  grid_schema_version := (p_grid_json ->> 'schema_version')::double precision;
  grid_rows_value := (p_grid_json ->> 'rows')::double precision;
  grid_columns_value := (p_grid_json ->> 'columns')::double precision;
  section_width_value := (p_grid_json ->> 'section_width_m')::double precision;
  section_height_value := (p_grid_json ->> 'section_height_m')::double precision;

  if grid_schema_version <> trunc(grid_schema_version)
     or grid_rows_value <> trunc(grid_rows_value)
     or grid_columns_value <> trunc(grid_columns_value)
     or grid_schema_version <> 1
     or grid_rows_value <> p_grid_rows
     or grid_columns_value <> p_grid_columns
     or section_width_value <= 0
     or section_height_value <= 0
     or section_width_value::text in ('NaN', 'Infinity', '-Infinity')
     or section_height_value::text in ('NaN', 'Infinity', '-Infinity') then
    return false;
  end if;

  boundary_points := array[
    p_boundary_json -> 'topLeft',
    p_boundary_json -> 'topRight',
    p_boundary_json -> 'bottomRight',
    p_boundary_json -> 'bottomLeft'
  ];

  for point_index in 1..4 loop
    point := boundary_points[point_index];
    if jsonb_typeof(point) <> 'object'
       or jsonb_typeof(point -> 'x') <> 'number'
       or jsonb_typeof(point -> 'y') <> 'number' then
      return false;
    end if;
    x_value := (point ->> 'x')::double precision;
    y_value := (point ->> 'y')::double precision;
    if x_value < 0 or x_value > 1 or y_value < 0 or y_value > 1
       or x_value::text in ('NaN', 'Infinity', '-Infinity')
       or y_value::text in ('NaN', 'Infinity', '-Infinity') then
      return false;
    end if;
    boundary_x := array_append(boundary_x, x_value);
    boundary_y := array_append(boundary_y, y_value);
  end loop;

  -- Mirrors HatcheryBoundary.isValid: corners must form a non-degenerate,
  -- consistently winding convex quadrilateral, not merely four points in
  -- range. This prevents a folded perspective projection from being saved.
  for point_index in 1..4 loop
    next_index := case when point_index = 4 then 1 else point_index + 1 end;
    previous_index := case when next_index = 4 then 1 else next_index + 1 end;
    cross_value :=
      (boundary_x[next_index] - boundary_x[point_index])
        * (boundary_y[previous_index] - boundary_y[next_index])
      - (boundary_y[next_index] - boundary_y[point_index])
        * (boundary_x[previous_index] - boundary_x[next_index]);

    if abs(cross_value) <= boundary_turn_epsilon then
      return false;
    end if;

    if boundary_orientation = 0 then
      boundary_orientation := case when cross_value > 0 then 1 else -1 end;
    elsif (boundary_orientation = 1 and cross_value < 0)
       or (boundary_orientation = -1 and cross_value > 0) then
      return false;
    end if;

    area_value := area_value
      + boundary_x[point_index] * boundary_y[next_index]
      - boundary_x[next_index] * boundary_y[point_index];
  end loop;

  if abs(area_value) * 0.5 <= 0.01 then
    return false;
  end if;

  select array_agg(value order by ordinal_position)
    into sand_points
  from jsonb_array_elements(p_sand_region_json) with ordinality
    as sand_point(value, ordinal_position);

  point_count := array_length(sand_points, 1);
  area_value := 0;

  for point_index in 1..point_count loop
    point := sand_points[point_index];
    if jsonb_typeof(point) <> 'object'
       or jsonb_typeof(point -> 'x') <> 'number'
       or jsonb_typeof(point -> 'y') <> 'number' then
      return false;
    end if;
    x_value := (point ->> 'x')::double precision;
    y_value := (point ->> 'y')::double precision;
    if x_value < 0 or x_value > 1 or y_value < 0 or y_value > 1
       or x_value::text in ('NaN', 'Infinity', '-Infinity')
       or y_value::text in ('NaN', 'Infinity', '-Infinity') then
      return false;
    end if;

    -- HatcherySandRegion rejects duplicate or effectively coincident points.
    if point_index > 1 then
      for second_edge in 1..point_index - 1 loop
        if (x_value - sand_x[second_edge]) * (x_value - sand_x[second_edge])
           + (y_value - sand_y[second_edge]) * (y_value - sand_y[second_edge])
             <= geometry_epsilon * geometry_epsilon then
          return false;
        end if;
      end loop;
    end if;

    sand_x := array_append(sand_x, x_value);
    sand_y := array_append(sand_y, y_value);
  end loop;

  -- The sand footprint may be concave, but it cannot be collapsed,
  -- backtrack along an edge, or self-intersect. These tests mirror the
  -- on-device HatcherySandRegion topology checks.
  for point_index in 1..point_count loop
    next_index := case when point_index = point_count then 1 else point_index + 1 end;
    area_value := area_value
      + sand_x[point_index] * sand_y[next_index]
      - sand_x[next_index] * sand_y[point_index];
  end loop;

  if abs(area_value) * 0.5 <= geometry_epsilon then
    return false;
  end if;

  for point_index in 1..point_count loop
    previous_index := case when point_index = 1 then point_count else point_index - 1 end;
    next_index := case when point_index = point_count then 1 else point_index + 1 end;
    cross_value :=
      (sand_x[point_index] - sand_x[previous_index])
        * (sand_y[next_index] - sand_y[point_index])
      - (sand_y[point_index] - sand_y[previous_index])
        * (sand_x[next_index] - sand_x[point_index]);
    dot_value :=
      (sand_x[point_index] - sand_x[previous_index])
        * (sand_x[next_index] - sand_x[point_index])
      + (sand_y[point_index] - sand_y[previous_index])
        * (sand_y[next_index] - sand_y[point_index]);
    if abs(cross_value) <= geometry_epsilon and dot_value < 0 then
      return false;
    end if;
  end loop;

  for first_edge in 1..point_count loop
    first_edge_end := case when first_edge = point_count then 1 else first_edge + 1 end;
    if first_edge < point_count then
      for second_edge in first_edge + 1..point_count loop
        -- Adjacent edges share their endpoint by design; all other pairs must
        -- not cross or touch.
        if abs(first_edge - second_edge) <> 1
           and not (first_edge = 1 and second_edge = point_count) then
          second_edge_end := case when second_edge = point_count then 1 else second_edge + 1 end;
          first_cross_start :=
            (sand_x[first_edge_end] - sand_x[first_edge])
              * (sand_y[second_edge] - sand_y[first_edge])
            - (sand_y[first_edge_end] - sand_y[first_edge])
              * (sand_x[second_edge] - sand_x[first_edge]);
          first_cross_end :=
            (sand_x[first_edge_end] - sand_x[first_edge])
              * (sand_y[second_edge_end] - sand_y[first_edge])
            - (sand_y[first_edge_end] - sand_y[first_edge])
              * (sand_x[second_edge_end] - sand_x[first_edge]);
          second_cross_start :=
            (sand_x[second_edge_end] - sand_x[second_edge])
              * (sand_y[first_edge] - sand_y[second_edge])
            - (sand_y[second_edge_end] - sand_y[second_edge])
              * (sand_x[first_edge] - sand_x[second_edge]);
          second_cross_end :=
            (sand_x[second_edge_end] - sand_x[second_edge])
              * (sand_y[first_edge_end] - sand_y[second_edge])
            - (sand_y[second_edge_end] - sand_y[second_edge])
              * (sand_x[first_edge_end] - sand_x[second_edge]);

          if (abs(first_cross_start) <= geometry_epsilon
                and sand_x[second_edge] >= least(sand_x[first_edge], sand_x[first_edge_end]) - geometry_epsilon
                and sand_x[second_edge] <= greatest(sand_x[first_edge], sand_x[first_edge_end]) + geometry_epsilon
                and sand_y[second_edge] >= least(sand_y[first_edge], sand_y[first_edge_end]) - geometry_epsilon
                and sand_y[second_edge] <= greatest(sand_y[first_edge], sand_y[first_edge_end]) + geometry_epsilon)
             or (abs(first_cross_end) <= geometry_epsilon
                and sand_x[second_edge_end] >= least(sand_x[first_edge], sand_x[first_edge_end]) - geometry_epsilon
                and sand_x[second_edge_end] <= greatest(sand_x[first_edge], sand_x[first_edge_end]) + geometry_epsilon
                and sand_y[second_edge_end] >= least(sand_y[first_edge], sand_y[first_edge_end]) - geometry_epsilon
                and sand_y[second_edge_end] <= greatest(sand_y[first_edge], sand_y[first_edge_end]) + geometry_epsilon)
             or (abs(second_cross_start) <= geometry_epsilon
                and sand_x[first_edge] >= least(sand_x[second_edge], sand_x[second_edge_end]) - geometry_epsilon
                and sand_x[first_edge] <= greatest(sand_x[second_edge], sand_x[second_edge_end]) + geometry_epsilon
                and sand_y[first_edge] >= least(sand_y[second_edge], sand_y[second_edge_end]) - geometry_epsilon
                and sand_y[first_edge] <= greatest(sand_y[second_edge], sand_y[second_edge_end]) + geometry_epsilon)
             or (abs(second_cross_end) <= geometry_epsilon
                and sand_x[first_edge_end] >= least(sand_x[second_edge], sand_x[second_edge_end]) - geometry_epsilon
                and sand_x[first_edge_end] <= greatest(sand_x[second_edge], sand_x[second_edge_end]) + geometry_epsilon
                and sand_y[first_edge_end] >= least(sand_y[second_edge], sand_y[second_edge_end]) - geometry_epsilon
                and sand_y[first_edge_end] <= greatest(sand_y[second_edge], sand_y[second_edge_end]) + geometry_epsilon)
             or (
                (first_cross_start > geometry_epsilon and first_cross_end < -geometry_epsilon
                  or first_cross_start < -geometry_epsilon and first_cross_end > geometry_epsilon)
                and (second_cross_start > geometry_epsilon and second_cross_end < -geometry_epsilon
                  or second_cross_start < -geometry_epsilon and second_cross_end > geometry_epsilon)
             ) then
            return false;
          end if;
        end if;
      end loop;
    end if;
  end loop;

  for cell in select value from jsonb_array_elements(p_grid_json -> 'active_cells') loop
    if jsonb_typeof(cell) <> 'object'
       or jsonb_typeof(cell -> 'row') <> 'number'
       or jsonb_typeof(cell -> 'column') <> 'number' then
      return false;
    end if;
    row_number := (cell ->> 'row')::double precision;
    column_number := (cell ->> 'column')::double precision;
    if row_number <> trunc(row_number)
       or column_number <> trunc(column_number)
       or row_number < 0 or row_number >= p_grid_rows
       or column_number < 0 or column_number >= p_grid_columns
       or row_number::text in ('NaN', 'Infinity', '-Infinity')
       or column_number::text in ('NaN', 'Infinity', '-Infinity') then
      return false;
    end if;
    row_value := row_number::bigint;
    column_value := column_number::bigint;
    cell_key := row_value::text || ':' || column_value::text;
    if cell_key = any(seen_cells) then
      return false;
    end if;
    seen_cells := array_append(seen_cells, cell_key);
  end loop;

  return true;
exception when others then
  return false;
end;
$$;

create table public.hatchery_layout (
  id uuid primary key,
  hatchery_id uuid not null references public.hatchery(id) on delete cascade,
  revision integer not null check (revision > 0),
  created_by uuid not null references auth.users(id) on delete restrict,
  state public.hatchery_layout_state not null default 'uploading',
  is_current boolean not null default false,

  capture_mode public.hatchery_capture_mode not null,
  source_photo_path text,
  source_photo_mime_type text,
  source_photo_bytes bigint check (source_photo_bytes is null or source_photo_bytes > 0),
  source_photo_width integer check (source_photo_width is null or source_photo_width > 0),
  source_photo_height integer check (source_photo_height is null or source_photo_height > 0),

  -- Historical values are intentionally duplicated from `hatchery`. They
  -- preserve the exact dimensions used for this revision even after a future
  -- rescan.
  name text not null,
  length_m double precision not null check (length_m > 0),
  width_m double precision not null check (width_m > 0),
  grid_rows bigint not null check (grid_rows > 0),
  grid_columns bigint not null check (grid_columns > 0),
  boundary_json jsonb not null,
  sand_region_json jsonb not null,
  grid_json jsonb not null,
  layout_schema_version smallint not null default 1 check (layout_schema_version = 1),
  processing_version text not null,

  created_at timestamptz not null default now(),
  finalized_at timestamptz,
  superseded_at timestamptz,

  constraint hatchery_layout_revision_unique unique (hatchery_id, revision),
  constraint hatchery_layout_current_requires_ready
    check ((state = 'ready') = is_current),
  constraint hatchery_layout_capture_path_is_consistent
    check (
      (capture_mode = 'captured' and source_photo_path is not null)
      or (
        capture_mode = 'skipped'
        and source_photo_path is null
        and source_photo_mime_type is null
        and source_photo_bytes is null
        and source_photo_width is null
        and source_photo_height is null
      )
    ),
  constraint hatchery_layout_source_path_matches_revision
    check (
      source_photo_path is null
      or source_photo_path = hatchery_id::text || '/' || id::text || '/source.jpg'
    ),
  constraint hatchery_layout_boundary_shape
    check (
      jsonb_typeof(boundary_json) = 'object'
      and boundary_json ?& array['topLeft', 'topRight', 'bottomRight', 'bottomLeft']
    ),
  constraint hatchery_layout_sand_region_shape
    check (
      jsonb_typeof(sand_region_json) = 'array'
      and jsonb_array_length(sand_region_json) between 3 and 12
    ),
  constraint hatchery_layout_grid_shape
    check (
      jsonb_typeof(grid_json) = 'object'
      and grid_json ? 'active_cells'
      and jsonb_typeof(grid_json -> 'active_cells') = 'array'
    ),
  constraint hatchery_layout_payload_is_valid
    check (
      public.hatchery_layout_payload_is_valid(
        boundary_json,
        sand_region_json,
        grid_json,
        grid_rows,
        grid_columns
      )
    )
);

create unique index hatchery_layout_one_current_per_hatchery_idx
  on public.hatchery_layout(hatchery_id)
  where is_current;

create index hatchery_layout_hatchery_revision_idx
  on public.hatchery_layout(hatchery_id, revision desc);

create index hatchery_layout_created_by_idx
  on public.hatchery_layout(created_by);

alter table public.hatchery_layout enable row level security;

-- Layout writes are deliberately RPC-only. The functions below validate the
-- lifecycle and are the sole place that can switch `is_current`.
revoke all on public.hatchery_layout from public, anon, authenticated;
grant select on public.hatchery_layout to authenticated;

create policy "Hatchery owners can read layout revisions"
  on public.hatchery_layout for select
  to authenticated
  using (public.is_hatchery_owner(hatchery_layout.hatchery_id));

insert into storage.buckets (
  id,
  name,
  public,
  file_size_limit,
  allowed_mime_types
)
values (
  'hatchery-layouts',
  'hatchery-layouts',
  false,
  26214400,
  array['image/jpeg']::text[]
)
on conflict (id) do update
set public = excluded.public,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

-- An object may be read or uploaded only while its corresponding revision is
-- owned by the caller. Upload is allowed only during the `uploading` state and
-- only to the exact immutable source path recorded by `begin_hatchery_layout`.
-- A failed upload is first locked and moved to `failed` by the abandonment RPC;
-- only then may its exact object be removed. This avoids a timeout race where
-- a late finalization could otherwise commit a layout after its photo vanished.
create policy "Hatchery owners can read layout photos"
  on storage.objects for select
  to authenticated
  using (
    bucket_id = 'hatchery-layouts'
    and exists (
      select 1
      from public.hatchery_layout layout
      where layout.source_photo_path = storage.objects.name
        and public.is_hatchery_owner(layout.hatchery_id)
    )
  );

create policy "Hatchery owners can upload pending layout photos"
  on storage.objects for insert
  to authenticated
  with check (
    bucket_id = 'hatchery-layouts'
    and exists (
      select 1
      from public.hatchery_layout layout
      where layout.source_photo_path = storage.objects.name
        and public.is_hatchery_owner(layout.hatchery_id)
        and layout.state = 'uploading'
    )
  );

create policy "Hatchery owners can remove failed layout photos"
  on storage.objects for delete
  to authenticated
  using (
    bucket_id = 'hatchery-layouts'
    and exists (
      select 1
      from public.hatchery_layout layout
      where layout.source_photo_path = storage.objects.name
        and public.is_hatchery_owner(layout.hatchery_id)
        and layout.state = 'failed'
    )
  );

-- ---------------------------------------------------------------------------
-- 3. Lifecycle RPCs. Storage is not transactional with Postgres, so an upload
--    first creates a non-current revision, then finalizes it atomically.
-- ---------------------------------------------------------------------------

create or replace function public.begin_hatchery_layout(
  p_layout_id uuid,
  p_hatchery_id uuid,
  p_name text,
  p_length_m double precision,
  p_width_m double precision,
  p_grid_rows bigint,
  p_grid_columns bigint,
  p_capture_mode public.hatchery_capture_mode,
  p_boundary_json jsonb,
  p_sand_region_json jsonb,
  p_grid_json jsonb,
  p_processing_version text
)
returns setof public.hatchery_layout
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  owner uuid;
  next_revision integer;
  existing public.hatchery_layout;
begin
  if auth.uid() is null then
    raise exception 'An authenticated user is required to save a hatchery layout';
  end if;

  select * into existing
  from public.hatchery_layout
  where id = p_layout_id;

  if found then
    if existing.hatchery_id <> p_hatchery_id
       or existing.created_by <> auth.uid() then
      raise exception 'The layout ID does not belong to this hatchery';
    end if;
    return query select existing;
    return;
  end if;

  -- Row locking serializes revision allocation and prevents two concurrent
  -- rescans from both becoming the next revision.
  select owner_id into owner
  from public.hatchery
  where id = p_hatchery_id
  for update;

  if not found or owner is distinct from auth.uid() then
    raise exception 'The hatchery was not found or is not owned by this user';
  end if;

  if p_name is null or btrim(p_name) = ''
     or p_length_m is null or p_length_m <= 0
     or p_width_m is null or p_width_m <= 0
     or p_grid_rows is null or p_grid_rows <= 0
     or p_grid_columns is null or p_grid_columns <= 0
     or p_processing_version is null or btrim(p_processing_version) = '' then
    raise exception 'The hatchery layout metadata is invalid';
  end if;

  if not public.hatchery_layout_payload_is_valid(
    p_boundary_json,
    p_sand_region_json,
    p_grid_json,
    p_grid_rows,
    p_grid_columns
  ) then
    raise exception 'The hatchery layout geometry is invalid';
  end if;

  select coalesce(max(revision), 0) + 1
    into next_revision
    from public.hatchery_layout
   where hatchery_id = p_hatchery_id;

  insert into public.hatchery_layout (
    id,
    hatchery_id,
    revision,
    created_by,
    capture_mode,
    source_photo_path,
    name,
    length_m,
    width_m,
    grid_rows,
    grid_columns,
    boundary_json,
    sand_region_json,
    grid_json,
    processing_version
  )
  values (
    p_layout_id,
    p_hatchery_id,
    next_revision,
    auth.uid(),
    p_capture_mode,
    case
      when p_capture_mode = 'captured'
        then p_hatchery_id::text || '/' || p_layout_id::text || '/source.jpg'
      else null
    end,
    btrim(p_name),
    p_length_m,
    p_width_m,
    p_grid_rows,
    p_grid_columns,
    p_boundary_json,
    p_sand_region_json,
    p_grid_json,
    btrim(p_processing_version)
  )
  returning * into existing;

  return query select existing;
end;
$$;

-- Initial setup creates the hatchery row and its pending layout in the same
-- database transaction. This closes the crash window between a plain hatchery
-- insert and the first scan revision; Storage remains the only separate step.
create or replace function public.begin_new_hatchery_layout(
  p_layout_id uuid,
  p_hatchery_id uuid,
  p_name text,
  p_length_m double precision,
  p_width_m double precision,
  p_grid_rows bigint,
  p_grid_columns bigint,
  p_capture_mode public.hatchery_capture_mode,
  p_boundary_json jsonb,
  p_sand_region_json jsonb,
  p_grid_json jsonb,
  p_processing_version text
)
returns setof public.hatchery_layout
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if auth.uid() is null then
    raise exception 'An authenticated user is required to create a hatchery layout';
  end if;

  if exists (select 1 from public.hatchery where id = p_hatchery_id) then
    if exists (select 1 from public.hatchery_layout where id = p_layout_id) then
      return query
      select *
      from public.begin_hatchery_layout(
        p_layout_id,
        p_hatchery_id,
        p_name,
        p_length_m,
        p_width_m,
        p_grid_rows,
        p_grid_columns,
        p_capture_mode,
        p_boundary_json,
        p_sand_region_json,
        p_grid_json,
        p_processing_version
      );
      return;
    end if;
    raise exception 'The requested hatchery ID already exists';
  end if;

  -- `begin_hatchery_layout` validates all metadata and geometry. Any error
  -- rolls this enclosing insert back automatically.
  insert into public.hatchery (
    id,
    number_of_row,
    number_of_collumn,
    name,
    shape,
    length_m,
    width_m
  ) values (
    p_hatchery_id,
    p_grid_rows,
    p_grid_columns,
    p_name,
    'rectangle',
    p_length_m,
    p_width_m
  );

  return query
  select *
  from public.begin_hatchery_layout(
    p_layout_id,
    p_hatchery_id,
    p_name,
    p_length_m,
    p_width_m,
    p_grid_rows,
    p_grid_columns,
    p_capture_mode,
    p_boundary_json,
    p_sand_region_json,
    p_grid_json,
    p_processing_version
  );
end;
$$;

create or replace function public.finalize_hatchery_layout(
  p_layout_id uuid,
  p_source_photo_mime_type text default null,
  p_source_photo_bytes bigint default null,
  p_source_photo_width integer default null,
  p_source_photo_height integer default null
)
returns setof public.hatchery_layout
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  pending public.hatchery_layout;
  current_layout public.hatchery_layout;
  hatchery_row public.hatchery;
  has_nests boolean;
begin
  if auth.uid() is null then
    raise exception 'An authenticated user is required to finalize a hatchery layout';
  end if;

  select * into pending
  from public.hatchery_layout
  where id = p_layout_id
  for update;

  if not found or pending.created_by <> auth.uid() then
    raise exception 'The pending layout was not found';
  end if;

  if pending.state in ('ready', 'superseded') then
    return query select pending;
    return;
  end if;

  if pending.state <> 'uploading' then
    raise exception 'The layout is not available for finalization';
  end if;

  -- Serialize finalization against both rescan starts and nest placement.
  -- The nest trigger takes a compatible parent-row lock before it validates a
  -- coordinate, so a nest cannot slip in after this function checks `has_nests`.
  select * into hatchery_row
  from public.hatchery
  where id = pending.hatchery_id
  for update;

  if not found or hatchery_row.owner_id is distinct from auth.uid() then
    raise exception 'The hatchery was not found or is not owned by this user';
  end if;

  if pending.capture_mode = 'captured' then
    if p_source_photo_mime_type <> 'image/jpeg'
       or p_source_photo_bytes is null or p_source_photo_bytes <= 0
       or p_source_photo_width is null or p_source_photo_width <= 0
       or p_source_photo_height is null or p_source_photo_height <= 0
       or not exists (
         select 1
         from storage.objects
         where bucket_id = 'hatchery-layouts'
           and name = pending.source_photo_path
       ) then
      raise exception 'The hatchery source photo has not been uploaded correctly';
    end if;
  elsif p_source_photo_mime_type is not null
     or p_source_photo_bytes is not null
     or p_source_photo_width is not null
     or p_source_photo_height is not null then
    raise exception 'A skipped hatchery layout cannot include source-photo metadata';
  end if;

  select exists (
    select 1 from public.nest where hatchery_id = pending.hatchery_id
  ) into has_nests;

  select * into current_layout
  from public.hatchery_layout
  where hatchery_id = pending.hatchery_id
    and is_current;

  if current_layout.id is not null
     and pending.revision <= current_layout.revision then
    raise exception 'A newer hatchery layout revision is already current';
  end if;

  -- A nest's coordinates refer to the current layout. We do not silently
  -- remap those coordinates during a rescan: an explicit remapping flow is a
  -- future feature. Until then, any geometry/grid change is safely refused.
  if has_nests and (
    current_layout.id is null
    or current_layout.boundary_json is distinct from pending.boundary_json
    or current_layout.sand_region_json is distinct from pending.sand_region_json
    or current_layout.grid_json is distinct from pending.grid_json
    or current_layout.length_m is distinct from pending.length_m
    or current_layout.width_m is distinct from pending.width_m
    or current_layout.grid_rows is distinct from pending.grid_rows
    or current_layout.grid_columns is distinct from pending.grid_columns
  ) then
    raise exception 'Cannot change a hatchery layout while it contains nests. Remap those nests before re-scanning.';
  end if;

  perform set_config('app.hatchery_layout_finalizing', 'true', true);

  update public.hatchery
  set name = pending.name,
      number_of_row = pending.grid_rows,
      number_of_collumn = pending.grid_columns,
      length_m = pending.length_m,
      width_m = pending.width_m,
      layout_status = 'ready'
  where id = pending.hatchery_id;

  update public.hatchery_layout
  set state = 'superseded',
      is_current = false,
      superseded_at = now()
  where hatchery_id = pending.hatchery_id
    and is_current;

  update public.hatchery_layout
  set state = 'ready',
      is_current = true,
      source_photo_mime_type = p_source_photo_mime_type,
      source_photo_bytes = p_source_photo_bytes,
      source_photo_width = p_source_photo_width,
      source_photo_height = p_source_photo_height,
      finalized_at = now()
  where id = pending.id
  returning * into pending;

  return query select pending;
end;
$$;

create or replace function public.abandon_hatchery_layout(p_layout_id uuid)
returns setof public.hatchery_layout
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  pending public.hatchery_layout;
begin
  if auth.uid() is null then
    raise exception 'An authenticated user is required to abandon a hatchery layout';
  end if;

  select * into pending
  from public.hatchery_layout
  where id = p_layout_id
  for update;

  if not found or pending.created_by <> auth.uid() then
    raise exception 'The pending layout was not found';
  end if;

  -- This call shares the layout-row lock with finalization. If finalization
  -- committed first, return its immutable ready revision and leave its image
  -- untouched. Otherwise, prevent all later finalization before cleanup.
  if pending.state in ('ready', 'superseded', 'failed') then
    return query select pending;
    return;
  end if;

  if pending.state <> 'uploading' then
    raise exception 'The layout is not available for abandonment';
  end if;

  update public.hatchery_layout
  set state = 'failed',
      is_current = false
  where id = pending.id
  returning * into pending;

  return query select pending;
end;
$$;

-- The photo store is separate from Postgres. Once the client has removed a
-- failed revision's exact object, this RPC removes the metadata and (for a
-- first layout) its hidden parent hatchery. It never deletes a ready revision.
create or replace function public.purge_failed_hatchery_layout(p_layout_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  failed_layout public.hatchery_layout;
  hatchery_row public.hatchery;
begin
  if auth.uid() is null and auth.role() <> 'service_role' then
    raise exception 'An authenticated user is required to purge a failed hatchery layout';
  end if;

  select * into failed_layout
  from public.hatchery_layout
  where id = p_layout_id
  for update;

  if not found
     or (
       failed_layout.created_by <> auth.uid()
       and auth.role() <> 'service_role'
     ) then
    raise exception 'The failed layout was not found';
  end if;

  if failed_layout.state <> 'failed' then
    raise exception 'Only a failed hatchery layout can be purged';
  end if;

  select * into hatchery_row
  from public.hatchery
  where id = failed_layout.hatchery_id
  for update;

  if not found
     or (
       hatchery_row.owner_id <> auth.uid()
       and auth.role() <> 'service_role'
     ) then
    raise exception 'The hatchery was not found or is not owned by this user';
  end if;

  if failed_layout.source_photo_path is not null and exists (
    select 1
    from storage.objects
    where bucket_id = 'hatchery-layouts'
      and name = failed_layout.source_photo_path
  ) then
    raise exception 'Remove the failed hatchery source photo before purging its layout';
  end if;

  delete from public.hatchery_layout where id = failed_layout.id;

  delete from public.hatchery
  where id = failed_layout.hatchery_id
    and layout_status = 'uploading'
    and not exists (
      select 1
      from public.hatchery_layout
      where hatchery_id = failed_layout.hatchery_id
    );
end;
$$;

-- A process can be terminated between Storage upload and finalization. A
-- service-role cleanup worker may safely retire old uploads; it must delete
-- each returned Storage object, then call `purge_failed_hatchery_layout`.
create or replace function public.expire_stale_hatchery_layouts(
  p_before timestamptz
)
returns setof public.hatchery_layout
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if auth.role() <> 'service_role' then
    raise exception 'Only the service role may expire stale hatchery layouts';
  end if;

  if p_before is null or p_before > now() - interval '15 minutes' then
    raise exception 'Stale hatchery layouts must be at least 15 minutes old';
  end if;

  return query
  update public.hatchery_layout
  set state = 'failed',
      is_current = false
  where state = 'uploading'
    and created_at < p_before
  returning *;
end;
$$;

revoke all on function public.begin_hatchery_layout(
  uuid, uuid, text, double precision, double precision, bigint, bigint,
  public.hatchery_capture_mode, jsonb, jsonb, jsonb, text
) from public, anon, authenticated;
revoke all on function public.begin_new_hatchery_layout(
  uuid, uuid, text, double precision, double precision, bigint, bigint,
  public.hatchery_capture_mode, jsonb, jsonb, jsonb, text
) from public, anon, authenticated;
revoke all on function public.finalize_hatchery_layout(
  uuid, text, bigint, integer, integer
) from public, anon, authenticated;
revoke all on function public.abandon_hatchery_layout(uuid) from public, anon, authenticated;
revoke all on function public.purge_failed_hatchery_layout(uuid)
  from public, anon, authenticated;
revoke all on function public.expire_stale_hatchery_layouts(timestamptz)
  from public, anon, authenticated;

grant execute on function public.begin_hatchery_layout(
  uuid, uuid, text, double precision, double precision, bigint, bigint,
  public.hatchery_capture_mode, jsonb, jsonb, jsonb, text
) to authenticated;
grant execute on function public.begin_new_hatchery_layout(
  uuid, uuid, text, double precision, double precision, bigint, bigint,
  public.hatchery_capture_mode, jsonb, jsonb, jsonb, text
) to authenticated;
grant execute on function public.finalize_hatchery_layout(
  uuid, text, bigint, integer, integer
) to authenticated;
grant execute on function public.abandon_hatchery_layout(uuid) to authenticated;
grant execute on function public.purge_failed_hatchery_layout(uuid) to authenticated, service_role;
grant execute on function public.expire_stale_hatchery_layouts(timestamptz) to service_role;

-- Extend the existing placement trigger with an active-cell guard whenever a
-- current persisted layout exists. Legacy hatcheries without a layout retain
-- the original rows/columns-only behavior until they are deliberately adopted.
create or replace function public.nest_placement_within_hatchery()
returns trigger
language plpgsql
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

-- Operations on iotdata, inspection, and device still have their own
-- development policies. They are intentionally out of this migration's scope;
-- do not treat this layout-specific auth cutover as a complete project-wide
-- authorization audit.
