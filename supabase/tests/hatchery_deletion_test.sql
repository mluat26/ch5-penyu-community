-- Behaviour check for 20260822010000_let_an_owner_or_manager_delete_a_hatchery.
--
--   docker exec -i supabase_db_ch5-penyu-community \
--     psql -U postgres -d postgres -v ON_ERROR_STOP=1 \
--     < supabase/tests/hatchery_deletion_test.sql
--
-- A delete that quietly removes nothing looks identical to one that worked, so
-- every check here counts rows rather than trusting the statement to raise.

begin;

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
  owner_id uuid := gen_random_uuid();
  colleague uuid := gen_random_uuid();
  officer uuid := gen_random_uuid();
  outsider uuid := gen_random_uuid();
  team_hatchery uuid := gen_random_uuid();
  own_hatchery uuid := gen_random_uuid();
  scanning_hatchery uuid := gen_random_uuid();
  outsider_hatchery uuid := gen_random_uuid();
  the_nest uuid := gen_random_uuid();
  invite_code text;
  removed integer;
begin
  insert into auth.users (id, instance_id, aud, role, email, created_at, updated_at)
  values
    (owner_id,  '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'owner@test.local',     now(), now()),
    (colleague, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'colleague@test.local', now(), now()),
    (officer,   '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'officer@test.local',   now(), now()),
    (outsider,  '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'outsider@test.local',  now(), now());

  -- The insert trigger mints an organization and makes the owner its manager.
  insert into public.hatchery (id, name, shape, number_of_row, number_of_collumn, length_m, width_m, layout_status, owner_id)
  values
    (team_hatchery,     'Team',     'rectangle', 4, 4, 5, 4, 'ready',     owner_id),
    (own_hatchery,      'Second',   'rectangle', 4, 4, 5, 4, 'ready',     owner_id),
    (scanning_hatchery, 'Scanning', 'rectangle', 4, 4, 5, 4, 'uploading', owner_id),
    (outsider_hatchery, 'Theirs',   'rectangle', 4, 4, 5, 4, 'ready',     outsider);

  insert into public.nest (id, hatchery_id, placement_row, placement_col, number_of_eggs, date_eggs_laid)
  values (the_nest, team_hatchery, 1, 1, 12, current_date);

  -- Both join as officers; one is then promoted, so the manager under test is
  -- deliberately not the hatchery's owner.
  perform pg_temp.become(owner_id);
  select code into invite_code from public.generate_organization_invite();
  perform pg_temp.become(colleague);
  perform public.redeem_organization_invite(invite_code);

  perform pg_temp.become(owner_id);
  select code into invite_code from public.generate_organization_invite();
  perform pg_temp.become(officer);
  perform public.redeem_organization_invite(invite_code);

  perform pg_temp.become(owner_id);
  perform public.set_organization_member_role(colleague, 'manager');
  perform pg_temp.become_admin();

  perform pg_temp.check(
    (select role from public.profile where id = colleague) = 'manager',
    'the colleague is a manager'
  );
  perform pg_temp.check(
    (select role from public.profile where id = officer) = 'officer',
    'the officer is not'
  );

  -- 1. An officer in the organization removes nothing.
  perform pg_temp.become(officer);
  delete from public.hatchery where id = team_hatchery;
  get diagnostics removed = row_count;
  perform pg_temp.become_admin();
  perform pg_temp.check(removed = 0, 'an officer deletes no hatchery');
  perform pg_temp.check(
    exists (select 1 from public.hatchery where id = team_hatchery),
    'the team hatchery survives the officer'
  );

  -- 2. Somebody outside the organization removes nothing either.
  perform pg_temp.become(outsider);
  delete from public.hatchery where id = team_hatchery;
  get diagnostics removed = row_count;
  perform pg_temp.become_admin();
  perform pg_temp.check(removed = 0, 'an outsider deletes no hatchery');

  -- 3. The nest foreign key is the backstop, not the app.
  perform pg_temp.become(colleague);
  begin
    delete from public.hatchery where id = team_hatchery;
    raise exception 'FAILED: a hatchery holding a nest was deleted';
  exception when foreign_key_violation then
    raise notice 'ok: a hatchery holding a nest is refused';
  end;
  perform pg_temp.become_admin();

  -- 4. Emptied, the manager may delete it -- and the layout rows cascade.
  insert into public.hatchery_layout (
    id, hatchery_id, revision, created_by, state, is_current, capture_mode,
    name, length_m, width_m, grid_rows, grid_columns,
    boundary_json, sand_region_json, grid_json, processing_version
  )
  values (
    gen_random_uuid(), team_hatchery, 1, owner_id, 'ready', true, 'skipped',
    'Team', 5, 4, 4, 4, '{}'::jsonb, '{}'::jsonb, '{}'::jsonb, 'test'
  );

  delete from public.nest where id = the_nest;

  perform pg_temp.become(colleague);
  delete from public.hatchery where id = team_hatchery;
  get diagnostics removed = row_count;
  perform pg_temp.become_admin();
  perform pg_temp.check(removed = 1, 'a manager deletes an empty hatchery they do not own');
  perform pg_temp.check(
    not exists (select 1 from public.hatchery_layout where hatchery_id = team_hatchery),
    'its layout revisions cascade away'
  );

  -- 5. The owner may delete their own.
  perform pg_temp.become(owner_id);
  delete from public.hatchery where id = own_hatchery;
  get diagnostics removed = row_count;
  perform pg_temp.become_admin();
  perform pg_temp.check(removed = 1, 'an owner deletes their own hatchery');

  -- 6. A scan still in flight belongs to the layout lifecycle, not to this.
  perform pg_temp.become(owner_id);
  delete from public.hatchery where id = scanning_hatchery;
  get diagnostics removed = row_count;
  perform pg_temp.become_admin();
  perform pg_temp.check(removed = 0, 'a hatchery mid-scan is not deletable');

  -- 7. Nobody else was touched.
  perform pg_temp.check(
    exists (select 1 from public.hatchery where id = outsider_hatchery),
    'an unrelated hatchery survives'
  );

  -- 8. The photo paths answer to the same question as the delete.
  perform pg_temp.become(officer);
  perform pg_temp.check(
    not exists (select 1 from public.hatchery_layout_photo_paths(outsider_hatchery)),
    'an officer reads no photo paths for a hatchery they cannot delete'
  );
  perform pg_temp.become_admin();

  raise notice 'ALL CHECKS PASSED';
end
$$;

rollback;
