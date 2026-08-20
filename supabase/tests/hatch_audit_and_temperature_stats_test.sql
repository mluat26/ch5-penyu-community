-- Behaviour check for 20260820010000_record_who_logged_the_hatch and
-- 20260820020000_add_nest_temperature_stats.
--
--   docker exec -i supabase_db_ch5-penyu-community \
--     psql -U postgres -d postgres -v ON_ERROR_STOP=1 \
--     < supabase/tests/hatch_audit_and_temperature_stats_test.sql
--
-- Both migrations ship together and both make claims that are only true under
-- a real user session, so they are checked in one file under one.
--
-- The session is simulated the way PostgREST supplies it: set the role to
-- `authenticated` and put the user's id in request.jwt.claims, which is where
-- auth.uid() reads from. Running these checks as `postgres` would prove
-- nothing -- that role bypasses RLS and has no uid, so the recorder would come
-- out NULL and the ownership check would never run.
--
-- The two claims worth failing over:
--
--   * recorded_by is decided by the server. If the client could set it, a hatch
--     could be attributed to a colleague by anyone holding the publishable key.
--   * nest_temperature_stats is security invoker, so the iotdata policy still
--     applies. If it were definer it would happily average another
--     organization's readings for whoever asked.

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
  v_user_a    uuid := gen_random_uuid();
  v_user_b    uuid := gen_random_uuid();
  v_hatchery  uuid := gen_random_uuid();
  v_nest      uuid := gen_random_uuid();
  v_hatching  uuid := gen_random_uuid();
  v_device    uuid := gen_random_uuid();

  -- Readings placed to pin down both window edges at once.
  v_day_start timestamptz := '2026-06-20 00:00:00+00';
  v_midday    timestamptz := '2026-06-20 12:00:00+00';
  v_day_end   timestamptz := '2026-06-21 00:00:00+00';

  v_avg       double precision;
  v_max       double precision;
  v_min       double precision;
  v_created   timestamptz;
  v_recorder  uuid;
