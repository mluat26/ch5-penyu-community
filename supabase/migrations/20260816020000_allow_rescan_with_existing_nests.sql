-- Allow re-scanning a hatchery that already contains nests.
--
-- `finalize_hatchery_layout` refused any geometry change once a hatchery had
-- nests, and a rescan always produces a new photo, boundary, and sand region.
-- The effect was that a hatchery could never be re-photographed after its
-- first nest was recorded.
--
-- A nest stores its position as grid coordinates (`placement_row` /
-- `placement_col`), not as a point on the image, so a new photo does not move
-- any nest. The only change that genuinely invalidates one is a grid that
-- shrinks past it, which is what this now refuses — the same invariant the
-- `hatchery_grid_change_is_safe` trigger already enforces on the table.

CREATE OR REPLACE FUNCTION public.finalize_hatchery_layout(p_layout_id uuid, p_source_photo_mime_type text DEFAULT NULL::text, p_source_photo_bytes bigint DEFAULT NULL::bigint, p_source_photo_width integer DEFAULT NULL::integer, p_source_photo_height integer DEFAULT NULL::integer)
 RETURNS SETOF hatchery_layout
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
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

  -- A nest's position is stored as grid coordinates (placement_row /
  -- placement_col), not as a point on the photo. Re-photographing therefore
  -- leaves every nest valid: only a grid that shrinks past an existing nest
  -- actually invalidates one, so that is all this refuses. Matches the 0-based
  -- convention used by hatchery_grid_change_is_safe.
  if has_nests and exists (
    select 1
    from public.nest
    where nest.hatchery_id = pending.hatchery_id
      and (
        nest.placement_row >= pending.grid_rows
        or nest.placement_col >= pending.grid_columns
      )
  ) then
    raise exception 'Cannot shrink a hatchery grid while it contains nests outside the new grid. Remap those nests before re-scanning.';
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
$function$

;
