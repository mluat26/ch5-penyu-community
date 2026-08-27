-- Behaviour check for staged per-device IoT authentication.

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
  v_owner_id uuid := gen_random_uuid();
  v_hatchery_id uuid := gen_random_uuid();
  v_nest_id uuid := gen_random_uuid();
  v_device_id uuid := gen_random_uuid();
  v_secret text;
  v_reading public.iotdata;
  wrong_secret_rejected boolean := false;
  disabled_secret_rejected boolean := false;
begin
  insert into auth.users (
    id, instance_id, aud, role, email, created_at, updated_at
  ) values (
    v_owner_id, '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'ingest-auth@test.local', now(), now()
  );

  insert into public.hatchery (
    id, name, shape, number_of_row, number_of_collumn,
    length_m, width_m, layout_status, owner_id
  ) values (
    v_hatchery_id, 'Ingest auth', 'rectangle', 1, 1,
    1, 1, 'ready', v_owner_id
  );

  insert into public.nest (
    id, hatchery_id, placement_row, placement_col,
    number_of_eggs, date_eggs_laid
  ) values (
    v_nest_id, v_hatchery_id, 0, 0, 100, current_date
  );

  insert into public.device (id, name, owner_id)
  values (v_device_id, 'Authenticated logger', v_owner_id);

  insert into public.device_assignment (
    device_id, nest_id, assigned_by
  ) values (
    v_device_id, v_nest_id, v_owner_id
  );

  perform set_config(
    'request.jwt.claims',
    json_build_object('role', 'service_role')::text,
    true
  );

  v_secret := public.rotate_device_ingest_secret(v_device_id);
  perform pg_temp.check(length(v_secret) = 64, 'rotation returns one strong device secret');
  perform pg_temp.check(
    (select secret_hash <> v_secret
     from private.device_ingest_credential
     where device_id = v_device_id),
    'only a hash is stored'
  );

  begin
    perform public.ingest_iot_reading_authenticated(
      v_device_id, repeat('0', 64), 29.5
    );
  exception when invalid_authorization_specification then
    wrong_secret_rejected := true;
  end;
  perform pg_temp.check(wrong_secret_rejected, 'a wrong secret is rejected');

  v_reading := public.ingest_iot_reading_authenticated(
    v_device_id, v_secret, 29.5, null, null, 45,
    'none', 'online', 4.1, -67
  );
  perform pg_temp.check(v_reading.nest_id = v_nest_id, 'a valid reading follows its assignment');

  perform public.disable_device_ingest_secret(v_device_id);
  begin
    perform public.ingest_iot_reading_authenticated(
      v_device_id, v_secret, 29.6
    );
  exception when invalid_authorization_specification then
    disabled_secret_rejected := true;
  end;
  perform pg_temp.check(disabled_secret_rejected, 'a disabled secret is rejected');

  raise notice 'ALL CHECKS PASSED';
end
$$;

rollback;
