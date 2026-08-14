-- A composite variable is one column when selected (`select layout_row`), but
-- these RPCs return SETOF public.hatchery_layout and therefore need to emit the
-- composite as a row. `RETURN NEXT` performs that expansion correctly.

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
    return next existing;
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

  return next existing;
  return;
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
    return next pending;
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

  return next pending;
  return;
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
    return next pending;
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

  return next pending;
  return;
end;
$$;
