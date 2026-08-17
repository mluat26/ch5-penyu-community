-- Integrity hardening for public.nest and public.hatchery.
--
-- The pulled baseline let the database accept rows the app can never display:
-- nullable hatchery_id/placement, and DEFAULT gen_random_uuid() on foreign key
-- columns, so every nest silently received a founder_id pointing at nothing.
-- Nothing tied a nest's placement to its hatchery's grid either, so a nest
-- placed outside the grid inserted fine and then vanished from every section
-- while still counting toward the dashboard totals.
--
-- Scope is integrity only. Ownership, profiles, organization membership, and
-- per-user RLS still wait on authentication; the dev-only anon policy from
-- 20260813132557 remains in force and is still a launch blocker.
--
-- No existing row is modified or deleted. Verified before writing this: no
-- NULLs in the columns becoming NOT NULL, every hatchery has positive
-- dimensions, the only nest is within its grid, and iotdata is empty.

-- 1. Stop inventing data. Existing rows keep the values already generated;
--    this only governs future inserts.
alter table public.nest    alter column hatchery_id drop default;
alter table public.nest    alter column founder_id  drop default;
alter table public.iotdata alter column nest_id     drop default;
alter table public.iotdata alter column sensor_id   drop default;

-- 2. Required values. A nest with no hatchery or no placement cannot be shown.
alter table public.nest alter column hatchery_id   set not null;
alter table public.nest alter column placement_row set not null;
alter table public.nest alter column placement_col set not null;

-- HatcheryDTO.toEntity() already throws when any of these are missing, so the
-- app treats them as required; make the database agree.
alter table public.hatchery alter column name     set not null;
alter table public.hatchery alter column shape    set not null;
alter table public.hatchery alter column length_m set not null;
alter table public.hatchery alter column width_m  set not null;

-- 3. Value sanity, mirroring validation the app already performs in
--    NestService.createNest and HatcheryService.createHatchery.
alter table public.nest add constraint nest_placement_non_negative
  check (placement_row >= 0 and placement_col >= 0);

alter table public.nest add constraint nest_number_of_eggs_positive
  check (number_of_eggs > 0);

alter table public.hatchery add constraint hatchery_dimensions_positive
  check (number_of_row > 0 and number_of_collumn > 0
         and length_m > 0 and width_m > 0);

-- 4. A reading must belong to a real nest, and dies with it. Telemetry is
--    derived data: unlike nests, it carries nothing worth keeping once its
--    subject is gone.
--
--    NOT VALID because iotdata already holds at least one orphan reading whose
--    nest_id was never a real nest. The constraint is still enforced on every
--    future insert and update; it only skips checking rows that predate it.
--    Those rows are invisible to the app: the anon policy on this table grants
--    INSERT and nothing else, so nothing can read or delete them without
--    elevated access. Once they are cleaned up, promote this with:
--        alter table public.iotdata validate constraint iotdata_nest_id_fkey;
alter table public.iotdata add constraint iotdata_nest_id_fkey
  foreign key (nest_id) references public.nest(id) on delete cascade
  not valid;

-- 5. Placement must land inside its hatchery's grid. A CHECK constraint cannot
--    express this because it cannot reference another table, so it is a
--    trigger. Fires on future writes only; it does not re-validate existing
--    rows.
create or replace function public.nest_placement_within_hatchery()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
declare
  grid_rows bigint;
  grid_cols bigint;
begin
  select number_of_row, number_of_collumn
    into grid_rows, grid_cols
    from public.hatchery
   where id = new.hatchery_id;

  if not found then
    raise exception 'hatchery % does not exist', new.hatchery_id;
  end if;

  if new.placement_row >= grid_rows or new.placement_col >= grid_cols then
    raise exception
      'nest placement (%, %) is outside the % x % grid of hatchery %',
      new.placement_row, new.placement_col, grid_rows, grid_cols,
      new.hatchery_id;
  end if;

  return new;
end;
$$;

create trigger nest_placement_within_hatchery
  before insert or update on public.nest
  for each row
  execute function public.nest_placement_within_hatchery();

-- nest_hatchery_id_fkey is deliberately left as ON DELETE NO ACTION. That
-- RESTRICT behaviour is what makes "a hatchery holding nests cannot be
-- deleted" enforceable at the database, not merely in HatcheryService.
