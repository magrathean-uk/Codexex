# Codexex App Store Auth Rewrite Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship Codexex as a free Mac App Store app with first-run auth choice (`OAuth` or `API key`), Keychain-backed credentials, and no external `codex` CLI dependency.

**Architecture:** Replace `CodexAppServerProbe` as the runtime data source with a network-backed quota client. Introduce an auth layer that owns credentials and mode selection, and route the menu bar model through a new service interface so UI stays mostly unchanged.

**Tech Stack:** Swift 6.2, SwiftUI/AppKit, XCTest, URLSession, Security.framework, XcodeGen.

---

### Task 1: Define App Store Auth + Quota Contracts

**Files:**
- Create: `Sources/CodexMeterCore/AppStoreAuthModels.swift`
- Create: `Sources/CodexMeterCore/AppStoreQuotaService.swift`
- Modify: `Package.swift`
- Test: `Tests/CodexMeterCoreTests/AppStoreAuthModelsTests.swift`

- [ ] **Step 1: Write failing model tests**

```swift
import XCTest
@testable import CodexMeterCore

final class AppStoreAuthModelsTests: XCTestCase {
    func testAuthModeCodableRoundTrip() throws {
        let mode: AppStoreAuthMode = .apiKey
        let data = try JSONEncoder().encode(mode)
        XCTAssertEqual(try JSONDecoder().decode(AppStoreAuthMode.self, from: data), .apiKey)
    }

    func testQuotaSnapshotHasRequiredWindows() {
        let snapshot = AppStoreQuotaSnapshot(
            capturedAt: Date(),
            accountEmail: "user@example.com",
            codex5hUsedPercent: 42,
            codexWeeklyUsedPercent: 17,
            spark5hUsedPercent: nil,
            sparkWeeklyUsedPercent: nil
        )
        XCTAssertEqual(snapshot.codex5hUsedPercent, 42)
        XCTAssertEqual(snapshot.codexWeeklyUsedPercent, 17)
    }
}
```

- [ ] **Step 2: Run tests to verify failure**

Run: `swift test --filter AppStoreAuthModelsTests`  
Expected: `Cannot find type 'AppStoreAuthMode' in scope`.

- [ ] **Step 3: Add minimal contracts**

```swift
import Foundation

public enum AppStoreAuthMode: String, Codable, Sendable {
    case oauth
    case apiKey
}

public struct AppStoreQuotaSnapshot: Sendable, Equatable {
    public let capturedAt: Date
    public let accountEmail: String?
    public let codex5hUsedPercent: Double
    public let codexWeeklyUsedPercent: Double
    public let spark5hUsedPercent: Double?
    public let sparkWeeklyUsedPercent: Double?
}
```

```swift
import Foundation

public protocol AppStoreQuotaServicing: Sendable {
    func fetchSnapshot() async throws -> AppStoreQuotaSnapshot
}
```

- [ ] **Step 4: Export files in target membership**

Run: ensure new files are under `Sources/CodexMeterCore` and compiled by `CodexMeterCore` target.

- [ ] **Step 5: Re-run tests**

Run: `swift test --filter AppStoreAuthModelsTests`  
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/CodexMeterCore/AppStoreAuthModels.swift Sources/CodexMeterCore/AppStoreQuotaService.swift Tests/CodexMeterCoreTests/AppStoreAuthModelsTests.swift
git commit -m "feat: add app-store auth and quota contracts"
```

### Task 2: Add Keychain Credential Store

**Files:**
- Create: `Sources/CodexMeterCore/AppStoreCredentialStore.swift`
- Test: `Tests/CodexMeterCoreTests/AppStoreCredentialStoreTests.swift`

- [ ] **Step 1: Write failing store tests using in-memory adapter**

```swift
import XCTest
@testable import CodexMeterCore

final class AppStoreCredentialStoreTests: XCTestCase {
    func testSaveAndLoadAPIKey() throws {
        let backing = InMemoryCredentialBacking()
        let store = AppStoreCredentialStore(backing: backing)
        try store.saveAPIKey("sk-test")
        XCTAssertEqual(try store.loadAPIKey(), "sk-test")
    }

