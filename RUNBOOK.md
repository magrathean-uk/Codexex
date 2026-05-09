# Codexex Runbook

## Architecture map

- `Sources/CodexMeterCore/` owns quota models, formatting, binary lookup, and service contracts.
- `Sources/CodexMeterApp/Support/` owns auth state, usage history, launch-at-login, XPC client, and menu bar model.
- `Sources/CodexMeterApp/UI/` and `Windows/` own popup, settings, onboarding, and status item presentation.
- `Helper/CodexexHelper/` is the Rust helper for ChatGPT sign-in, implemented as an OAuth device-code flow, and quota reads.
- `Sources/CodexexXPCService/` is the sandbox-safe bridge that launches the helper inside the app bundle.

## Build loop

Always start with the shared build env:

```bash
source ../build-env.sh
```

Swift package tests:

```bash
swift test
```

Regenerate the Xcode project after `project.yml` changes:

```bash
xcodegen generate
```

`Package.swift` is a local development and package-test adapter. Keep Xcode target wiring in `project.yml`.

## Local Codex usage path

Codexex reads official local Codex session logs under `~/.codex/sessions/`.
It parses `token_count` events, local rate-limit fields, project/model context, command counts, and context-window metadata.
This is separate from ChatGPT sign-in: sign-in remains the quota truth, local sessions explain what burned the quota.

The local reader stays sandbox-safe and does not read browser state, cookies, private APIs, or token stores.
It can surface:

- today/week/session/project/model token burn
- cache-read pressure
- heavy shell/tool loops
- expensive max-model turns with small output
- missing local sessions or missing hook setup

## Companion commands

These are optional local helpers:

```bash
Scripts/codexex-status.sh
Scripts/check-codexex-companions.sh
Scripts/install-codexex-companions.sh
```

`codexex-status.sh` emits compact JSON from local session logs. The hook command writes redacted event metadata only: event, cwd, tool, session id, turn id, and status.
The installer backs up `~/.codex/hooks.json` and `~/.codex/config.toml` before adding Codexex hook entries.

Build or test the app target:

```bash
xcodebuild -project CodexMeter.xcodeproj \
  -scheme CodexMeterApp \
  -derivedDataPath "$XCODE_DERIVED_DATA_PATH" \
  -clonedSourcePackagesDirPath "$SWIFTPM_SHARED_CACHE" \
  test
```

## Helper and XPC flow

- Prebuild script: `Scripts/build-codexex-helper.sh`
- Embed/sign script: `Scripts/embed-codexex-helper.sh`
- Helper crate: `Helper/CodexexHelper/`
- XPC service target: `Sources/CodexexXPCService/`

The normal path is:

1. Xcode prebuild compiles the helper in release mode.
2. The helper binary is staged in derived data.
3. The app target embeds that helper into `Contents/Helpers/`.
4. The embed script signs it when code signing is enabled.
5. The app talks to the helper through the bundled XPC service.

`CodexAppServerProbe` in core is a legacy parity path only. App Store builds should stay on the helper plus XPC path.

## Release inputs

- Privacy text: `PRIVACY.md`
- App Store text bundle: `fastlane/metadata/up-6762058457/`
- App entitlements: `AppStore/`

Keep review-facing copy in those files. Do not recreate `FEATURES.md`, `APP_REVIEW.md`, or ad hoc release notes.

## Review smoke path

1. Launch the app.
2. Use `Preview Mode` or start ChatGPT sign-in from Settings.
3. Confirm the popup shows quota cards, reset timing, Peaks/Cycle/Month history, and forecast state.
4. Confirm the settings window can sign out, change refresh cadence, switch System/Light/Dark appearance, and toggle menu bar labels.

## Scripted release smoke

Run the lightweight release guard before archiving:

```bash
Scripts/release-smoke.sh
```

This is a static release guard, not full UI proof. It checks the project source of truth, App Store entitlements, helper build/embed wiring, `LSUIElement`, review metadata, privacy text, the versioned helper protocol markers, and the legacy-probe compile flag. It also runs helper tests when `cargo` is available and an Xcode build-settings smoke when `xcodebuild` is available.

## Legacy probe quarantine

Direct `codex app-server` capture is excluded from normal shipping builds unless `CODEXEX_ENABLE_LEGACY_PROBE` is explicitly defined. The reducer and payload support types remain available so existing core regression tests can still validate snapshot mapping without enabling the probe path.

## Guardrails

- Keep the app menu-bar-only and sandbox-safe.
- Use official Codex interfaces only.
- Do not add alternate sign-in flows, browser scraping, or token extraction.
- Update `project.yml` when target wiring changes; update helper scripts when helper packaging changes.
