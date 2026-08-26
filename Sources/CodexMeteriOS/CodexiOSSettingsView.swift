import SwiftUI

enum CodexiOSSettingsKeys {
    static let autoCheckSignInOnReturn = "ios.autoCheckSignInOnReturn"
    static let refreshWhenActive = "ios.refreshWhenActive"
    static let showSpark = "ios.showSpark"
    static let showHistory = "ios.showHistory"
    static let resetDisplayStyle = "ios.resetDisplayStyle"
    static let refreshIntervalSeconds = "ios.refreshIntervalSeconds"
    static let hasCompletedOnboarding = "ios.hasCompletedOnboarding"
    static let previewModeEnabled = "ios.previewModeEnabled"
    static let appearanceMode = "ios.appearanceMode"
    static let defaultHistoryMode = "ios.defaultHistoryMode"
    static let showPaceConfidence = "ios.showPaceConfidence"
    static let showFiveHourPresentation = "ios.showFiveHourPresentation"
    static let showUsedQuota = "ios.showUsedQuota"
    static let matrixThemeEnabled = "ios.matrixThemeEnabled"
    static let summarySnoozeFingerprint = "ios.summarySnoozeFingerprint"
    static let summarySnoozeExpiresAt = "ios.summarySnoozeExpiresAt"

    static let all = [
        autoCheckSignInOnReturn,
        refreshWhenActive,
        showSpark,
        showHistory,
        resetDisplayStyle,
        refreshIntervalSeconds,
        hasCompletedOnboarding,
        previewModeEnabled,
        appearanceMode,
        defaultHistoryMode,
        showPaceConfidence,
        showFiveHourPresentation,
        showUsedQuota,
        matrixThemeEnabled,
        summarySnoozeFingerprint,
        summarySnoozeExpiresAt
    ]
}

enum CodexiOSLegalLinks {
    static let privacyPolicy = URL(string: "https://codexex.eu/privacy/")!
    static let termsOfService = URL(string: "https://codexex.eu/terms/")!
}

enum CodexiOSResetDisplayStyle: String, CaseIterable, Identifiable {
    case relative
    case absolute

    var id: String { rawValue }

    var title: String {
        switch self {
        case .relative:
            return "Countdown"
        case .absolute:
            return "Clock"
        }
    }

}

enum CodexiOSAppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system:
            return "System"
        case .light:
            return "Light"
        case .dark:
            return "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system:
            return nil
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }
}

enum CodexiOSHistoryMode: String, CaseIterable, Identifiable {
    case dailyPeaks
    case monthly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dailyPeaks:
            return "Peaks"
        case .monthly:
            return "Month"
        }
    }

}

struct CodexiOSSettingsView: View {
    @AppStorage(CodexiOSSettingsKeys.autoCheckSignInOnReturn) private var autoCheckSignInOnReturn = true
    @AppStorage(CodexiOSSettingsKeys.refreshWhenActive) private var refreshWhenActive = true
    @AppStorage(CodexiOSSettingsKeys.showSpark) private var showSpark = true
    @AppStorage(CodexiOSSettingsKeys.showHistory) private var showHistory = true
    @AppStorage(CodexiOSSettingsKeys.resetDisplayStyle) private var resetDisplayStyle = CodexiOSResetDisplayStyle.relative.rawValue
    @AppStorage(CodexiOSSettingsKeys.appearanceMode) private var appearanceMode = CodexiOSAppearanceMode.system.rawValue
    @AppStorage(CodexiOSSettingsKeys.defaultHistoryMode) private var defaultHistoryMode = CodexiOSHistoryMode.dailyPeaks.rawValue
    @AppStorage(CodexiOSSettingsKeys.refreshIntervalSeconds) private var refreshIntervalSeconds = 300
    @AppStorage(CodexiOSSettingsKeys.showFiveHourPresentation) private var showFiveHourPresentation = false
    @AppStorage(CodexiOSSettingsKeys.showUsedQuota) private var showUsedQuota = false
    @AppStorage(CodexiOSSettingsKeys.matrixThemeEnabled) private var matrixThemeEnabled = false
    @Bindable var model: CodexiOSModel
    let onMatrixThemeEnabled: () -> Void
    @State private var isShowingResetConfirmation = false
    @State private var isShowingLiveActivityStartWarning = false

    init(model: CodexiOSModel, onMatrixThemeEnabled: @escaping () -> Void = {}) {
        self.model = model
        self.onMatrixThemeEnabled = onMatrixThemeEnabled
    }

