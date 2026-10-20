# Codexex Mac theme: VM verification

14 October 2026. [Open the gallery](index.html).

The Mac theme now uses the iOS neutral light/charcoal surfaces and adaptive blue
actions. Quota green and graph accents remain unchanged. Small dim labels have
stronger contrast. Settings and onboarding keep their native controls and layout.

All app execution, test execution, and captures ran inside Bolyki Lab
`macos26-agent`, macOS 26.6.2 (25G83), arm64. The host only compiled/signed.
The development-signed Xcode app was temporarily installed at the unique guest
path `/Applications/CodexexThemeReview.app`; its strict signature check passed.
The app launched its XPC service and embedded helper. No provider sign-in was
started, and no credentials were transferred.

## Evidence

- `live/`: original VNC screenshot of the signed native app, captioned by actual
  visible content. Guest desktop chrome is part of the unedited original.
- `fixtures/`: 20 actual SwiftUI Settings/onboarding view renders across light
  and dark appearances, with isolated defaults and sample API preview data.
  These standalone test panels are inactive; grey controls reflect that state.
  JSON sidecars record native focus and appearance.
  About fixtures use the CLI runner's icon/version metadata, not release branding.
- `manifest.json`: exact image and source hashes.
- `verification/`: five test logs, without VNC connection/authentication output.

## Checks

The VM passed 148 App XCTest cases plus 16 App Swift Testing cases, and 86 Core
XCTest cases plus 20 Core Swift Testing cases. The final XPC suite passed all five
cases, including real helper discovery, launch, and roundtrip from a path with
spaces, `#`, and `%`. The Settings render case passed its viewport checks and
produced all 20 fixtures. The corrected monthly-history clock fixture passed
both America/Los_Angeles and UTC.

The VM found and fixed a real helper lookup issue: `URL.path()` encoded spaces
before filesystem lookup. The source now uses the decoded `.path` property.

## Limits and environment findings

The readonly shared Xcode toolchain can run standalone XCTest. App-hosted
`xcodebuild test-without-building` requires a missing CoreSimulator first-launch
component; no additional SDK/component installation was made. Fixture renders
therefore validate native layout and appearance, with inactive focus recorded.
The separate signed app capture verifies actual guest app launch.

Framework symlinks were transferred in a ZIP and extracted on the guest native
filesystem. Direct traversal through the Virtio shared filesystem produced
symlink errors, and relocating Apple's signed `/bin/cat` into that mount was
killed by the guest. The regression uses an executable shell wrapper around the
original `/bin/cat` and passes. These findings are retained in task scratch.

Provider quota/balance, a live account login, signing distribution, and APNs
delivery were outside this Mac theme verification.

The unique guest test app was removed. `macos26-agent` was returned to its
initial stopped state; the provider stop command followed a bounded wait for
the guest-initiated shutdown. Other guests and host coding sessions were preserved.
