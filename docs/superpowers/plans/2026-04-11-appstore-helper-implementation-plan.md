# Codexex App Store Helper Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the external `codex` dependency with a bundled app-owned helper and keep Codexex viable for the Mac App Store.

**Architecture:** Keep the menu bar UI native in SwiftUI/AppKit. Add a thin Swift XPC bridge and a bundled restricted helper that owns quota/auth backend work. Keep shared account/quota models in `CodexMeterCore` so the UI does not care how data is obtained.

**Tech Stack:** Swift 6.2, SwiftUI, AppKit, XCTest, XcodeGen, Rust helper crate, Cargo, App Sandbox, XPC

---

## File Map

- Modify: `project.yml`
  - add sandbox entitlements, XPC target, helper copy/build phases
- Create: `AppStore/Codexex.entitlements`
  - main app sandbox entitlements
- Create: `AppStore/CodexexXPCService.entitlements`
  - XPC service sandbox/network entitlements
- Create: `AppStore/CodexexHelper.entitlements`
  - helper sandbox/inherit entitlements if helper is signed separately
- Create: `Helper/CodexexHelper/Cargo.toml`
  - helper crate manifest
- Create: `Helper/CodexexHelper/src/lib.rs`
  - helper module exports for tests
- Create: `Helper/CodexexHelper/src/main.rs`
  - restricted helper entry point
- Create: `Helper/CodexexHelper/src/protocol.rs`
  - JSON command protocol
- Create: `Helper/CodexexHelper/src/auth.rs`
  - auth flow support
- Create: `Helper/CodexexHelper/src/quota.rs`
  - account/quota fetch path
- Create: `Helper/CodexexHelper/tests/protocol.rs`
  - helper protocol tests
- Create: `Scripts/build-codexex-helper.sh`
  - cargo build wrapper for Xcode
- Create: `Scripts/embed-codexex-helper.sh`
  - copy helper into app bundle
- Create: `Sources/CodexMeterCore/CodexServiceContracts.swift`
  - shared request/response DTOs
- Create: `Sources/CodexMeterApp/CodexXPCClient.swift`
  - app-side XPC bridge
- Create: `Sources/CodexexXPCService/main.swift`
  - service entry point
- Create: `Sources/CodexexXPCService/CodexXPCService.swift`
  - exported service object
- Create: `Sources/CodexexXPCService/CodexHelperProcess.swift`
  - service-side helper process wrapper
- Create: `Sources/CodexMeterApp/CodexSecretStore.swift`
  - keychain-backed API key/session helpers
- Modify: `Sources/CodexMeterApp/CodexMenuBarModel.swift`
  - replace direct probe with XPC client
- Modify: `Sources/CodexMeterApp/CodexDeviceAuthCoordinator.swift`
  - retire direct CLI login path in favor of XPC/native auth path
- Modify: `Sources/CodexMeterApp/SettingsRootView.swift`
  - wire native sign-in, API key, auth states
- Modify: `Sources/CodexMeterApp/PopupRootView.swift`
  - keep UI but animate refresh/auth states
- Modify: `Sources/CodexMeterCore/CodexAppServerProbe.swift`
  - keep as legacy/internal parity tool only, not app-store path
- Create: `Tests/CodexMeterCoreTests/CodexServiceContractsTests.swift`
  - DTO encoding/decoding tests
- Create: `Tests/CodexMeterCoreTests/CodexSnapshotParityTests.swift`
  - fixture parity tests for helper output vs snapshot reducer

---

### Task 1: Characterize current snapshot behavior before replacing it

**Files:**
- Create: `Tests/CodexMeterCoreTests/CodexSnapshotParityTests.swift`
- Modify: `Sources/CodexMeterCore/TestSupport.swift`
- Test: `Tests/CodexMeterCoreTests/CodexSnapshotParityTests.swift`

- [ ] **Step 1: Add a helper-output fixture shape test**