    var body: some View {
        Form {
            accountSection
            quotaPresentationSection
            liveActivitySection
            displaySection
            refreshSection
            privacySection
            resetSection
        }
        .scrollContentBackground(.hidden)
        .background(CodexiOSTheme.background.ignoresSafeArea())
        .tint(Color.primary)
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(CodexiOSAppearanceMode(rawValue: appearanceMode)?.colorScheme)
        .onChange(of: showFiveHourPresentation) { _, enabled in
            Task {
                await model.updateLiveActivityPresentation(
                    showFiveHour: enabled,
                    showUsedQuota: showUsedQuota
                )
            }
        }
        .onChange(of: showUsedQuota) { _, enabled in
            Task {
                await model.updateLiveActivityPresentation(
                    showFiveHour: showFiveHourPresentation,
                    showUsedQuota: enabled
                )
            }
        }
        .onChange(of: matrixThemeEnabled) { _, enabled in
            if enabled {
                onMatrixThemeEnabled()
            }
        }
        .confirmationDialog(
            "Reset Codexex?",
            isPresented: $isShowingResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("Reset App", role: .destructive) {
                Task {
                    await model.resetApp()
                }
            }
            .disabled(model.isResetting)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This deletes sign-in, pending login, settings, preview state, and local usage history.")
        }
        .alert(
            "Keep Codexex running",
            isPresented: $isShowingLiveActivityStartWarning
        ) {
            Button("Not now", role: .cancel) {}
            Button("Start Live Activity") {
                Task { await model.startLiveActivity() }
            }
        } message: {
            Text("Codexex refreshes this on your phone when iOS allows it. Please do not manually close it from the app switcher.")
        }
    }

    private var accountSection: some View {
        Section {
            if model.previewModeEnabled {
                LabeledContent("Status") {
                    Text("Preview")
                        .foregroundStyle(.secondary)
                }
            } else if model.hasPendingSignIn {
                LabeledContent("Status") {
                    Text("Waiting")
                        .foregroundStyle(.secondary)
                }
            } else if model.isSignedIn {
                LabeledContent("Status") {
                    Text("Signed in")
                        .foregroundStyle(.secondary)
                }
            } else if model.liveAccountState == .authExpired {
                LabeledContent("Status") {
                    Text("Sign-in expired")
                        .foregroundStyle(.secondary)
                }
            } else if model.liveAccountState == .unavailable {
                LabeledContent("Status") {
                    Text("Unavailable")
                        .foregroundStyle(.secondary)
                }
            } else {
                LabeledContent("Status") {
                    Text("Signed out")
                        .foregroundStyle(.secondary)
                }
            }

            Toggle("Preview mode", isOn: previewModeBinding)

            if model.previewModeEnabled == false {
                if model.hasPendingSignIn {
                    if let code = model.deviceCode {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Device code")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(code)
                                .font(.system(.title2, design: .monospaced, weight: .bold))
                                .textSelection(.enabled)
                            Text(model.statusMessage)
                                .font(.caption)
                                .foregroundStyle(CodexiOSTheme.secondary)
                        }
                        .padding(.vertical, 6)
                    }
                    Button("Open Safari") {
                        Task { await model.openSignInPage() }
                    }
                    Button("Copy Code") {
                        model.copyCode()
                    }
                    Button("Check Now") {
                        Task { await model.checkSignIn() }
                    }
                    .disabled(model.isSigningIn)
                    Button("Start Over") {
                        Task { await model.restartSignIn() }
                    }
                    .disabled(model.isSigningIn)
                    Button("Cancel Sign-in", role: .destructive) {
                        Task { await model.cancelSignIn() }
                    }
                    .disabled(model.isSigningIn)
                } else if model.isSignedIn {
                    Button("Refresh Now") {
                        Task { await model.refresh() }
                    }
                    Button("Sign Out", role: .destructive) {
                        Task { await model.signOut() }
                    }
                } else if model.liveAccountState == .unavailable {
                    Button("Retry") {
                        Task { await model.refresh() }
                    }
                    Button("Sign Out", role: .destructive) {
                        Task { await model.signOut() }
                    }
                } else {
                    Button("Sign In") {
                        Task { await model.beginSignIn() }
                    }
                    .disabled(model.isSigningIn)
                }

                if let error = model.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } header: {
            Text("Account")
        } footer: {
            Text(accountFooter)
        }
    }

    private var displaySection: some View {
        Section {
            Toggle("Show Spark", isOn: $showSpark)
            Toggle("Show 5-hour window", isOn: $showFiveHourPresentation)
                .accessibilityIdentifier("ios.settings.showFiveHour")
            Toggle("Show Usage History", isOn: $showHistory)
            Toggle("Matrix theme", isOn: $matrixThemeEnabled)
                .accessibilityIdentifier("ios.settings.matrixTheme")

            Picker("Reset Times", selection: $resetDisplayStyle) {
                ForEach(CodexiOSResetDisplayStyle.allCases) { style in
                    Text(style.title).tag(style.rawValue)
                }
            }

            Picker("Appearance", selection: $appearanceMode) {
                ForEach(CodexiOSAppearanceMode.allCases) { mode in
                    Text(mode.title).tag(mode.rawValue)
                }
            }

            Picker("History", selection: $defaultHistoryMode) {
                ForEach(CodexiOSHistoryMode.allCases) { mode in
                    Text(mode.title).tag(mode.rawValue)
                }
            }
        } header: {
            Text("Display")
        } footer: {
            Text("Matrix theme opens the fullscreen Matrix view. 5-hour presentation controls rows, headlines, history, and Live Activity.")
        }
    }

