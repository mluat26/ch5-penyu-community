-- Behaviour check for 20260816030000_backfill_profiles_and_organizations.
--
--   docker exec -i supabase_db_ch5-penyu-community \
--     psql -U postgres -d postgres -v ON_ERROR_STOP=1 \
--     < supabase/tests/backfill_profiles_test.sql
--
-- Reproduces the reported failure: a hatchery that existed before the
-- membership trigger, whose owner therefore had no profile. The symptom was a
-- profile screen stuck on Role "Agent" / Organization ID "—" that silently
-- refused to save, because the update matched zero rows.

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

do $$
declare
  legacy_owner uuid := gen_random_uuid();
  hatchery_id uuid := gen_random_uuid();
  v_organization_id uuid;
  updated_rows integer;
begin
  -- Recreate the pre-migration world: an account and a hatchery with no
  -- profile and no organization. The auth.users trigger would normally make a
  -- profile, so it is removed to model an account that predates it.
  insert into auth.users (id, instance_id, aud, role, email, created_at, updated_at)
  values (legacy_owner, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'legacy@test.local', now(), now());

  insert into public.hatchery
    (id, name, shape, number_of_row, number_of_collumn, length_m, width_m, layout_status, owner_id)
  values
    (hatchery_id, 'Hatch_01', 'rectangle', 4, 4, 5, 4, 'ready', legacy_owner);

  update public.hatchery set organization_id = null where id = hatchery_id;
  delete from public.organization where owner_id = legacy_owner;
  delete from public.profile where id = legacy_owner;

  perform pg_temp.check(
    not exists (select 1 from public.profile where id = legacy_owner),
    'reproduced the broken state: hatchery owner with no profile'
  );

  -- Saving a name in this state is exactly what the app was doing, and it
  -- changes nothing at all — the bug the user hit.
  update public.profile set display_name = 'Andrian' where id = legacy_owner;
  get diagnostics updated_rows = row_count;
  perform pg_temp.check(updated_rows = 0, 'editing the profile silently did nothing');

  -- Now run what the migration does.
  insert into public.profile (id)
  select u.id from auth.users u
  where not exists (select 1 from public.profile p where p.id = u.id)
  on conflict (id) do nothing;

  select organization_id into v_organization_id from public.profile where id = legacy_owner;
  if v_organization_id is null then
    insert into public.organization (name, owner_id, code, date_created)
    values ('Hatch_01 organization', legacy_owner, public.generate_organization_code(), current_date)
    returning id into v_organization_id;

    insert into public.profile (id, organization_id, role)
    values (legacy_owner, v_organization_id, 'manager')
    on conflict (id) do update
      set organization_id = excluded.organization_id, role = 'manager';
  end if;

  update public.hatchery h
  set organization_id = p.organization_id
  from public.profile p
  where h.owner_id = p.id and h.organization_id is null and p.organization_id is not null;

  -- The state the profile screen needs.
  perform pg_temp.check(
    exists (select 1 from public.profile where id = legacy_owner and role = 'manager'),
    'the existing hatchery owner becomes a manager'
  );
  perform pg_temp.check(
    (select code from public.organization where id = v_organization_id) like 'ORG-%',
    'they get a readable organization code instead of a dash'
  );
  perform pg_temp.check(
    (select organization_id from public.hatchery where id = hatchery_id) = v_organization_id,
    'their existing hatchery joins that organization'
  );

  -- And editing now actually writes.
  update public.profile set display_name = 'Andrian' where id = legacy_owner;
  get diagnostics updated_rows = row_count;
  perform pg_temp.check(updated_rows = 1, 'editing the profile now saves');
  perform pg_temp.check(
    (select display_name from public.profile where id = legacy_owner) = 'Andrian',
    'the saved name reads back'
  );

  raise notice 'ALL CHECKS PASSED';
end
$$;

rollback;