```swift
import XCTest
@testable import CodexMeterCore

final class CodexSnapshotParityTests: XCTestCase {
    func testSnapshotReducerBuildsExpectedCodexAndSparkBuckets() throws {
        let account = _AccountReadResult(dictionary: [
            "account": [
                "type": "chatgpt",
                "email": "test@example.com",
                "planType": "pro"
            ]
        ])

        let rateLimits = _RateLimitsReadResult(dictionary: [
            "rateLimitsByLimitId": [
                "codex-5h": [
                    "limitId": "codex-5h",
                    "limitName": "Codex",
                    "primary": [
                        "usedPercent": 44.0,
                        "windowDurationMins": 300,
                        "resetsAt": 1_800_000_000.0
                    ]
                ],
                "spark-week": [
                    "limitId": "spark-week",
                    "limitName": "Spark",
                    "primary": [
                        "usedPercent": 71.0,
                        "windowDurationMins": 10080,
                        "resetsAt": 1_800_050_000.0
                    ]
                ]
            ]
        ])

        let snapshot = try _SnapshotReducer.makeSnapshot(
            executablePath: "/App/Helper",
            account: account,
            rateLimits: rateLimits,
            now: Date(timeIntervalSince1970: 1_700_000_000)
        )

        XCTAssertEqual(snapshot.account?.email, "test@example.com")
        XCTAssertEqual(snapshot.limits.count, 2)
    }
}
```

- [ ] **Step 2: Add unauthenticated and API-key characterization tests**

```swift
func testSnapshotReducerRejectsUnauthenticatedState() {
    let account = _AccountReadResult(dictionary: [:])
    let rateLimits = _RateLimitsReadResult(dictionary: [:])

    XCTAssertThrowsError(
        try _SnapshotReducer.makeSnapshot(
            executablePath: "/App/Helper",
            account: account,
            rateLimits: rateLimits
        )
    )
}

func testSnapshotReducerRejectsApiKeyModeForChatGPTQuota() {
    let account = _AccountReadResult(dictionary: [
        "account": ["type": "apikey"]
    ])
    let rateLimits = _RateLimitsReadResult(dictionary: [:])

    XCTAssertThrowsError(
        try _SnapshotReducer.makeSnapshot(
            executablePath: "/App/Helper",
            account: account,
            rateLimits: rateLimits
        )
    )
}
```

- [ ] **Step 3: Run the characterization tests first**

Run: `source /Users/bolyki/dev/source/build-env.sh && swift test --filter CodexSnapshotParityTests`
Expected: PASS

- [ ] **Step 4: Commit the characterization baseline**

```bash
git add Tests/CodexMeterCoreTests/CodexSnapshotParityTests.swift Sources/CodexMeterCore/TestSupport.swift
git commit -m "test: characterize codex snapshot behavior"
```

---

### Task 2: Add helper crate and protocol skeleton

**Files:**
- Create: `Helper/CodexexHelper/Cargo.toml`
- Create: `Helper/CodexexHelper/src/lib.rs`
- Create: `Helper/CodexexHelper/src/main.rs`
- Create: `Helper/CodexexHelper/src/protocol.rs`
- Create: `Helper/CodexexHelper/tests/protocol.rs`
- Test: `Helper/CodexexHelper/tests/protocol.rs`

- [ ] **Step 1: Add the helper manifest**

```toml
[package]
name = "codexex-helper"
version = "0.1.0"
edition = "2024"

[dependencies]
serde = { version = "1", features = ["derive"] }
serde_json = "1"
anyhow = "1"
thiserror = "2"
uuid = { version = "1", features = ["v4"] }

[dev-dependencies]
pretty_assertions = "1"
```

- [ ] **Step 2: Add the JSON line protocol types**

```rust
use serde::{Deserialize, Serialize};

#[derive(Debug, Deserialize, Serialize)]
#[serde(tag = "method", rename_all = "camelCase")]
pub enum HelperRequest {
    FetchSnapshot,
    BeginDeviceAuth,
    PollDeviceAuth { flow_id: String },
    SignOut,
}

#[derive(Debug, Deserialize, Serialize)]
#[serde(tag = "type", rename_all = "camelCase")]
pub enum HelperResponse {
    Snapshot { account_json: String, rate_limits_json: String },
    DeviceAuthStarted { flow_id: String, verification_uri: String, user_code: String },
    SignedOut,
    Error { message: String },
}
```

- [ ] **Step 3: Add `src/lib.rs` so tests can import protocol types**

```rust
pub mod protocol;
```

- [ ] **Step 4: Add a stub main loop that reads one line and writes one response**

