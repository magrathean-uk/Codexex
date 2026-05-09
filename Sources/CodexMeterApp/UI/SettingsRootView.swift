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
        switch self {
        case .general, .about:
            return Color(red: 0.42, green: 0.47, blue: 0.56)
        case .popup:
            return CodexTheme.accent
        case .menuBar:
            return Color(red: 0.0, green: 0.55, blue: 0.58)
        case .forecast:
            return Color(red: 0.08, green: 0.55, blue: 0.20)
        }
    }
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
                    .overlay(CodexTheme.hairline)

                ScrollView {
                    content
                        .padding(.horizontal, 28)
                        .padding(.vertical, 26)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .scrollIndicators(.hidden)
                .background(CodexTheme.window)
            }
        }
        .frame(minWidth: 760, minHeight: 540)
        .background(CodexTheme.window)
        .foregroundStyle(CodexTheme.text)
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
                .foregroundStyle(CodexTheme.text)
        }
        .frame(height: 38)
        .background(CodexTheme.titlebar)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(CodexTheme.hairline)
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
        .background(CodexTheme.sidebar)
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
                    .background(selection == section ? Color.white.opacity(0.18) : section.tint, in: RoundedRectangle(cornerRadius: 5, style: .continuous))

                Text(section.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(selection == section ? .white : CodexTheme.text)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 32)
            .background {
                if selection == section {
                    selectedGradient
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var selectedGradient: LinearGradient {
        LinearGradient(
            colors: [Color(red: 0.28, green: 0.56, blue: 1.0), Color(red: 0.12, green: 0.39, blue: 0.92)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var sidebarAccount: some View {
        HStack(spacing: 10) {
            Image(systemName: "person")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(
                    LinearGradient(colors: [CodexTheme.accent, CodexTheme.accent2], startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: Circle()
                )

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
                            .background(selectedGradient, in: RoundedRectangle(cornerRadius: 3, style: .continuous))
                    }

                    Text("Account")
                        .font(.system(size: 11))
                        .foregroundStyle(CodexTheme.dim)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(CodexTheme.dim)
        }
        .padding(8)
        .background(CodexTheme.window, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(CodexTheme.hairline, lineWidth: 1)
        }
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
                    .buttonStyle(CodexGhostButtonStyle())
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
                        .buttonStyle(CodexGhostButtonStyle())
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
            SettingsListRow(title: "Codex Spark", detail: "Show the Spark secondary meter.") {
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
                    Image(nsImage: appIconImage)
                        .resizable()
                        .frame(width: 48, height: 48)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Codexex")
                            .font(.system(size: 13.5, weight: .semibold))
                        Text("Menu bar meter for Codex usage")
                            .font(.system(size: 11.5))
                            .foregroundStyle(CodexTheme.muted)
                    }

                    Spacer()

                    Text(Bundle.main.codexexVersionString)
                        .font(.system(size: 11.5))
                        .foregroundStyle(CodexTheme.dim)
                }
                .padding(.horizontal, 14)
                .frame(height: 72)

                SettingsListRow(title: "Check for updates") {
                    Button("Check") { model.openAppStoreUpdates() }
                        .buttonStyle(CodexGhostButtonStyle())
                }

                SettingsListRow(title: "Release notes") {
                    Button { model.openReleaseNotes() } label: {
                        Label("Open", systemImage: "chevron.right")
                            .labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(CodexGhostButtonStyle())
                }

                SettingsListRow(title: "Terms of Use") {
                    Button { NSWorkspace.shared.open(CodexAppLinks.termsURL) } label: {
                        Label("Open", systemImage: "chevron.right")
                            .labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(CodexGhostButtonStyle())
                }

                SettingsListRow(title: "Privacy Policy", isLast: true) {
                    Button { NSWorkspace.shared.open(CodexAppLinks.privacyURL) } label: {
                        Label("Open", systemImage: "chevron.right")
                            .labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(CodexGhostButtonStyle())
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
                        .buttonStyle(CodexGhostButtonStyle())
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
                    Image(systemName: "person")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(
                            LinearGradient(colors: [CodexTheme.accent, CodexTheme.accent2], startPoint: .topLeading, endPoint: .bottomTrailing),
                            in: Circle()
                        )

                    VStack(alignment: .leading, spacing: 4) {
                        Text(model.accountHeadline)
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(1)

                        Text(model.accountDetail ?? "Account")
                            .font(.system(size: 11.5))
                            .foregroundStyle(CodexTheme.dim)
                            .lineLimit(1)
                    }

                    Spacer()

                    accountPrimaryAction
                }
                .padding(.horizontal, 14)
                .frame(height: 66)

                if let code = model.authDeviceCode {
                    VStack(alignment: .leading, spacing: 9) {
                        Text("Device code")
                            .font(.system(size: 11, weight: .semibold))
                            .textCase(.uppercase)
                            .tracking(1.3)
                            .foregroundStyle(CodexTheme.dim)

                        HStack(spacing: 12) {
                            Text(code)
                                .textSelection(.enabled)
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(CodexTheme.text)

                            Spacer()

                            Button("Open Safari") { model.openAuthVerificationPage() }
                                .buttonStyle(CodexPrimaryButtonStyle())
                                .disabled(model.authVerificationURL == nil)

                            Button("Copy") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(code, forType: .string)
                            }
                            .buttonStyle(CodexGhostButtonStyle())

                            Button("Check") { model.checkPendingChatGPTSignIn() }
                                .buttonStyle(CodexGhostButtonStyle())
                                .disabled(model.canCheckPendingChatGPTSignIn == false)

                            Button("Cancel") { model.cancelPendingChatGPTSignIn() }
                                .buttonStyle(CodexGhostButtonStyle())
                        }
                    }
                    .padding(14)
                    .overlay(alignment: .bottom) {
                        Rectangle()
                            .fill(CodexTheme.hairline)
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
                    .buttonStyle(CodexGhostButtonStyle())
                }

                SettingsListRow(title: "Sign out", isLast: true) {
                    if model.isSignedIn, model.previewModeEnabled == false {
                        Button("Sign Out") { model.signOut() }
                            .buttonStyle(CodexDestructiveButtonStyle())
                    } else {
                        Text(model.previewModeEnabled ? "Sample data active" : "Not signed in")
                            .font(.system(size: 11.5))
                            .foregroundStyle(CodexTheme.dim)
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
                .buttonStyle(CodexGhostButtonStyle())
        } else {
            Button("Sign In") { model.startChatGPTSignIn() }
                .buttonStyle(CodexPrimaryButtonStyle())
                .disabled(model.canStartChatGPTSignIn == false)
        }
    }

    private var appIconImage: NSImage {
        let image = NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)
        image.size = NSSize(width: 256, height: 256)
        image.isTemplate = false
        return image
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
                .tracking(1.8)
                .foregroundStyle(CodexTheme.dim)
                .padding(.horizontal, 4)

            VStack(spacing: 0) {
                content
            }
            .background(CodexTheme.surface, in: RoundedRectangle(cornerRadius: GlassTokens.groupRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: GlassTokens.groupRadius, style: .continuous)
                    .strokeBorder(CodexTheme.hairlineStrong, lineWidth: 1)
            }

            if let footer {
                Text(footer)
                    .font(.system(size: 11.5))
                    .foregroundStyle(CodexTheme.dim)
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
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(CodexTheme.text)

                if let detail {
                    Text(detail)
                        .font(.system(size: 11.5))
                        .foregroundStyle(CodexTheme.dim)
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
                    .fill(CodexTheme.hairline)
                    .frame(height: 1)
            }
        }
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
                    .fill(isOn ? CodexTheme.accent : Color.white.opacity(0.10))
                    .overlay {
                        Capsule(style: .continuous)
                            .strokeBorder(isOn ? Color.white.opacity(0.20) : Color.white.opacity(0.14), lineWidth: 1)
                    }

                Circle()
                    .fill(Color.white.opacity(0.94))
                    .frame(width: 17, height: 17)
                    .shadow(color: .black.opacity(0.26), radius: 2, y: 1)
                    .offset(x: isOn ? 9 : -9)
            }
            .frame(width: 40, height: 22)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.45)
        .animation(.easeInOut(duration: 0.14), value: isOn)
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
                        .foregroundStyle(selection == segment.1 ? Color.white : CodexTheme.muted)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background {
                    if selection == segment.1 {
                        RoundedRectangle(cornerRadius: GlassTokens.pillRadius, style: .continuous)
                            .fill(CodexTheme.accent)
                    }
                }

                if index < segments.count - 1 {
                    Rectangle()
                        .fill(CodexTheme.hairline)
                        .frame(width: 1, height: 16)
                        .opacity(selection == segment.1 || selection == segments[index + 1].1 ? 0 : 1)
                }
            }
        }
        .padding(2)
        .background(CodexTheme.control, in: RoundedRectangle(cornerRadius: GlassTokens.pillRadius + 2, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: GlassTokens.pillRadius + 2, style: .continuous)
                .strokeBorder(CodexTheme.hairline, lineWidth: 1)
        }
        .opacity(isEnabled ? 1 : 0.45)
        .animation(.easeInOut(duration: 0.14), value: selection)
    }
}

struct CodexPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12.5, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 13)
            .frame(height: GlassTokens.pillHeight)
            .background(
                LinearGradient(colors: [Color(red: 0.36, green: 0.60, blue: 1.0), Color(red: 0.12, green: 0.42, blue: 0.93)], startPoint: .top, endPoint: .bottom),
                in: RoundedRectangle(cornerRadius: GlassTokens.pillRadius, style: .continuous)
            )
            .opacity(configuration.isPressed ? 0.82 : 1)
            .modifier(CodexPressableScale(isPressed: configuration.isPressed))
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
            .modifier(CodexPressableScale(isPressed: configuration.isPressed))
    }
}
#endif
