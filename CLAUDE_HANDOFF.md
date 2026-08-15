# Smart Nest — Claude Handoff

## Start here

- Repository: `/Users/andrian/Work/Apple/sea-turtles/ch5-penyu-community`
- Active branch: `fix/hatchery-selector-touch-target`
- Latest shared merge: `61d770b Merge remote-tracking branch 'origin/develop' into fix/hatchery-selector-touch-target`
- The worktree is intentionally **dirty** with many user-owned, uncommitted changes. Do not reset, checkout, clean, or discard unrelated changes.
- Safety backup exists: `stash@{0}` (`codex-pre-develop-merge-2026-08-15`). Do not drop it without explicit approval.
- The Xcode project uses a filesystem-synchronized root group: Swift files below `community-challenge/community-challenge/` are auto-included. Do not add source-file membership to `project.pbxproj` manually.

## Current product direction

This is a native SwiftUI iOS app called Smart Nest / Penyu Community. The user is implementing Figma-accurate hatchery onboarding, scan/layout persistence, management sheets, home, and Add Nest flows backed by Supabase.

The main Figma reference is `https://www.figma.com/design/MeqBEKm6HebtDPwj6zFy3P/Challenge-5`.

Use a 402 pt-wide reference canvas for Figma matching. Adapt/center it for iPad and landscape rather than globally hard-locking 402×874.

## Sign in with Apple — implemented in code

The Figma pre-onboarding screens were already visually implemented:

- Welcome: Figma `119:3271`
- “Let’s get started”: Figma `119:3284`
- View: `community-challenge/community-challenge/Views/PreFirstHatchOnboardingView.swift`

The previous Apple button was visual-only. It now uses Apple's native SwiftUI `SignInWithAppleButton` and a SHA-256 nonce:

```
SignInWithAppleButton
  → ASAuthorizationAppleIDCredential.identityToken
  → AppRootView.signInWithApple(...)
  → AppContainer.signInWithApple(...)
  → SupabaseAuthenticationService.signInWithApple(...)
  → client.auth.signInWithIdToken(provider: .apple, idToken, nonce)
  → reload hatchery list
```

Relevant source files:

- `Views/PreFirstHatchOnboardingView.swift`
- `Views/AppRootView.swift`
- `Controller/AppContainer.swift`
- `Repository/Supabase/SupabaseAuthenticationService.swift`
- `community-challenge.entitlements`
- `community-challenge.xcodeproj/project.pbxproj`

Behavior:

- New Apple user with no hatcheries: native Apple sheet → successful Supabase session → “Let’s get started”.
- Returning Apple user with hatcheries: native Apple sheet → list reload → first hatchery opens.
- The app currently reaches this action only from the empty-hatchery onboarding route. That matters because the app creates anonymous Supabase sessions for backend calls. Do **not** reuse direct `signInWithIdToken` for a data-bearing anonymous user: it changes `auth.uid()` and would hide their owner-scoped hatcheries. A future anonymous-account upgrade needs `linkIdentityWithIdToken` and Supabase manual linking enabled.

### Apple/Supabase external setup

Current app target settings:

- Bundle ID: `com.andrian.community-challenge`
- Debug/Release Apple Team: `NA9CXGVRMK`
- Sign in with Apple entitlement: `com.apple.developer.applesignin = Default`

The user reported that they registered the App ID in Apple Developer and enabled Sign in with Apple. Verify it in Xcode Signing & Capabilities if device signing fails.

In Supabase Dashboard → Authentication → Providers → Apple:

- Enable Apple.
- Client IDs: `com.andrian.community-challenge`
- Native iOS only: leave the OAuth Secret Key blank and leave the callback URL unchanged.
- Do not place an Apple `.p8` key, Supabase key, or any secret in the iOS app/repository/chat.

The user last said “donee”, but runtime authentication still needs a physical-device test. Local `supabase/config.toml` was previously observed with Apple disabled; hosted dashboard config is separate. Do not read or print secret config files.

