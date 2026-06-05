#if os(macOS)
import AppKit
import Observation
import SwiftUI

private enum SettingsSection: String, CaseIterable, Identifiable {
    case general
    case popup
    case menuBar
    case forecast
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general:
            return "General"
        case .popup:
            return "Popup"
        case .menuBar:
            return "Menu Bar"
        case .forecast:
            return "Forecast"
        case .about:
            return "About"
        }
    }

    var systemImage: String {
        switch self {
        case .general:
            return "slider.horizontal.3"
        case .popup:
            return "rectangle.topthird.inset.filled"
        case .menuBar:
            return "menubar.rectangle"
        case .forecast:
            return "chart.line.uptrend.xyaxis"
        case .about:
            return "info.circle"
        }
    }

    var tint: Color {
        SettingsTheme.accent
    }
}

private enum SettingsTheme {
    static let accent = Color.accentColor
    static let groupedBackground = Color(nsColor: .windowBackgroundColor)
    static let sidebarBackground = Color(nsColor: .underPageBackgroundColor)
    static let cardFill = Color(nsColor: .controlBackgroundColor)
    static let secondaryFill = Color.primary.opacity(0.06)
    static let selectedFill = accent.opacity(0.13)
    static let hairline = Color.primary.opacity(0.08)
    static let hairlineStrong = Color.primary.opacity(0.12)
}

struct SettingsRootView: View {
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @Bindable var model: CodexMenuBarModel
    @State private var selection: SettingsSection = .general
    @State private var isShowingResetConfirmation = false

    var body: some View {
        VStack(spacing: 0) {
            titleBar

            HStack(spacing: 0) {
                sidebar
                    .frame(width: 200)

                Divider()
                    .overlay(SettingsTheme.hairline)

                ScrollView {
                    content
                        .padding(.horizontal, 28)
                        .padding(.vertical, 26)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .scrollIndicators(.hidden)
                .background(SettingsTheme.groupedBackground)
            }
        }
        .frame(minWidth: 760, minHeight: 540)
        .background(SettingsTheme.groupedBackground)
        .foregroundStyle(.primary)
        .preferredColorScheme(model.appearanceMode.colorScheme)
        .onAppear {
            model.setReduceMotionEnabled(accessibilityReduceMotion)
        }
        .onChange(of: accessibilityReduceMotion) { _, newValue in
            model.setReduceMotionEnabled(newValue)
        }
        .alert("Reset Codexex?", isPresented: $isShowingResetConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Reset App", role: .destructive) {
                CodexAppResetter.resetAndQuit()
            }
        } message: {
            Text("This deletes sign-in, settings, preview state, history, and helper data. Codexex will quit after reset.")
        }
    }

