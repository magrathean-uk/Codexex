# Codexex Glass Overhaul Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rework Codexex popup and settings into a macOS 26+ hybrid-glass design that stays native, avoids scrolling in Settings, and keeps reliable menubar behavior.

**Architecture:** Keep the AppKit shell limited to the status item and right-click menu, while SwiftUI owns popup and settings content. Introduce one reusable glass-surface helper so popup and settings share the same material, inset panel, spacing, and radius rules without rebuilding the whole app chrome.

**Tech Stack:** Swift 6.2, SwiftUI, AppKit status-item bridge, Charts, XcodeGen, xcodebuild

---

## File Map

- Modify: `Sources/CodexMeterApp/GlassCard.swift`
  - Expand the current single glass card into reusable surface variants for primary card, inset panel, and subtle card.
- Create: `Sources/CodexMeterApp/GlassTokens.swift`
  - Centralize spacing, corner radius, and width constants for popup and settings.
- Modify: `Sources/CodexMeterApp/PopupRootView.swift`
  - Apply the new surface hierarchy to quota cards, history card, and footer.
- Modify: `Sources/CodexMeterApp/SettingsRootView.swift`
  - Replace the grouped form with a fixed-height custom hybrid-glass layout that does not scroll.
- Modify: `Sources/CodexMeterApp/CodexStatusItemController.swift`
  - Tune popover size to fit the refreshed popup layout.
- Modify: `Sources/CodexMeterApp/main.swift`
  - Tune the Settings scene title and default window sizing if needed after the new layout lands.

---

### Task 1: Add shared glass tokens and surface variants

**Files:**
- Create: `Sources/CodexMeterApp/GlassTokens.swift`
- Modify: `Sources/CodexMeterApp/GlassCard.swift`
- Test: `swift build`

- [ ] **Step 1: Add glass layout tokens**

```swift
#if os(macOS)
import SwiftUI

enum GlassTokens {
    static let popupWidth: CGFloat = 372
    static let settingsWidth: CGFloat = 488
    static let settingsHeight: CGFloat = 356

    static let pagePadding: CGFloat = 18
    static let cardPadding: CGFloat = 16
    static let contentSpacing: CGFloat = 12
    static let sectionSpacing: CGFloat = 14

    static let cardRadius: CGFloat = 20
    static let insetRadius: CGFloat = 16
}
#endif
```

- [ ] **Step 2: Replace the one-style glass card with variants**

```swift
#if os(macOS)
import SwiftUI

enum GlassSurfaceStyle {
    case primary
    case secondary
    case inset

    var tintOpacity: Double {
        switch self {
        case .primary: 0.14
        case .secondary: 0.10
        case .inset: 0.06
        }
    }

    var radius: CGFloat {
        switch self {
        case .primary, .secondary: GlassTokens.cardRadius
        case .inset: GlassTokens.insetRadius
        }
    }
}

struct GlassCard<Content: View>: View {
    let style: GlassSurfaceStyle
    @ViewBuilder let content: Content

    init(style: GlassSurfaceStyle = .primary, @ViewBuilder content: () -> Content) {
        self.style = style
        self.content = content()
    }

    var body: some View {
        content
            .padding(GlassTokens.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                .white.opacity(style.tintOpacity),
                in: RoundedRectangle(cornerRadius: style.radius, style: .continuous)
            )
            .glassEffect(.regular, in: .rect(cornerRadius: style.radius))
    }
}
#endif
```

- [ ] **Step 3: Build once to catch naming or import issues**

Run:

```bash
source /Users/bolyki/dev/source/build-env.sh && swift build
```

Expected: build succeeds

- [ ] **Step 4: Commit**

```bash
git add Sources/CodexMeterApp/GlassTokens.swift Sources/CodexMeterApp/GlassCard.swift
git commit -m "feat: add shared glass design tokens"
```

---

### Task 2: Rebuild the popup into a stronger glass hierarchy

**Files:**
- Modify: `Sources/CodexMeterApp/PopupRootView.swift`
- Modify: `Sources/CodexMeterApp/CodexStatusItemController.swift`
- Test: `swift build`

- [ ] **Step 1: Tune popup root spacing and width**

```swift
GlassEffectContainer(spacing: GlassTokens.sectionSpacing) {
    VStack(alignment: .leading, spacing: GlassTokens.sectionSpacing) {
        // cards
        footer
    }
    .padding(GlassTokens.pagePadding)
}
.frame(width: GlassTokens.popupWidth)
```

- [ ] **Step 2: Make quota windows read as inset panels inside one glass plate**

```swift
GlassCard(style: .primary) {
    VStack(alignment: .leading, spacing: GlassTokens.contentSpacing) {
        HStack(alignment: .firstTextBaseline) {
            Text(limit.displayName).font(.headline)
            Spacer()
            Text(headlineWindow.usedPercentText)
                .font(.title3.monospacedDigit().weight(.semibold))
        }

        GlassCard(style: .inset) {
            VStack(alignment: .leading, spacing: 8) {
                topRow
                UsageBar(progress: window.clampedUsedPercent / 100)
                metricsRow
            }
        }
    }
}
```

- [ ] **Step 3: Tighten history card**

```swift
GlassCard(style: .secondary) {
    VStack(alignment: .leading, spacing: 12) {
        header
        chart.frame(height: 84)
        HStack(spacing: 10) {
            forecastPill(label: "H", forecast: fiveHourForecast)
            forecastPill(label: "W", forecast: weeklyForecast)
        }
    }
}
```

