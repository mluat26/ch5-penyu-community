# Supabase schema

`migrations/20260812103134_remote_schema.sql` is an unmodified baseline pulled
from the linked Supabase project on 2026-08-12. It documents the database as it
exists today; it is not the target application schema.

Do not edit that pulled migration. Create a new migration for every database
change:

```sh
supabase migration new describe_the_change
supabase db push --dry-run
supabase db push
```

Before connecting the iOS app, the team needs a reviewed hardening migration
that defines:

- authenticated ownership, profiles, and organization membership;
- foreign keys and required values for hatcheries, nests, and telemetry;
- hatchery scan/image layout metadata and a Storage policy;
- a telemetry timestamp and safe sensor-ingestion path; and
- Row Level Security policies for every client-accessible table.

The current `iotdata` anonymous-insert policy is not appropriate for direct
mobile-client sensor writes. Route device ingestion through a trusted backend
or Edge Function instead.
