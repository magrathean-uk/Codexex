# Codexex project context

Codexex is an Apple-platform app for tracking Codex usage quota. It has a Swift package, an Xcode project generated from `project.yml`, and a React prototype under `Prototypes/MatrixQuota`.

## Structure and references

- `README.md` describes the product and layout. `docs/development/runbook.md` and `Scripts/release-smoke.sh` describe release tooling.
- `Sources/CodexMeterCore/` contains quota models, parsing, formatting, and shared contracts.
- `Sources/CodexMeterApp/` contains the macOS menu bar app, onboarding, settings, and local history UI.
- `Sources/CodexMeteriOS/` contains the iPhone and iPad companion, using shared core quota contracts.
- `Helper/CodexexHelper/` implements device authentication and quota helper work. `Sources/CodexexXPCService/` contains the sandbox bridge.
- `fastlane/metadata/` contains release metadata; `PRIVACY.md` contains privacy copy. Diagnostics are local.
- `project.yml` defines Xcode targets and build settings; `xcodegen generate --spec project.yml` generates `CodexMeter.xcodeproj`. `Package.swift` defines the Swift package.
- No project-local Codex hook is installed.
- `Prototypes/MatrixQuota/AGENTS.md` describes the Matrix prototype. Native UI uses SwiftUI and project tokens/components.

## Command and validation reference

Xcode commands use the workstation's `XCODE_DERIVED_DATA_PATH` and `SWIFTPM_SHARED_CACHE` locations, provided by `~/dev/machine/env.zsh`.

```bash
source "$HOME/dev/machine/env.zsh"
swift test
cargo test --manifest-path Helper/CodexexHelper/Cargo.toml
xcodegen generate --spec project.yml
xcodebuild -project CodexMeter.xcodeproj -scheme CodexMeterApp \
  -derivedDataPath "$XCODE_DERIVED_DATA_PATH/codexex-derived-data" \
  -clonedSourcePackagesDirPath "$SWIFTPM_SHARED_CACHE/codexex-swiftpm-cache" test
bash Scripts/check-codexex-companions.sh
bash Scripts/release-smoke.sh
```

`.github/workflows/cargo-deny.yml` checks Rust dependency licences, sources, and bans. Local checks, device testing, APNs checks, deployment, signing, and App Store acceptance cover different environments.

The workstation environment also provides `$TMPDIR` for session scratch, `$CLEAN_DEV_BUILDS` for throwaway build output, and tool-specific cache variables. `.clean-development.json` describes this project's build and dependency directories.

## URL migration reference

[NEXT-RELEASE-URLS.md](NEXT-RELEASE-URLS.md) records the migration to `https://magrathean.uk/solutions/<slug>/` and `contact+<slug>@magrathean.uk`.
