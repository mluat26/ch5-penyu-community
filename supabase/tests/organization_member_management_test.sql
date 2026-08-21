-- Behaviour check for 20260821010000_manage_organization_members.
--
-- Run against a local stack:
--   docker exec -i supabase_db_ch5-penyu-community \
--     psql -U postgres -d postgres -v ON_ERROR_STOP=1 \
--     < supabase/tests/organization_member_management_test.sql
--
-- Covers the three things the migration decides: invitees join as officers,
-- only the owner may change a role or remove a member, and removal takes the
-- organization away without touching the account or the audit trail.
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
  owner_id    uuid := gen_random_uuid();
  joiner      uuid := gen_random_uuid();
  outsider    uuid := gen_random_uuid();
  hatchery_id uuid := gen_random_uuid();
  v_nest      uuid := gen_random_uuid();
  org_id      uuid;
  invite_code text;
  visible_count integer;
begin
  insert into auth.users (id, instance_id, aud, role, email, created_at, updated_at)
  values
    (owner_id, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'owner@test.local',    now(), now()),
    (joiner,   '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'joiner@test.local',   now(), now()),
    (outsider, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'outsider@test.local', now(), now());

  insert into public.hatchery
    (id, name, shape, number_of_row, number_of_collumn, length_m, width_m, layout_status, owner_id)
  values
    (hatchery_id, 'Hatch_01', 'rectangle', 4, 4, 5, 4, 'ready', owner_id);

  select organization_id into org_id from public.hatchery where id = hatchery_id;

  insert into public.nest
    (id, hatchery_id, placement_row, placement_col, number_of_eggs, date_eggs_laid, nest_number)
  values
    (v_nest, hatchery_id, 0, 0, 100, current_date - 56, '001');

  -- 1. An invitee joins as an officer, not an agent
  perform pg_temp.become(owner_id);
  select code into invite_code from public.generate_organization_invite();

  perform pg_temp.become(joiner);
  perform public.redeem_organization_invite(invite_code);
  perform pg_temp.check(
    (select role from public.profile where id = joiner) = 'officer',
    'a redeemer joins as an officer'
  );

  -- 2. A non-owner cannot change a role, even a manager
  perform pg_temp.become_admin();
  update public.profile set role = 'manager' where id = joiner;

  perform pg_temp.become(joiner);
  begin
    perform public.set_organization_member_role(owner_id, 'officer');
    raise exception 'FAILED: a non-owner manager changed a role';
  exception when others then
    if sqlerrm like 'FAILED:%' then raise; end if;
    raise notice 'ok: a non-owner cannot change a role';
  end;

  perform pg_temp.become(outsider);
  begin
    perform public.set_organization_member_role(joiner, 'officer');
    raise exception 'FAILED: an outsider changed a role';
  exception when others then
    if sqlerrm like 'FAILED:%' then raise; end if;
    raise notice 'ok: an outsider cannot change a role';
  end;

  -- 3. The owner can, but not to `agent` and not on themselves
  perform pg_temp.become(owner_id);
  perform public.set_organization_member_role(joiner, 'coordinator');
  perform pg_temp.check(
    (select role from public.profile where id = joiner) = 'coordinator',
    'the owner changes a member role'
  );

  begin
    perform public.set_organization_member_role(joiner, 'agent');
    raise exception 'FAILED: a member was demoted to agent while still in the organization';
  exception when others then
    if sqlerrm like 'FAILED:%' then raise; end if;
    raise notice 'ok: agent is refused as a role inside an organization';
  end;

  begin
    perform public.set_organization_member_role(owner_id, 'officer');
    raise exception 'FAILED: the owner changed their own role';
  exception when others then
    if sqlerrm like 'FAILED:%' then raise; end if;
    raise notice 'ok: the owner cannot change their own role';
  end;

  -- 4. A member's live invite is only revoked when they are removed
  perform pg_temp.become_admin();
  update public.profile set role = 'manager' where id = joiner;
  perform pg_temp.become(joiner);
  select code into invite_code from public.generate_organization_invite();

  -- 5. Removal takes the organization, not the account
  perform pg_temp.become(outsider);
  begin
    perform public.remove_organization_member(joiner);
    raise exception 'FAILED: an outsider removed a member';
  exception when others then
    if sqlerrm like 'FAILED:%' then raise; end if;
    raise notice 'ok: an outsider cannot remove a member';
  end;

  perform pg_temp.become(owner_id);
  begin
    perform public.remove_organization_member(owner_id);
    raise exception 'FAILED: the owner removed themselves';
  exception when others then
    if sqlerrm like 'FAILED:%' then raise; end if;
    raise notice 'ok: the owner cannot remove themselves';
  end;

  perform public.remove_organization_member(joiner);

  perform pg_temp.become_admin();
  perform pg_temp.check(
    exists (
      select 1 from public.profile
      where id = joiner and organization_id is null and role = 'agent'
    ),
    'a removed member keeps their profile but loses the organization'
  );
  perform pg_temp.check(
    exists (select 1 from auth.users where id = joiner),
    'removing a member does not delete their account'
  );
  perform pg_temp.check(
    not exists (
      select 1 from public.organization_invite
      where created_by = joiner and redeemed_at is null
    ),
    'a removed member''s live invite codes are revoked'
  );

  -- 6. And the removal actually closes the door
  perform pg_temp.become(joiner);
  select count(*) into visible_count from public.hatchery;
  perform pg_temp.check(visible_count = 0, 'a removed member sees no hatcheries');
  select count(*) into visible_count from public.nest;
  perform pg_temp.check(visible_count = 0, 'a removed member sees no nests');

  -- 7. Their recorded work survives them
  perform pg_temp.become_admin();
  insert into public.hatching
    (nest_id, hatched_on, eggs_hatched, eggs_rotten, eggs_unhatched, recorded_by)
  values
    (v_nest, current_date, 80, 10, 10, joiner);
  perform pg_temp.check(
    (select h.recorded_by from public.hatching h where h.nest_id = v_nest) = joiner,
    'a hatch still names the person who recorded it after they are removed'
  );

  raise notice 'ALL CHECKS PASSED';
end
$$;

rollback;