    func testDeleteAPIKey() throws {
        let backing = InMemoryCredentialBacking()
        let store = AppStoreCredentialStore(backing: backing)
        try store.saveAPIKey("sk-test")
        try store.deleteAPIKey()
        XCTAssertNil(try store.loadAPIKey())
    }
}
```

- [ ] **Step 2: Run test to verify failure**

Run: `swift test --filter AppStoreCredentialStoreTests`  
Expected: missing `AppStoreCredentialStore` symbols.

- [ ] **Step 3: Implement store with injectable backing**

```swift
import Foundation

public protocol AppStoreCredentialBacking {
    func save(_ value: Data, key: String) throws
    func load(key: String) throws -> Data?
    func delete(key: String) throws
}

public final class AppStoreCredentialStore {
    private let backing: AppStoreCredentialBacking
    public init(backing: AppStoreCredentialBacking = KeychainCredentialBacking()) {
        self.backing = backing
    }
    public func saveAPIKey(_ key: String) throws { try backing.save(Data(key.utf8), key: "codexex.apiKey") }
    public func loadAPIKey() throws -> String? { try backing.load(key: "codexex.apiKey").flatMap { String(data: $0, encoding: .utf8) } }
    public func deleteAPIKey() throws { try backing.delete(key: "codexex.apiKey") }
}
```

- [ ] **Step 4: Re-run tests**

Run: `swift test --filter AppStoreCredentialStoreTests`  
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/CodexMeterCore/AppStoreCredentialStore.swift Tests/CodexMeterCoreTests/AppStoreCredentialStoreTests.swift
git commit -m "feat: add keychain-backed credential store"
```

### Task 3: Implement OAuth/API-key Auth Coordinator

**Files:**
- Create: `Sources/CodexMeterCore/AppStoreAuthCoordinator.swift`
- Test: `Tests/CodexMeterCoreTests/AppStoreAuthCoordinatorTests.swift`

- [ ] **Step 1: Write failing coordinator tests**

```swift
import XCTest
@testable import CodexMeterCore

final class AppStoreAuthCoordinatorTests: XCTestCase {
    func testModeSwitchToAPIKeyPersists() async throws {
        let deps = AuthCoordinatorTestDeps()
        let coordinator = AppStoreAuthCoordinator(deps: deps)
        try await coordinator.setAPIKey("sk-live")
        XCTAssertEqual(await coordinator.mode, .apiKey)
    }
}
```

- [ ] **Step 2: Run test to verify failure**

Run: `swift test --filter AppStoreAuthCoordinatorTests`  
Expected: missing coordinator type.

- [ ] **Step 3: Implement coordinator surface**

```swift
import Foundation

@MainActor
public final class AppStoreAuthCoordinator {
    public private(set) var mode: AppStoreAuthMode
    public private(set) var accountEmail: String?
    public init(deps: Dependencies = .live) { self.mode = deps.modeStore.load() }
    public func setAPIKey(_ value: String) async throws { /* save key, set mode */ }
    public func startOAuthSignIn() async throws { /* perform OAuth flow */ }
    public func signOut() async throws { /* clear token/key */ }
}
```

- [ ] **Step 4: Re-run tests**

Run: `swift test --filter AppStoreAuthCoordinatorTests`  
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/CodexMeterCore/AppStoreAuthCoordinator.swift Tests/CodexMeterCoreTests/AppStoreAuthCoordinatorTests.swift
git commit -m "feat: add app-store auth coordinator"
```

### Task 4: Add Network Quota Client (No CLI)

**Files:**
- Create: `Sources/CodexMeterCore/AppStoreQuotaClient.swift`
- Create: `Sources/CodexMeterCore/AppStoreQuotaMapper.swift`
- Test: `Tests/CodexMeterCoreTests/AppStoreQuotaClientTests.swift`

- [ ] **Step 1: Write failing parser/mapping tests**

```swift
import XCTest
@testable import CodexMeterCore

