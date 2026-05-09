# Codexex

## Stack
Swift 6 / SwiftUI macOS (XcodeGen + SwiftPM), fastlane

## Build
```
source /Users/bolyki/dev/source/build-env.sh
xcodegen generate --spec project.yml   # regenerate .xcodeproj
xcodebuild -project CodexMeter.xcodeproj -scheme CodexMeter build
swift test
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

## Notes
- No browser scraping, private APIs, cookie theft, or alternate auth flows
- No external telemetry
