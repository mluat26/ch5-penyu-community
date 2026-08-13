-- Adds the predicted hatch date to public.nest.
--
-- The column was created directly in the Supabase project on 2026-08-13; this
-- migration records it so a fresh `supabase db reset` reproduces the same
-- schema. IF NOT EXISTS keeps `supabase db push` a no-op against the project
-- that already has the column.
--
-- Type matches the sibling date columns (date_eggs_laid, place_eggs_laid).

ALTER TABLE public.nest
  ADD COLUMN IF NOT EXISTS date_predicted_hatch date;
