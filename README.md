# Codexex

Codexex is a macOS menu bar app for viewing Codex quota state, reset windows, history, and forecast without turning into a full desktop dashboard.

## Canonical docs

- [AGENTS.md](./AGENTS.md)
- [RUNBOOK.md](./RUNBOOK.md)
- [PRIVACY.md](./PRIVACY.md)

## Product shape

- Menu bar first. No dock-facing main window.
- SwiftUI app content with a small AppKit shell for status item behavior.
- `5H` and weekly quota views, reset times, local history, and forecast.
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
