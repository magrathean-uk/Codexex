# Codexex App Store Helper Design

## Goal

Ship `Codexex` as a real Mac App Store app without depending on an external `codex` install.

This version must keep the core value of the product:

- show Codex quota state in the menu bar
- let the user sign in with ChatGPT or use an API key
- stay native on macOS
- stay review-safe for the App Store

## Chosen Direction

Use a native macOS app with a bundled app-owned helper.

- main app: SwiftUI/AppKit UI, settings, menu bar shell
- native auth: `AuthenticationServices` for web auth, Safari handoff only when needed
- bundled helper: app-owned restricted backend for Codex auth/quota work
- local bridge: narrow XPC contract between app and helper

The helper is not a general CLI.
It exists only to support:

- sign in
- sign out
- account state
- rate limit / quota state

## Why This Path

This is the only path that still matches the product.

Pure network/XPC was attractive, but it depends on official quota endpoints we do not have confidence in.
External `codex` from `PATH` is not App Store-safe.
Electron for login adds a second runtime, weakens the native app, and creates more review risk.

A bundled helper keeps the product native while removing the external dependency.

## Product Architecture

### 1. Main App

Owns:

- menu bar item
- popup UI
- settings UI
- launch at login
- reduced-motion aware animations
- auth state presentation

It does not probe binaries or parse local Codex files.

### 2. Native Auth Layer

Use Apple-native auth surfaces first.

Preferred order:

1. `ASWebAuthenticationSession` when the Codex/OpenAI auth flow supports redirect-based web auth cleanly
2. Safari device flow when device-code auth is the supported Codex path

Rules:

- no embedded Chromium
- no Electron
- no browser cookie access
- no browser profile scraping
- no token theft

### 3. Bundled Helper

The helper is bundled inside the app and signed with it.
It is app-owned, sandboxed, and limited in scope.

Responsibilities:

- perform Codex-compatible auth flow support
- fetch account state
- fetch rate-limit state
- normalize helper output into shared snapshot models

Non-goals:

- local code execution
- agent runtime
- generic shell access
- arbitrary filesystem access

### 4. XPC Bridge

The UI process talks only to a thin app-local XPC service/client layer.
This keeps the helper boundary narrow and reviewable.

Calls needed:

- `fetchSnapshot()`
- `beginSignIn()`
- `pollSignIn()` or streamed auth progress
- `saveAPIKey()`
- `signOut()`

## Auth Model

### ChatGPT Sign-In

User taps `Sign in with ChatGPT`.
The app starts native auth.
If device flow is required, the app shows the code in Settings and opens Safari.
The helper completes the exchange and stores only the minimal session material needed for quota reads.

### API Key

User pastes key in Settings.
The app stores it in Keychain.
The helper receives it only for requests that need it.

### Sign Out

Sign out removes helper session state and clears any app-owned keychain entries for this app.

## Data Model

Keep `CodexMeterCore` as the shared model layer.

The helper returns normalized values only:

- account email / plan
- Codex quota buckets
- Spark quota buckets when present
- reset timestamps
- capture timestamp
- auth mode / signed-in state

The UI should not know whether the data came from device auth, API key, or helper internals.

## App Store Policy Shape

### Safe

- sandboxed app
- bundled helper only
- native auth APIs or Safari handoff
- app-owned Keychain storage
- no dependency on Homebrew or PATH
- no cookie scraping
- no browser automation

### Not Allowed In This Build

- external `codex` lookup
- reading `~/.codex/auth.json`
- scraping ChatGPT or Codex browser sessions
- hidden webviews for login
- embedded Electron/Chromium auth shell

## UX Changes

Keep current product shape.
Only the backend/auth plumbing changes.

### Popup

- keep hybrid glass style
- keep quota cards
- keep history and forecast toggle
- animate progress changes and refresh transitions

### Settings

- account section
- sign in / sign out
- API key section
- behavior section
- no diagnostics wall

## Motion

Use subtle macOS-style motion only.

- progress bar interpolation
- content fade on refresh
- value transitions for percentages
- auth state row reveal/collapse
- respect Reduce Motion

## Build Structure

Add these pieces:

- `Sources/CodexHelperBridge/` shared contract types if needed
- `Sources/CodexexXPCService/` thin XPC boundary
- `Sources/CodexexHelper/` bundled helper implementation
- app entitlements
- XPC/helper entitlements

The current `CodexAppServerProbe` becomes legacy and must not be part of the App Store path.

## Main Risks

### 1. Helper Scope Risk

If we bundle too much of Codex CLI behavior, App Review risk rises.
The helper must stay narrow.

### 2. Auth Flow Risk

If OpenAI/Codex only supports device flow for this data path, UX is slightly worse but still acceptable.
That is still better than Electron or cookie access.

### 3. Upstream Drift

If Codex helper internals drift from upstream behavior, quota parsing can break.
We should isolate that logic behind a tiny stable interface.

## Acceptance Criteria

- no external `codex` dependency
- menu bar app remains native
- right click menu still works
- ChatGPT sign-in works through native auth or Safari device flow
- API key mode works
- quota refresh works without `PATH` lookup
- app is sandbox-ready for Mac App Store review
- no Electron, no cookie scraping, no browser theft

## Recommendation

Proceed with the helper-based App Store architecture.

This is the strongest balance of:

- feature parity
- native UX
- App Store compliance
- maintainability
