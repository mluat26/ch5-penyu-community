-- Hatchery names are unique per owner after trimming outer whitespace and
-- ignoring case. Existing deployments may already contain legacy/test
-- duplicates, so this guard preserves those historical rows while preventing
-- any new duplicate insert, rename, or owner adoption.
--
-- The advisory lock is essential: a plain trigger-level EXISTS check is not
-- atomic across two concurrent transactions. The lock serializes only equal
-- owner/name pairs; hash collisions merely serialize unrelated writes and
-- cannot cause a false duplicate error.

create or replace function public.enforce_hatchery_owner_unique_name()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  normalized_name text;
begin
  if new.owner_id is null or new.name is null then
    return new;
  end if;

  normalized_name := pg_catalog.lower(pg_catalog.btrim(new.name));
  if normalized_name = '' then
    return new;
  end if;

  if tg_op = 'UPDATE'
     and new.owner_id is not distinct from old.owner_id
     and normalized_name is not distinct from pg_catalog.lower(pg_catalog.btrim(old.name)) then
    return new;
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtext(new.owner_id::text),
    pg_catalog.hashtext(normalized_name)
  );

  if exists (
    select 1
    from public.hatchery as existing
    where existing.owner_id = new.owner_id
      and pg_catalog.lower(pg_catalog.btrim(existing.name)) = normalized_name
      and existing.id <> new.id
  ) then
    raise exception using
      errcode = '23505',
      message = 'Name already exists',
      detail = 'hatchery_owner_normalized_name_unique';
  end if;

  new.name := pg_catalog.btrim(new.name);
  return new;
end;
$$;

revoke all on function public.enforce_hatchery_owner_unique_name()
  from public, anon, authenticated;

drop trigger if exists enforce_hatchery_owner_unique_name on public.hatchery;

create trigger enforce_hatchery_owner_unique_name
before insert or update of name, owner_id on public.hatchery
for each row
execute function public.enforce_hatchery_owner_unique_name();
