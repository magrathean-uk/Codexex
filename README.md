# Codexex

Codexex is a macOS menu bar app for viewing Codex quota state, reset windows, history, and forecast without turning into a full desktop dashboard.

Built by [Magrathean UK](https://magrathean.uk).

## Canonical docs

- [AGENTS.md](./AGENTS.md)
- [RUNBOOK.md](./RUNBOOK.md)
- [PRIVACY.md](./PRIVACY.md)

## Product shape

- Menu bar first. No dock-facing main window.
- SwiftUI app content with a small AppKit shell for status item behavior.
- `5H`, weekly, and 30-day history views, reset times, local history, and forecast.
- Local Codex session usage: project/model/session burn, cache-read pressure, tool-loop and model-overkill signals.
- Companion scripts for local status JSON and Codex lifecycle hook capture.
- System, Light, and Dark appearance modes that follow the same app theme in popup and Settings.
- ChatGPT sign-in plus Preview Mode for offline review.
- Sandboxed app with a bundled helper and XPC bridge.

## Repo layout

- `Sources/CodexMeterCore/`: quota models, formatting, binary discovery, and service contracts.
- `Sources/CodexMeterApp/`: app lifecycle, menu bar model, popup, settings, onboarding, and history UI.
- `Sources/CodexexXPCService/`: XPC service that brokers the helper process.
- `Helper/CodexexHelper/`: Rust helper used for the OAuth device-code flow and quota reads.
- `Scripts/`: helper build and embed scripts used by the Xcode target.
- `AppStore/`: entitlements and App Store-facing bundle settings.
- `Tests/`: XCTest coverage for both core logic and app behavior.
- `fastlane/metadata/`: checked-in App Store text inputs.
- `Package.swift`: SwiftPM adapter for local development and package tests; `project.yml` remains the Xcode source of truth.

## Quick start

```bash
source ../build-env.sh
swift test
xcodegen generate
xcodebuild -project CodexMeter.xcodeproj \
  -scheme CodexMeterApp \
  -derivedDataPath "$XCODE_DERIVED_DATA_PATH" \
  -clonedSourcePackagesDirPath "$SWIFTPM_SHARED_CACHE" \
  build
```

Use [RUNBOOK.md](./RUNBOOK.md) for helper flow, XPC notes, and release hygiene.

## Legal

Copyright © 2026 Magrathean UK Ltd. All rights reserved.

Codexex is proprietary software. See [`LICENSE`](./LICENSE) for the full licence text. Third-party components and their licences are listed in [`LICENSE.md`](./LICENSE.md). Apache-2.0 attribution required by the openai/codex Rust crates and other upstream components is recorded in [`NOTICE`](./NOTICE). Public availability of this repository does not grant any right to copy, modify, redistribute, or use the Codexex source outside the licence terms.

The published Codexex application (macOS & iOS) is governed by the user-facing terms published at:

- Privacy Policy — <https://magrathean.uk/apps/codexex/privacy/>
- Terms of Service — <https://magrathean.uk/apps/codexex/terms/>

### Quota information is informational only

Quota readings, reset timing, history, session-burn analytics, and forecast values shown by Codexex are derived from third-party API responses (notably from OpenAI) and from local computation. They may be incomplete, delayed, inaccurate, rounded, cached, or unavailable for reasons outside our control. Codexex is **not a billing system, an audit log, or a contractual record** and is **not a substitute for the source of truth provided by your OpenAI account dashboard or invoices**.

### Trademarks and disclaimers

OpenAI, ChatGPT, GPT, Codex, and Spark are trademarks of OpenAI, Inc. or its affiliates. Anthropic and Claude are trademarks of Anthropic, PBC. Apple, the Apple logo, macOS, iPadOS, iOS, and Swift are trademarks of Apple Inc.

Codexex is **not affiliated with, endorsed by, sponsored by, authorised by, or in any way officially connected to** OpenAI, Anthropic, or Apple. References to these names exist solely for descriptive interoperability. All trademarks remain the property of their respective owners.

### Reporting

For security issues, see [`SECURITY.md`](./SECURITY.md). For licensing or commercial enquiries, email <contact@magrathean.uk>.

---

Magrathean UK Ltd. is a company registered in England and Wales (Company No. 16955343) with registered office at 16 Caledonian Court West Street, Watford, England, WD17 1RY.
