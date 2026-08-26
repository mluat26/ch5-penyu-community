-- One nest reporting 35 degrees, to make the "Temperature out of range" alert
-- fire on Andrian Ang's hatchery.
--
-- 35 is above the app's 33 degree ceiling (`NestDashboardItem.incubationRange`),
-- so the dashboard shows the red bar and the nest appears in the list it opens.
--
-- Every lookup raises rather than defaulting, so this cannot quietly seed a
-- different account's hatchery.

do $$
declare
  v_owner_id    uuid;
  v_hatchery_id uuid;
  v_nest_id     uuid;
  v_device_id   uuid;
  v_hatchery_owner uuid;
  v_row         bigint;
  v_col         bigint;
begin
  select p.id into v_owner_id
  from public.profile p
  where p.display_name ilike '%andrian%'
  order by p.created_at desc
  limit 1;

  if v_owner_id is null then
    raise exception 'No profile whose display_name looks like "Andrian".'
      using hint = 'Set it first: update public.profile set display_name = ''Andrian Ang'' where id = ''<your-user-id>'';';
  end if;

  -- Owned, or reachable through the organization. An Officer is a member
  -- rather than an owner, so requiring ownership found nothing for exactly the
  -- account this is meant to seed. Own hatcheries are preferred when both
  -- exist, so a manager still seeds their own.
  select h.id into v_hatchery_id
  from public.hatchery h
  join public.profile me on me.id = v_owner_id
  where h.layout_status = 'ready'
    and (
      h.owner_id = v_owner_id
      or (
        h.organization_id is not null
        and h.organization_id = me.organization_id
      )
    )
  order by (h.owner_id = v_owner_id) desc, h.created_at desc nulls last
  limit 1;

  if v_hatchery_id is null then
    raise exception
      'That account can reach no hatchery with layout_status = ''ready''.'
      using hint = 'It owns none, and its profile.organization_id matches none.';
  end if;

  -- The logger has to belong to whoever owns the hatchery, not to whoever is
  -- seeding. `validate_device_assignment` refuses a device assigned to a nest
  -- owned by a different user, which is what an Officer seeding into their
  -- manager's hatchery would otherwise produce.
  select h.owner_id into v_hatchery_owner
  from public.hatchery h
  where h.id = v_hatchery_id;

  -- A cell inside the traced sand and not already taken.
  -- `validate_nest_placement` refuses anything outside the sand mask, so the
  -- placement is read from the layout rather than generated.
  select cell."row", cell."column"
  into v_row, v_col
  from public.hatchery_layout layout,
       jsonb_to_recordset(layout.grid_json -> 'active_cells')
         as cell("row" bigint, "column" bigint)
  where layout.hatchery_id = v_hatchery_id
    and layout.is_current
    and not exists (
      select 1 from public.nest n
      where n.hatchery_id = v_hatchery_id
        and n.placement_row = cell."row"
        and n.placement_col = cell."column"
    )
  order by cell."row", cell."column"
  limit 1;

  if v_row is null then
    raise exception 'Every active cell in that hatchery already holds a nest.';
  end if;

  insert into public.nest (
    hatchery_id, founder_id, number_of_eggs,
    placement_row, placement_col, bucket_id,
    date_eggs_laid, date_predicted_hatch, next_inspection_date
  )
  values (
    v_hatchery_id, v_owner_id, 96,
    v_row, v_col, 'SEED-HOT',
    current_date - 12, current_date + 43, current_date + 2
  )
  returning id into v_nest_id;

  -- A reading needs a device, and `resolve_reading_nest` needs that device to
  -- have a live assignment -- it refuses any reading from an unassigned one.
  insert into public.device (name, owner_id, installed_at)
  values ('SEED-HOT', v_hatchery_owner, now())
  returning id into v_device_id;

  insert into public.device_assignment (device_id, nest_id, assigned_by)
  values (v_device_id, v_nest_id, v_owner_id);

  -- `nest_id` is deliberately not supplied: the trigger fills it from the
  -- assignment above, which is the path the firmware uses.
  insert into public.iotdata (sensor_id, temperature, battery_voltage, sensor_status)
  values (v_device_id, 35.0, 4.05, 'online');

  raise notice 'Seeded nest % at 35C in hatchery %', v_nest_id, v_hatchery_id;
end $$;

select
  p.display_name                                                as owner,
  h.name                                                        as hatchery,
  chr(65 + n.placement_col::int) || (n.placement_row + 1)::text as section,
  n.nest_number,
  round(i.temperature::numeric, 1)                              as celsius
from public.nest n
join public.hatchery h on h.id = n.hatchery_id
join public.profile p on p.id = h.owner_id
join public.iotdata i on i.nest_id = n.id
where n.bucket_id = 'SEED-HOT';