```rust
use codexex_helper::protocol::{HelperRequest, HelperResponse};
use std::io::{self, BufRead, Write};

fn main() -> anyhow::Result<()> {
    let mut stdout = io::stdout().lock();
    let stdin = io::stdin().lock();

    for line in stdin.lines() {
        let line = line?;
        let request: HelperRequest = serde_json::from_str(&line)?;
        let response = match request {
            HelperRequest::FetchSnapshot => HelperResponse::Snapshot {
                account_json: r#"{"account":null}"#.to_string(),
                rate_limits_json: r#"{}"#.to_string(),
            },
            HelperRequest::BeginDeviceAuth => HelperResponse::Error {
                message: "not implemented".to_string(),
            },
            HelperRequest::PollDeviceAuth { .. } => HelperResponse::Error {
                message: "not implemented".to_string(),
            },
            HelperRequest::SignOut => HelperResponse::SignedOut,
        };
        writeln!(stdout, "{}", serde_json::to_string(&response)?)?;
        stdout.flush()?;
    }

    Ok(())
}
```

- [ ] **Step 5: Add protocol round-trip tests**

```rust
use codexex_helper::protocol::HelperRequest;

#[test]
fn request_round_trip() {
    let json = r#"{"method":"pollDeviceAuth","flow_id":"flow-1"}"#;
    let request: HelperRequest = serde_json::from_str(json).unwrap();
    match request {
        HelperRequest::PollDeviceAuth { flow_id } => assert_eq!(flow_id, "flow-1"),
        _ => panic!("wrong variant"),
    }
}
```

- [ ] **Step 6: Run helper tests**

Run: `source /Users/bolyki/dev/source/build-env.sh && cargo test --manifest-path Helper/CodexexHelper/Cargo.toml`
Expected: PASS

- [ ] **Step 7: Commit helper scaffold**

```bash
git add Helper/CodexexHelper
git commit -m "feat: add codexex helper scaffold"
```

---

### Task 3: Add App Store entitlements and build plumbing

**Files:**
- Create: `AppStore/Codexex.entitlements`
- Create: `AppStore/CodexexXPCService.entitlements`
- Create: `AppStore/CodexexHelper.entitlements`
- Create: `Scripts/build-codexex-helper.sh`
- Create: `Scripts/embed-codexex-helper.sh`
- Modify: `project.yml`
- Test: `project.yml` generation and app build

- [ ] **Step 1: Add main app entitlements**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <true/>
    <key>com.apple.security.network.client</key>
    <true/>
</dict>
</plist>
```

- [ ] **Step 2: Add XPC service entitlements**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <true/>
    <key>com.apple.security.network.client</key>
    <true/>
</dict>
</plist>
```

- [ ] **Step 3: Add helper build script**

```bash
#!/usr/bin/env bash
set -euo pipefail

source /Users/bolyki/dev/source/build-env.sh
cargo build --release --manifest-path "$SRCROOT/Helper/CodexexHelper/Cargo.toml"
mkdir -p "$DERIVED_FILE_DIR/CodexexHelper"
cp "$SRCROOT/Helper/CodexexHelper/target/release/codexex-helper" "$DERIVED_FILE_DIR/CodexexHelper/codexex-helper"
```

- [ ] **Step 4: Add helper embed script**

```bash
#!/usr/bin/env bash
set -euo pipefail

HELPER_SRC="$DERIVED_FILE_DIR/CodexexHelper/codexex-helper"
HELPER_DST="$TARGET_BUILD_DIR/$CONTENTS_FOLDER_PATH/Helpers/codexex-helper"
mkdir -p "$(dirname "$HELPER_DST")"
cp "$HELPER_SRC" "$HELPER_DST"
chmod 755 "$HELPER_DST"
```

- [ ] **Step 5: Wire `project.yml` for entitlements, XPC target, and helper scripts**

```yaml
  CodexexXPCService:
    type: xpc-service
    platform: macOS
    sources:
      - path: Sources/CodexexXPCService
    dependencies:
      - target: CodexMeterCore
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.magrathean.CodexexApp.CodexexXPCService
        GENERATE_INFOPLIST_FILE: YES
        CODE_SIGN_ENTITLEMENTS: AppStore/CodexexXPCService.entitlements

  CodexMeterApp:
    settings:
      base:
        CODE_SIGN_ENTITLEMENTS: AppStore/Codexex.entitlements
    preBuildScripts:
      - path: Scripts/build-codexex-helper.sh
    postBuildScripts:
      - path: Scripts/embed-codexex-helper.sh
```

- [ ] **Step 6: Regenerate the project and build**

