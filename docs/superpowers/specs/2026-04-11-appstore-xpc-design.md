# Codexex App Store XPC Design

## Goal

Ship `Codexex` as a Mac App Store-safe menu bar app.

This means:

- no external `codex` binary lookup
- no Homebrew dependency
- no browser scraping
- sandboxed app
- bundled app-owned service only

## Chosen Architecture

Use a bundled `XPC` service.

- main app: UI, settings, Keychain, launch-at-login state
- XPC service: network/auth/quota bridge
- shared model layer: normalized account + usage snapshot

The app talks only to the XPC service.

## Why This Path

It is safer than:

- shelling out to `codex`
- depending on `PATH`
- embedding a general CLI helper

It also gives tighter control over:

- entitlements
- auth handling
- sandbox boundaries
- future App Store review

## Auth

Supported modes:

1. `Sign in with ChatGPT`
2. `API key`

Rules:

- Safari/device or supported web flow only
- API key stored in Keychain by the main app
- no cookies
- no token scraping
- no reading browser state

The app owns credentials.
The XPC service receives only what it needs for requests.

## Data Flow

1. UI asks model to refresh
2. model calls XPC client
3. XPC service performs supported network requests
4. XPC returns normalized snapshot
5. UI renders Codex / Spark / history

The current `CodexAppServerProbe` path becomes non-App-Store legacy and must not be used by the App Store build.

## Targets

Add one new bundled XPC target.

- `Codexex` app target
- `CodexexXPCService` service target
- keep `CodexMeterCore` for shared models/formatting where useful

## Entitlements

Main app:

- App Sandbox: on
- Keychain access: app-owned
- no external process execution

XPC service:

- App Sandbox: on
- outgoing network client entitlement
- only minimal capabilities needed for remote auth/quota calls

## UI Changes

Popup and Settings stay as they are structurally.
Only data source changes.

Add subtle motion:

- animated progress fill
- numeric text transitions
- card fade/scale on refreshed snapshot
- settings inline note reveal for auth or launch-at-login state
- respect Reduce Motion

## Migration

1. add XPC service target in `project.yml`
2. define request/response contract
3. move auth/network into service
4. replace `CodexAppServerProbe` usage in app model
5. gate old external-binary path out of App Store build
6. add sandbox entitlements
7. verify app still works from menu bar

## Acceptance Criteria

- app no longer depends on external `codex`
- app launches and refreshes inside sandbox
- sign in and API key both work
- popup/settings still work
- right click still works
- launch-at-login still works
- no browser scraping or unsupported auth shortcuts

## Main Risk

This plan depends on supported direct network auth/quota endpoints existing for the needed Codex data.

If those endpoints do not exist or do not expose quota data, the App Store build must reduce scope instead of falling back to external CLI behavior.
