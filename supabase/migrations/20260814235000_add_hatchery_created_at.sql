-- Keep a durable creation timestamp on the hatchery itself. A layout revision
-- timestamp is not a substitute because re-scanning creates a later revision.
alter table public.hatchery
  add column if not exists created_at timestamptz;

-- Backfill only records with a known first scan. Hatcheries which predate the
-- layout system intentionally remain NULL instead of receiving this migration's
-- timestamp as a fabricated creation date.
with first_layout as (
  select distinct on (hatchery_id)
    hatchery_id,
    created_at
  from public.hatchery_layout
  order by hatchery_id, created_at asc, revision asc, id asc
)
update public.hatchery as hatchery
set created_at = first_layout.created_at
from first_layout
where hatchery.id = first_layout.hatchery_id
  and hatchery.created_at is null;

alter table public.hatchery
  alter column created_at set default now();

-- A row owner must not be able to forge the audit timestamp through a direct
-- PostgREST update. Insertions always receive the database's server time.
create or replace function public.enforce_hatchery_created_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    new.created_at := now();
  elsif new.created_at is distinct from old.created_at then
    raise exception 'hatchery created_at is immutable';
  end if;

  return new;
end;
$$;

drop trigger if exists hatchery_created_at_guard on public.hatchery;

create trigger hatchery_created_at_guard
before insert or update of created_at on public.hatchery
for each row
execute function public.enforce_hatchery_created_at();