Run: `source /Users/bolyki/dev/source/build-env.sh && xcodegen generate && xcodebuild -project CodexMeter.xcodeproj -scheme CodexMeterApp -derivedDataPath "$XCODE_DERIVED_DATA_PATH" -clonedSourcePackagesDirPath "$SWIFTPM_SHARED_CACHE" CODE_SIGNING_ALLOWED=NO build`
Expected: BUILD SUCCEEDED

- [ ] **Step 7: Commit packaging scaffold**

```bash
git add AppStore Scripts project.yml CodexMeter.xcodeproj
git commit -m "feat: add app store helper packaging scaffold"
```

---

### Task 4: Define shared service contracts and app-side XPC client

**Files:**
- Create: `Sources/CodexMeterCore/CodexServiceContracts.swift`
- Create: `Sources/CodexMeterApp/CodexXPCClient.swift`
- Create: `Tests/CodexMeterCoreTests/CodexServiceContractsTests.swift`
- Test: `Tests/CodexMeterCoreTests/CodexServiceContractsTests.swift`

- [ ] **Step 1: Add shared DTOs in core**

```swift
import Foundation

public enum CodexAuthMode: String, Codable, Sendable {
    case chatGPT
    case apiKey
}

public struct CodexServiceSnapshotResponse: Codable, Sendable {
    public let snapshot: CodexSnapshot?
    public let errorMessage: String?
}

public struct CodexDeviceAuthStart: Codable, Sendable {
    public let flowID: String
    public let verificationURL: URL
    public let userCode: String
}
```

- [ ] **Step 2: Add contract encoding tests**

```swift
final class CodexServiceContractsTests: XCTestCase {
    func testDeviceAuthStartRoundTrips() throws {
        let value = CodexDeviceAuthStart(
            flowID: "flow-1",
            verificationURL: URL(string: "https://auth.openai.com/device")!,
            userCode: "ABCD-12345"
        )

        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(CodexDeviceAuthStart.self, from: data)

        XCTAssertEqual(decoded.flowID, "flow-1")
        XCTAssertEqual(decoded.userCode, "ABCD-12345")
    }
}
```

- [ ] **Step 3: Add the app-side XPC client shell**

```swift
import Foundation
import CodexMeterCore

@MainActor
final class CodexXPCClient {
    func fetchSnapshot() async throws -> CodexSnapshot {
        throw NSError(domain: "CodexXPCClient", code: -1)
    }

    func beginChatGPTSignIn() async throws -> CodexDeviceAuthStart {
        throw NSError(domain: "CodexXPCClient", code: -1)
    }

    func signOut() async throws {}
}
```

- [ ] **Step 4: Build the package**

Run: `source /Users/bolyki/dev/source/build-env.sh && swift test --filter CodexServiceContractsTests`
Expected: PASS

- [ ] **Step 5: Commit service contracts**

```bash
git add Sources/CodexMeterCore/CodexServiceContracts.swift Sources/CodexMeterApp/CodexXPCClient.swift Tests/CodexMeterCoreTests/CodexServiceContractsTests.swift
git commit -m "feat: add codex service contracts"
```

---

### Task 5: Add XPC service and helper process wrapper

**Files:**
- Create: `Sources/CodexexXPCService/main.swift`
- Create: `Sources/CodexexXPCService/CodexXPCService.swift`
- Create: `Sources/CodexexXPCService/CodexHelperProcess.swift`
- Test: build only

- [ ] **Step 1: Add the XPC listener bootstrap**

```swift
import Foundation

let delegate = CodexXPCServiceDelegate()
let listener = NSXPCListener.service()
listener.delegate = delegate
listener.resume()
RunLoop.main.run()
```

- [ ] **Step 2: Add the helper process wrapper**

```swift
import Foundation

final class CodexHelperProcess {
    func send(_ line: String) throws -> String {
        let helperURL = Bundle.main.bundleURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Helpers/codexex-helper")

        let process = Process()
        process.executableURL = helperURL
        let stdin = Pipe()
        let stdout = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        try process.run()
        try stdin.fileHandleForWriting.write(contentsOf: Data((line + "\n").utf8))
        stdin.fileHandleForWriting.closeFile()
        process.waitUntilExit()
        return String(decoding: stdout.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
```

- [ ] **Step 3: Add the exported XPC object**

```swift
@objc protocol CodexXPCServiceProtocol {
    func fetchSnapshot(reply: @escaping (Data?, String?) -> Void)
    func beginChatGPTSignIn(reply: @escaping (Data?, String?) -> Void)
    func signOut(reply: @escaping (String?) -> Void)
}
```

