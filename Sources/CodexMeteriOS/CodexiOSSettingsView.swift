import SwiftUI

enum CodexiOSSettingsKeys {
    static let autoCheckSignInOnReturn = "ios.autoCheckSignInOnReturn"
    static let refreshWhenActive = "ios.refreshWhenActive"
    static let showHistory = "ios.showHistory"
    static let resetDisplayStyle = "ios.resetDisplayStyle"
    static let refreshIntervalSeconds = "ios.refreshIntervalSeconds"
    static let hasCompletedOnboarding = "ios.hasCompletedOnboarding"
    static let previewModeEnabled = "ios.previewModeEnabled"
    static let appearanceMode = "ios.appearanceMode"
    static let defaultHistoryMode = "ios.defaultHistoryMode"
    static let showPaceConfidence = "ios.showPaceConfidence"
    static let showUsedQuota = "ios.showUsedQuota"
    static let matrixThemeEnabled = "ios.matrixThemeEnabled"
    static let summarySnoozeFingerprint = "ios.summarySnoozeFingerprint"
    static let summarySnoozeExpiresAt = "ios.summarySnoozeExpiresAt"

    static let all = [
        autoCheckSignInOnReturn,
        refreshWhenActive,
        showHistory,
        resetDisplayStyle,
        refreshIntervalSeconds,
        hasCompletedOnboarding,
        previewModeEnabled,
        appearanceMode,
        defaultHistoryMode,
        showPaceConfidence,
        showUsedQuota,
        matrixThemeEnabled,
        summarySnoozeFingerprint,
        summarySnoozeExpiresAt
    ]
}

enum CodexiOSLegalLinks {
    static let privacyPolicy = URL(string: "https://magrathean.uk/solutions/codexex/privacy/")!
    static let termsOfService = URL(string: "https://magrathean.uk/solutions/codexex/terms/")!
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AppStorage(CodexiOSSettingsKeys.appearanceMode) private var appearanceMode = CodexiOSAppearanceMode.system.rawValue
    @AppStorage(CodexiOSSettingsKeys.showUsedQuota) private var showUsedQuota = false
    @AppStorage(CodexiOSSettingsKeys.showHistory) private var showHistory = true
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
            Section("Accounts") {
                NavigationLink {
                    CodexiOSSubscriptionConnectionView(model: model)
                } label: {
                    connectionRow("ChatGPT", symbol: "person.crop.circle", status: CodexiOSSubscriptionConnectionView.status(for: model))
                }
                .accessibilityIdentifier("ios.settings.subscription")
                NavigationLink {
                    CodexiOSAPIConnectionView(monitor: model.apiMonitor, preview: model.previewModeEnabled)
                } label: {
                    connectionRow("OpenAI API", symbol: "key", status: apiConnectionStatus)
                }
                .accessibilityIdentifier("ios.settings.api")
            }
            Section("Appearance") {
                Picker("Appearance", selection: $appearanceMode) {
                    ForEach(CodexiOSAppearanceMode.allCases) { Text($0.title).tag($0.rawValue) }
                }
                Toggle("Show used quota", isOn: $showUsedQuota)
                    .accessibilityIdentifier("ios.settings.showUsedQuota")
                Toggle("Matrix theme", isOn: $matrixThemeEnabled)
                    .accessibilityIdentifier("ios.settings.matrixTheme")
            }
            if model.isSignedIn || model.previewModeEnabled || model.isLiveActivityRunning {
                Section {
                    Button {
                        if model.isLiveActivityRunning { Task { await model.stopLiveActivity() } }
                        else { isShowingLiveActivityStartWarning = true }
                    } label: {
                        LabeledContent(model.isLiveActivityRunning ? "Stop Live Activity" : "Start Live Activity",
                                       value: model.isLiveActivityTransitioning ? "Updating" : model.isLiveActivityRunning ? "On" : "Off")
                    }
                    .disabled(model.isLiveActivityTransitioning || (!model.isLiveActivityRunning && (!model.hasCheckedLiveActivityAvailability || !model.isLiveActivityAvailable)))
                    .accessibilityIdentifier("ios.settings.liveActivity")
                    if !model.previewModeEnabled {
                        NavigationLink("Background updates") { CodexiOSBackgroundUpdateSettingsView(model: model) }
                    }
                } header: { Text("Live Activity") } footer: {
                    Text(liveActivityFooter)
                }
            }
            Section {
                Toggle("Preview mode", isOn: previewModeBinding)
                Toggle("Show history", isOn: $showHistory)
                NavigationLink("Refresh") { CodexiOSRefreshSettingsView() }
                Button("Reset App", role: .destructive) { isShowingResetConfirmation = true }
                    .disabled(model.isResetting)
                    .accessibilityIdentifier("ios.settings.reset")
            } header: { Text("Data") } footer: { Text("History and settings stay on this device.") }
            Section("About") {
                LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—")
                Link("Privacy Policy", destination: CodexiOSLegalLinks.privacyPolicy)
                    .accessibilityIdentifier("ios.settings.privacyPolicy")
                Link("Terms of Service", destination: CodexiOSLegalLinks.termsOfService)
                    .accessibilityIdentifier("ios.settings.termsOfService")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .tint(CodexiOSTheme.actionTint)
        .preferredColorScheme(CodexiOSAppearanceMode(rawValue: appearanceMode)?.colorScheme)
        .onChange(of: showUsedQuota) { _, enabled in
            Task { await model.updateLiveActivityPresentation(showFiveHour: model.snapshot?.showsFiveHourLimit ?? false, showUsedQuota: enabled) }
        }
        .onChange(of: matrixThemeEnabled) { _, enabled in if enabled { onMatrixThemeEnabled() } }
        .confirmationDialog("Reset Codexex?", isPresented: $isShowingResetConfirmation, titleVisibility: .visible) {
            Button("Reset App", role: .destructive) { Task { await model.resetApp() } }
                .disabled(model.isResetting)
            Button("Cancel", role: .cancel) {}
        } message: { Text("Deletes sign-in, settings, and local history.") }
        .alert("Keep Codexex running", isPresented: $isShowingLiveActivityStartWarning) {
            Button("Not now", role: .cancel) {}
            Button("Start Live Activity") { Task { await model.startLiveActivity() } }
        } message: { Text("Codexex refreshes this on your phone when iOS allows it. Please do not manually close it from the app switcher.") }
    }

