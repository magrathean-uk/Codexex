<!-- clean-development-policy:v6 -->
# Codexex

Apple-platform app for tracking Codex usage quota: Swift package, Xcode project generated from `project.yml`, a Rust helper, and a React prototype under `Prototypes/MatrixQuota`. State and decisions live in `~/dev/records/Codexex/` (public repo, so nothing private here).

## Layout

- `Sources/CodexMeterCore/` quota models, parsing, formatting, shared contracts.
- `Sources/CodexMeterApp/` macOS menu bar app, onboarding, settings, local history. `Sources/CodexMeteriOS/` iPhone and iPad companion.
- `Helper/CodexexHelper/` Rust device-auth and quota helper; `Sources/CodexexXPCService/` is the sandbox bridge.
- `project.yml` defines targets; `CodexMeter.xcodeproj` is generated from it. Regenerate after changing versions.
- `fastlane/metadata/`, `PRIVACY.md`, `AppStore/`: release metadata and privacy copy. `docs/development/runbook.md` and `Scripts/release-smoke.sh` describe release tooling.
- `Prototypes/MatrixQuota/AGENTS.md` covers the Matrix prototype. Native UI uses SwiftUI and project tokens/components. Diagnostics are local.

## Commands and acceptance

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

`.github/workflows/cargo-deny.yml` checks Rust licences, sources and bans. Device testing, APNs, signing and App Store acceptance are separate from these local checks.

## Constraints

- No GitHub Releases; tags are annotated `vX.Y.Z` on the shipping commit.
