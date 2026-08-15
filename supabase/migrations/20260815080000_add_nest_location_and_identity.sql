-- Where a nest was found, and the identifiers written on it in the field.
--
-- The Add Nest flow asks for a bucket/QR id and a nest number on its first
-- screen and shows both again on the confirmation screen, but neither had a
-- column: they lived only in NestFormDraft and were discarded on save, so the
-- number a ranger wrote on the bucket could never be read back. The flow also
-- gains a map step, and a coordinate is not something any existing column can
-- hold.
--
-- The address is stored alongside the coordinates rather than derived on
-- demand. Reverse geocoding needs the network, and the screens that display a
-- nest are exactly the ones a ranger opens on a beach; caching the string at
-- capture time keeps them readable offline.

alter table public.nest
  add column if not exists latitude         double precision,
  add column if not exists longitude        double precision,
  add column if not exists location_address text,
  add column if not exists bucket_id        text,
  add column if not exists nest_number      text;

alter table public.nest add constraint nest_latitude_valid
  check (latitude is null or (latitude >= -90 and latitude <= 90));

alter table public.nest add constraint nest_longitude_valid
  check (longitude is null or (longitude >= -180 and longitude <= 180));

-- Half a pin is worse than none: a lone latitude places the marker on the
-- prime meridian, somewhere off the coast of Ghana, and looks like real data.
alter table public.nest add constraint nest_coordinates_complete
  check (num_nulls(latitude, longitude) <> 1);

-- Finding the nests near a point is the query this exists to serve.
create index if not exists nest_latitude_longitude_idx
  on public.nest (latitude, longitude)
  where latitude is not null;

-- Drop place_eggs_laid.
--
-- The name promised a location but the column is a `date`, so it never held
-- one, and nothing ever wrote to it: NestController passes nil on every
-- create, as does every test. The three columns added above are what it was
-- reaching for.
--
-- Guarded rather than dropped outright. Nothing in the app can have populated
-- it, but a column is not something to delete on the strength of a grep --
-- psql, a script, or a teammate could have written rows this repository never
-- sees. If anything is in there, the migration fails loudly instead of
-- discarding it.
do $$
begin
  if exists (select 1 from public.nest where place_eggs_laid is not null) then
    raise exception
      'place_eggs_laid holds data; export it before dropping this column';
  end if;
end $$;

alter table public.nest drop column if exists place_eggs_laid;

-- No RLS work: the owner policies from 20260814093000 are row-scoped, so these
-- columns are already covered by them.
