# Research notes

Target: build a single-provider Codex-only macOS menu bar app.

## Repos analysed

### 1. CodexBar
Most important source pattern.

Useful takeaways:
- menu bar-first UX
- no-login expectation
- provider-specific probing
- Codex app / CLI reuse instead of forcing fresh auth
- multi-bucket rate-limit model for Codex
- reset-window centric presentation

Deliberately *not* copied:
- multi-provider scope
- web/API fallback layers
- large settings surface

### 2. ClaudeBar
Useful takeaways:
- state kept close to UI entrypoints, with separable auth and dashboard logic
- clean separation between probing and presentation
- protocol-friendly architecture for testability
- direct SwiftUI views instead of unnecessary ViewModel layers

Deliberately *not* copied:
- provider sprawl
- theming complexity
- settings-heavy architecture

### 3. Claude Usage Tracker
Useful takeaways:
- native Swift / SwiftUI menu bar approach
- refresh-after-sleep behaviour
- careful attention to stale usage / reset windows
- focus on low-friction visibility in the status item

Deliberately *not* copied:
- charts/history DB
- profile switching
- broader provider/auth surface

## Final architecture

Chosen synthesis:

- native Swift 6
- Swift Package project
- split app state across menu bar shell, auth session, and dashboard state
- menu bar extra with focused popup/settings/onboarding views
- bundled helper plus XPC bridge for auth and quota reads
- ChatGPT device code sign-in and Preview Mode
- no unsupported token scraping
- Spark displayed separately when the upstream bucket id/name exposes it