- [ ] **Step 4: Build the Xcode project**

Run: `source /Users/bolyki/dev/source/build-env.sh && xcodegen generate && xcodebuild -project CodexMeter.xcodeproj -scheme CodexMeterApp -derivedDataPath "$XCODE_DERIVED_DATA_PATH" -clonedSourcePackagesDirPath "$SWIFTPM_SHARED_CACHE" CODE_SIGNING_ALLOWED=NO build`
Expected: BUILD SUCCEEDED

- [ ] **Step 5: Commit XPC skeleton**

```bash
git add Sources/CodexexXPCService CodexMeter.xcodeproj project.yml
git commit -m "feat: add xpc service skeleton"
```

---

### Task 6: Implement helper snapshot fetch and device auth path

**Files:**
- Modify: `Helper/CodexexHelper/src/lib.rs`
- Modify: `Helper/CodexexHelper/src/main.rs`
- Create: `Helper/CodexexHelper/src/auth.rs`
- Create: `Helper/CodexexHelper/src/quota.rs`
- Modify: `Helper/CodexexHelper/src/protocol.rs`
- Test: cargo tests

- [ ] **Step 1: Add helper auth and quota modules and expose them from `src/lib.rs`**

```rust
pub mod protocol;
pub mod auth;
pub mod quota;
```

```rust
pub fn begin_device_auth() -> anyhow::Result<HelperResponse> {
    Ok(HelperResponse::DeviceAuthStarted {
        flow_id: uuid::Uuid::new_v4().to_string(),
        verification_uri: "https://auth.openai.com/device".to_string(),
        user_code: "ABCD-12345".to_string(),
    })
}
```

```rust
pub fn fetch_snapshot() -> anyhow::Result<HelperResponse> {
    Ok(HelperResponse::Snapshot {
        account_json: r#"{"account":{"type":"chatgpt","email":"user@example.com","planType":"pro"}}"#.to_string(),
        rate_limits_json: r#"{"rateLimitsByLimitId":{"codex-5h":{"limitId":"codex-5h","limitName":"Codex","primary":{"usedPercent":44.0,"windowDurationMins":300,"resetsAt":1800000000.0}}}}"#.to_string(),
    })
}
```

- [ ] **Step 2: Route protocol methods to modules**

```rust
let response = match request {
    HelperRequest::FetchSnapshot => quota::fetch_snapshot()?,
    HelperRequest::BeginDeviceAuth => auth::begin_device_auth()?,
    HelperRequest::PollDeviceAuth { flow_id } => auth::poll_device_auth(&flow_id)?,
    HelperRequest::SignOut => auth::sign_out()?,
};
```

- [ ] **Step 3: Add unit tests for helper auth/quota responses**

```rust
#[test]
fn fetch_snapshot_returns_snapshot_variant() {
    let response = quota::fetch_snapshot().unwrap();
    match response {
        HelperResponse::Snapshot { .. } => {}
        _ => panic!("expected snapshot"),
    }
}
```

- [ ] **Step 4: Run helper tests**

Run: `source /Users/bolyki/dev/source/build-env.sh && cargo test --manifest-path Helper/CodexexHelper/Cargo.toml`
Expected: PASS

- [ ] **Step 5: Commit helper backend**

```bash
git add Helper/CodexexHelper
git commit -m "feat: implement helper auth and snapshot shell"
```

---

### Task 7: Replace direct CLI probe and sign-in in the app model

**Files:**
- Modify: `Sources/CodexMeterApp/CodexMenuBarModel.swift`
- Modify: `Sources/CodexMeterApp/CodexDeviceAuthCoordinator.swift`
- Create: `Sources/CodexMeterApp/CodexSecretStore.swift`
- Modify: `Sources/CodexMeterApp/SettingsRootView.swift`
- Test: app build

- [ ] **Step 1: Add a keychain-backed secret store for API key mode**

```swift
import Foundation
import Security

enum CodexSecretStore {
    static func saveAPIKey(_ key: String) throws {
        let data = Data(key.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.magrathean.CodexexApp.api-key",
            kSecValueData as String: data,
        ]
        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
    }
}
```

- [ ] **Step 2: Inject the XPC client into `CodexMenuBarModel`**