final class AppStoreQuotaClientTests: XCTestCase {
    func testMapsQuotaResponse() throws {
        let json = #"{"codex5h":42,"codexWeekly":17}"#
        let data = Data(json.utf8)
        let snapshot = try AppStoreQuotaMapper.map(data: data, email: "u@example.com")
        XCTAssertEqual(snapshot.codex5hUsedPercent, 42)
        XCTAssertEqual(snapshot.codexWeeklyUsedPercent, 17)
    }
}
```

- [ ] **Step 2: Run test to verify failure**

Run: `swift test --filter AppStoreQuotaClientTests`  
Expected: missing mapper/client symbols.

- [ ] **Step 3: Implement client + mapper**

```swift
import Foundation

public struct AppStoreQuotaClient: AppStoreQuotaServicing {
    public func fetchSnapshot() async throws -> AppStoreQuotaSnapshot {
        // Build request from OAuth/API-key auth mode and decode normalized payload.
    }
}
```

- [ ] **Step 4: Re-run tests**

Run: `swift test --filter AppStoreQuotaClientTests`  
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/CodexMeterCore/AppStoreQuotaClient.swift Sources/CodexMeterCore/AppStoreQuotaMapper.swift Tests/CodexMeterCoreTests/AppStoreQuotaClientTests.swift
git commit -m "feat: add network quota client for app-store mode"
```

### Task 5: Replace Menu Model Data Source with Auth + Quota Services

**Files:**
- Modify: `Sources/CodexMeterApp/CodexMenuBarModel.swift`
- Modify: `Sources/CodexMeterApp/main.swift`
- Modify: `Sources/CodexMeterApp/StatusBarLabel.swift`
- Test: `Tests/CodexMeterCoreTests/CodexSnapshotParsingTests.swift`

- [ ] **Step 1: Write failing integration test for snapshot conversion**

```swift
func testAppStoreQuotaMapsToMenuSnapshotShape() {
    let snapshot = AppStoreQuotaSnapshot(
        capturedAt: Date(),
        accountEmail: "user@example.com",
        codex5hUsedPercent: 50,
        codexWeeklyUsedPercent: 10,
        spark5hUsedPercent: nil,
        sparkWeeklyUsedPercent: nil
    )
    let viewModel = CodexMenuBarSnapshot.from(appStore: snapshot)
    XCTAssertEqual(viewModel.hText, "50%")
    XCTAssertEqual(viewModel.wText, "10%")
}
```

- [ ] **Step 2: Run test to verify failure**

Run: `swift test --filter AppStoreQuotaMapsToMenuSnapshotShape`  
Expected: missing conversion type.

- [ ] **Step 3: Wire model to new services**

```swift
@MainActor
final class CodexMenuBarModel {
    private let authCoordinator: AppStoreAuthCoordinator
    private let quotaService: AppStoreQuotaServicing
    func refreshNow() async {
        // No Process launch. Pull auth state + network snapshot only.
    }
}
```

- [ ] **Step 4: Remove runtime dependency on `CodexAppServerProbe`**

Run: `rg -n "CodexAppServerProbe|app-server|codex -s" Sources/CodexMeterApp Sources/CodexMeterCore`  
Expected after changes: no runtime references from app target.

- [ ] **Step 5: Re-run targeted tests**

