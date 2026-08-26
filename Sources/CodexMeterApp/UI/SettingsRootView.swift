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
    static let accent = CodexTheme.accent
    static let groupedBackground = color(light: ns(0xFAFAFB), dark: ns(0x1E1E20))
    static let sidebarBackground = color(light: ns(0xF0F1F3), dark: ns(0x252527))
    static let cardFill = color(light: ns(0xFFFFFF), dark: ns(0x242426))
    static let controlFill = color(light: ns(0xF1F2F4), dark: ns(0x303034))
    static let pressedControlFill = color(light: ns(0xE7E9ED), dark: ns(0x3A3A3E))
    static let secondaryFill = color(light: ns(0xF1F2F4), dark: ns(0x303034))
    static let selectedFill = color(light: ns(0xE8F0FF), dark: ns(0x273654))
    static let hairline = color(light: ns(0x111827, alpha: 0.10), dark: ns(0xFFFFFF, alpha: 0.08))
    static let hairlineStrong = color(light: ns(0x111827, alpha: 0.14), dark: ns(0xFFFFFF, alpha: 0.12))
    static let destructiveText = color(light: ns(0xB42318), dark: ns(0xFFB4AB))
    static let destructiveFill = color(light: ns(0xFEE4E2), dark: ns(0x421815))
    static let destructivePressedFill = color(light: ns(0xFECACA), dark: ns(0x53211D))
    static let destructiveBorder = color(light: ns(0xF04438, alpha: 0.38), dark: ns(0xFF6B61, alpha: 0.44))

    private static func color(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let match = appearance.bestMatch(from: [.aqua, .darkAqua])
            return match == .darkAqua ? dark : light
        })
    }

    private static func ns(_ hex: UInt32, alpha: CGFloat = 1) -> NSColor {
        NSColor(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}

private enum SettingsControlMetrics {
    static let cornerRadius: CGFloat = 10
    static let controlHeight: CGFloat = 28
    static let actionMinWidth: CGFloat = 86
    static let contentMaxWidth: CGFloat = 600
    static let switchWidth: CGFloat = 40
    static let switchHeight: CGFloat = 22
    static let switchKnobSize: CGFloat = 17

    static func iconRadius(for size: CGFloat) -> CGFloat {
        min(cornerRadius, size / 2)
    }
}

private enum SettingsScrollTarget: Hashable {
    case account
}

struct SettingsRootView: View {
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @Bindable var model: CodexMenuBarModel
    @State private var selection: SettingsSection = .general
    @State private var isShowingResetConfirmation = false
    @State private var accountScrollRequest = 0
    @State private var pendingAccountScroll = false
    @State private var resetErrorMessage: String?
    @State private var isResetting = false

    var body: some View {
        VStack(spacing: 0) {
            titleBar

            HStack(spacing: 0) {
                sidebar
                    .frame(width: 200)

                Divider()
                    .overlay(SettingsTheme.hairline)

                ScrollViewReader { proxy in
                    ScrollView {
                        content
                            .padding(.horizontal, 28)
                            .padding(.vertical, 26)
                            .frame(maxWidth: SettingsControlMetrics.contentMaxWidth, alignment: .topLeading)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                    .scrollIndicators(.hidden)
                    .background(SettingsTheme.groupedBackground)
                    .onChange(of: accountScrollRequest) { _, _ in
                        scrollToAccount(using: proxy)
                    }
                    .onChange(of: selection) { _, newSelection in
                        guard newSelection == .about, pendingAccountScroll else { return }
                        scrollToAccount(using: proxy)
                    }
                }
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
                isResetting = true
                Task { @MainActor in
                    if let helperFailure = await model.clearHelperStateForAppReset() {
                        resetErrorMessage = helperFailure
                        isResetting = false
                        return
                    }
                    let result = CodexAppResetter.resetAndQuit()
                    if result.succeeded == false {
                        resetErrorMessage = result.message
                        isResetting = false
                    }
                }
            }
        } message: {
            Text("This deletes sign-in, settings, preview state, history, and helper data. Codexex will quit after reset.")
        }
        .alert(
            "Reset incomplete",
            isPresented: Binding(
                get: { resetErrorMessage != nil },
                set: { if $0 == false { resetErrorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { resetErrorMessage = nil }
        } message: {
            Text(resetErrorMessage ?? "Codexex could not finish the reset.")
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
                    .background(
                        section.tint,
                        in: RoundedRectangle(
                            cornerRadius: SettingsControlMetrics.iconRadius(for: 22),
                            style: .continuous
                        )
                    )

                Text(section.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 32)
            .background {
                if selection == section {
                    SettingsTheme.selectedFill
                        .clipShape(RoundedRectangle(cornerRadius: SettingsControlMetrics.cornerRadius, style: .continuous))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var sidebarAccount: some View {
        Button {
            openAccountSettings()
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
            .background(
                SettingsTheme.cardFill,
                in: RoundedRectangle(cornerRadius: SettingsControlMetrics.cornerRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: SettingsControlMetrics.cornerRadius, style: .continuous)
                    .strokeBorder(selection == .about ? SettingsTheme.accent.opacity(0.35) : SettingsTheme.hairline, lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: SettingsControlMetrics.cornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Account")
        .accessibilityHint("Opens About settings with account sign-in")
    }

    private func openAccountSettings() {
        pendingAccountScroll = true
        selection = .about
        accountScrollRequest += 1
    }

    private func scrollToAccount(using proxy: ScrollViewProxy) {
        Task { @MainActor in
            await Task.yield()
            await Task.yield()
            withAnimation(.easeInOut(duration: 0.18)) {
                proxy.scrollTo(SettingsScrollTarget.account, anchor: .center)
            }
            pendingAccountScroll = false
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
                    ), accessibilityLabel: "Launch at login")
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
                    ), accessibilityLabel: "Auto-refresh")
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
                    .frame(width: 146, height: SettingsControlMetrics.controlHeight)
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
                    detail: model.localUsageSettingsDetail,
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
                CodexSwitch(
                    isOn: Binding(get: { model.showSparkEnabled }, set: { model.setShowSparkEnabled($0) }),
                    accessibilityLabel: "Show Spark"
                )
            }

            SettingsListRow(title: "Usage history") {
                CodexSwitch(
                    isOn: Binding(get: { model.showHistoryEnabled }, set: { model.setShowHistoryEnabled($0) }),
                    accessibilityLabel: "Show usage history"
                )
            }

            SettingsListRow(title: "History chart", detail: "Bars and trend line inside usage history.", isLast: true) {
                CodexSwitch(
                    isOn: Binding(
                        get: { model.showHistoryChartEnabled },
                        set: { model.setShowHistoryChartEnabled($0) }
                    ),
                    accessibilityLabel: "Show history chart"
                )
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
                .frame(width: 198, height: SettingsControlMetrics.controlHeight)
            }
        }
    }

    private var menuBarSection: some View {
        SettingsListGroup(
            title: "Quota presentation",
            footer: "5-hour visibility controls main Codex usage. Spark remains visible. Weekly visibility is menu-bar only."
        ) {
            SettingsListRow(title: "Mode", detail: "Menu bar usage, remaining quota, or weekly pace.") {
                CodexSegmentedControl(selection: Binding(
                    get: { model.menuBarDisplayMode },
                    set: { model.setMenuBarDisplayMode($0) }
                ), segments: [
                    ("Used", .used),
                    ("Left", .remaining),
                    ("Pace", .pace)
                ])
                .frame(width: 174, height: SettingsControlMetrics.controlHeight)
            }

            SettingsListRow(
                title: "Show Codex 5-hour window",
                detail: "Main Codex menu bar, popup, summaries, and history. Spark stays visible."
            ) {
                CodexSwitch(
                    isOn: Binding(
                        get: { model.showFiveHourInMenubar },
                        set: { model.setShowFiveHourInMenubar($0) }
                    ),
                    accessibilityLabel: "Show Codex 5-hour window"
                )
                .accessibilityIdentifier("mac.settings.showFiveHour")
            }

            SettingsListRow(title: "Weekly window") {
                CodexSwitch(
                    isOn: Binding(
                        get: { model.showWeeklyInMenubar },
                        set: { model.setShowWeeklyInMenubar($0) }
                    ),
                    accessibilityLabel: "Show weekly window"
                )
            }

            SettingsListRow(title: "Reset times", detail: "Choose countdown or clock time.", isLast: true) {
                CodexSegmentedControl(selection: Binding(
                    get: { model.resetDisplayStyle },
                    set: { model.setResetDisplayStyle($0) }
                ), segments: [
                    ("In 2h", .relative),
                    ("Clock", .absolute)
                ])
                .frame(width: 132, height: SettingsControlMetrics.controlHeight)
            }
        }
    }

    private var forecastSection: some View {
        SettingsListGroup(
            title: "Forecast",
            footer: "Early estimate uses prior cycles. Stable uses current weekly pace. ML tuned starts after one month with enough data. Volatile appears when the projection swings."
        ) {
            SettingsListRow(title: "Pace confidence", detail: "Show Early, Stable, ML tuned, or Volatile labels.") {
                CodexSwitch(
                    isOn: Binding(get: { model.showPaceConfidence }, set: { model.setShowPaceConfidence($0) }),
                    accessibilityLabel: "Show pace confidence"
                )
            }

            SettingsListRow(
                title: "Quota notifications",
                detail: model.quotaNotificationStatusMessage
                    ?? "Opt-in alerts for 5H pressure, reset, and weekly risk."
            ) {
                CodexSwitch(isOn: Binding(
                    get: { model.quotaNotificationsEnabled },
                    set: { model.setQuotaNotificationsEnabled($0) }
                ), accessibilityLabel: "Quota notifications")
            }

            SettingsListRow(title: "Hide idle limits", detail: "Collapse secondary limits when inactive.") {
                CodexSwitch(
                    isOn: Binding(
                        get: { model.hideIdleSecondaryLimits },
                        set: { model.setHideIdleSecondaryLimits($0) }
                    ),
                    accessibilityLabel: "Hide idle limits"
                )
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
                .frame(width: 190, height: SettingsControlMetrics.controlHeight)
            }
        }
    }

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsListGroup(title: "Application") {
                HStack(spacing: 14) {
                    SettingsAppIconView(size: 44)

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
                    Button(isResetting ? "Resetting…" : "Reset") { isShowingResetConfirmation = true }
                        .buttonStyle(CodexDestructiveButtonStyle())
                        .disabled(isResetting)
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
                        isCancelling: model.isCancellingPendingSignIn,
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
                    .disabled(model.isAuthBusy)
                }

                SettingsListRow(title: "Sign out", isLast: true) {
                    if model.isSigningOut {
                        ProgressView()
                            .controlSize(.small)
                            .accessibilityLabel("Signing out")
                    } else if model.isSignedIn, model.previewModeEnabled == false {
                        Button("Sign Out") { model.signOut() }
                            .buttonStyle(CodexDestructiveButtonStyle())
                    } else {
                        Text(model.previewModeEnabled ? "Sample data active" : "Not signed in")
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .id(SettingsScrollTarget.account)
        }
    }

    @ViewBuilder
    private var accountPrimaryAction: some View {
        if model.isSigningOut {
            Text("Signing out…")
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.secondary)
        } else if model.isSignedIn, model.previewModeEnabled == false {
            Button("Manage") { model.openManageSubscription() }
                .buttonStyle(CodexPrimaryButtonStyle())
        } else if model.authDeviceCode != nil {
            Button(model.isCancellingPendingSignIn ? "Clearing…" : "Clear Code") { model.clearAuthCode() }
                .buttonStyle(SettingsGhostButtonStyle())
                .disabled(model.isCancellingPendingSignIn)
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
            .background(
                SettingsTheme.accent,
                in: RoundedRectangle(
                    cornerRadius: SettingsControlMetrics.iconRadius(for: size),
                    style: .continuous
                )
            )
            .accessibilityHidden(true)
    }
}

private struct SettingsAppIconView: View {
    let size: CGFloat

    var body: some View {
        Image(nsImage: appIconImage)
            .renderingMode(.original)
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: SettingsControlMetrics.iconRadius(for: size), style: .continuous))
            .accessibilityHidden(true)
    }

    private var appIconImage: NSImage {
        if let namedImage = NSImage(named: "AppIcon"), namedImage.isValid {
            return prepared(namedImage)
        }

        if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let image = NSImage(contentsOf: iconURL) {
            return prepared(image)
        }

        if NSApplication.shared.applicationIconImage.isValid {
            return prepared(NSApplication.shared.applicationIconImage)
        }

        let image = NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)
        return prepared(image)
    }

    private func prepared(_ image: NSImage) -> NSImage {
        let copy = image.copy() as? NSImage ?? image
        copy.size = NSSize(width: 256, height: 256)
        copy.isTemplate = false
        return copy
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
        case "Show Codex 5-hour window":
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
    let isCancelling: Bool
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
                .disabled(isCancelling)

                Button {
                    copyCode()
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .buttonStyle(SettingsGhostButtonStyle())
                .disabled(isCancelling)

                Spacer(minLength: 0)

                Button {
                    cancel()
                } label: {
                    Label(isCancelling ? "Cancelling…" : "Cancel", systemImage: "xmark")
                }
                .buttonStyle(SettingsGhostButtonStyle())
                .disabled(isCancelling)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct CodexSwitch: View {
    @Binding var isOn: Bool
    let accessibilityLabel: String
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
                    .frame(width: SettingsControlMetrics.switchKnobSize, height: SettingsControlMetrics.switchKnobSize)
                    .offset(x: isOn ? 9 : -9)
            }
            .frame(width: SettingsControlMetrics.switchWidth, height: SettingsControlMetrics.switchHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.45)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityRepresentation {
            Toggle(accessibilityLabel, isOn: $isOn)
                .toggleStyle(.switch)
        }
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
                .accessibilityAddTraits(selection == segment.1 ? .isSelected : [])
                .background {
                    if selection == segment.1 {
                        RoundedRectangle(cornerRadius: SettingsControlMetrics.cornerRadius, style: .continuous)
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
        .background(
            SettingsTheme.controlFill,
            in: RoundedRectangle(cornerRadius: SettingsControlMetrics.cornerRadius, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: SettingsControlMetrics.cornerRadius, style: .continuous)
                .strokeBorder(SettingsTheme.hairline, lineWidth: 1)
        }
        .opacity(isEnabled ? 1 : 0.45)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Options")
    }
}

struct SettingsGhostButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12.5, weight: .semibold))
            .foregroundStyle(isEnabled ? Color.primary : Color.secondary)
            .padding(.horizontal, 13)
            .frame(minWidth: SettingsControlMetrics.actionMinWidth)
            .frame(height: SettingsControlMetrics.controlHeight)
            .background(
                configuration.isPressed ? SettingsTheme.pressedControlFill : SettingsTheme.controlFill,
                in: RoundedRectangle(cornerRadius: SettingsControlMetrics.cornerRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: SettingsControlMetrics.cornerRadius, style: .continuous)
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
            .frame(minWidth: SettingsControlMetrics.actionMinWidth)
            .frame(height: SettingsControlMetrics.controlHeight)
            .background(
                SettingsTheme.accent.opacity(configuration.isPressed ? 0.88 : 1),
                in: RoundedRectangle(cornerRadius: SettingsControlMetrics.cornerRadius, style: .continuous)
            )
            .opacity(isEnabled ? (configuration.isPressed ? 0.82 : 1) : 0.45)
    }
}

struct CodexDestructiveButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12.5, weight: .semibold))
            .foregroundStyle(SettingsTheme.destructiveText)
            .padding(.horizontal, 13)
            .frame(minWidth: SettingsControlMetrics.actionMinWidth)
            .frame(height: SettingsControlMetrics.controlHeight)
            .background(
                configuration.isPressed ? SettingsTheme.destructivePressedFill : SettingsTheme.destructiveFill,
                in: RoundedRectangle(cornerRadius: SettingsControlMetrics.cornerRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: SettingsControlMetrics.cornerRadius, style: .continuous)
                    .strokeBorder(SettingsTheme.destructiveBorder, lineWidth: 1)
            }
    }
}
#endif