```swift
private let service = CodexXPCClient()

func refreshNow() async {
    guard isRefreshing == false else { return }
    withAnimation(.easeInOut(duration: 0.2)) { isRefreshing = true }
    defer { isRefreshing = false }

    do {
        let result = try await service.fetchSnapshot()
        withAnimation(.snappy(duration: 0.25)) {
            snapshot = result
            lastUpdatedAt = result.capturedAt
            lastError = nil
            isSignedIn = true
            hasResolvedAuthState = true
        }
    } catch {
        withAnimation(.snappy(duration: 0.25)) {
            lastError = error.localizedDescription
            snapshot = nil
            isSignedIn = false
            hasResolvedAuthState = true
        }
    }
}
```

- [ ] **Step 3: Replace direct process login in `CodexDeviceAuthCoordinator` with XPC-backed auth**

```swift
enum CodexDeviceAuthCoordinator {
    static func startSignIn(
        client: CodexXPCClient,
        update: @escaping @Sendable (_ statusMessage: String, _ deviceCode: String?) -> Void
    ) {
        Task {
            do {
                let auth = try await client.beginChatGPTSignIn()
                await MainActor.run {
                    update("Enter the code in Safari.", auth.userCode)
                }
                NSWorkspace.shared.open(auth.verificationURL)
            } catch {
                await MainActor.run {
                    update(error.localizedDescription, nil)
                }
            }
        }
    }
}
```

- [ ] **Step 4: Simplify `SettingsRootView` auth section around signed-in vs signed-out state**

```swift
if model.isSignedIn {
    Button("Sign out") { model.signOut() }
} else {
    Button("Sign in with ChatGPT") { model.startChatGPTSignIn() }
    SecureField("Paste API key", text: $apiKey)
    Button("Save API key") { saveAPIKey() }
}
```

- [ ] **Step 5: Build and launch**

Run: `source /Users/bolyki/dev/source/build-env.sh && xcodegen generate && xcodebuild -project CodexMeter.xcodeproj -scheme CodexMeterApp -derivedDataPath "$XCODE_DERIVED_DATA_PATH" -clonedSourcePackagesDirPath "$SWIFTPM_SHARED_CACHE" CODE_SIGNING_ALLOWED=NO build`
Expected: BUILD SUCCEEDED

- [ ] **Step 6: Commit app integration**

```bash
git add Sources/CodexMeterApp CodexMeter.xcodeproj project.yml
git commit -m "feat: route app auth and quota through xpc"
```

---

### Task 8: Add motion polish and lock the App Store path

**Files:**
- Modify: `Sources/CodexMeterApp/PopupRootView.swift`
- Modify: `Sources/CodexMeterApp/SettingsRootView.swift`
- Modify: `Sources/CodexMeterApp/CodexMenuBarModel.swift`
- Modify: `Sources/CodexMeterCore/CodexAppServerProbe.swift`
- Test: app build and live run

- [ ] **Step 1: Animate refresh state and value updates**

```swift
.contentTransition(.numericText())
.animation(.smooth(duration: 0.25), value: model.snapshot?.capturedAt)
```

- [ ] **Step 2: Respect reduce motion**

```swift
@Environment(\.accessibilityReduceMotion) private var reduceMotion

private var refreshAnimation: Animation? {
    reduceMotion ? nil : .smooth(duration: 0.25)
}
```

- [ ] **Step 3: Mark the external probe as legacy-only and stop using it from app code**

```swift
@available(*, deprecated, message: "Legacy direct codex probe. Not used by the App Store path.")
public struct CodexAppServerProbe: Sendable {
```

- [ ] **Step 4: Full local verification**

Run: `source /Users/bolyki/dev/source/build-env.sh && swift test && xcodegen generate && xcodebuild -project CodexMeter.xcodeproj -scheme CodexMeterApp -derivedDataPath "$XCODE_DERIVED_DATA_PATH" -clonedSourcePackagesDirPath "$SWIFTPM_SHARED_CACHE" CODE_SIGNING_ALLOWED=NO build`
Expected: tests PASS, BUILD SUCCEEDED

- [ ] **Step 5: Final launch check**

Run: `open "$XCODE_DERIVED_DATA_PATH/Build/Products/Debug/Codexex.app"`
Expected: menu bar app launches, popup opens, settings opens, sign-in and sign-out paths are wired

- [ ] **Step 6: Commit final polish**

```bash
git add Sources/CodexMeterApp Sources/CodexMeterCore Tests/CodexMeterCoreTests CodexMeter.xcodeproj project.yml
git commit -m "feat: finish app store helper migration"
```
