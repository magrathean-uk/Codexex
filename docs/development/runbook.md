# Codexex Runbook

The iOS app and widget extension are configured for version `6.2.0`, build `27`.
The macOS targets retain version `6.1.1`, build `26`. Keep these per-platform
`MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` values in `project.yml`;
regenerate the Xcode project after changing them.

## Architecture map

- `Sources/CodexMeterCore/` owns quota models, formatting, binary lookup, and service contracts.
- `Sources/CodexMeterApp/Support/` owns auth state, usage history, launch-at-login, XPC client, and menu bar model.
- `Sources/CodexMeterApp/UI/` and `Windows/` own popup, settings, onboarding, and status item presentation.
- `Helper/CodexexHelper/` is the Rust helper for ChatGPT sign-in, implemented as an OAuth device-code flow, and quota reads.
- `Sources/CodexexXPCService/` is the sandbox-safe bridge that launches the helper inside the app bundle.

## Build loop

The mandatory [Clean development](../../AGENTS.md#clean-development-mandatory) rules in `AGENTS.md` apply to every command below: run them through `clean-development run --session session-only -- <command>` and never unset, override or bypass the routed environment variables.

Xcode commands take their derived-data and SwiftPM cache locations from the routed `XCODE_DERIVED_DATA_PATH` and `SWIFTPM_SHARED_CACHE` variables and fall back to `/tmp` only when those are unset.

Swift package tests:

```bash
swift test
```

Rust helper tests:

```bash
cargo test --manifest-path Helper/CodexexHelper/Cargo.toml
```

The helper pins Codex `0.162.1` at commit
`092d3acd6bec3e3a14bdc7e7a2810ab628ab759d`. Reqwest stays on `0.12`
because the upstream custom-CA builder exposes that version's client types.
Keep the committed lock file: upstream pins Rama `0.3.0-alpha.4`, and its
`rama-error`, `rama-macros`, and `rama-utils` must stay on the matching alpha
versions. Their stable `0.3.0` releases are incompatible with this cohort.
Use `--locked` for repeatable verification and packaged helper builds.

Regenerate the Xcode project after `project.yml` changes:

```bash
xcodegen generate --spec project.yml
```

`Package.swift` is a local development and package-test adapter. Keep Xcode target wiring in `project.yml`.

Use builds and tests as the Swift typecheck gate. The existing
[compliance workflow](../../.github/workflows/cargo-deny.yml) runs `cargo-deny`
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

`codexex-status.sh` emits JSON derived from local session logs, including token totals, session summaries, usage signals, reset windows, plan type, and context-window pressure. The hook command records event metadata: event, working directory, tool, session ID, turn ID, and status. Working directory paths and identifiers can still be sensitive. It appends one JSONL file per day under `CODEXEX_HOOK_LOG_DIR`, or `$XDG_STATE_HOME/codexex/hooks` when that is unset, or the temporary directory when neither is set.

The installer uses `CODEX_HOME`, or `~/.codex` by default. It backs up an existing `hooks.json`, then replaces the `SessionStart`, `PermissionRequest`, `PostToolUse`, and `Stop` entries with Codexex commands. It may also back up and append a feature setting to an existing `config.toml`. Review those changes and the resulting TOML before using the hooks; installation is optional and changes user configuration. Keep this checkout available because installed commands reference its script paths.

Build or test the app target:

```bash
source ~/dev/machine/env.zsh
clean-development run --session session-only -- \
xcodebuild -project CodexMeter.xcodeproj \
  -scheme CodexMeterApp \
  -derivedDataPath "${XCODE_DERIVED_DATA_PATH:?load routed env}/codexex-derived-data" \
  -clonedSourcePackagesDirPath "${SWIFTPM_SHARED_CACHE:?load routed env}/codexex-swiftpm-cache" \
  test
```

`script/build_and_run.sh` preserves explicit caller cache paths and loads
`~/dev/machine/env.zsh` when either route is missing. It fails before stopping or
building the app if routing is unavailable, relative, or unwritable, or if an
external output volume is unmounted or its output parent is on another device. The machine preferences in
`~/dev/machine/storage.conf` select mounted `/Volumes/4TB/machine/cache` or real `~/dev/machine/cache`
for new sessions; persistent labs remain external.

The iOS target is wired through the `CodexMeteriOS` scheme in `project.yml`.
Pick an installed simulator destination before running iOS tests.

## iOS Live Activity

Home Screen widgets now have separate `Subscription quota` and `API balance`
configurations, each supporting small and medium sizes. The phone publishes a
display-only atomic App Group cache; the extension never reads credentials or
calls a provider. Successful source refreshes reload the timelines, while future
entries age the cached observation. Installed widgets also qualify for
BGAppRefresh without an active Live Activity. Keep the app and widget extension
provisioned for `group.com.magrathean.CodexexApp`.

WidgetKit timeline requests and BGAppRefresh grants are opportunistic, not a
five-minute polling guarantee. The existing relay still uses silent app wakes
while a live activity is registered; it does not send direct ActivityKit or
WidgetKit content pushes. API-only Live Activity content is not implemented.

Live Activity starts explicitly from iOS Settings after a valid quota refresh.
While it runs, the app schedules on-device background refresh and registers
for background notification wakes at the configured relay endpoint. The
registration request carries an APNs token, its environment, and an opaque
installation credential. It does not carry OpenAI credentials, account
identity, quota, or usage history. The relay's documented data handling is in
[PRIVACY.md](../../PRIVACY.md); its server implementation and deployment are outside
this repository.

After a wake, the phone attempts a direct quota refresh and updates the
activity. ActivityKit is requested with `pushType: nil`: these are app wake
notifications, not direct ActivityKit content pushes. Timing is controlled by
iOS. Tapping a stale activity opens Codexex and requests a manual refresh.
The activity shows account quota, not Mac-only session-log token usage.
Silent wakes fetch subscription quota without waiting for API billing requests.
BGAppRefresh also fetches quota first, then refreshes any installed API widgets.
Settings shows `Background updates` as Disabled, Pending or Registered; only an
accepted relay registration is Registered. Reopening the app retries both SDK
token registration and a pending relay request without discarding its retry.
`Test background update` requests a content-free wake for this installation only,
then instructs the owner to background the app. The relay delays delivery by
15 seconds and limits tests to once a minute. A successful request is not a
successful phone refresh; inspect the subsequent local receipt.

The card's Updated time comes from the last quota snapshot fetched on the
device; receiving a wake alone does not advance it. For physical-device
verification, all builds overwrite `Library/Caches/CodexexAPNsWake.json`
inside the app container with only the most recent wake's timestamps and
result. A `refreshed` receipt must have a `snapshotCapturedAt` after
`receivedAt`. Read only this file when checking delivery; it contains no
account, token, quota, or history. Settings also displays the last wake outcome.
APNs acceptance, registration renewal, and an unchanged percentage alone do
not prove that a background quota refresh completed.

Relevant history: `73f4632` (2026-08-09) repaired shared ActivityAttributes,
duplicate recovery and stale retention; `a3875d5` (2026-08-11) introduced
background refresh and adjusted freshness timing; `fca7629` (2026-08-26)
serialized ActivityKit work and rejected older completions after newer updates,
sign-out or reset. Relay commit `4b8b0963` (2026-09-26) prevented delayed invalid
token responses from deleting renewed registrations. The Home Screen widget
work also removes the requirement for an active Live Activity before an
installed widget can obtain a BGAppRefresh grant.

On 2026-10-13, a scoped aggregate query found no Codexex registrations in the
live relay. The existing distributed 6.1.1 build's container was inaccessible.
A new signed development build was installed and launched on the paired iPhone
after enabling the app and extension's matching App Group and APNs provisioning.
Enrollment and a fresh on-device background receipt must be checked separately;
a successful installation is not evidence of either.
The subsequent signed-device self-test received HTTP 202. The local receipt
records a wake at 22:54:46 BST and a newer quota observation about 0.63 seconds
later; an immediate retry returned 429. A subsequent Home Screen launch/test
received HTTP 202 at 23:15:14 BST. Its local receipt recorded `appState: background`
at 23:17:38 BST and a new quota observation at 23:17:39 BST, confirming refresh
while the app was backgrounded. The roughly 143-second delay is not a delivery
deadline. Protected data was available, so this receipt does not establish locked
execution. Diagnostic exports remain on the phone and contain no tokens,
installation IDs, provider IDs or quota values.

See Apple's [widget refresh guidance](https://developer.apple.com/documentation/widgetkit/keeping-a-widget-up-to-date),
[background notification guidance](https://developer.apple.com/documentation/usernotifications/pushing-background-updates-to-your-app),
and [Live Activity lifecycle](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities).

## Menu bar presentation

Settings opens at Accounts, with separate subscription and API setup. General,
Appearance, Data and About use native sidebar navigation and controls. On iOS,
grouped Settings separates Accounts, Appearance, Live Activity, Data and About;
API key, balance and report setup each has a dedicated form. Onboarding and device
sign-in use native navigation and focused actions. Custom stage transitions use
short opacity changes and honor Reduce Motion.

`SettingsDesignRenderTests` captures the Mac groups and setup stages in light and
dark appearance when `SETTINGS_DESIGN_RENDER_OUTPUT` names an existing output
folder. It uses isolated preferences and API preview mode. Review the captured
layouts alongside signed-phone navigation; compilation alone does not verify
touch targets, VoiceOver or device text scaling.

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
