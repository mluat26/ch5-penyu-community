-- Behaviour check for 20260816010000_add_organization_membership_and_invites.
--
-- Run against a local stack:
--   docker exec -i supabase_db_ch5-penyu-community \
--     psql -U postgres -d postgres -v ON_ERROR_STOP=1 \
--     < supabase/tests/organization_invite_test.sql
--
-- Every assertion raises on failure, so a clean run means the whole flow —
-- auto-created organization, manager-only invites, single use, and expiry —
-- still holds. The transaction is rolled back, so it leaves no rows behind.

begin;

create or replace function pg_temp.become(user_id uuid)
returns void language plpgsql as $$
begin
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims', json_build_object('sub', user_id)::text, true);
end;
$$;

-- Back to the owning role. Needed whenever the test has to change data that
-- RLS deliberately protects — as `authenticated`, such an update silently
-- matches zero rows instead of failing, which quietly invalidates a check.
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
  founder uuid := gen_random_uuid();
  joiner  uuid := gen_random_uuid();
  outsider uuid := gen_random_uuid();
  hatchery_id uuid := gen_random_uuid();
  org_id uuid;
  invite_code text;
  invite_expires timestamptz;
  redeemed_org uuid;
  second_code text;
  visible_count integer;
begin
  insert into auth.users (id, instance_id, aud, role, email, created_at, updated_at)
  values
    (founder,  '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'founder@test.local',  now(), now()),
    (joiner,   '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'joiner@test.local',   now(), now()),
    (outsider, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'outsider@test.local', now(), now());

  -- 1. Creating a hatchery creates the organization and makes the owner manager
  insert into public.hatchery
    (id, name, shape, number_of_row, number_of_collumn, length_m, width_m, layout_status, owner_id)
  values
    (hatchery_id, 'Hatch_01', 'rectangle', 4, 4, 5, 4, 'ready', founder);

  select organization_id into org_id from public.hatchery where id = hatchery_id;
  perform pg_temp.check(org_id is not null, 'hatchery gets an organization_id');

  perform pg_temp.check(
    exists (select 1 from public.profile where id = founder and organization_id = org_id and role = 'manager'),
    'hatchery creator becomes a manager of the new organization'
  );

  perform pg_temp.check(
    (select code from public.organization where id = org_id) like 'ORG-%',
    'organization gets a human-readable ORG- code'
  );

  -- 2. A second hatchery reuses the same organization rather than making another
  insert into public.hatchery
    (id, name, shape, number_of_row, number_of_collumn, length_m, width_m, layout_status, owner_id)
  values
    (gen_random_uuid(), 'Hatch_02', 'rectangle', 3, 3, 3, 3, 'ready', founder);

  perform pg_temp.check(
    (select count(*) from public.organization where owner_id = founder) = 1,
    'a second hatchery reuses the existing organization'
  );

  -- 3. A manager can generate an invite; a non-member cannot
  perform pg_temp.become(founder);
  select code, expires_at into invite_code, invite_expires
  from public.generate_organization_invite();

  perform pg_temp.check(length(invite_code) = 4, 'invite code is 4 characters');
  perform pg_temp.check(invite_code !~ '[01OI]', 'invite code avoids look-alike characters');
  perform pg_temp.check(
    invite_expires between now() + interval '9 minutes' and now() + interval '11 minutes',
    'invite expires in about 10 minutes'
  );

  perform pg_temp.become(outsider);
  begin
    perform public.generate_organization_invite();
    raise exception 'FAILED: a user with no organization generated an invite';
  exception when others then
    if sqlerrm like 'FAILED:%' then raise; end if;
    raise notice 'ok: a user with no organization cannot generate an invite';
  end;

  -- 4. Redeeming joins the organization, and only once
  perform pg_temp.become(joiner);
  select public.redeem_organization_invite(invite_code) into redeemed_org;
  perform pg_temp.check(redeemed_org = org_id, 'redeeming returns the organization joined');
  perform pg_temp.check(
    exists (select 1 from public.profile where id = joiner and organization_id = org_id and role = 'agent'),
    'a redeemer joins as an agent'
  );

  perform pg_temp.become(outsider);
  begin
    perform public.redeem_organization_invite(invite_code);
    raise exception 'FAILED: an invite code was redeemed twice';
  exception when others then
    if sqlerrm like 'FAILED:%' then raise; end if;
    raise notice 'ok: an invite code cannot be redeemed twice';
  end;

  -- 5. Case and whitespace are forgiving, but expiry is not
  perform pg_temp.become(founder);
  select code into second_code from public.generate_organization_invite();

  perform pg_temp.become_admin();
  update public.organization_invite
    set expires_at = now() - interval '1 minute'
    where code = second_code;
  perform pg_temp.check(
    (select expires_at from public.organization_invite where code = second_code) < now(),
    'test setup actually expired the invite'
  );

  perform pg_temp.become(outsider);
  begin
    perform public.redeem_organization_invite(lower(second_code));
    raise exception 'FAILED: an expired invite code was accepted';
  exception when others then
    if sqlerrm like 'FAILED:%' then raise; end if;
    raise notice 'ok: an expired invite code is refused';
  end;

  -- 6. A joined member can see the organization's hatcheries; an outsider cannot
  perform pg_temp.become(joiner);
  select count(*) into visible_count from public.hatchery;
  perform pg_temp.check(visible_count = 2, 'a joined member sees the organization hatcheries');

  perform pg_temp.become(outsider);
  select count(*) into visible_count from public.hatchery;
  perform pg_temp.check(visible_count = 0, 'a non-member sees no hatcheries');

  perform pg_temp.become_admin();
  raise notice 'ALL CHECKS PASSED';
end
$$;

rollback;
