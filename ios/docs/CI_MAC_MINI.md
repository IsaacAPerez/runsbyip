# Mac Mini CI Handoff

If you're a Claude session opening this on the mini, read this whole file
before doing anything signing- or release-related. The mini is wired into
real Apple Developer / App Store Connect / GitHub infrastructure; mistakes
here cost real time (revoked certs, broken builds for other apps).

## TL;DR — what the mini does

The Mac mini hosts a self-hosted GitHub Actions runner. On every push to
`main` that touches `ios/**`, the runner archives the iOS app and uploads
it to TestFlight via Fastlane. No human is in the loop after the push.

## Fast facts

| Thing | Value |
|---|---|
| App bundle ID | `com.isaacperez.runsbyip` |
| App Store Connect team ID | `K98N9692X9` (Isaac Perez) |
| Apple Developer login | `iperez2435@gmail.com` |
| Source repo | `https://github.com/IsaacAPerez/RunsByIP` |
| Signing repo (Match) | `https://github.com/IsaacAPerez/ios-certificates` |
| Runner work dir on mini | `/Users/isaacperez/actions-runner-runsbyip/` |
| ASC API key path on mini | `/Users/isaacperez/.appstoreconnect/private_keys/AuthKey_RRYR26DJLS.p8` |
| Fastlane lanes | `beta` (build+upload), `sync_signing` (pull profile), `rotate_signing` (regenerate) |
| Match profile name | `match AppStore com.isaacperez.runsbyip` |

## 1Password items (vault: Personal)

These are the only sources of truth for secrets. Don't paste secrets into
git, GitHub Issues, or terminal scrollback. Read with `op` instead.

- **`Fastlane Match - ios-certificates`** — passphrase that decrypts the
  signing repo. Read with: `op read "op://Personal/Fastlane Match - ios-certificates/password"`
- **`App Store Connect API Key - RRYR26DJLS`** — document, contains the
  `.p8` private key plus Key ID + Issuer ID metadata.
- **`GitHub PAT — ios-certificates read`** — fine-grained PAT used by the
  runner to clone the signing repo.

## Recent context (May 2026)

- The pre-Match world used Xcode automatic signing. That broke when a new
  capability (Apple Pay) was added to the App ID — Xcode's local profile
  cache went stale and shipped a TestFlight build without Apple Pay
  entitled. Today's switch to Match fixes that class of bug.
- App Store marketing version 1.0.2 is **closed** for new builds; 1.0.3 is
  live. Bump `ios/project.yml` (not just `pbxproj`) when you raise it
  again — `xcodegen generate` rewrites `pbxproj` in CI.

## How signing works

- Distribution cert + provisioning profile live encrypted in
  `git@github.com:IsaacAPerez/ios-certificates`.
- `fastlane match(readonly: true)` clones that repo and installs both
  into the mini's `login.keychain`.
- The mini never logs into Apple Developer or runs 2FA. It only needs the
  Match passphrase, the ASC API key, and git read-access to
  `ios-certificates`.

If profiles ever drift (e.g. you add a capability to the App ID), regenerate
**from the laptop**, not the mini:

```bash
cd ~/Coding/RunsByIP/ios
export MATCH_PASSWORD=$(op read "op://Personal/Fastlane Match - ios-certificates/password")
bundle exec fastlane rotate_signing
```

The mini will pick up the new profile on the next CI run via `readonly: true`.

## Required GitHub repository secrets

Repo: `IsaacAPerez/RunsByIP` → Settings → Secrets and variables → Actions.