    private var quotaPresentationSection: some View {
        Section {
            Toggle("Show used quota", isOn: $showUsedQuota)
                .accessibilityIdentifier("ios.settings.showUsedQuota")
        } header: {
            Text("Quota")
        } footer: {
            Text("Show usage instead of quota left.")
        }
    }

    @ViewBuilder
    private var liveActivitySection: some View {
        if model.isSignedIn || model.previewModeEnabled || model.isLiveActivityRunning {
            Section {
                Button {
                    if model.isLiveActivityRunning {
                        Task { await model.stopLiveActivity() }
                    } else {
                        isShowingLiveActivityStartWarning = true
                    }
                } label: {
                    Label(
                        model.isLiveActivityRunning ? "Stop Live Activity" : "Start Live Activity",
                        systemImage: model.isLiveActivityRunning ? "stop.circle" : "waveform"
                    )
                }
                .disabled(
                    model.isLiveActivityTransitioning
                        || (model.isLiveActivityRunning == false
                            && (model.hasCheckedLiveActivityAvailability == false || model.isLiveActivityAvailable == false))
                )
                .accessibilityIdentifier("ios.settings.liveActivity")
                .accessibilityValue(liveActivityAccessibilityValue)

                if model.hasCheckedLiveActivityAvailability, model.isLiveActivityAvailable == false {
                    Text("Live Activities are unavailable on this device.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Live Activity")
            } footer: {
                Text("Shows the selected quota display on the Lock Screen and Dynamic Island. Refresh timing is decided by iOS.")
            }
        }
    }

    private var liveActivityAccessibilityValue: String {
        if model.isLiveActivityTransitioning { return "Updating" }
        if model.isLiveActivityRunning { return "On" }
        return model.hasCheckedLiveActivityAvailability && model.isLiveActivityAvailable == false
            ? "Unavailable"
            : "Off"
    }

    private var refreshSection: some View {
        Section {
            Toggle("Check After Safari Login", isOn: $autoCheckSignInOnReturn)
            Toggle("Refresh When App Opens", isOn: $refreshWhenActive)

            Picker("Update Interval", selection: refreshIntervalBinding) {
                Text("Every 5 Minutes").tag(300)
                Text("Every 10 Minutes").tag(600)
                Text("Every Hour").tag(3600)
            }
            .disabled(refreshWhenActive == false)
        } header: {
            Text("Refresh")
        } footer: {
            Text("Default matches Mac: refresh every 5 minutes while the app is active.")
        }
    }

    private var privacySection: some View {
        Section {
            Link(destination: CodexiOSLegalLinks.privacyPolicy) {
                externalLinkRow(title: "Privacy Policy")
            }
            .accessibilityIdentifier("ios.settings.privacyPolicy")

            Link(destination: CodexiOSLegalLinks.termsOfService) {
                externalLinkRow(title: "Terms of Service")
            }
            .accessibilityIdentifier("ios.settings.termsOfService")
        } header: {
            Text("Privacy")
        }
    }

    private func externalLinkRow(title: LocalizedStringKey) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "globe")
                .foregroundStyle(.secondary)
                .frame(width: 20)
            Text(title)
                .foregroundStyle(.primary)
            Spacer()
            Image(systemName: "arrow.up.right")
                .font(.body.weight(.semibold))
                .foregroundStyle(.tertiary)
                .frame(width: 14, height: 14)
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }

    private var resetSection: some View {
        Section {
            Button("Reset App", role: .destructive) {
                isShowingResetConfirmation = true
            }
            .accessibilityIdentifier("ios.settings.reset")
        } footer: {
            Text("Deletes sign-in, pending login, settings, preview state, and local usage history. Codexex stays open.")
        }
    }

    private var accountFooter: String {
        if model.previewModeEnabled {
            return "Preview mode uses sample quota data and pauses live reads."
        }
        if model.hasPendingSignIn {
            return model.statusMessage
        }
        if model.isSignedIn {
            return "Quota reads stay local to this device."
        }
        return "Sign in with ChatGPT to read Codex quota on this device."
    }

    private var refreshIntervalBinding: Binding<Int> {
        Binding(
            get: { max(refreshIntervalSeconds, 300) },
            set: { refreshIntervalSeconds = max($0, 300) }
        )
    }

    private var previewModeBinding: Binding<Bool> {
        Binding(
            get: { model.previewModeEnabled },
            set: { isEnabled in
                if isEnabled {
                    model.enablePreviewMode()
                } else {
                    model.disablePreviewMode()
                }
            }
        )
    }
}
