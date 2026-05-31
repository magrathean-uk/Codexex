# Codexex

## Stack
Swift 6 / SwiftUI macOS (XcodeGen + SwiftPM), fastlane

## Build
```
xcodegen generate --spec project.yml   # regenerate .xcodeproj
xcodebuild -project CodexMeter.xcodeproj -scheme CodexMeterApp -derivedDataPath /tmp/codexex-derived-data -clonedSourcePackagesDirPath /tmp/codexex-swiftpm-cache build
swift test
cargo test --manifest-path Helper/CodexexHelper/Cargo.toml
bash Scripts/release-smoke.sh
```

## Key paths
- `Sources/CodexMeterCore/` — quota parsing and contracts
- `Sources/CodexMeterApp/` — menu bar UI, onboarding, settings, history state
- `Sources/CodexexXPCService/` — sandbox bridge
- `Helper/CodexexHelper/` — helper auth and quota work
- `Scripts/` — hook event, status, companion install scripts
- `fastlane/metadata/` — App Store release text

## Generated — do not hand-edit
- `CodexMeter.xcodeproj` — edit `project.yml` instead

## Done when
- Relevant build/test/smoke command ran, or the blocker is explicit
- `project.yml` changes are followed by `xcodegen generate --spec project.yml`
- Final note includes verification result and remaining unknowns

## Notes
- No browser scraping, private APIs, cookie theft, or alternate auth flows
- No external telemetry
