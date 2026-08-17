-- Migration unit 1: schema_changes
-- Transaction mode: transactional
-- Boundary reason: default

DROP EXTENSION pg_net;

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT DELETE, INSERT, SELECT, UPDATE ON TABLES TO anon;

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT SELECT, USAGE ON SEQUENCES TO anon;

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON ROUTINES TO anon;

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT DELETE, INSERT, SELECT, UPDATE ON TABLES TO authenticated;

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT SELECT, USAGE ON SEQUENCES TO authenticated;

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON ROUTINES TO authenticated;

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT DELETE, INSERT, SELECT, UPDATE ON TABLES TO service_role;

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT SELECT, USAGE ON SEQUENCES TO service_role;

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON ROUTINES TO service_role;

CREATE TABLE public.hatchery (
  number_of_row     bigint           NOT NULL,
  number_of_collumn bigint           NOT NULL,
  name              text,
  shape             text,
  length_m          double precision,
  width_m           double precision,
  id                uuid             DEFAULT gen_random_uuid() NOT NULL
);

ALTER TABLE public.hatchery
  ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.hatchery
  ADD CONSTRAINT hatchery_pkey PRIMARY KEY (id);

GRANT ALL ON public.hatchery TO anon;

GRANT ALL ON public.hatchery TO authenticated;

GRANT ALL ON public.hatchery TO service_role;

CREATE TABLE public.iotdata (
  id          uuid             DEFAULT gen_random_uuid() NOT NULL,
  nest_id     uuid             DEFAULT gen_random_uuid() NOT NULL,
  sensor_id   uuid             DEFAULT gen_random_uuid(),
  temperature double precision,
  alert       text
);

ALTER TABLE public.iotdata
  ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.iotdata
  ADD CONSTRAINT iotdata_pkey PRIMARY KEY (id);

GRANT ALL ON public.iotdata TO anon;

GRANT ALL ON public.iotdata TO authenticated;

GRANT ALL ON public.iotdata TO service_role;

CREATE POLICY "Allow anon inserts" ON public.iotdata
  FOR INSERT
  TO anon
  WITH CHECK (true);

CREATE TABLE public.nest (
  id                 uuid   DEFAULT gen_random_uuid() NOT NULL,
  number_of_eggs     bigint NOT NULL,
  date_eggs_laid     date,
  place_eggs_laid    date,
  success_eggs_hatch bigint,
  hatchery_id        uuid   DEFAULT gen_random_uuid(),
  placement_row      bigint,
  placement_col      bigint,
  founder_id         uuid   DEFAULT gen_random_uuid()
);

ALTER TABLE public.nest
  ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.nest
  ADD CONSTRAINT nest_hatchery_id_fkey FOREIGN KEY (hatchery_id) REFERENCES public.hatchery(id);

ALTER TABLE public.nest
  ADD CONSTRAINT nest_pkey PRIMARY KEY (id);

GRANT ALL ON public.nest TO anon;

GRANT ALL ON public.nest TO authenticated;

GRANT ALL ON public.nest TO service_role;

CREATE TABLE public.organiztion (
  id           uuid DEFAULT gen_random_uuid() NOT NULL,
  name         text,
  date_created date
);

ALTER TABLE public.organiztion
  ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.organiztion
  ADD CONSTRAINT organiztion_pkey PRIMARY KEY (id);

GRANT ALL ON public.organiztion TO anon;

GRANT ALL ON public.organiztion TO authenticated;

GRANT ALL ON public.organiztion TO service_role;