- [ ] **Step 4: Size the popover to the new layout**

```swift
popover.contentSize = NSSize(width: GlassTokens.popupWidth, height: 520)
```

- [ ] **Step 5: Build**

Run:

```bash
source /Users/bolyki/dev/source/build-env.sh && swift build
```

Expected: build succeeds

- [ ] **Step 6: Commit**

```bash
git add Sources/CodexMeterApp/PopupRootView.swift Sources/CodexMeterApp/CodexStatusItemController.swift
git commit -m "feat: redesign popup with hybrid glass hierarchy"
```

---

### Task 3: Replace the Settings form with a fixed non-scrolling hybrid-glass layout

**Files:**
- Modify: `Sources/CodexMeterApp/SettingsRootView.swift`
- Modify: `Sources/CodexMeterApp/main.swift`
- Test: `swift build`

- [ ] **Step 1: Replace the current `Form` with a fixed layout**

```swift
VStack(alignment: .leading, spacing: GlassTokens.sectionSpacing) {
    accountCard
    behaviorAndStatusRow
}
.padding(GlassTokens.pagePadding)
.frame(width: GlassTokens.settingsWidth, height: GlassTokens.settingsHeight, alignment: .topLeading)
```

- [ ] **Step 2: Build the account card**

```swift
private var accountCard: some View {
    GlassCard(style: .primary) {
        VStack(alignment: .leading, spacing: 10) {
            Text("Account").font(.headline)
            Text(accountSubtitle).foregroundStyle(.secondary)

            if model.isSigningIn, let code = model.authDeviceCode {
                Text(code)
                    .font(.system(.body, design: .monospaced, weight: .semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.white.opacity(0.08), in: Capsule())
            }

            HStack {
                actionButton
                Spacer()
            }
        }
    }
}
```

- [ ] **Step 3: Build the behavior and status split**

```swift
private var behaviorAndStatusRow: some View {
    HStack(alignment: .top, spacing: GlassTokens.sectionSpacing) {
        GlassCard(style: .secondary) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Behavior").font(.headline)
                Toggle("Launch at login", isOn: ...)
                Toggle("Auto-refresh", isOn: ...)
                Toggle("Show history chart", isOn: ...)
                Picker("Refresh every", selection: ...) { ... }
                    .pickerStyle(.segmented)
            }
        }

        GlassCard(style: .secondary) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Status").font(.headline)
                LabeledContent("Account") { Text(accountValue) }
                LabeledContent("Last refresh") { Text(lastUpdatedValue) }
                LabeledContent("Message") { Text(statusMessage) }
            }
        }
    }
}
```

- [ ] **Step 4: Keep the settings window title clean**

```swift
Settings {
    SettingsRootView(model: sharedModel)
}
```

If the scene title is shown in code, keep it as `Codexex Settings` and remove any extra header inside the view.

- [ ] **Step 5: Build**

Run:

```bash
source /Users/bolyki/dev/source/build-env.sh && swift build
```

Expected: build succeeds

- [ ] **Step 6: Commit**

```bash
git add Sources/CodexMeterApp/SettingsRootView.swift Sources/CodexMeterApp/main.swift
git commit -m "feat: redesign settings with native hybrid glass"
```

---

### Task 4: Regenerate project, rebuild app bundle, and verify live behavior

**Files:**
- Modify: `project.yml` only if build settings need popup/settings sizing help
- Test: Xcode build and live app launch

- [ ] **Step 1: Regenerate the project if files changed**

Run:

```bash
source /Users/bolyki/dev/source/build-env.sh && xcodegen generate
```

Expected: `Created project at /Users/bolyki/dev/source/Codexex/CodexMeter.xcodeproj`

- [ ] **Step 2: Build the app bundle**

Run:

```bash
source /Users/bolyki/dev/source/build-env.sh && \
xcodebuild -project CodexMeter.xcodeproj -scheme CodexMeterApp -configuration Debug \
  -derivedDataPath "$XCODE_DERIVED_DATA_PATH" \
  -clonedSourcePackagesDirPath "$SWIFTPM_SHARED_CACHE" build
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Replace the live app**

Run:

```bash
source /Users/bolyki/dev/source/build-env.sh && \
pkill -x Codexex || true && \
open -n "$XCODE_DERIVED_DATA_PATH/Build/Products/Debug/Codexex.app"
```

Expected: the new Codexex menubar app launches

- [ ] **Step 4: Manually verify acceptance points**

Check:

```text
1. Right-click menu still opens
2. Left-click popup still opens
3. Popup cards look tighter and more glass-forward
4. Settings window has no scroll
5. Settings opens cleanly and closes popup first
6. Sign in / sign out still works
```

- [ ] **Step 5: Commit**

```bash
git add .
git commit -m "feat: apply macos hybrid glass overhaul"
```

---

## Self-Review

- Spec coverage:
  - hybrid glass direction: covered by Tasks 1 to 3
  - popup emphasis: covered by Task 2
  - non-scrolling settings: covered by Task 3
  - native menubar behavior: preserved in Task 4 verification
- Placeholder scan:
  - no `TODO`, `TBD`, or vague “handle later” steps remain
- Type consistency:
  - `GlassTokens`, `GlassSurfaceStyle`, and `GlassCard(style:)` are defined before later tasks use them
