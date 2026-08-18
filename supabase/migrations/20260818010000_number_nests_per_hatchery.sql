-- Nest numbers are per hatchery and never handed out twice: Hatchery A's nest
-- 002 and Hatchery B's nest 002 are unrelated, but two nests inside one
-- hatchery cannot both be 002.
--
-- Bucket IDs are the opposite and stay unconstrained: a bucket is physical,
-- reused nest after nest, so repeats are expected rather than corrected.
--
-- The app numbers a new nest client-side (highest + 1) so the ranger sees the
-- number while filling the form. Two devices reading that maximum at the same
-- moment both compute the same value, so the server settles it: whichever
-- insert lands first keeps the number, and the later one is moved on to the
-- next free number rather than being rejected. A ranger standing on a beach
-- should never lose a filled-in form to a numbering clash.
--
-- The advisory lock is essential: an EXISTS check alone is not atomic across
-- two concurrent transactions. It serializes writes per hatchery only; a hash
-- collision merely serializes unrelated hatcheries and cannot misnumber.
--
-- No unique index accompanies this. Existing deployments may already hold
-- duplicate or hand-written numbers, and those historical rows are preserved
-- rather than blocking the migration -- the same choice
-- 20260815152000_prevent_duplicate_hatchery_names.sql made.

create or replace function public.assign_nest_number()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  requested        text;
  requested_bucket text;
  next_number      integer;
begin
  if new.hatchery_id is null then
    return new;
  end if;

  requested := pg_catalog.btrim(coalesce(new.nest_number, ''));
  requested_bucket := pg_catalog.btrim(coalesce(new.bucket_id, ''));

  -- Numeric numbers are stored in one canonical shape, so that '007' and
  -- '0007' cannot sit in the same hatchery looking distinct while meaning the
  -- same nest. `lpad` alone would truncate a hatchery that passes 999.
  if requested ~ '^[0-9]+$' then
    requested := case
      when requested::integer < 1000 then pg_catalog.lpad(requested::integer::text, 3, '0')
      else requested::integer::text
    end;
  end if;

  -- An update that leaves the number and the hatchery alone is not a clash
  -- with itself.
  if tg_op = 'UPDATE'
     and new.hatchery_id is not distinct from old.hatchery_id
     and requested is not distinct from pg_catalog.btrim(coalesce(old.nest_number, '')) then
    return new;
  end if;

  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext(new.hatchery_id::text));

  if requested <> '' and not exists (
    select 1
    from public.nest as existing
    where existing.hatchery_id = new.hatchery_id
      and pg_catalog.btrim(coalesce(existing.nest_number, '')) = requested
      and existing.id <> new.id
  ) then
    new.nest_number := requested;
  else
    -- Taken, or never supplied: continue this hatchery's own sequence. One
    -- past the highest ever issued, not a count, so a deleted nest's number is
    -- not reused by a later one. `case` rather than a `where` filter because
    -- the cast must not see non-numeric legacy values at all.
    select coalesce(
             max(
               case when existing.nest_number ~ '^[0-9]+$'
                    then existing.nest_number::integer
               end
             ),
             0
           ) + 1
      into next_number
      from public.nest as existing
     where existing.hatchery_id = new.hatchery_id
       and existing.id <> new.id;

    new.nest_number := case
      when next_number < 1000 then pg_catalog.lpad(next_number::text, 3, '0')
      else next_number::text
    end;
  end if;

  -- Bucket IDs are deliberately NOT unique and are never corrected. A bucket
  -- is a physical container: it is emptied and reused, so the same ID
  -- legitimately appears on many nests over time, and two nests sharing one is
  -- a fact about the beach rather than a clash to resolve. Only an absent one
  -- is filled in, standing in for the NFC tag payload until that is read.
  if requested_bucket = '' then
    new.bucket_id := new.nest_number;
  end if;

  return new;
end;
$$;

revoke all on function public.assign_nest_number() from public, anon, authenticated;

drop trigger if exists assign_nest_number on public.nest;

create trigger assign_nest_number
before insert or update of nest_number, hatchery_id on public.nest
for each row
execute function public.assign_nest_number();

-- Check after applying, against a hatchery id you own:
--
--   insert into public.nest (hatchery_id, number_of_eggs, nest_number, bucket_id)
--   values ('<hatchery-uuid>', 10, '007', 'B-12'),
--          ('<hatchery-uuid>', 10, '007', 'B-12')
--   returning nest_number, bucket_id;
--
-- The first row keeps 007, the second comes back with the next free number,
-- and both keep bucket B-12 -- one bucket, two nests.
