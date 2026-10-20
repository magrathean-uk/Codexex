#if os(macOS)
import AppKit
import Observation
import SwiftUI

enum SettingsSection: String, CaseIterable, Identifiable {
    case accounts, general, appearance, data, about
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var systemImage: String {
        switch self {
        case .accounts: "person.crop.circle"
        case .general: "gearshape"
        case .appearance: "paintbrush"
        case .data: "folder"
        case .about: "info.circle"
        }
    }
}

enum SettingsAccountDestination: String { case subscription, api }

private enum SettingsTheme {
    static let accent = CodexTheme.actionTint
    static let groupedBackground = color(light: ns(0xFAFAFB), dark: ns(0x1E1E20))
    static let sidebarBackground = color(light: ns(0xF0F1F3), dark: ns(0x252527))
    static let cardFill = color(light: ns(0xFFFFFF), dark: ns(0x242426))
    static let controlFill = color(light: ns(0xF1F2F4), dark: ns(0x303034))
    static let pressedControlFill = color(light: ns(0xE7E9ED), dark: ns(0x3A3A3E))
    static let secondaryFill = color(light: ns(0xF1F2F4), dark: ns(0x303034))
    static let selectedFill = color(light: ns(0xE8F0FF), dark: ns(0x273654))
    static let hairline = color(light: ns(0x111827, alpha: 0.10), dark: ns(0xFFFFFF, alpha: 0.08))
    static let hairlineStrong = color(
        light: ns(0x111827, alpha: 0.14), dark: ns(0xFFFFFF, alpha: 0.12))
    static let destructiveText = color(light: ns(0xB42318), dark: ns(0xFFB4AB))
    static let destructiveFill = color(light: ns(0xFEE4E2), dark: ns(0x421815))
    static let destructivePressedFill = color(light: ns(0xFECACA), dark: ns(0x53211D))
    static let destructiveBorder = color(
        light: ns(0xF04438, alpha: 0.38), dark: ns(0xFF6B61, alpha: 0.44))

