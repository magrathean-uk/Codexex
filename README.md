<p align="center">
  <img src="https://raw.githubusercontent.com/magrathean-uk/magrathean-uk/main/assets/icons/codexex.png" width="96" height="96" alt="">
</p>

<h1 align="center">Codexex</h1>

<p align="center">A native macOS menu bar utility with an iPhone and iPad companion for viewing Codex quota windows, reset timing, and local usage signals.</p>

<p align="center">
  <a href="https://codexex.eu">Website</a> ·
  <a href="docs/index.md">Documentation</a> ·
  <a href="https://codexex.eu/privacy/">Privacy</a>
</p>

## Overview

Codexex is independent from OpenAI, Anthropic, and Apple. It shows the reported 5-hour
quota window when one is available, with weekly allowance and reset timing alongside it,
and falls back to weekly allowance and progress when an account reports no 5-hour window.
Quota and forecast values are informational: they can be delayed, incomplete, rounded,
unavailable, or different from the source of truth in your OpenAI account dashboard or
invoices.

## Features

- Compact macOS menu bar popup, Settings, onboarding, refresh controls, notifications,
  appearance choices, and launch-at-login support.
- Native iPhone and iPad quota views, Preview Mode, settings, and an optional Live
  Activity for the Lock Screen and Dynamic Island.
- On-device quota history and forecast views.
- On macOS, reads official local Codex session logs to show token burn, project and model
  activity, cache-read pressure, tool-loop signals, and context-window pressure when the
  relevant data is present.
- ChatGPT sign-in through an OAuth device-code flow; the macOS app uses a bundled Rust
  helper behind a sandboxed XPC service.

Sign-in, token storage, quota requests, quota history, and local session analysis run on
the device. Codexex does not use browser cookies or browser scraping, and does not send
OpenAI credentials, account identity, quota values, or usage history to a Magrathean
account service. See the [privacy notice](https://codexex.eu/privacy/) for the full
picture, including the optional iOS Live Activity wake path.

## Getting started

Run commands from the repository root:

```bash
swift test
cargo test --manifest-path Helper/CodexexHelper/Cargo.toml
xcodegen generate --spec project.yml
```

See the [runbook](docs/development/runbook.md) for the full build loop, release checks,
and the helper/XPC flow.

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

## Optional local companions

The status script inspects local Codex session data. The optional installer writes lifecycle hooks at the user level:

```bash
Scripts/codexex-status.sh
Scripts/install-codexex-companions.sh
```

The installer backs up an existing hooks file and backs up the user configuration when it needs to enable Codex hooks. It replaces entries for the four named lifecycle events it manages. Review the resulting user-level configuration before relying on the hooks; the [runbook](docs/development/runbook.md#companion-commands) describes the changes. Hook metadata can still contain private paths and identifiers.

## Documentation

- [docs/index.md](docs/index.md) — documentation index.
- [AGENTS.md](./AGENTS.md) — project boundaries and source-backed development rules.
- [.github/CONTRIBUTING.md](.github/CONTRIBUTING.md) — contribution workflow.
- [.github/SUPPORT.md](.github/SUPPORT.md) — support requests and useful diagnostic material.
- [.github/SECURITY.md](.github/SECURITY.md) — vulnerability reporting and safe-harbour boundaries.
- [PRIVACY.md](./PRIVACY.md) — local data, network communication, and the optional wake service.

## Licence

Codexex is proprietary; all rights reserved. See [LICENSE](LICENSE) and
[NOTICE](NOTICE).

<sub>© 2026 MAGRATHEAN UK LTD · [Legal](https://github.com/magrathean-uk/.github/blob/main/LEGAL.md)</sub>
