# Codexex App Store XPC Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Convert Codexex into a Mac App Store-safe app by removing the external `codex` dependency and moving auth/quota networking into a bundled XPC service.

**Architecture:** Keep the menu bar app as the only UI process. Add a bundled XPC service that owns network calls and auth operations. The app talks to the service through a narrow request/response layer and renders the returned normalized snapshot.

**Tech Stack:** Swift 6.2, SwiftUI, AppKit shell for status item, XPC service target, App Sandbox entitlements, Keychain, XcodeGen

---

## File Map

- Modify: `project.yml`
  - Add XPC service target and entitlements.
- Create: `AppStore/Codexex.entitlements`
  - Main app sandbox entitlements.
- Create: `AppStore/CodexexXPCService.entitlements`
  - XPC service sandbox/network entitlements.
- Create: `Sources/CodexXPCShared/` or equivalent shared files inside existing targets
  - Service contract types and protocols.
- Create: `Sources/CodexexXPCService/`
  - XPC service entry point and quota/auth implementation.
- Modify: `Sources/CodexMeterApp/CodexMenuBarModel.swift`
  - Replace direct probe path with XPC client.
- Create: `Sources/CodexMeterApp/CodexXPCClient.swift`
  - App-side XPC bridge.
- Modify: `Sources/CodexMeterApp/CodexDeviceAuthCoordinator.swift`
  - Route auth through service or retire in favor of service-backed auth API.
- Modify: `Sources/CodexMeterCore/`
  - Keep models/formatting; remove app-store path dependence on external binary locator/probe.

---

### Task 1: Add App Store target structure and entitlements

**Files:**
- Modify: `project.yml`
- Create: `AppStore/Codexex.entitlements`
- Create: `AppStore/CodexexXPCService.entitlements`
- Test: XcodeGen generation

- [ ] **Step 1: Add main app sandbox entitlements**

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
    <key>com.apple.security.inherit</key>
    <true/>
    <key>com.apple.security.network.client</key>
    <true/>
</dict>
</plist>
```

- [ ] **Step 3: Add XPC target to `project.yml`**

Include:

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
```

And for app target:

```yaml
        CODE_SIGN_ENTITLEMENTS: AppStore/Codexex.entitlements
```

- [ ] **Step 4: Regenerate project**

Run:

```bash
source /Users/bolyki/dev/source/build-env.sh && xcodegen generate
```

Expected: project regenerates successfully

---

### Task 2: Define the XPC contract and shared client shape

**Files:**
- Create: `Sources/CodexMeterCore/CodexServiceContracts.swift`
- Create: `Sources/CodexMeterApp/CodexXPCClient.swift`
- Test: `swift build`

- [ ] **Step 1: Define request/response DTOs**

Add shared Codable/Sendable types for:

```swift
enum CodexAuthMode: String, Codable, Sendable {
    case chatGPT
    case apiKey
}

struct CodexQuotaRequest: Codable, Sendable {
    let authMode: CodexAuthMode
}

struct CodexQuotaResponse: Codable, Sendable {
    let snapshot: CodexSnapshot?
    let errorMessage: String?
}
```

- [ ] **Step 2: Define app-side client shell**

Create an app-side client with methods like:

```swift
@MainActor
final class CodexXPCClient {
    func fetchQuota() async throws -> CodexSnapshot
    func beginChatGPTSignIn() async throws -> CodexAuthProgress
    func signOut() async throws
}
```

Keep this layer thin.

- [ ] **Step 3: Build**

Run:

```bash
source /Users/bolyki/dev/source/build-env.sh && swift build
```

Expected: build succeeds

---

### Task 3: Implement bundled XPC service skeleton

**Files:**
- Create: `Sources/CodexexXPCService/main.swift`
- Create: `Sources/CodexexXPCService/CodexXPCService.swift`
- Test: `swift build`

- [ ] **Step 1: Add XPC service entry point**

Create a standard `NSXPCListener.service()` bootstrap.

- [ ] **Step 2: Add service implementation shell**

Implement the exported object with methods for:

- quota fetch
- auth start
- sign out

Methods can be stubbed at first but must compile.

- [ ] **Step 3: Build**

Run:

```bash
source /Users/bolyki/dev/source/build-env.sh && swift build
```

Expected: build succeeds

---

### Task 4: Move auth and quota networking behind the service

**Files:**
- Modify: `Sources/CodexexXPCService/CodexXPCService.swift`
- Modify: `Sources/CodexMeterApp/CodexMenuBarModel.swift`
- Modify: `Sources/CodexMeterApp/CodexDeviceAuthCoordinator.swift` or remove it from app-owned auth path
- Test: `swift build`

- [ ] **Step 1: Replace direct external binary capture in the app model**

`CodexMenuBarModel` should stop calling the local `CodexAppServerProbe` for the App Store path and instead call `CodexXPCClient`.

- [ ] **Step 2: Route sign-in through service**

The main app should request sign-in through the XPC bridge and only manage UI state and Safari presentation.

- [ ] **Step 3: Route sign-out through service**

- [ ] **Step 4: Build**

Run:

```bash
source /Users/bolyki/dev/source/build-env.sh && swift build
```

Expected: build succeeds

---

### Task 5: Add App Store-safe motion polish

**Files:**
- Modify: `Sources/CodexMeterApp/PopupRootView.swift`
- Modify: `Sources/CodexMeterApp/SettingsRootView.swift`
- Modify: `Sources/CodexMeterApp/CodexMenuBarModel.swift`
- Test: `swift build`

- [ ] **Step 1: Animate progress and numeric changes**

- [ ] **Step 2: Add subtle card transition on refresh**

- [ ] **Step 3: Respect Reduce Motion**

- [ ] **Step 4: Build**

Run:

```bash
source /Users/bolyki/dev/source/build-env.sh && swift build
```

Expected: build succeeds

---

### Task 6: Full app build and live verification

**Files:**
- Modify: none unless fixes are needed
- Test: Xcode build and live app launch

- [ ] **Step 1: Regenerate project**

```bash
source /Users/bolyki/dev/source/build-env.sh && xcodegen generate
```

- [ ] **Step 2: Build app**

```bash
source /Users/bolyki/dev/source/build-env.sh && \
xcodebuild -project CodexMeter.xcodeproj -scheme CodexMeterApp -configuration Debug \
  -derivedDataPath "$XCODE_DERIVED_DATA_PATH" \
  -clonedSourcePackagesDirPath "$SWIFTPM_SHARED_CACHE" build
```

- [ ] **Step 3: Replace running app**

```bash
source /Users/bolyki/dev/source/build-env.sh && \
pkill -x Codexex || true && \
open -n "$XCODE_DERIVED_DATA_PATH/Build/Products/Debug/Codexex.app"
```

- [ ] **Step 4: Verify**

Check:

```text
1. menubar app launches
2. popup opens
3. right-click menu opens
4. settings opens
5. sign-in and sign-out paths still render correctly
6. launch-at-login toggle stays truthful
7. no external codex path is required
```

---

## Self-Review

- Spec coverage:
  - XPC service: covered
  - sandbox entitlements: covered
  - removal of external CLI dependence: covered
  - auth/API key path shape: covered at architecture level
  - motion polish: covered
- Placeholder scan:
  - no `TODO` or vague steps remain
- Type consistency:
  - contract and client names are consistent across tasks