    private static func color(light: NSColor, dark: NSColor) -> Color {
        Color(
            nsColor: NSColor(name: nil) { appearance in
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
    static let cornerRadius: CGFloat = 4
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

struct SettingsRootView: View {
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @Bindable var model: CodexMenuBarModel
    @State private var selection: SettingsSection
    @State private var accountDestination: SettingsAccountDestination?
    @State private var isShowingResetConfirmation = false
    @State private var resetErrorMessage: String?
    @State private var isResetting = false

    init(
        model: CodexMenuBarModel, initialSection: SettingsSection = .accounts,
        initialAccount: SettingsAccountDestination? = nil
    ) {
        self.model = model
        _selection = State(initialValue: initialSection)
        _accountDestination = State(initialValue: initialAccount)
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(
                accountDestination == .api && selection == .accounts
                    ? "API monitoring" : selection.title
            )
            .font(.headline)
            .frame(maxWidth: .infinity)
            .frame(height: 38)
            Divider()
            HStack(spacing: 0) {
                List(
                    SettingsSection.allCases,
                    selection: Binding<SettingsSection?>(
                        get: { selection }, set: { if let value = $0 { selection = value } }
                    )
                ) { section in
                    Label(section.title, systemImage: section.systemImage).tag(section)
                }
                .listStyle(.sidebar)
                .frame(width: 190)
                Divider()
                ScrollView {
                    content
                        .id(selection)
                        .transition(.opacity)
                        .frame(
                            maxWidth: SettingsControlMetrics.contentMaxWidth, alignment: .topLeading
                        )
                        .padding(24)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .background(Color(nsColor: .windowBackgroundColor))
            }
        }
        .frame(minWidth: 760, minHeight: 540)
        .background(Color(nsColor: .windowBackgroundColor))
        .tint(CodexTheme.actionTint)
        .preferredColorScheme(model.appearanceMode.colorScheme)
        .animation(accessibilityReduceMotion ? nil : .easeInOut(duration: 0.16), value: selection)
        .animation(
            accessibilityReduceMotion ? nil : .easeInOut(duration: 0.16), value: accountDestination
        )
        .onChange(of: selection) { _, _ in accountDestination = nil }
        .onAppear { model.setReduceMotionEnabled(accessibilityReduceMotion) }
        .onChange(of: accessibilityReduceMotion) { _, value in model.setReduceMotionEnabled(value) }
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
            Text(
                "This deletes sign-in, settings, preview state, history, and helper data. Codexex will quit after reset."
            )
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

    @ViewBuilder
    private var content: some View {
        switch selection {
        case .accounts: accountsSection
        case .general: generalSection
        case .appearance:
            VStack(alignment: .leading, spacing: 26) {
                themeSection
                menuBarSection
            }
        case .data: dataSection
        case .about: aboutSection
        }
    }

    private var accountsSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            if let destination = accountDestination {
                Button {
                    accountDestination = nil
                } label: {
                    Label("Accounts", systemImage: "chevron.left")
                }
                .buttonStyle(.borderless)
                if destination == .api {
                    OpenAIMonitorView(monitor: model.apiMonitor, preview: model.previewModeEnabled)
                } else {
                    Text("Approve sign-in in your browser, then return here.").font(.callout)
                        .foregroundStyle(.secondary)

                    SettingsListGroup(title: "ChatGPT subscription") {
                        HStack(spacing: 14) {
                            SettingsRowIcon(
                                systemImage: "person.crop.circle", size: 40, imageSize: 18)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(
                                    model.isSignedIn
                                        ? model.accountHeadline
                                        : model.isSigningIn ? "Connecting…" : "Not connected"
                                )
                                .font(.system(size: 13, weight: .semibold))
                                .lineLimit(1)

                                Text(
                                    model.isSignedIn
                                        ? (model.accountDetail ?? "Subscription")
                                        : "Subscription limits and resets"
                                )
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

                        if (model.isSignedIn && !model.previewModeEnabled) || model.isSigningOut {
                            SettingsListRow(title: "Sign out", isLast: true) {
                                if model.isSigningOut {
                                    ProgressView()
                                        .controlSize(.small)
                                        .accessibilityLabel("Signing out")
                                } else if model.isSignedIn, model.previewModeEnabled == false {
                                    Button("Sign Out") { model.signOut() }
                                        .buttonStyle(.bordered)
                                        .tint(.red)
                                } else {
                                    Text(
                                        model.previewModeEnabled
                                            ? "Sample data active" : "Not signed in"
                                    )
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }

                    if let error = model.lastError {
                        Text(error).font(.callout).foregroundStyle(.secondary)
                    }
                }
            } else {
                SettingsListGroup(title: "Connections") {
                    connectionRow(
                        "ChatGPT subscription",
                        detail: model.previewModeEnabled
                            ? "Preview"
                            : model.isSignedIn ? model.accountHeadline : "Not connected",
                        destination: .subscription)
                    Divider()
                    connectionRow(
                        "OpenAI API",
                        detail: model.apiMonitor.isValidated ? "Connected" : "Not connected",
                        destination: .api)
                }
                SettingsListGroup(title: "Preview") {
                    SettingsListRow(
                        title: "Sample data", detail: "Explore the app without a connection.",
                        isLast: true
                    ) {
                        CodexSwitch(
                            isOn: Binding(
                                get: { model.previewModeEnabled },
                                set: { value in
                                    if value {
                                        model.enablePreviewMode()
                                    } else {
                                        model.disablePreviewMode()
                                    }
                                }), accessibilityLabel: "Sample data"
                        )
                        .disabled(model.isAuthBusy)
                    }
                }
            }
        }
        .id(accountDestination)
        .transition(.opacity)
    }

    private func connectionRow(
        _ title: String, detail: String, destination: SettingsAccountDestination
    ) -> some View {
        Button {
            accountDestination = destination
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.body.weight(.medium)).foregroundStyle(.primary)
                    Text(detail).font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.secondary)
            }
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var generalSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsListGroup(title: "Startup") {
                SettingsListRow(
                    title: "Launch at login",
                    detail: model.launchAtLoginStatusMessage
                        ?? "Open Codexex when your Mac starts.",
                    isLast: true
                ) {
                    CodexSwitch(
                        isOn: Binding(
                            get: { model.launchAtLoginEnabled },
                            set: { model.setLaunchAtLoginEnabled($0) }
                        ), accessibilityLabel: "Launch at login")
                }
            }

            SettingsListGroup(
                title: "Refresh",
                footer: nil
            ) {
                SettingsListRow(title: "Auto-refresh") {
                    CodexSwitch(
                        isOn: Binding(
                            get: { model.autoRefreshEnabled },
                            set: { model.setAutoRefreshEnabled($0) }
                        ), accessibilityLabel: "Auto-refresh")
                }

                SettingsListRow(title: "Interval") {
                    CodexSegmentedControl(
                        selection: Binding(
                            get: { model.refreshIntervalSeconds },
                            set: { model.setRefreshIntervalSeconds($0) }
                        ),
                        segments: [
                            ("5m", 300),
                            ("10m", 600),
                            ("60m", 3600),
                        ], accessibilityLabel: "Refresh interval"
                    )
                    .frame(width: 146, height: SettingsControlMetrics.controlHeight)
                    .disabled(model.autoRefreshEnabled == false)
                }

                SettingsListRow(
                    title: "Refresh now", detail: "Pull the latest quota data.", isLast: true
                ) {
                    Button {
                        Task { await model.refreshNow(manual: true) }
                    } label: {
                        Label(
                            model.isRefreshing ? "Refreshing" : "Refresh",
                            systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .disabled(model.isRefreshing)
                }
            }

            notificationsSection
        }
    }

    private var themeSection: some View {
        SettingsListGroup(
            title: "Theme",
            footer: nil
        ) {
            SettingsListRow(title: "Appearance", isLast: true) {
                CodexSegmentedControl(
                    selection: Binding(
                        get: { model.appearanceMode },
                        set: { model.setAppearanceMode($0) }
                    ),
                    segments: [
                        ("System", .system),
                        ("Light", .light),
                        ("Dark", .dark),
                    ], accessibilityLabel: "Appearance"
                )
                .frame(width: 198, height: SettingsControlMetrics.controlHeight)
            }
        }
    }

    private var menuBarSection: some View {
        SettingsListGroup(
            title: "Quota presentation",
            footer: nil
        ) {
            SettingsListRow(
                title: "Mode", detail: "Menu bar usage, remaining quota, or weekly pace."
            ) {
                CodexSegmentedControl(
                    selection: Binding(
                        get: { model.menuBarDisplayMode },
                        set: { model.setMenuBarDisplayMode($0) }
                    ),
                    segments: [
                        ("Used", .used),
                        ("Left", .remaining),
                        ("Pace", .pace),
                    ], accessibilityLabel: "Menu bar display"
                )
                .frame(width: 174, height: SettingsControlMetrics.controlHeight)
            }

            SettingsListRow(title: "Weekly window", isLast: true) {
                CodexSwitch(
                    isOn: Binding(
                        get: { model.showWeeklyInMenubar },
                        set: { model.setShowWeeklyInMenubar($0) }
                    ),
                    accessibilityLabel: "Show weekly window"
                )
            }

        }
    }

    private var notificationsSection: some View {
        SettingsListGroup(
            title: "Quota notifications",
            footer: nil
        ) {
            SettingsListRow(
                title: "Quota notifications",
                detail: model.quotaNotificationStatusMessage
                    ?? "Opt-in alerts for 5-hour pressure, reset, and weekly risk.",
                isLast: true
            ) {
                CodexSwitch(
                    isOn: Binding(
                        get: { model.quotaNotificationsEnabled },
                        set: { model.setQuotaNotificationsEnabled($0) }
                    ), accessibilityLabel: "Quota notifications")
            }
        }
    }

    private var dataSection: some View {
        VStack(alignment: .leading, spacing: 26) {
            SettingsListGroup(title: "Local activity") {
                SettingsListRow(
                    title: "Sessions folder", detail: model.localUsageSettingsDetail, isLast: true
                ) {
                    Button("Choose…") { model.chooseCodexSessionsFolder() }.buttonStyle(.bordered)
                }
            }
            SettingsListGroup(
                title: "Diagnostics",
                footer: "Copies a redacted support report."
            ) {
                SettingsListRow(
                    title: "Copy diagnostics",
                    detail: model.diagnosticsStatusMessage
                        ?? "Useful when reporting quota or refresh issues.",
                    isLast: true
                ) {
                    Button("Copy") { model.copyDiagnosticsReport() }
                        .buttonStyle(.bordered)
                }
            }

            SettingsListGroup(
                title: "Reset",
                footer: "Remove all local data and return to first launch."
            ) {
                SettingsListRow(
                    title: "Reset app", detail: "Return Codexex to first launch.", isLast: true
                ) {
                    Button(isResetting ? "Resetting…" : "Reset") {
                        isShowingResetConfirmation = true
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                    .disabled(isResetting)
                }
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
                    Button {
                        NSWorkspace.shared.open(CodexAppLinks.termsURL)
                    } label: {
                        Label("Open", systemImage: "chevron.right")
                            .labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(.bordered)
                }

                SettingsListRow(title: "Privacy Policy", isLast: true) {
                    Button {
                        NSWorkspace.shared.open(CodexAppLinks.privacyURL)
                    } label: {
                        Label("Open", systemImage: "chevron.right")
                            .labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(.bordered)
                }
            }

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
                .buttonStyle(.borderedProminent)
                .tint(CodexTheme.prominentTint)
        } else if model.authDeviceCode != nil {
            Button(model.isCancellingPendingSignIn ? "Clearing…" : "Clear Code") {
                model.clearAuthCode()
            }
            .buttonStyle(.bordered)
            .disabled(model.isCancellingPendingSignIn)
        } else {
            Button("Sign In") { model.startChatGPTSignIn() }
                .buttonStyle(.borderedProminent)
                .tint(CodexTheme.prominentTint)
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
                .font(.headline)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)

            VStack(spacing: 0) {
                content
            }
            .overlay(alignment: .top) { Divider() }

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
                        .fixedSize(horizontal: false, vertical: true)
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
    var size: CGFloat = 20
    var imageSize: CGFloat = 14
    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: imageSize))
            .foregroundStyle(.secondary)
            .frame(width: size, height: size)
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
            .clipShape(
                RoundedRectangle(
                    cornerRadius: SettingsControlMetrics.iconRadius(for: size), style: .continuous)
            )
            .accessibilityHidden(true)
    }

    private var appIconImage: NSImage {
        if let namedImage = NSImage(named: "AppIcon"), namedImage.isValid {
            return prepared(namedImage)
        }

        if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
            let image = NSImage(contentsOf: iconURL)
        {
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
                .background(
                    SettingsTheme.secondaryFill,
                    in: RoundedRectangle(cornerRadius: 4, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .strokeBorder(SettingsTheme.hairline, lineWidth: 1)
                }

            HStack(spacing: 8) {
                Button {
                    openSafari()
                } label: {
                    Label("Open", systemImage: "safari")
                }
                .buttonStyle(.borderedProminent)
                .tint(CodexTheme.prominentTint)
                .keyboardShortcut(.defaultAction)
                .disabled(isCancelling)

                Button {
                    copyCode()
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)
                .disabled(isCancelling)

                Spacer(minLength: 0)

                Button {
                    cancel()
                } label: {
                    Label(isCancelling ? "Cancelling…" : "Cancel", systemImage: "xmark")
                }
                .buttonStyle(.bordered)
                .disabled(isCancelling)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct CodexSwitch: View {
    @Binding var isOn: Bool
    let accessibilityLabel: String
    var body: some View {
        Toggle(accessibilityLabel, isOn: $isOn).toggleStyle(.switch).labelsHidden().controlSize(
            .small
        )
        .accessibilityLabel(accessibilityLabel)
    }
}

private struct CodexSegmentedControl<Value: Hashable>: View {
    @Binding var selection: Value
    let segments: [(String, Value)]
    var accessibilityLabel = "Options"
    var body: some View {
        Picker(accessibilityLabel, selection: $selection) {
            ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                Text(segment.0).tag(segment.1)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .controlSize(.small)
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
                configuration.isPressed
                    ? SettingsTheme.pressedControlFill : SettingsTheme.controlFill,
                in: RoundedRectangle(
                    cornerRadius: SettingsControlMetrics.cornerRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: SettingsControlMetrics.cornerRadius, style: .continuous
                )
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
                CodexTheme.prominentTint.opacity(configuration.isPressed ? 0.88 : 1),
                in: RoundedRectangle(
                    cornerRadius: SettingsControlMetrics.cornerRadius, style: .continuous)
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
                configuration.isPressed
                    ? SettingsTheme.destructivePressedFill : SettingsTheme.destructiveFill,
                in: RoundedRectangle(
                    cornerRadius: SettingsControlMetrics.cornerRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: SettingsControlMetrics.cornerRadius, style: .continuous
                )
                .strokeBorder(SettingsTheme.destructiveBorder, lineWidth: 1)
            }
    }
}
#endif
