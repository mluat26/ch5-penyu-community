-- Put a name and a time against both halves of a nest's record.
--
-- The post-hatch nest detail screen ends its Info tab with an accountability
-- block:
--
--     Nest collection   Pak Wayan   Manager   Jan 1, 2026 | 03:00
--     Hatching          Made Sari   Officer   Mar 1, 2026 | 10:00
--
-- Four of those six cells already resolve. The names come from founder_id and
-- the profile read policy added in 20260817010000, the roles from that same
-- profile row, and the hatching timestamp from hatching.created_at. The two
-- missing ones are when the nest was recorded, and who recorded the hatch.
--
-- This is conservation data that gets reported upward. A hatch tally with
-- nobody's name against it is a number no one can follow up on.

-- ---------------------------------------------------------------------------
-- 1. When the nest was recorded.
-- ---------------------------------------------------------------------------
--
-- Deliberately nullable rather than `not null default now()`.
--
-- A default would stamp today onto every nest already in the table, including
-- ones collected months ago, and this is an audit column: a fabricated
-- timestamp in it is worse than an absent one, because it looks like evidence.
-- Existing rows stay NULL and the screen shows nothing for them, which is the
-- truth. Same reasoning that left legacy hatchery.owner_id NULL in
-- 20260814093000 instead of guessing an owner.
--
-- date_eggs_laid is not a substitute: that is when the eggs were laid in the
-- field, which is what the ranger reports, not when the row was written.

alter table public.nest
  add column if not exists created_at timestamptz default now();

-- ---------------------------------------------------------------------------
-- 2. Who recorded the hatch.
-- ---------------------------------------------------------------------------
--
-- Nullable for the same reason: the hatching rows that predate this column
-- have no recorder, and inventing one would defeat the point of the column.
--
-- ON DELETE SET NULL, not RESTRICT. Deleting an account must not be blocked by
-- the hatch records that account wrote -- delete_my_account already exists and
-- the tally is the organization's record, not the person's. The name is lost;
-- the conservation figures survive.

alter table public.hatching
  add column if not exists recorded_by uuid
    references auth.users(id) on delete set null;

-- ---------------------------------------------------------------------------
-- 3. The server decides who wrote it, not the client.
-- ---------------------------------------------------------------------------
--
-- If Swift supplied recorded_by, anyone holding the anon key could write a row
-- attributing a hatch to a colleague. auth.uid() is read from the JWT Postgres
-- has already verified, so it cannot be forged. This is the same shape as
-- assign_hatchery_owner in 20260814093000.
--
-- Two differences from that function, both deliberate:
--
--   * A null uid does not raise. The RLS policy on hatching already routes
--     through owns_nest(), which denies an anonymous caller outright, so an
--     unauthenticated insert cannot reach this trigger through the API at all.
--     Raising here would only break service_role work -- seeds, backfills, and
--     the SQL tests -- which legitimately runs without a uid.
--
--   * A correction does not reassign the record. Whoever recorded the hatch
--     recorded it; someone editing the counts afterwards does not become its
--     author. hatching.created_at is likewise left alone, so the pair keeps
--     meaning "recorded by X at T" rather than drifting to the last edit.

create or replace function public.assign_hatching_recorder()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  if tg_op = 'INSERT' then
    if new.recorded_by is null then
      new.recorded_by := auth.uid();
    end if;
    return new;
  end if;

  -- UPDATE: the recorder is fixed once written.
  new.recorded_by := old.recorded_by;
  return new;
end;
$$;

drop trigger if exists assign_hatching_recorder on public.hatching;
create trigger assign_hatching_recorder
  before insert or update on public.hatching
  for each row execute function public.assign_hatching_recorder();

-- No RLS work. Both tables already carry row-scoped owner policies -- nest via
-- the owner checks from 20260814093000, hatching via owns_nest() from
-- 20260815061500 -- and a policy grants a row, not a column, so these are
-- covered the moment they exist.
--
-- No index on recorded_by either: it is read one row at a time, by nest, when
-- a detail screen opens. A lookup of "everything this person recorded" is not
-- a query the app makes.
