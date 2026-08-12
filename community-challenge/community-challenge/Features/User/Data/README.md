# User data boundary

The pulled schema has no public `profiles` or user table. `auth.users` is
managed by Supabase Auth and should not be queried directly from the iOS app.

Add a `profiles` table, organization membership model, and Row Level Security
policies in a new reviewed migration before creating an `AppUserDTO` or a user
repository here.
