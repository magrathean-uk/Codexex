https://github.com/bolyki01/Codexex

# Codexex Improvement Plan

## Current State

- Codexex is a menu-bar-first macOS app with three core layers: SwiftUI app shell, XPC bridge, and a Rust helper.
- The repo has good source-of-truth discipline: `project.yml`, helper build/embed scripts, App Store entitlements, and checked-in metadata.
- Core logic and analytics already have solid unit coverage.
- The biggest risks are concentrated logic and long-term contract drift:
  - `Sources/CodexMeterApp/Support/CodexMenuBarModel.swift`
  - `Sources/CodexMeterApp/Support/CodexUsageHistoryAnalytics.swift`
  - `Sources/CodexMeterCore/CodexAppServerProbe.swift`
  - `Sources/CodexMeterApp/Support/CodexXPCClient.swift`
  - `Helper/CodexexHelper/src/auth.rs`
  - `Helper/CodexexHelper/src/quota.rs`

## High-Leverage Files

- `project.yml`: app target wiring, helper scripts, tests, entitlements.
- `Sources/CodexMeterCore/CodexModels.swift`: domain contract for snapshots, limits, windows, credits.
- `Sources/CodexMeterCore/CodexServiceContracts.swift`: app/helper wire contract.
- `Sources/CodexMeterApp/Support/CodexMenuBarModel.swift`: app state, refresh loop, auth flow, settings bridge.
- `Sources/CodexMeterApp/Support/CodexUsageHistoryAnalytics.swift`: insight and forecast logic.
- `Sources/CodexMeterApp/Support/CodexXPCClient.swift`: helper transport.
- `Sources/CodexexXPCService/`: sandbox bridge runtime.
- `Helper/CodexexHelper/src/`: ChatGPT auth and quota reads through official Codex crates.
- `Scripts/build-codexex-helper.sh` and `Scripts/embed-codexex-helper.sh`: packaging seam.

## Key Opportunities

### 1. Split app state management into smaller, testable flows

- `CodexMenuBarModel` currently owns too many concerns:
  - refresh loop
  - auth lifecycle
  - onboarding state
  - settings state
  - usage history refresh
  - launch-at-login behavior
- Extract smaller units with narrow ownership:
  - auth controller
  - refresh scheduler
  - history coordinator
  - settings state
  - menu presentation adapter
- Keep the menu-bar model as a composition root, not the behavior dump.

### 2. Turn the helper wire protocol into an explicit, versioned contract

- Today the helper path is newline-delimited JSON over a long-lived child process with ad hoc request and response handling.
- Improve this by:
  - versioning the protocol
  - defining explicit request and response envelopes
  - testing malformed, partial, delayed, and cancelled responses
  - making helper restart and cancellation behavior deterministic
- Keep App Store-safe XPC plus helper flow as the canonical path.

### 3. Reduce legacy surface area

- `CodexAppServerProbe.swift` is marked legacy but still large and easy to treat as active product code.
- Either move it behind debug-only/internal-only compilation or isolate it in a clearly non-shipping support target.
- Remove any product ambiguity about which path is canonical: helper plus XPC only for shipping builds.

### 4. Make analytics easier to trust and evolve

- `CodexUsageHistoryAnalytics.swift` is valuable but dense.
- Break it into smaller pieces:
  - point extraction
  - cycle classification
  - forecast generation
  - insight text rendering
- Add more fixture-driven tests from real snapshot histories:
  - sparse histories
  - reset changes
  - missing windows
  - volatile cycles
  - Spark-only or credits-only accounts

### 5. Strengthen UX for menu-bar constraints

- Keep the menu-bar-first product shape, but improve clarity in small spaces:
  - first-run onboarding
  - signed-out state
  - helper unavailable state
  - stale snapshot state
  - preview mode labeling
- Ensure popup, onboarding, and settings all describe the same auth and quota concepts.
- Add empty-state language for accounts that return auth but no quota windows.

### 6. Raise release and packaging confidence

- Build, helper packaging, signing, testing, and metadata validation should be one repeatable release path.
- Add a scripted release smoke that validates:
  - helper builds
  - helper embeds and signs
  - app launches as an `LSUIElement`
  - preview mode works
  - sign-in path shows device code state
  - sign-out path clears state
- Keep App Store text in `fastlane/metadata/` and privacy text in `PRIVACY.md`.

### 7. Improve observability without leaking secrets

- Add lightweight timing and failure metrics for:
  - helper launch
  - snapshot fetch
  - device auth begin
  - device auth poll
  - history load and append
- Keep tokens, user codes, and sensitive account data out of public logs.
- Log failures with enough structure to separate helper startup failures from backend or auth failures.

## Prioritized Roadmap

### Phase 1: Contract and state refactor

- Split `CodexMenuBarModel` into smaller controllers and keep a stable composition API for the views.
- Formalize the helper protocol and add transport failure tests.
- Quarantine or remove the legacy probe from the shipping path.
- Expand snapshot and history fixtures for analytics regression tests.

### Phase 2: UX and resilience

- Tighten onboarding, sign-in, sign-out, and preview mode transitions.
- Add clearer stale-data and helper-unavailable states in the popup and settings.
- Improve cancellation, timeout, and retry behavior around helper calls.
- Add menu-bar and settings smoke coverage beyond unit-only tests.

### Phase 3: Release automation and supportability

- Create one documented release flow for regenerate, test, build, package, and metadata checks.
- Add a concise troubleshooting map for auth failures, helper packaging failures, and no-quota responses.
- Add timing telemetry so regressions in helper startup or refresh cadence are obvious.

## Guardrails

- `project.yml` remains the Xcode source of truth.
- Shipping builds must stay on the official helper plus XPC path.
- Do not add alternate auth flows, browser scraping, token extraction, or private API dependency.
- Keep the app menu-bar-only. No dashboard creep into a full main-window product.
- Keep review-facing text inside `fastlane/metadata/` and `PRIVACY.md`.

## Acceptance Signals

- The menu-bar model no longer mixes every subsystem and its extracted collaborators have direct tests.
- Helper request cancellation and helper restart behavior are deterministic and covered.
- Legacy probe code is clearly non-shipping or gone from the main product path.
- Forecast and insight tests cover real sparse and volatile histories, not only happy paths.
- A single release smoke path validates helper build/embed/sign, preview mode, ChatGPT sign-in state, and sign-out cleanup.

## Output Required At End

- A full zip containing the updated source code, this improvement plan, and all implementation changes.
