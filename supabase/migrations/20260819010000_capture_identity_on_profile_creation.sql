-- Fill a profile's identity at creation instead of leaving it blank.
--
-- `create_profile_for_new_user` inserted `(id)` and nothing else, and so did
-- every other path that creates a profile row -- the hatchery trigger, invite
-- redemption, and the original backfill all write only `id`, `organization_id`
-- and `role`. So `display_name` and `apple_email` were null on every row from
-- the moment it existed, and could only ever be filled by a later UPDATE from
-- the client.
--
-- That UPDATE is the wrong place for it. It is a second round trip that can
-- fail, be refused, or be cancelled by the person closing the screen, and when
-- it did the address was simply lost -- even though `auth.users` was holding it
-- the whole time.
--
-- The address is therefore captured here, where it cannot be missed. The name
-- is captured too when the provider supplies it, but Apple sends a name only on
-- a person's very first authorization and does not put it in the identity
-- token, so the client-side capture in `AppContainer.signInWithApple` remains
-- the path that usually catches it.
--
-- Anonymous accounts have neither, and still get a row with both columns null.
-- That is correct: there is no identity to record yet.

create or replace function public.create_profile_for_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profile (id, display_name, apple_email)
  values (
    new.id,
    nullif(
      btrim(
        coalesce(
          new.raw_user_meta_data ->> 'full_name',
          new.raw_user_meta_data ->> 'name',
          ''
        )
      ),
      ''
    ),
    nullif(btrim(coalesce(new.email, '')), '')
  )
  on conflict (id) do nothing;

  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- Rows that already exist
-- ---------------------------------------------------------------------------

-- Only ever fills a blank. A profile whose name or address was edited in the
-- app is the more recent truth, and `auth.users` must not overwrite it.

update public.profile p
set apple_email = nullif(btrim(u.email), '')
from auth.users u
where u.id = p.id
  and nullif(btrim(coalesce(p.apple_email, '')), '') is null
  and nullif(btrim(coalesce(u.email, '')), '') is not null;

update public.profile p
set display_name = nullif(
  btrim(
    coalesce(
      u.raw_user_meta_data ->> 'full_name',
      u.raw_user_meta_data ->> 'name',
      ''
    )
  ),
  ''
)
from auth.users u
where u.id = p.id
  and nullif(btrim(coalesce(p.display_name, '')), '') is null
  and nullif(
    btrim(
      coalesce(
        u.raw_user_meta_data ->> 'full_name',
        u.raw_user_meta_data ->> 'name',
        ''
      )
    ),
    ''
  ) is not null;