    private var titleBar: some View {
        ZStack {
            HStack(spacing: 6) {
                Color.clear.frame(width: 70)

                Spacer()
            }
            .padding(.horizontal, 12)

            Text(selection.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
        }
        .frame(height: 38)
        .background(SettingsTheme.groupedBackground)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(SettingsTheme.hairline)
                .frame(height: 1)
        }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            VStack(spacing: 4) {
                ForEach(SettingsSection.allCases) { section in
                    sidebarItem(section)
                }
            }
            .padding(8)

            Spacer(minLength: 0)

            sidebarAccount
                .padding(8)
        }
        .background(SettingsTheme.sidebarBackground)
    }

    private func sidebarItem(_ section: SettingsSection) -> some View {
        Button {
            selection = section
        } label: {
            HStack(spacing: 11) {
                Image(systemName: section.systemImage)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(section.tint, in: RoundedRectangle(cornerRadius: 5, style: .continuous))

                Text(section.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(selection == section ? SettingsTheme.accent : .primary)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 32)
            .background {
                if selection == section {
                    SettingsTheme.selectedFill
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var sidebarAccount: some View {
        Button {
            selection = .about
        } label: {
            HStack(spacing: 10) {
                SettingsRowIcon(systemImage: "person.crop.circle")

                VStack(alignment: .leading, spacing: 2) {
                    Text(model.accountHeadline)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)

                    HStack(spacing: 5) {
                        if model.snapshot?.account.planType?.isEmpty == false {
                            Text(model.snapshot?.account.planType?.uppercased() ?? "")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(SettingsTheme.accent, in: RoundedRectangle(cornerRadius: 3, style: .continuous))
                        }

                        Text("Account")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(8)
            .background(SettingsTheme.cardFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(selection == .about ? SettingsTheme.accent.opacity(0.35) : SettingsTheme.hairline, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Account")
        .accessibilityHint("Opens About settings with account sign-in")
    }

    @ViewBuilder
    private var content: some View {
        switch selection {
        case .general:
            generalSection
        case .popup:
            popupSection
        case .menuBar:
            menuBarSection
        case .forecast:
            forecastSection
        case .about:
            aboutSection
        }
    }

    private var generalSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsListGroup(title: "Startup") {
                SettingsListRow(
                    title: "Launch at login",
                    detail: model.launchAtLoginStatusMessage ?? "Open Codexex when your Mac starts.",
                    isLast: true
                ) {
                    CodexSwitch(isOn: Binding(
                        get: { model.launchAtLoginEnabled },
                        set: { model.setLaunchAtLoginEnabled($0) }
                    ))
                }
            }

            SettingsListGroup(
                title: "Refresh",
                footer: "Background refresh keeps your menu bar meter up to date without opening the popup."
            ) {
                SettingsListRow(title: "Auto-refresh") {
                    CodexSwitch(isOn: Binding(
                        get: { model.autoRefreshEnabled },
                        set: { model.setAutoRefreshEnabled($0) }
                    ))
                }

                SettingsListRow(title: "Interval") {
                    CodexSegmentedControl(selection: Binding(
                        get: { model.refreshIntervalSeconds },
                        set: { model.setRefreshIntervalSeconds($0) }
                    ), segments: [
                        ("5m", 300),
                        ("10m", 600),
                        ("60m", 3600)
                    ])
                    .frame(width: 146, height: GlassTokens.pillHeight)
                    .disabled(model.autoRefreshEnabled == false)
                }

                SettingsListRow(title: "Refresh now", detail: "Pull the latest quota data.", isLast: true) {
                    Button {
                        Task { await model.refreshNow(manual: true) }
                    } label: {
                        Label(model.isRefreshing ? "Refreshing" : "Refresh", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(SettingsGhostButtonStyle())
                    .disabled(model.isRefreshing)
                }
            }

            SettingsListGroup(
                title: "Codex data",
                footer: "Choose the Codex sessions folder if sandbox permissions block the default path."
            ) {
                SettingsListRow(
                    title: "Sessions folder",
                    detail: model.codexSessionsPath ?? "~/.codex/sessions",
                    isLast: true
                ) {
                    Button("Choose") { model.chooseCodexSessionsFolder() }
                        .buttonStyle(SettingsGhostButtonStyle())
                }
            }

            appearanceSection
        }
    }

    private var popupSection: some View {
        SettingsListGroup(
            title: "Popup contents",
            footer: "Choose which sections appear in the menu bar popup."
        ) {
            SettingsListRow(title: "Spark", detail: "Show the secondary Spark meter.") {
                CodexSwitch(isOn: Binding(get: { model.showSparkEnabled }, set: { model.setShowSparkEnabled($0) }))
            }

            SettingsListRow(title: "Usage history") {
                CodexSwitch(isOn: Binding(get: { model.showHistoryEnabled }, set: { model.setShowHistoryEnabled($0) }))
            }

            SettingsListRow(title: "History chart", detail: "Bars and trend line inside usage history.", isLast: true) {
                CodexSwitch(isOn: Binding(get: { model.showHistoryChartEnabled }, set: { model.setShowHistoryChartEnabled($0) }))
                    .disabled(model.showHistoryEnabled == false)
            }
        }
    }

    private var appearanceSection: some View {
        SettingsListGroup(
            title: "Theme",
            footer: "System follows macOS. Light and Dark force Codexex only."
        ) {
            SettingsListRow(title: "Appearance", isLast: true) {
                CodexSegmentedControl(selection: Binding(
                    get: { model.appearanceMode },
                    set: { model.setAppearanceMode($0) }
                ), segments: [
                    ("System", .system),
                    ("Light", .light),
                    ("Dark", .dark)
                ])
                .frame(width: 198, height: GlassTokens.pillHeight)
            }
        }
    }

    private var menuBarSection: some View {
        SettingsListGroup(
            title: "Menu bar meters",
            footer: "What stays visible in the menu bar at all times."
        ) {
            SettingsListRow(title: "Mode", detail: "Show usage, remaining quota, or weekly pace.") {
                CodexSegmentedControl(selection: Binding(
                    get: { model.menuBarDisplayMode },
                    set: { model.setMenuBarDisplayMode($0) }
                ), segments: [
                    ("Used", .used),
                    ("Left", .remaining),
                    ("Pace", .pace)
                ])
                .frame(width: 174, height: GlassTokens.pillHeight)
            }

            SettingsListRow(title: "5-hour window") {
                CodexSwitch(isOn: Binding(get: { model.showFiveHourInMenubar }, set: { model.setShowFiveHourInMenubar($0) }))
            }

            SettingsListRow(title: "Weekly window") {
                CodexSwitch(isOn: Binding(get: { model.showWeeklyInMenubar }, set: { model.setShowWeeklyInMenubar($0) }))
            }

            SettingsListRow(title: "Reset times", detail: "Choose countdown or clock time.", isLast: true) {
                CodexSegmentedControl(selection: Binding(
                    get: { model.resetDisplayStyle },
                    set: { model.setResetDisplayStyle($0) }
                ), segments: [
                    ("In 2h", .relative),
                    ("Clock", .absolute)
                ])
                .frame(width: 132, height: GlassTokens.pillHeight)
            }
        }
    }

    private var forecastSection: some View {
        SettingsListGroup(
            title: "Forecast",
            footer: "Early estimate uses prior cycles. Stable uses current weekly pace. ML tuned starts after one month with enough data. Volatile appears when the projection swings."
        ) {
            SettingsListRow(title: "Pace confidence", detail: "Show Early, Stable, ML tuned, or Volatile labels.") {
                CodexSwitch(isOn: Binding(get: { model.showPaceConfidence }, set: { model.setShowPaceConfidence($0) }))
            }

            SettingsListRow(title: "Quota notifications", detail: "Opt-in alerts for 5H pressure, reset, and weekly risk.") {
                CodexSwitch(isOn: Binding(
                    get: { model.quotaNotificationsEnabled },
                    set: { model.setQuotaNotificationsEnabled($0) }
                ))
            }

            SettingsListRow(title: "Hide idle limits", detail: "Collapse secondary limits when inactive.") {
                CodexSwitch(isOn: Binding(get: { model.hideIdleSecondaryLimits }, set: { model.setHideIdleSecondaryLimits($0) }))
            }

            SettingsListRow(title: "History default", isLast: true) {
                CodexSegmentedControl(selection: Binding(
                    get: { model.defaultHistoryMode },
                    set: { model.setDefaultHistoryMode($0) }
                ), segments: [
                    ("Peaks", .dailyPeaks),
                    ("Cycle", .thisCycle),
                    ("Month", .monthly)
                ])
                .frame(width: 190, height: GlassTokens.pillHeight)
            }
        }
    }

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsListGroup(title: "Application") {
                HStack(spacing: 14) {
                    SettingsRowIcon(systemImage: "command.circle.fill", size: 44, imageSize: 22)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Codexex")
                            .font(.system(size: 13.5, weight: .semibold))
                        Text("Menu bar meter for Codex usage")
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Text(Bundle.main.codexexVersionString)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14)
                .frame(height: 72)

                SettingsListRow(title: "Terms of Use") {
                    Button { NSWorkspace.shared.open(CodexAppLinks.termsURL) } label: {
                        Label("Open", systemImage: "chevron.right")
                            .labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(SettingsGhostButtonStyle())
                }

                SettingsListRow(title: "Privacy Policy", isLast: true) {
                    Button { NSWorkspace.shared.open(CodexAppLinks.privacyURL) } label: {
                        Label("Open", systemImage: "chevron.right")
                            .labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(SettingsGhostButtonStyle())
                }
            }

            SettingsListGroup(
                title: "Diagnostics",
                footer: "Copies a redacted report. No email, device code, cookies, or tokens."
            ) {
                SettingsListRow(
                    title: "Copy diagnostics",
                    detail: model.diagnosticsStatusMessage ?? "Useful when reporting quota or refresh issues.",
                    isLast: true
                ) {
                    Button("Copy") { model.copyDiagnosticsReport() }
                        .buttonStyle(SettingsGhostButtonStyle())
                }
            }

            SettingsListGroup(
                title: "Reset",
                footer: "Deletes sign-in, settings, preview state, history, and helper data. Codexex quits when done."
            ) {
                SettingsListRow(title: "Reset app", detail: "Return Codexex to first launch.", isLast: true) {
                    Button("Reset") { isShowingResetConfirmation = true }
                        .buttonStyle(CodexDestructiveButtonStyle())
                }
            }

            SettingsListGroup(title: "Account") {
                HStack(spacing: 14) {
                    SettingsRowIcon(systemImage: "person.crop.circle", size: 40, imageSize: 18)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(model.accountHeadline)
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(1)

                        Text(model.accountDetail ?? "Account")
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    accountPrimaryAction
                }
                .padding(.horizontal, 14)
                .frame(height: 66)

                if let code = model.authDeviceCode {
                    SettingsDeviceCodeCallout(
                        code: code,
                        openSafari: { model.openAuthVerificationPage() },
                        copyCode: { model.copyAuthCode() },
                        cancel: { model.cancelPendingChatGPTSignIn() }
                    )
                    .padding(14)
                    .overlay(alignment: .bottom) {
                        Rectangle()
                            .fill(SettingsTheme.hairline)
                            .frame(height: 1)
                    }
                }

                SettingsListRow(title: "Sample data", detail: "Inspect the UI without touching live usage.") {
                    Button(model.previewModeEnabled ? "Disable" : "Enable") {
                        if model.previewModeEnabled {
                            model.disablePreviewMode()
                        } else {
                            model.enablePreviewMode()
                        }
                    }
                    .buttonStyle(SettingsGhostButtonStyle())
                }

                SettingsListRow(title: "Sign out", isLast: true) {
                    if model.isSignedIn, model.previewModeEnabled == false {
                        Button("Sign Out") { model.signOut() }
                            .buttonStyle(CodexDestructiveButtonStyle())
                    } else {
                        Text(model.previewModeEnabled ? "Sample data active" : "Not signed in")
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var accountPrimaryAction: some View {
        if model.isSignedIn, model.previewModeEnabled == false {
            Button("Manage") { model.openManageSubscription() }
                .buttonStyle(CodexPrimaryButtonStyle())
        } else if model.authDeviceCode != nil {
            Button("Clear Code") { model.clearAuthCode() }
                .buttonStyle(SettingsGhostButtonStyle())
        } else {
            Button("Sign In") { model.startChatGPTSignIn() }
                .buttonStyle(CodexPrimaryButtonStyle())
                .disabled(model.canStartChatGPTSignIn == false)
        }
    }
}

private struct SettingsListGroup<Content: View>: View {
    let title: String
    var footer: String? = nil
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)

            VStack(spacing: 0) {
                content
            }
            .background(SettingsTheme.cardFill, in: RoundedRectangle(cornerRadius: GlassTokens.groupRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: GlassTokens.groupRadius, style: .continuous)
                    .strokeBorder(SettingsTheme.hairlineStrong, lineWidth: 1)
            }

            if let footer {
                Text(footer)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }
        }
    }
}

private struct SettingsListRow<Accessory: View>: View {
    let title: String
    var detail: String?
    var isLast: Bool = false
    @ViewBuilder let accessory: Accessory

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            SettingsRowIcon(systemImage: SettingsRowIconName.systemImage(for: title))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)

                if let detail {
                    Text(detail)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.vertical, detail == nil ? 0 : 8)

            Spacer(minLength: 16)

            accessory
        }
        .padding(.horizontal, 14)
        .frame(minHeight: detail == nil ? 40 : 52)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) {
            if isLast == false {
                Rectangle()
                    .fill(SettingsTheme.hairline)
                    .frame(height: 1)
                    .padding(.leading, 60)
            }
        }
    }
}

private struct SettingsRowIcon: View {
    let systemImage: String
    var size: CGFloat = 30
    var imageSize: CGFloat = 14

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: imageSize, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(SettingsTheme.accent, in: RoundedRectangle(cornerRadius: min(8, size * 0.22), style: .continuous))
            .accessibilityHidden(true)
    }
}

private enum SettingsRowIconName {
    static func systemImage(for title: String) -> String {
        switch title {
        case "Launch at login":
            return "power"
        case "Auto-refresh":
            return "arrow.clockwise"
        case "Interval":
            return "timer"
        case "Refresh now":
            return "arrow.triangle.2.circlepath"
        case "Sessions folder":
            return "folder"
        case "Appearance":
            return "circle.lefthalf.filled"
        case "Spark":
            return "sparkles"
        case "Usage history":
            return "chart.bar.xaxis"
        case "History chart":
            return "waveform.path.ecg"
        case "Mode":
            return "menubar.rectangle"
        case "5-hour window":
            return "clock"
        case "Weekly window":
            return "calendar"
        case "Reset times":
            return "clock.badge.checkmark"
        case "Pace confidence":
            return "chart.line.uptrend.xyaxis"
        case "Quota notifications":
            return "bell"
        case "Hide idle limits":
            return "eye.slash"
        case "History default":
            return "chart.xyaxis.line"
        case "Terms of Use":
            return "doc.text"
        case "Privacy Policy":
            return "hand.raised"
        case "Copy diagnostics":
            return "doc.on.doc"
        case "Reset app":
            return "trash"
        case "Sample data":
            return "square.stack.3d.up"
        case "Sign out":
            return "rectangle.portrait.and.arrow.right"
        default:
            return "gearshape"
        }
    }
}

private struct SettingsDeviceCodeCallout: View {
    let code: String
    let openSafari: () -> Void
    let copyCode: () -> Void
    let cancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                SettingsRowIcon(systemImage: "key")

                VStack(alignment: .leading, spacing: 3) {
                    Text("Device code")
                        .font(.system(size: 13, weight: .medium))
                    Text("Use this code to finish sign-in.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                }
            }

            Text(code)
                .font(.system(size: 26, weight: .bold, design: .monospaced))
                .minimumScaleFactor(0.78)
                .lineLimit(1)
                .textSelection(.enabled)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(SettingsTheme.secondaryFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(SettingsTheme.hairline, lineWidth: 1)
                }

            HStack(spacing: 8) {
                Button {
                    openSafari()
                } label: {
                    Label("Open", systemImage: "safari")
                }
                .buttonStyle(CodexPrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)

                Button {
                    copyCode()
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .buttonStyle(SettingsGhostButtonStyle())

                Spacer(minLength: 0)

                Button {
                    cancel()
                } label: {
                    Label("Cancel", systemImage: "xmark")
                }
                .buttonStyle(SettingsGhostButtonStyle())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct CodexSwitch: View {
    @Binding var isOn: Bool
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            ZStack {
                Capsule(style: .continuous)
                    .fill(isOn ? SettingsTheme.accent : SettingsTheme.secondaryFill)
                    .overlay {
                        Capsule(style: .continuous)
                            .strokeBorder(isOn ? SettingsTheme.accent.opacity(0.35) : SettingsTheme.hairlineStrong, lineWidth: 1)
                    }

                Circle()
                    .fill(Color.white)
                    .frame(width: 17, height: 17)
                    .offset(x: isOn ? 9 : -9)
            }
            .frame(width: 40, height: 22)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.45)
    }
}

private struct CodexSegmentedControl<Value: Hashable>: View {
    @Binding var selection: Value
    let segments: [(String, Value)]
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                Button {
                    selection = segment.1
                } label: {
                    Text(segment.0)
                        .font(.system(size: 12.5, weight: selection == segment.1 ? .semibold : .medium))
                        .foregroundStyle(selection == segment.1 ? Color.white : Color.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background {
                    if selection == segment.1 {
                        RoundedRectangle(cornerRadius: GlassTokens.pillRadius, style: .continuous)
                            .fill(SettingsTheme.accent)
                    }
                }

                if index < segments.count - 1 {
                    Rectangle()
                        .fill(SettingsTheme.hairline)
                        .frame(width: 1, height: 16)
                        .opacity(selection == segment.1 || selection == segments[index + 1].1 ? 0 : 1)
                }
            }
        }
        .padding(2)
        .background(SettingsTheme.secondaryFill, in: RoundedRectangle(cornerRadius: GlassTokens.pillRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: GlassTokens.pillRadius, style: .continuous)
                .strokeBorder(SettingsTheme.hairline, lineWidth: 1)
        }
        .opacity(isEnabled ? 1 : 0.45)
    }
}

struct SettingsGhostButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12.5, weight: .semibold))
            .foregroundStyle(isEnabled ? Color.primary : Color.secondary)
            .padding(.horizontal, 13)
            .frame(height: GlassTokens.pillHeight)
            .background(
                configuration.isPressed ? SettingsTheme.secondaryFill.opacity(0.72) : SettingsTheme.secondaryFill,
                in: RoundedRectangle(cornerRadius: GlassTokens.pillRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: GlassTokens.pillRadius, style: .continuous)
                    .strokeBorder(SettingsTheme.hairlineStrong, lineWidth: 1)
            }
            .opacity(isEnabled ? 1 : 0.45)
    }
}

struct CodexPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12.5, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 13)
            .frame(height: GlassTokens.pillHeight)
            .background(
                Color.accentColor,
                in: RoundedRectangle(cornerRadius: GlassTokens.pillRadius, style: .continuous)
            )
            .opacity(isEnabled ? (configuration.isPressed ? 0.82 : 1) : 0.45)
    }
}

struct CodexDestructiveButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12.5, weight: .medium))
            .foregroundStyle(Color(red: 1.0, green: 0.66, blue: 0.62))
            .padding(.horizontal, 13)
            .frame(height: GlassTokens.pillHeight)
            .background(
                Color(red: 0.25, green: 0.08, blue: 0.08).opacity(configuration.isPressed ? 0.9 : 0.7),
                in: RoundedRectangle(cornerRadius: GlassTokens.pillRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: GlassTokens.pillRadius, style: .continuous)
                    .strokeBorder(Color(red: 0.8, green: 0.22, blue: 0.20).opacity(0.55), lineWidth: 1)
            }
    }
}
#endif