begin
  -- -------------------------------------------------------------------
  -- Setup, as postgres: RLS is bypassed and auth.uid() is NULL here, so
  -- everything that depends on a session happens further down.
  -- -------------------------------------------------------------------
  insert into auth.users (id, instance_id, aud, role, email, created_at, updated_at)
  values
    (v_user_a, '00000000-0000-0000-0000-000000000000',
     'authenticated', 'authenticated', 'owner@test.local', now(), now()),
    (v_user_b, '00000000-0000-0000-0000-000000000000',
     'authenticated', 'authenticated', 'stranger@test.local', now(), now());

  -- layout_status must be 'ready': owns_nest() requires it, so a hatchery
  -- still uploading its layout would deny every check below for the wrong
  -- reason and make this test look like a security pass.
  insert into public.hatchery
    (id, name, shape, number_of_row, number_of_collumn, length_m, width_m, layout_status, owner_id)
  values
    (v_hatchery, 'Hatch_Audit', 'rectangle', 5, 5, 5, 5, 'ready', v_user_a);

  insert into public.nest
    (id, hatchery_id, placement_row, placement_col, number_of_eggs, date_eggs_laid, nest_number)
  values
    (v_nest, v_hatchery, 0, 0, 100, current_date - 56, '001');

  -- Every reading must name the hardware that produced it
  -- (iotdata_sensor_id_required, 20260815170000).
  insert into public.device (id, name, owner_id)
  values (v_device, 'Logger_Test', v_user_a);

  -- No user role may write readings at all: 20260815170000 dropped the anon
  -- insert policy and revoked insert/update/delete from anon and authenticated,
  -- leaving ingest_iot_reading() -- service-role only -- as the way in. These
  -- go in here, as postgres, for the same reason.
  insert into public.iotdata (nest_id, sensor_id, "timestamp", temperature)
  values
    (v_nest, v_device, v_day_start, 26),
    (v_nest, v_device, v_midday,    30),
    (v_nest, v_device, v_day_end,   40);   -- exactly on the upper bound

  -- -------------------------------------------------------------------
  -- 1. nest.created_at is stamped for rows written from now on.
  -- -------------------------------------------------------------------
  select created_at into v_created from public.nest where id = v_nest;

  perform pg_temp.check(
    v_created is not null,
    'a nest recorded now carries a creation timestamp'
  );
  perform pg_temp.check(
    v_created between now() - interval '1 minute' and now() + interval '1 minute',
    'the creation timestamp is the moment the row was written'
  );

  -- The column is nullable on purpose, so nests predating the migration stay
  -- honestly blank rather than claiming to have been recorded today. An
  -- explicit NULL must therefore be accepted, not silently defaulted.
  update public.nest set created_at = null where id = v_nest;
  perform pg_temp.check(
    (select created_at is null from public.nest where id = v_nest),
    'creation time may be absent, for nests that predate the column'
  );
  update public.nest set created_at = now() where id = v_nest;

  -- -------------------------------------------------------------------
  -- Become user A, the hatchery owner. Everything below runs as a real
  -- session would.
  -- -------------------------------------------------------------------
  perform set_config(
    'request.jwt.claims',
    json_build_object('sub', v_user_a, 'role', 'authenticated')::text,
    true
  );
  perform set_config('role', 'authenticated', true);

  perform pg_temp.check(auth.uid() = v_user_a, 'the simulated session resolves to user A');

  -- -------------------------------------------------------------------
  -- 2. The recorder is stamped from the session, not sent by the client.
  -- -------------------------------------------------------------------
  insert into public.hatching
    (id, nest_id, hatched_on, eggs_hatched, eggs_rotten, eggs_unhatched)
  values
    (v_hatching, v_nest, current_date, 90, 5, 5);

  select recorded_by into v_recorder from public.hatching where id = v_hatching;
  perform pg_temp.check(
    v_recorder = v_user_a,
    'the hatch is attributed to the signed-in user without the client saying so'
  );

  -- -------------------------------------------------------------------
  -- 3. A client-supplied recorder does not win.
  --
  --    This is the attack the trigger exists for: the publishable key is
  --    public by design, so anyone can craft this update.
  -- -------------------------------------------------------------------
  update public.hatching
     set eggs_hatched = 80, eggs_rotten = 10, eggs_unhatched = 10,
         recorded_by  = v_user_b
   where id = v_hatching;

  perform pg_temp.check(
    (select recorded_by from public.hatching where id = v_hatching) = v_user_a,
    'a correction cannot reassign the hatch to somebody else'
  );
  perform pg_temp.check(
    (select eggs_hatched from public.hatching where id = v_hatching) = 80,
    'pinning the recorder does not block the correction itself'
  );

  -- -------------------------------------------------------------------
  -- 4. The temperature window is half-open: [from, to).
  --
  --    26 at midnight and 30 at midday are in; 40 sits exactly on the upper
  --    bound and is out. With `between` it would be counted, dragging the
  --    average to 32 and reporting the next day's first reading as today's
  --    high.
  -- -------------------------------------------------------------------
  select avg_c, max_c, min_c into v_avg, v_max, v_min
    from public.nest_temperature_stats(v_nest, v_day_start, v_day_end);

  perform pg_temp.check(v_avg = 28, 'the daily average covers only the readings inside the window');
  perform pg_temp.check(v_max = 30, 'a reading exactly on the upper bound is excluded');
  perform pg_temp.check(v_min = 26, 'a reading exactly on the lower bound is included');

  -- -------------------------------------------------------------------
  -- 5. An empty window reports nothing rather than zero.
  --
  --    0°C would render as a real measurement on a screen that has no way to
  --    tell the difference.
  -- -------------------------------------------------------------------
  select avg_c into v_avg
    from public.nest_temperature_stats(
      v_nest, v_day_start - interval '10 days', v_day_start - interval '9 days');

  perform pg_temp.check(v_avg is null, 'a window with no readings averages to NULL, not 0');

  -- -------------------------------------------------------------------
  -- 6. Another user gets nothing back.
  --
  --    The whole point of security invoker. User B is authenticated and may
  --    execute the function; they simply cannot see the rows. A definer
  --    function would answer this call with A's readings.
  -- -------------------------------------------------------------------
  perform set_config(
    'request.jwt.claims',
    json_build_object('sub', v_user_b, 'role', 'authenticated')::text,
    true
  );

  perform pg_temp.check(auth.uid() = v_user_b, 'the session now resolves to user B');

  select avg_c, max_c, min_c into v_avg, v_max, v_min
    from public.nest_temperature_stats(v_nest, v_day_start, v_day_end);

  perform pg_temp.check(
    v_avg is null and v_max is null and v_min is null,
    'a stranger averaging somebody else''s nest gets an empty window'
  );

  -- And cannot read the tally either, which is the policy this leans on.
  perform pg_temp.check(
    not exists (select 1 from public.hatching where id = v_hatching),
    'a stranger cannot read the hatch record behind those readings'
  );

  perform set_config('role', 'postgres', true);

  raise notice 'ALL CHECKS PASSED';
end
$$;

rollback;
