# Codexex

Codexex is a native macOS 26+ menu bar app for watching Codex quota use.

It shows:
- `5H` and `W` Codex usage in the menu bar
- detailed Codex and Spark windows in the popup
- reset times
- 30-day usage history
- weekly pace marker and forecast
- ChatGPT OAuth sign-in and Preview Mode

## Main features

- Menu bar first. No dock UI.
- Native Swift 6 app.
- SwiftUI UI with small AppKit shell for menu bar behavior.
- Sandboxed app target.
- Embedded helper for auth and quota reads.
- Launch at login.
- Auto refresh with 5 min, 10 min, or 60 min intervals.
- Optional history chart in popup.
- Menubar label can show `5H`, `W`, or both.

## Sign-in

Codexex supports:
- `Sign in with ChatGPT`
- `Preview Mode`

ChatGPT sign-in uses device code flow:
1. Open `Settings`
2. Click `Sign In with ChatGPT`
3. Copy the code shown in the app
4. Click `Open Safari`
5. Finish sign-in in Safari

First launch also offers `Preview Mode` for review and offline testing.

## Build

```bash
source ../build-env.sh
swift test
xcodegen generate
xcodebuild -project CodexMeter.xcodeproj \
  -scheme CodexMeterApp \
  -derivedDataPath "$XCODE_DERIVED_DATA_PATH" \
  -clonedSourcePackagesDirPath "$SWIFTPM_SHARED_CACHE" build
```

## Project layout

- `Sources/CodexMeterApp/Support/` app state, auth, storage, helper client
- `Sources/CodexMeterApp/UI/` menu bar, popup, settings, onboarding views
- `Sources/CodexMeterApp/Windows/` window controllers
- `Sources/CodexMeterCore/` shared models and reducers
- `Sources/CodexexXPCService/` XPC service target
- `Helper/CodexexHelper/` embedded helper
- `AppStore/` entitlements
- `Scripts/` helper build and embed scripts
- `Tests/CodexMeterCoreTests/` unit tests

## App Store notes

Current app shape is App-Store-oriented:
- App Sandbox enabled
- utility category set
- no browser scraping
- no cookie theft
- no private APIs
- helper is bundled inside app

Before App Store submission, do a Release archive and validation pass.

See:
- `docs/FEATURES.md`
- `docs/APP_REVIEW.md`
- `CHANGELOG.md`
