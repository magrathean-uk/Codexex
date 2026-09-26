# Codexex Runbook

The checkout is configured for version `6.1.1`, build `26`. Keep `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `project.yml`; regenerate the Xcode project after changing them.

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

For optional cache and build-output management, consider [Clean Development](https://github.com/magrathean-uk/clean-development). It is not required for the commands below.

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

Use builds and tests as the Swift typecheck gate. The existing
[compliance workflow](.github/workflows/cargo-deny.yml) runs `cargo-deny`
license, dependency-ban, and source checks for the Rust helper on pushes and
pull requests to `main`. It does not run app tests or the vulnerability
advisory check. No standalone formatter or linter configuration is supplied.

## Local Codex usage path

Codexex reads official local Codex session logs under `~/.codex/sessions/`.
It parses `token_count` events, local rate-limit fields, project/model context, command counts, and context-window metadata.
This is separate from ChatGPT sign-in: authenticated quota responses provide account allowance data; local sessions provide token-usage context. Session totals are not a complete billing record.

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

`codexex-status.sh` emits JSON derived from local session logs, including token totals, session summaries, usage signals, reset windows, plan type, and context-window pressure. The hook command records event metadata: event, working directory, tool, session ID, turn ID, and status. Working directory paths and identifiers can still be sensitive.

The installer uses `CODEX_HOME`, or `~/.codex` by default. It backs up an existing `hooks.json`, then replaces the `SessionStart`, `PermissionRequest`, `PostToolUse`, and `Stop` entries with Codexex commands. It may also back up and append a feature setting to an existing `config.toml`. Review those changes and the resulting TOML before using the hooks; installation is optional and changes user configuration. Keep this checkout available because installed commands reference its script paths.

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
While it runs, the app schedules on-device background refresh and registers
for background notification wakes at the configured relay endpoint. The
registration request carries an APNs token, its environment, and an opaque
installation credential. It does not carry OpenAI credentials, account
identity, quota, or usage history. The relay's documented data handling is in
[PRIVACY.md](PRIVACY.md); its server implementation and deployment are outside
this repository.

After a wake, the phone attempts a direct quota refresh and updates the
activity. ActivityKit is requested with `pushType: nil`: these are app wake
notifications, not direct ActivityKit content pushes. Timing is controlled by
iOS. Tapping a stale activity opens Codexex and requests a manual refresh.
The activity shows account quota, not Mac-only session-log token usage.

The card's Updated time comes from the last quota snapshot fetched on the
device; receiving a wake alone does not advance it. For physical-device
verification, Debug builds overwrite `Library/Caches/CodexexAPNsWake.json`
inside the app container with only the most recent wake's timestamps and
result. A `refreshed` receipt must have a `snapshotCapturedAt` after
`receivedAt`. Read only this file when checking delivery; it contains no
account, token, quota, or history. Release builds do not write this receipt.
APNs acceptance, registration renewal, and an unchanged percentage alone do
not prove that a background quota refresh completed.

## Menu bar presentation

The macOS status item uses the OpenAI mark followed by the weekly value when the
5-hour window is unavailable. Any account shows the main Codex 5-hour window
when OpenAI reports one, regardless of plan name.

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
the reset dashboard, refresh controls, notifications settings, and account settings offline.

## Review smoke path

1. Launch the app.
2. Use `Preview Mode` or start ChatGPT sign-in from Settings.
3. Confirm the popup shows the reset dashboard: any plan leads with a reported 5-hour reset; an account with only a weekly window leads with weekly allowance and progress. Check that stale data is identified and the Refresh control works.
4. Confirm the settings window can sign out, change refresh cadence, switch System/Light/Dark appearance, and toggle menu bar labels.

## Scripted release smoke

Run the release guard before archiving:

```bash
Scripts/release-smoke.sh
```

This combines static checks, helper tests, and toolchain/build-settings checks. It is not full UI proof and can compile Rust test artifacts. It checks the project source of truth, App Store entitlements, helper build/embed wiring, `LSUIElement`, review metadata, privacy text, the versioned helper protocol markers, and the legacy-probe compile flag. It also preflights both macOS Rust targets, runs helper tests with that same rustup toolchain, and runs macOS plus iOS Xcode build-settings smokes when `xcodebuild` is available.

## Legacy probe quarantine

Direct `codex app-server` capture is excluded from normal shipping builds unless `CODEXEX_ENABLE_LEGACY_PROBE` is explicitly defined. The reducer and payload support types remain available so existing core regression tests can still validate snapshot mapping without enabling the probe path.

## Guardrails

- Keep the app menu-bar-only and sandbox-safe.
- Use official Codex interfaces only.
- Do not add alternate sign-in flows, browser scraping, or token extraction.
- Update `project.yml` when target wiring changes; update helper scripts when helper packaging changes.
- Do not hand-edit `CodexMeter.xcodeproj`; regenerate it from `project.yml`.
- Do not add project-local Codex hooks; keep generated Xcode protection in the documented `project.yml` workflow.

## Validation scope

Run checks that cover the changed behavior. SwiftPM covers core and macOS package targets; Xcode also covers the XPC host and iOS target wiring. For iOS changes, run the `CodexMeteriOS` scheme against an installed simulator destination. For helper or packaging changes, include helper tests and the release smoke script.

Record the revision, command, result, and any blocker. A source review, passing unit test, or successful archive does not establish UI behavior, device background delivery, or App Store acceptance. Use the review smoke path and physical-device checks where those behaviors changed.
