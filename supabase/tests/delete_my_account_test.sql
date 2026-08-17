-- Behaviour check for 20260816040000_add_delete_my_account.
--
--   docker exec -i supabase_db_ch5-penyu-community \
--     psql -U postgres -d postgres -v ON_ERROR_STOP=1 \
--     < supabase/tests/delete_my_account_test.sql
--
-- The dangerous failure here is not "delete did not work" — it is deleting
-- somebody else's data, or a manager wiping a team's hatcheries on their way
-- out. Both are checked.

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
  solo uuid := gen_random_uuid();
  manager uuid := gen_random_uuid();
  joiner uuid := gen_random_uuid();
  bystander uuid := gen_random_uuid();
  solo_hatchery uuid := gen_random_uuid();
  manager_hatchery uuid := gen_random_uuid();
  bystander_hatchery uuid := gen_random_uuid();
  invite_code text;
begin
  insert into auth.users (id, instance_id, aud, role, email, created_at, updated_at)
  values
    (solo,      '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'solo@test.local',      now(), now()),
    (manager,   '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'manager@test.local',   now(), now()),
    (joiner,    '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'joiner@test.local',    now(), now()),
    (bystander, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'bystander@test.local', now(), now());

  insert into public.hatchery (id, name, shape, number_of_row, number_of_collumn, length_m, width_m, layout_status, owner_id)
  values
    (solo_hatchery,      'Solo',      'rectangle', 4, 4, 5, 4, 'ready', solo),
    (manager_hatchery,   'Team',      'rectangle', 4, 4, 5, 4, 'ready', manager),
    (bystander_hatchery, 'Untouched', 'rectangle', 4, 4, 5, 4, 'ready', bystander);

  insert into public.nest (id, hatchery_id, placement_row, placement_col, number_of_eggs, date_eggs_laid)
  values (gen_random_uuid(), solo_hatchery, 1, 1, 12, current_date);

  -- 1. A solo account deletes cleanly, taking its own data with it.
  perform pg_temp.become(solo);
  perform public.delete_my_account();
  perform pg_temp.become_admin();

  perform pg_temp.check(
    not exists (select 1 from auth.users where id = solo),
    'a solo account is deleted'
  );
  perform pg_temp.check(
    not exists (select 1 from public.hatchery where owner_id = solo),
    'their hatcheries go with them'
  );
  perform pg_temp.check(
    not exists (select 1 from public.nest where hatchery_id = solo_hatchery),
    'their nests go with them'
  );
  perform pg_temp.check(
    not exists (select 1 from public.profile where id = solo),
    'their profile is gone'
  );

  -- 2. Nobody else is touched.
  perform pg_temp.check(
    exists (select 1 from auth.users where id = bystander),
    'an unrelated account survives'
  );
  perform pg_temp.check(
    exists (select 1 from public.hatchery where id = bystander_hatchery),
    'an unrelated hatchery survives'
  );

  -- 3. A manager whose organization has other members is refused, because
  --    deleting would take the team's hatcheries too.
  perform pg_temp.become(manager);
  select code into invite_code from public.generate_organization_invite();
  perform pg_temp.become(joiner);
  perform public.redeem_organization_invite(invite_code);

  perform pg_temp.become(manager);
  begin
    perform public.delete_my_account();
    raise exception 'FAILED: a manager deleted an organization other members had joined';
  exception when others then
    if sqlerrm like 'FAILED:%' then raise; end if;
    if sqlerrm not ilike '%member%' then
      raise exception 'FAILED: refused, but not because of the other member: %', sqlerrm;
    end if;
    raise notice 'ok: a manager with other members is refused (%)', sqlerrm;
  end;
  perform pg_temp.become_admin();

  perform pg_temp.check(
    exists (select 1 from public.hatchery where id = manager_hatchery),
    'the team hatchery survives the refused delete'
  );

  -- 4. The member who joined can still leave freely.
  perform pg_temp.become(joiner);
  perform public.delete_my_account();
  perform pg_temp.become_admin();

  perform pg_temp.check(
    not exists (select 1 from auth.users where id = joiner),
    'a joined member can delete their own account'
  );
  perform pg_temp.check(
    exists (select 1 from public.hatchery where id = manager_hatchery),
    'the organization keeps its hatcheries when a member leaves'
  );

  -- 5. And once alone again, the manager can delete.
  perform pg_temp.become(manager);
  perform public.delete_my_account();
  perform pg_temp.become_admin();

  perform pg_temp.check(
    not exists (select 1 from auth.users where id = manager),
    'the manager can delete once nobody else remains'
  );

  raise notice 'ALL CHECKS PASSED';
end
$$;

rollback;