| Secret | Where to get it | Notes |
|---|---|---|
| `KEYCHAIN_PASSWORD` | Already set | Mini's `login.keychain` password. |
| `BB_PASSWORD` | Already set | iMessage notify script. |
| `MATCH_PASSWORD` | 1Password → "Fastlane Match - ios-certificates" → password field | Decrypts `ios-certificates`. |
| `MATCH_GIT_BASIC_AUTHORIZATION` | See "Match git access" below | Lets the runner read `ios-certificates`. |
| `ASC_KEY_ID` | 1Password → "App Store Connect API Key - RRYR26DJLS" → Key ID field | Currently `RRYR26DJLS`. |
| `ASC_ISSUER_ID` | Same 1Password item → Issuer ID field | Currently `d0ded18b-a760-49f9-82b3-135bb3b65703`. |
| `ASC_KEY_PATH` | Set to `/Users/isaacperez/.appstoreconnect/private_keys/AuthKey_RRYR26DJLS.p8` | Path on the mini, not laptop. |

### Match git access

`ios-certificates` is private. The default `GITHUB_TOKEN` only grants access
to the repo running the workflow, so Match needs an explicit credential.

1. Create a fine-grained PAT on github.com:
   - Resource owner: `IsaacAPerez`
   - Repository access: only `IsaacAPerez/ios-certificates`
   - Permissions: Contents → Read-only
   - Expiration: 1 year
2. Encode `username:pat` in base64 (no trailing newline):
   ```bash
   printf 'IsaacAPerez:ghp_xxxxxxxxxxxx' | base64
   ```
3. Save the base64 string as the `MATCH_GIT_BASIC_AUTHORIZATION` repo secret.
4. Save the raw PAT in 1Password as a new item ("GitHub PAT — ios-certificates
   read") for rotation.

## One-time mini setup

If the mini is fresh, do this once over Tailscale Screen Sharing:

```bash
# Tools
brew install rbenv ruby-build xcodegen 1password-cli gh
rbenv install 3.3.0 && rbenv global 3.3.0
gem install bundler

# ASC API key (do this from a clipboard paste of the .p8 contents from 1Password)
mkdir -p ~/.appstoreconnect/private_keys
pbpaste > ~/.appstoreconnect/private_keys/AuthKey_RRYR26DJLS.p8
chmod 600 ~/.appstoreconnect/private_keys/AuthKey_RRYR26DJLS.p8

# Sanity check Match can pull
cd ~/path-to-some-runs-by-ip-clone/ios
bundle install
export MATCH_PASSWORD=...           # paste from 1Password once for the test
export MATCH_GIT_BASIC_AUTHORIZATION=$(printf 'IsaacAPerez:ghp_xxx' | base64)
bundle exec fastlane sync_signing
```

After that, Xcode/Match has the cert and profile locally. CI runs no longer
need interactive input — they pull from the encrypted repo on every run.

## Common runner problems

- **`MATCH_PASSWORD` empty** → secret not set on the repo, or workflow not
  passing it through `env:`. Both already handled in `testflight.yml` —
  just ensure the secret exists.
- **Runner can't clone `ios-certificates`** → `MATCH_GIT_BASIC_AUTHORIZATION`
  missing or PAT expired/scoped wrong. Re-issue the PAT.
- **`fastlane finished with errors` at upload** with `Invalid Pre-Release
  Train` → marketing version (in `ios/project.yml`) is closed for new
  TestFlight builds. Bump `MARKETING_VERSION` and `CFBundleShortVersionString`
  in `project.yml`.
- **Archive fails with "X does not support provisioning profiles"** → don't
  pass `PROVISIONING_PROFILE_SPECIFIER` via global xcargs. Use
  `update_code_signing_settings` scoped to the `RunsByIP` target (already
  set up in `Fastfile`).
- **Disk full on mini** → clear `~/Library/Developer/Xcode/iOS DeviceSupport`
  and `~/Library/Developer/Xcode/DerivedData`. Both regenerate.

## Updating the runner host

The runner lives in `/Users/isaacperez/actions-runner-runsbyip/` on the mini.
To update the runner binary or restart the service, SSH/Screen Share in and
follow standard GitHub Actions runner update steps.

To keep `fastlane` reasonably current: bump the version in `ios/Gemfile`,
commit, and the next CI run reinstalls via `bundle install`.
