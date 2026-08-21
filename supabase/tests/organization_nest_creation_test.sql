-- Behaviour check for 20260821020000_let_organization_members_add_nests.
--
-- Run against a database:
--   psql "$(cat supabase/.temp/pooler-url)" -v ON_ERROR_STOP=1 \
--     -f supabase/tests/organization_nest_creation_test.sql
--
-- The bug this pins: a member who could see a hatchery on every screen got
-- "hatchery <uuid> does not exist" when adding a nest to it, because the
-- integrity trigger's `for share` read applied the owner-only UPDATE policy.
-- Rolled back, so it leaves no rows behind.

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
  founder     uuid := gen_random_uuid();
  member      uuid := gen_random_uuid();
  outsider    uuid := gen_random_uuid();
  hatchery_id uuid := gen_random_uuid();
  v_nest      uuid;
  invite_code text;
  visible_rows integer;
begin
  insert into auth.users (id, instance_id, aud, role, email, created_at, updated_at)
  values
    (founder,  '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'founder@test.local',  now(), now()),
    (member,   '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'member@test.local',   now(), now()),
    (outsider, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'outsider@test.local', now(), now());

  insert into public.hatchery
    (id, name, shape, number_of_row, number_of_collumn, length_m, width_m, layout_status, owner_id)
  values
    (hatchery_id, 'Hatch_01', 'rectangle', 4, 4, 5, 4, 'ready', founder);

  perform pg_temp.become(founder);
  select code into invite_code from public.generate_organization_invite();
  perform pg_temp.become(member);
  perform public.redeem_organization_invite(invite_code);

  -- 1. The member can read the hatchery. This always worked, and is what made
  --    "does not exist" such a confusing thing to be told.
  select count(*) into visible_rows from public.hatchery where id = hatchery_id;
  perform pg_temp.check(visible_rows = 1, 'a member can read the organization hatchery');

  -- 2. The locking read the trigger performs. Before the fix this returned no
  --    rows for a member, because FOR SHARE also applies the UPDATE policy.
  select count(*) into visible_rows
  from (select 1 from public.hatchery where id = hatchery_id for share) as locked;
  perform pg_temp.check(
    visible_rows = 1,
    'a member''s locking read of the hatchery still finds it'
  );

  -- 3. The whole point: a member can register a nest.
  insert into public.nest
    (hatchery_id, placement_row, placement_col, number_of_eggs, date_eggs_laid, founder_id)
  values
    (hatchery_id, 1, 1, 100, current_date, member)
  returning id into v_nest;
  perform pg_temp.check(v_nest is not null, 'a member can create a nest');

  perform pg_temp.check(
    (select nest_number from public.nest where id = v_nest) is not null,
    'the numbering trigger still runs for a member''s nest'
  );

  -- 4. And correct it afterwards.
  update public.nest set number_of_eggs = 90 where id = v_nest;
  perform pg_temp.check(
    (select number_of_eggs from public.nest where id = v_nest) = 90,
    'a member can correct a nest'
  );

  -- 5. The grid guard still bites -- widening who may write must not widen
  --    what may be written.
  begin
    insert into public.nest
      (hatchery_id, placement_row, placement_col, number_of_eggs, date_eggs_laid)
    values
      (hatchery_id, 99, 99, 10, current_date);
    raise exception 'FAILED: a nest was placed outside the hatchery grid';
  exception when others then
    if sqlerrm like 'FAILED:%' then raise; end if;
    raise notice 'ok: placement outside the grid is still refused';
  end;

  -- 6. Deleting a nest is still the hatchery owner's alone.
  delete from public.nest where id = v_nest;
  perform pg_temp.check(
    exists (select 1 from public.nest where id = v_nest),
    'a member cannot delete a nest'
  );

  -- 7. An outsider is refused, and is not told the hatchery is missing --
  --    they simply cannot write to it.
  perform pg_temp.become(outsider);
  begin
    insert into public.nest
      (hatchery_id, placement_row, placement_col, number_of_eggs, date_eggs_laid)
    values
      (hatchery_id, 2, 2, 50, current_date);
    raise exception 'FAILED: an outsider created a nest';
  exception when others then
    if sqlerrm like 'FAILED:%' then raise; end if;
    perform pg_temp.check(
      sqlerrm not like '%does not exist%',
      'an outsider is refused as a permission error, not a missing hatchery'
    );
  end;

  perform pg_temp.become_admin();
  raise notice 'ALL CHECKS PASSED';
end
$$;

rollback;