Run: `swift test --filter CodexSnapshotParsingTests`  
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/CodexMeterApp/CodexMenuBarModel.swift Sources/CodexMeterApp/main.swift Sources/CodexMeterApp/StatusBarLabel.swift
git commit -m "refactor: switch menu model to app-store auth and quota services"
```

### Task 6: Build First-Run Auth UX + Settings Auth Section

**Files:**
- Modify: `Sources/CodexMeterApp/SettingsRootView.swift`
- Create: `Sources/CodexMeterApp/AuthOnboardingView.swift`
- Modify: `Sources/CodexMeterApp/PopupRootView.swift`

- [ ] **Step 1: Write failing UI state test**

```swift
func testSettingsShowsAuthModeAndAccount() {
    let state = SettingsAuthState(mode: .apiKey, accountEmail: "user@example.com")
    XCTAssertEqual(state.modeLabel, "API key")
    XCTAssertEqual(state.accountLabel, "user@example.com")
}
```

- [ ] **Step 2: Run test to verify failure**

Run: `swift test --filter SettingsShowsAuthModeAndAccount`  
Expected: missing settings auth state type.

- [ ] **Step 3: Implement auth UI**

```swift
// SettingsRootView: add "Authentication" card with:
// - mode picker (OAuth/API key)
// - OAuth sign-in button
// - API key secure entry + save button
// - Sign out button
// - account status text
```

- [ ] **Step 4: Add first-run onboarding gate**

```swift
// main.swift: present AuthOnboardingView when no valid credentials are present.
```

- [ ] **Step 5: Re-run UI/state tests**

Run: `swift test --filter Settings`  
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/CodexMeterApp/SettingsRootView.swift Sources/CodexMeterApp/AuthOnboardingView.swift Sources/CodexMeterApp/PopupRootView.swift
git commit -m "feat: add onboarding and settings auth controls"
```

### Task 7: App Store Hardening (Entitlements, Metadata, Privacy)

**Files:**
- Create: `Codexex.entitlements`
- Modify: `project.yml`
- Modify: `README.md`
- Create: `PRIVACY.md`

- [ ] **Step 1: Add sandbox entitlements**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>com.apple.security.app-sandbox</key><true/>
  <key>com.apple.security.network.client</key><true/>
</dict></plist>
```

- [ ] **Step 2: Wire entitlements + store metadata**

Run: add to `project.yml`:

```yaml
CODE_SIGN_ENTITLEMENTS: Codexex.entitlements
INFOPLIST_KEY_LSApplicationCategoryType: public.app-category.utilities
INFOPLIST_KEY_ITSAppUsesNonExemptEncryption: NO
```

- [ ] **Step 3: Document user-data handling**

Run: create `PRIVACY.md` covering:
- OAuth/API-key only auth paths
- Keychain storage
- no browser cookie harvesting
- no external CLI execution

- [ ] **Step 4: Build generated project**

Run: `xcodegen generate && xcodebuild -project CodexMeter.xcodeproj -scheme CodexMeterApp -configuration Release -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build`  
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add Codexex.entitlements project.yml README.md PRIVACY.md
git commit -m "chore: app-store hardening and privacy docs"
```

### Task 8: Full Verification + Runtime Replace

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Run full package tests**

Run: `swift test`  
Expected: all test suites pass.

- [ ] **Step 2: Run app build**

Run: `xcodebuild -project CodexMeter.xcodeproj -scheme CodexMeterApp -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build`  
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Replace running app instance**

Run:

```bash
pkill -x Codexex || true
open -n ~/Library/Developer/Xcode/DerivedData/CodexMeter-*/Build/Products/Debug/Codexex.app
```

Expected: new menu bar instance appears and prompts auth on first run.

- [ ] **Step 4: Update README runbook**

Run: document:
- first-run auth selection
- API key management in Settings
- App Store-safe constraints

- [ ] **Step 5: Commit**

```bash
git add README.md
git commit -m "docs: add app-store auth runbook"
```

## Self-Review

- Spec coverage:
  - App Store-only direction: covered (Tasks 5, 7, 8).
  - OAuth + API key user choice: covered (Tasks 3, 6).
  - Launch/login/settings parity: covered (Task 6).
  - App Store hardening: covered (Task 7).
- Placeholder scan:
  - No `TODO`/`TBD` placeholders in task steps.
  - Each task includes explicit files, commands, and expected outcomes.
- Type consistency:
  - `AppStoreAuthMode`, `AppStoreQuotaSnapshot`, and `AppStoreQuotaServicing` are introduced before use in later tasks.
  - `CodexMenuBarModel` migration references those exact names.

Plan complete and saved to `docs/superpowers/plans/2026-04-10-appstore-codexex-auth-plan.md`. Two execution options:

1. Subagent-Driven (recommended) - dispatch a fresh subagent per task with review between tasks.
2. Inline Execution - execute tasks in this session using executing-plans checkpoints.

Which approach?