    private func connectionRow(_ title: String, symbol: String, status: String) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(spacing: 12))
        return layout {
            Label(title, systemImage: symbol)
                .fixedSize(horizontal: false, vertical: true)
            if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 8) }
            Text(status).foregroundStyle(.secondary).font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
    }

    private var liveActivityFooter: String {
        if !model.isLiveActivityRunning && !model.hasCheckedLiveActivityAvailability {
            return "Checking Live Activity availability."
        }
        if !model.isLiveActivityRunning && !model.isLiveActivityAvailable {
            return "Live Activities are unavailable. Check iOS Settings."
        }
        return "Quota on the Lock Screen and Dynamic Island. iOS controls refresh timing."
    }

    private var previewModeBinding: Binding<Bool> {
        Binding(get: { model.previewModeEnabled }, set: { $0 ? model.enablePreviewMode() : model.disablePreviewMode() })
    }

    private var apiConnectionStatus: String {
        if model.previewModeEnabled { return "Preview" }
        if model.apiMonitor.isRefreshing { return "Checking" }
        if model.apiMonitor.isValidated { return "Connected" }
        return model.apiMonitor.hasKey ? "Saved" : "Not connected"
    }
}

private struct CodexiOSRefreshSettingsView: View {
    @AppStorage(CodexiOSSettingsKeys.autoCheckSignInOnReturn) private var autoCheck = true
    @AppStorage(CodexiOSSettingsKeys.refreshWhenActive) private var refreshWhenActive = true
    @AppStorage(CodexiOSSettingsKeys.refreshIntervalSeconds) private var interval = 300
    var body: some View {
        Form {
            Section { Toggle("Check after Safari login", isOn: $autoCheck) }
            Section {
                Toggle("Refresh when app opens", isOn: $refreshWhenActive)
                Picker("Update interval", selection: Binding(get: { max(interval, 300) }, set: { interval = max($0, 300) })) {
                    Text("5 minutes").tag(300)
                    Text("10 minutes").tag(600)
                    Text("1 hour").tag(3600)
                }.disabled(!refreshWhenActive)
            } footer: { Text("Applies while the app is open.") }
        }
        .navigationTitle("Refresh").navigationBarTitleDisplayMode(.inline)
    }
}

private struct CodexiOSBackgroundUpdateSettingsView: View {
    @Bindable var model: CodexiOSModel
    var body: some View {
        Form {
            Section {
                LabeledContent("Registration", value: codexiOSSharedPushRegistrationManager.registrationState.title)
                LabeledContent("Last update", value: codexiOSSharedPushRegistrationManager.lastWake?.summary ?? "Not received")
            }
            if model.isLiveActivityRunning {
                Section {
                    Button("Test background update") { Task { await codexiOSSharedPushRegistrationManager.requestTestWake() } }
                        .disabled(codexiOSSharedPushRegistrationManager.registrationState != .registered || codexiOSSharedPushRegistrationManager.isRequestingTestWake || codexiOSSharedPushRegistrationManager.isTestWakeCoolingDown)
                        .accessibilityIdentifier("ios.settings.testBackgroundUpdate")
                    if let status = codexiOSSharedPushRegistrationManager.testWakeStatus { Text(status).font(.footnote).foregroundStyle(.secondary) }
                }
            }
        }
        .navigationTitle("Background updates").navigationBarTitleDisplayMode(.inline)
    }
}
