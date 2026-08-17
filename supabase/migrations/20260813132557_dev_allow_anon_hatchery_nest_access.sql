-- TEMPORARY / DEV ONLY.
--
-- hatchery and nest have RLS enabled with zero policies, so anon and
-- authenticated currently get denied on every read and write. That blocks
-- testing the app's nest CRUD against this database.
--
-- This grants anon unrestricted access to both tables so the app (no auth
-- yet) can be exercised end to end. It must be replaced -- not just
-- supplemented -- by the reviewed hardening migration described in
-- supabase/README.md (auth, ownership, per-user policies) before any real
-- launch. Do not build on top of this policy; delete it when that migration
-- lands.

create policy "dev: anon full access" on public.hatchery
  for all
  to anon
  using (true)
  with check (true);

create policy "dev: anon full access" on public.nest
  for all
  to anon
  using (true)
  with check (true);
