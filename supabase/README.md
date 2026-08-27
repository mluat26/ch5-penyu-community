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

The reviewed `20260814093000_add_hatchery_layout_persistence.sql` migration
now defines authenticated owner-scoped hatcheries/nests plus private scan
Storage. Remaining backend hardening work includes:

- user profiles and organization membership;
- Row Level Security policies for every remaining client-accessible table.

## Device assignments and IoT telemetry

`20260815170000_add_device_assignments_and_trusted_iot_ingest.sql` replaces
the mutable `device.nest_id` link with a history-preserving assignment table:

```text
physical device.id
  └─ device_assignment (one active row at a time)
       └─ nest
            └─ hatchery owner

iotdata.sensor_id = physical device.id
iotdata.nest_id   = server-resolved assignment snapshot
```

- The IoT hardware reports only its stable `device.id` as `sensor_id`; it does
  not need, receive, or guess a `nest_id`.
- The mobile app calls `save_device` to register, rename, assign, move, or
  unassign a device. The RPC closes an old assignment and opens a new one in
  one transaction.
- A reading must enter through the service-role-only
  `ingest_iot_reading(...)` RPC. It resolves the active assignment and writes
  both the device source and the historical nest snapshot.
- The device itself must never hold a Supabase service/secret key. Put that
  key only in a trusted gateway or Edge Function that authenticates the
  hardware first.

For a gateway, send the device UUID and sensor values to its server-side
Supabase client, then call `ingest_iot_reading`. For direct hardware-to-cloud
traffic, use the `ingest-iot` Edge Function and a unique per-device secret;
do not put one shared service key in firmware.

### Authenticated ESP32 rollout

`20260827090000_add_authenticated_device_ingestion.sql` stages the secure path
without breaking deployed loggers. It deliberately leaves the temporary
`ESP32 can insert IoT data` anonymous policy in place during the transition.

1. Apply the credential migration and deploy the function with
   `supabase functions deploy ingest-iot --no-verify-jwt`.
2. For each device, call the service-role-only
   `rotate_device_ingest_secret(device_id)` RPC. It returns a 64-character
   secret once; store it in that logger, never in the app or repository.
3. Change firmware to `POST /functions/v1/ingest-iot` with JSON containing
   `sensor_id`, `temperature`, and optional reading fields. Send the secret in
   the `x-device-secret` header. Do not send `nest_id`; the active assignment
   determines it.
4. Confirm new readings for every migrated logger. Rotation immediately
   invalidates the previous secret; `disable_device_ingest_secret(device_id)`
   stops one device without affecting the others.
5. Only after all production loggers use the Edge Function, add a final
   migration that drops the anonymous insert policy and revokes `anon` insert
   on `iotdata`.

Until step 5 is complete, assignment routing is correct but the legacy direct
endpoint can still be impersonated by anyone who has the anon key. This is a
temporary compatibility window, not the final security state.

## Hatchery scan persistence

`migrations/20260814093000_add_hatchery_layout_persistence.sql` adds the
durable scan contract used by the iOS onboarding/rescan flow:

```text
auth user / anonymous device identity
  └─ hatchery (owner_id, layout_status)
       └─ hatchery_layout (immutable revision, current revision pointer)
            └─ private Storage object: hatchery-layouts/{hatchery}/{layout}/source.jpg
```

- The source photo is stored only in the private `hatchery-layouts` bucket;
  Postgres stores its immutable object key and basic JPEG metadata, never image
  bytes.
- A revision stores the normalized four-corner boundary, sand-region polygon,
  compact active-cell grid mask, dimensions, and processing version. Section
  polygons and rectified imagery are regenerated on-device from that data.
- A skipped scan stores `capture_mode = skipped` and no photo path, so the app
  never uploads a fake white canvas.
- The app calls `begin_*_hatchery_layout`, uploads the fixed object key, then
  calls `finalize_hatchery_layout`. Only the final RPC makes a revision current
  and updates hatchery dimensions/grid values atomically.
- A new hatchery and its initial pending revision are created together. Its row
  remains hidden while an upload is incomplete. On failure,
  `abandon_hatchery_layout` locks the revision and marks it failed before the
  app removes its object; `purge_failed_hatchery_layout` then removes the
  failed metadata and any hidden first-hatch row. Existing hatcheries remain
  available while a rescan is pending.
- `expire_stale_hatchery_layouts(before)` is service-role-only and provides a
  safe recovery path for an app process that terminates mid-upload. A trusted
  cleanup worker must delete each returned Storage object, then call
  `purge_failed_hatchery_layout` for that revision.

### Security and rollout

This migration removes the temporary anonymous hatchery/nest policy and
replaces it with owner-only RLS. The iOS app uses Supabase anonymous Auth as a
stable per-device identity, persisted by the SDK in the Keychain.

Before applying this to the hosted project:

1. In the Supabase dashboard, enable **Anonymous sign-ins** under Auth. The
   tracked local configuration enables it for `supabase start`, but it does not
   modify the hosted Auth setting.
2. Run `supabase db push --dry-run`, review the SQL, then apply it through the
   team’s normal deployment path. Never place a service-role key in the iOS
   app.
3. Backfill a legacy owner only after deciding which real auth identity owns
   the row. Do not update `hatchery.owner_id` directly: call the
   service-role-only `adopt_legacy_hatchery_owner(hatchery_id, owner_id,
   adoption_reason)` RPC from a trusted backend. It accepts only unowned
   `legacy` rows, preserves owner immutability afterward, and records the
   reason, service role, subject, and timestamp in the private adoption audit
   table. The migration deliberately leaves legacy owners `NULL` rather than
   guessing, so those rows are inaccessible to ordinary users until adopted.
4. Test with two separate anonymous sessions: each must be able to read only
   its own hatcheries/layouts/photos, and a second session must not upload to a
   guessed object path.

Private Storage is deliberately immutable for ready revisions. Schedule the
service-role stale-upload cleanup above with the team’s trusted backend or Edge
Function. Hatchery deletion remains intentionally unavailable to mobile
clients until a privileged deletion workflow removes each immutable Storage
object before the database row; Storage itself cannot participate in the
Postgres transaction.
