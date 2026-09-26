# Codexex

Codexex is a native macOS menu bar utility with an iPhone and iPad companion for viewing Codex quota windows, reset timing, and local usage signals.

Built by [Magrathean UK](https://magrathean.uk). Codexex is independent from OpenAI, Anthropic, and Apple.

## What it does

- Shows the reported 5-hour quota window when one is available, with weekly allowance and reset timing alongside it.
- Uses weekly allowance and progress when an account reports no 5-hour window.
- Provides a compact macOS menu bar popup, Settings, onboarding, refresh controls, notifications, appearance choices, and launch-at-login support.
- Provides native iPhone and iPad quota views, Preview Mode, settings, and an optional Live Activity for the Lock Screen and Dynamic Island.
- Keeps quota history and forecast views on the device.
- On macOS, reads official local Codex session logs to show token burn, project and model activity, cache-read pressure, tool-loop signals, and context-window pressure when the relevant data is present.
- Uses ChatGPT sign-in through an OAuth device-code flow. The macOS app uses a bundled Rust helper behind a sandboxed XPC service.

Quota and forecast values are informational. They can be delayed, incomplete, rounded, unavailable, or different from the source of truth in your OpenAI account dashboard or invoices.

## Privacy model

Sign-in, token storage, quota requests, quota history, and local session analysis run on the device. Codexex does not use browser cookies or browser scraping, and it does not send OpenAI credentials, account identity, quota values, or usage history to a Magrathean account service.

The optional iOS Live Activity wake path uses content-free background notifications. The phone fetches quota directly from OpenAI after a wake. iOS controls background execution timing, so a wake or an unchanged display does not prove that a quota refresh completed. See [PRIVACY.md](./PRIVACY.md) for the full policy.

## Repository map

- `Sources/CodexMeterCore/` contains shared quota models, formatting, local usage parsing, and service contracts.
- `Sources/CodexMeterApp/` contains the macOS menu bar app, onboarding, Settings, history, and local diagnostics.
- `Sources/CodexMeteriOS/` contains the iPhone and iPad app.
- `Sources/CodexMeterWidgets/` contains the WidgetKit extension for Live Activity presentation.
- `Sources/CodexexXPCService/` contains the sandbox bridge to the helper.
- `Helper/CodexexHelper/` contains the Rust authentication and quota helper.
- `Scripts/` contains helper packaging and optional local companion scripts.
- `Tests/` contains Swift and XPC tests.
- `project.yml` is the Xcode project source of truth. `Package.swift` is the Swift Package Manager adapter for local package tests.
- `fastlane/metadata/` contains App Store metadata inputs.

## Requirements

The project targets macOS 26 and iOS 26. `Package.swift` declares Swift tools version 6.2, while the generated Xcode targets set `SWIFT_VERSION` to 6.0. Xcode project generation uses XcodeGen. The macOS helper build uses Rust's stable toolchain and supports the `aarch64-apple-darwin` and `x86_64-apple-darwin` targets for a universal app build.

## Build and test

Run commands from the repository root. These commands are defined by the checked-in manifests and runbook:

```bash
swift test
cargo test --manifest-path Helper/CodexexHelper/Cargo.toml
xcodegen generate --spec project.yml
```

The macOS app test scheme is:

```bash
xcodebuild -project CodexMeter.xcodeproj \
  -scheme CodexMeterApp \
  -derivedDataPath /tmp/codexex-derived-data \
  -clonedSourcePackagesDirPath /tmp/codexex-swiftpm-cache \
  test
```

The iOS target and tests are wired through the `CodexMeteriOS` scheme in `project.yml`; choose an installed iOS 26 simulator destination when invoking `xcodebuild` for that scheme.

Useful repository checks:

```bash
bash Scripts/check-codexex-companions.sh
bash Scripts/release-smoke.sh
```

After changing `project.yml`, regenerate `CodexMeter.xcodeproj`. Do not hand-edit the generated project.

## Optional local companions

The status script inspects local Codex session data. The optional installer writes lifecycle hooks at the user level:

```bash
Scripts/codexex-status.sh
Scripts/install-codexex-companions.sh
```

The installer backs up an existing hooks file and backs up the user configuration when it needs to enable Codex hooks. It replaces entries for the four named lifecycle events it manages. Review the resulting user-level configuration before relying on the hooks; [RUNBOOK.md](RUNBOOK.md#companion-commands) describes the changes. Hook metadata can still contain private paths and identifiers.

## Documentation

- [AGENTS.md](./AGENTS.md) contains project boundaries and source-backed development rules.
- [RUNBOOK.md](./RUNBOOK.md) describes the architecture, release checks, helper/XPC flow, and Live Activity behavior.
- [PRIVACY.md](./PRIVACY.md) describes local data, network communication, and the optional wake service.
- [SECURITY.md](./SECURITY.md) explains vulnerability reporting and safe-harbour boundaries.
- [CONTRIBUTING.md](./CONTRIBUTING.md) describes the contribution workflow.
- [SUPPORT.md](./SUPPORT.md) describes support requests and useful diagnostic material.
- [license.md](./license.md) inventories third-party components and their licence obligations.
- [NOTICE](./NOTICE) records attribution notices.

## Licence

The Codexex source is proprietary software. See [LICENSE](./LICENSE) for the complete source licence. Third-party components retain their own licences, documented in [license.md](./license.md) and [NOTICE](./NOTICE).

Copyright © 2026 Magrathean UK Ltd. All rights reserved.

For security reports, see [SECURITY.md](./SECURITY.md). For licensing enquiries, contact `contact@magrathean.uk`.