### Apple test checklist

1. Confirm the physical device is launching bundle `com.andrian.community-challenge`, not one of the older same-display-name `luat...` builds.
2. Run a signed physical-device build.
3. Tap **Sign in with Apple** from Welcome.
4. A new user reaches “Let’s get started”; a returning Apple user with saved hatcheries opens the first hatchery.
5. If the server rejects the token, check the Supabase Apple provider's Client IDs and Apple App ID / signing team match exactly.

## Verification already performed

This build passed after the Apple-login code and current bundle-ID configuration:

```bash
/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild -quiet \
  -project community-challenge/community-challenge.xcodeproj \
  -scheme community-challenge \
  -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /private/tmp/sea-turtles-apple-sign-in \
  CODE_SIGNING_ALLOWED=NO build
```

`plutil -lint community-challenge/community-challenge/community-challenge.entitlements` also passed.

There are pre-existing Swift 6 concurrency warnings in several Supabase repository/DTO files; the Apple implementation compiled cleanly and introduced no build errors.

## Major UI/work completed in this worktree

- First hatch creation / onboarding layout uses Figma's 402pt design canvas and handles keyboard movement without zooming the hero image.
- Dimension screen has a compact keyboard-up Figma state. Skipped scanning should show a white canvas with a grid, never a sample photo; inspect current uncommitted work before changing it.
- Management/home hatchery selectors were repeatedly refined for real-device hit targets. Use native SwiftUI controls and keep large rectangular hit areas—do not reintroduce glyph-only hit testing or invisible hit-test hacks.
- Management card flow is intended to be: card → detail bottom sheet → pencil → edit bottom sheet. Figma nodes: detail `122:3437`, edit `122:3333`.
- Management background hero asset was corrected to use the transparent Figma export rather than an opaque image.
- Duplicate hatchery-name UX/migration is present in the worktree. The database constraint is owner-scoped and normalized for trim/case. The migration was validated locally but has not been declared deployed to hosted Supabase.
- Hatchery layout persistence (photo/boundary/sand mask/grid) has substantial related work/migrations in the dirty tree. Do not reduce persistence back to only name/dimensions/grid counts.

## Add Nest restructuring

Friend's latest Add Nest UI from `origin/develop` was split without changing its visuals:

```
Views/Components/AddNest/
  AddNestFormComponents.swift
  AddNestPreviewComponents.swift

Views/Flows/AddNest/
  AddNestFlowViews.swift
  NestLocationPickerView.swift
  NestSectionPickerView.swift
```

The old root `Views/AddNestFlowViews.swift` and `Views/NestLocationPickerView.swift` were deleted/moved. Do not restore the stale root files: filesystem synchronization would compile both copies and produce invalid redeclarations. The Add Nest structural compile check passed.

## Known unfinished / caution points

- No pull request has been created for the large current dirty worktree.
- Hosted Supabase migrations/provider settings cannot be assumed applied just because local files exist.
- `Join with code` in pre-first onboarding remains a deliberate “not available yet” alert; there is no invite backend flow yet.
- Apple returns a full name only on the first authorization. No profile metadata persistence was added because there is no current profile UI/schema. Add it only if product needs it.
- Existing old app IDs/builds may remain installed on the physical phone. New bundle ID means a separate install; test the correct app icon/build.
- Do not expose or commit Supabase credentials, Apple `.p8` keys, auth tokens, or local secret files.

## Suggested first actions for the next agent

1. Read `git status --short` and preserve all unrelated changes.
2. Build before editing if the user reports a breakage.
3. Ask for the exact runtime error/screenshot if Apple sign-in fails; do not guess that hosted Supabase provider configuration is correct.
4. Keep all authentication action reachable only from empty onboarding unless an explicit anonymous-to-Apple identity-linking migration is designed.
