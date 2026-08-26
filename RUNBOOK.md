# Codexex Runbook

Current release: `6.0.0` (`19`). Keep `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `project.yml`; regenerate the Xcode project after changing them.

## Architecture map

- `Sources/CodexMeterCore/` owns quota models, formatting, binary lookup, and service contracts.
- `Sources/CodexMeterApp/Support/` owns auth state, usage history, launch-at-login, XPC client, and menu bar model.
- `Sources/CodexMeterApp/UI/` and `Windows/` own popup, settings, onboarding, and status item presentation.
- `Helper/CodexexHelper/` is the Rust helper for ChatGPT sign-in, implemented as an OAuth device-code flow, and quota reads.
- `Sources/CodexexXPCService/` is the sandbox-safe bridge that launches the helper inside the app bundle.

## Build loop

Build and test commands are self-contained in this checkout. Use explicit
derived-data and SwiftPM cache paths for Xcode commands instead of relying on a
shared parent-directory environment script.

Swift package tests:

```bash
swift test
```

Rust helper tests:

```bash
cargo test --manifest-path Helper/CodexexHelper/Cargo.toml
```

Regenerate the Xcode project after `project.yml` changes:

```bash
xcodegen generate --spec project.yml
```

`Package.swift` is a local development and package-test adapter. Keep Xcode target wiring in `project.yml`.

No standalone lint, format, typecheck, Makefile, Justfile, or GitHub Actions
workflow was found in this checkout. Use builds/tests as the typecheck gate.

Optional companion installation targets the user layer:

```bash
Scripts/install-codexex-companions.sh
```

That script backs up `~/.codex/hooks.json` and `~/.codex/config.toml` before updating the named lifecycle events. Inspect those user-level files after installation because user and project hook sources are additive.

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
- local reset-window, plan, and context-window pressure hints when present in session logs
- missing local sessions or missing hook setup

## Companion commands

These are optional local helpers:

```bash
Scripts/codexex-status.sh
Scripts/check-codexex-companions.sh
Scripts/install-codexex-companions.sh
```

`codexex-status.sh` emits compact JSON from local session logs, including all-session token totals, session autopsies, waste signals, reset windows, plan type, and context-window pressure. The hook command writes redacted event metadata only: event, cwd, tool, session id, turn id, and status.
The installer backs up `~/.codex/hooks.json` and `~/.codex/config.toml` before adding Codexex hook entries.

Build or test the app target:

```bash
xcodebuild -project CodexMeter.xcodeproj \
  -scheme CodexMeterApp \
  -derivedDataPath /tmp/codexex-derived-data \
  -clonedSourcePackagesDirPath /tmp/codexex-swiftpm-cache \
  test
```

The iOS target is wired through the `CodexMeteriOS` scheme in `project.yml`.
Pick an installed simulator destination before running iOS tests.

## iOS Live Activity

Live Activity starts explicitly from iOS Settings after a valid quota refresh.
While it runs, Codexex schedules an on-device `BGAppRefreshTask` to fetch the
latest quota and update the activity when iOS grants background runtime. Timing
is system-controlled and force-quitting the app stops these refreshes. Codexex
has no APNs backend or server-side account data; the activity uses its stale
date when refreshes stop. It shows the last-fetched ChatGPT account quota, not
Mac-only local session-log token burn.

## Menu bar presentation

Fresh installs keep the optional main Codex 5-hour window off. In that compact
weekly mode, the macOS status item uses the OpenAI mark followed by the weekly
value. Spark 5-hour data stays visible. Turning the main Codex 5-hour window
back on restores the explicit `5H` and `W` labels.

## Helper and XPC flow

- Prebuild script: `Scripts/build-codexex-helper.sh`
- Embed/sign script: `Scripts/embed-codexex-helper.sh`
- Helper crate: `Helper/CodexexHelper/`
- XPC service target: `Sources/CodexexXPCService/`

The normal path is:

1. Xcode prebuild compiles the helper in release mode.
2. The helper binary is staged in derived data.
3. The app target embeds that helper into `Contents/Helpers/` and into the bundled XPC service's `Contents/Helpers/`.
4. The embed script signs it when code signing is enabled.
5. The app talks to the helper through the bundled XPC service.

Release builds follow Xcode's `ARCHS`: the helper is compiled for both
`arm64` and `x86_64`, then combined before signing. Keep both Rust standard
library targets installed (`aarch64-apple-darwin` and
`x86_64-apple-darwin`) so the helper matches the universal macOS app. The
build uses the `stable` rustup toolchain for both Cargo and rustc by default;
set `CODEXEX_RUSTUP_TOOLCHAIN` to select another installed toolchain or
`CODEXEX_RUSTUP_BIN` to select a specific rustup executable. The staged helper
is stripped with Apple's `strip` after its slices are combined; set
`CODEXEX_STRIP_BIN` only when selecting another compatible Apple strip tool.

`CodexAppServerProbe` in core is a legacy parity path only. App Store builds should stay on the helper plus XPC path.

## Release inputs

- Privacy text: `PRIVACY.md`
- App Store text bundle: `fastlane/metadata/up-6762058457/`
- App entitlements: `AppStore/`

Keep review-facing copy in those files. Do not recreate `FEATURES.md`, `APP_REVIEW.md`, or ad hoc release notes.

## Paid packaging

Use paid-upfront App Store pricing for the current product. The repo has no
StoreKit products, entitlement-gated premium paths, paywall, subscription, or
in-app purchase target. Do not add one without approved product identifiers,
review copy, restore-purchase UX, and StoreKit tests.

Preview Mode must remain useful regardless of pricing so App Review can inspect
quota, history, local session usage, notifications copy, and Settings offline.

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

This is a static release guard, not full UI proof. It checks the project source of truth, App Store entitlements, helper build/embed wiring, `LSUIElement`, review metadata, privacy text, the versioned helper protocol markers, and the legacy-probe compile flag. It also preflights both macOS Rust targets, runs helper tests with that same rustup toolchain, and runs macOS plus iOS Xcode build-settings smokes when `xcodebuild` is available.

## Legacy probe quarantine

Direct `codex app-server` capture is excluded from normal shipping builds unless `CODEXEX_ENABLE_LEGACY_PROBE` is explicitly defined. The reducer and payload support types remain available so existing core regression tests can still validate snapshot mapping without enabling the probe path.

## Guardrails

- Keep the app menu-bar-only and sandbox-safe.
- Use official Codex interfaces only.
- Do not add alternate sign-in flows, browser scraping, or token extraction.
- Update `project.yml` when target wiring changes; update helper scripts when helper packaging changes.
- Do not hand-edit `CodexMeter.xcodeproj`; regenerate it from `project.yml`.
- Do not add project-local Codex hooks; keep generated Xcode protection in the documented `project.yml` workflow.

## Done criteria for agent work

- The touched files match the repo ownership map above.
- The narrowest useful test or smoke command has run.
- If a build/test command could not run, the exact blocker is listed.
- Generated Xcode project output is refreshed after `project.yml` changes.
- The final report names verification, result, blockers, and recommended next step.
