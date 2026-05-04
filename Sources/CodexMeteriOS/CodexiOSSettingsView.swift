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

    static let all = [
        autoCheckSignInOnReturn,
        refreshWhenActive,
        showSpark,
        showHistory,
        resetDisplayStyle,
        refreshIntervalSeconds,
        hasCompletedOnboarding,
        previewModeEnabled
    ]
}

enum CodexiOSResetDisplayStyle: String, CaseIterable, Identifiable {
    case countdown
    case clock

    var id: String { rawValue }

    var title: String {
        switch self {
        case .countdown:
            return "Countdown"
        case .clock:
            return "Clock"
        }
    }
}

struct CodexiOSSettingsView: View {
    @AppStorage(CodexiOSSettingsKeys.autoCheckSignInOnReturn) private var autoCheckSignInOnReturn = true
    @AppStorage(CodexiOSSettingsKeys.refreshWhenActive) private var refreshWhenActive = true
    @AppStorage(CodexiOSSettingsKeys.showSpark) private var showSpark = true
    @AppStorage(CodexiOSSettingsKeys.showHistory) private var showHistory = true
    @AppStorage(CodexiOSSettingsKeys.resetDisplayStyle) private var resetDisplayStyle = CodexiOSResetDisplayStyle.countdown.rawValue
    @AppStorage(CodexiOSSettingsKeys.refreshIntervalSeconds) private var refreshIntervalSeconds = 300
    @Bindable var model: CodexiOSModel
    @State private var isShowingResetConfirmation = false

    var body: some View {
        Form {
            accountSection
            displaySection
            refreshSection
            privacySection
            resetSection
        }
        .scrollContentBackground(.hidden)
        .background(CodexiOSTheme.background.ignoresSafeArea())
        .tint(CodexiOSTheme.secondary)
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
        .confirmationDialog(
            "Reset Codexex?",
            isPresented: $isShowingResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("Reset App", role: .destructive) {
                CodexiOSAppResetter.resetAndClose()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This deletes sign-in, settings, preview state, and local data. Codexex will close after reset.")
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
            } else {
                LabeledContent("Status") {
                    Text("Signed out")
                        .foregroundStyle(.secondary)
                }
            }

            Toggle("Preview mode", isOn: previewModeBinding)

            if model.previewModeEnabled == false {
                if model.hasPendingSignIn {
                    Button("Open Safari") {
                        model.openSignInPage()
                    }
                    Button("Check Now") {
                        Task { await model.checkSignIn() }
                    }
                    .disabled(model.isSigningIn)
                } else if model.isSignedIn {
                    Button("Refresh Now") {
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
            }
        } header: {
            Text("Account")
        } footer: {
            Text(accountFooter)
        }
    }

    private var displaySection: some View {
        Section {
            Toggle("Show Codex Spark", isOn: $showSpark)
            Toggle("Show Usage History", isOn: $showHistory)

            Picker("Reset Times", selection: $resetDisplayStyle) {
                ForEach(CodexiOSResetDisplayStyle.allCases) { style in
                    Text(style.title).tag(style.rawValue)
                }
            }
        } header: {
            Text("Display")
        } footer: {
            Text("Keep the home screen focused. These only change what is visible.")
        }
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
            LabeledContent("Data Flow") {
                Text("On device")
                    .foregroundStyle(.secondary)
            }
            LabeledContent("Cookies") {
                Text("Not used")
                    .foregroundStyle(.secondary)
            }
            LabeledContent("Storage") {
                Text("Keychain")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Privacy")
        } footer: {
            Text("No server, no Mac bridge, and no browser cookie scraping.")
        }
    }

    private var resetSection: some View {
        Section {
            Button("Reset App", role: .destructive) {
                isShowingResetConfirmation = true
            }
        } footer: {
            Text("Deletes sign-in, settings, preview state, and local data. The app closes when done.")
        }
    }

    private var accountFooter: String {
        if model.previewModeEnabled {
            return "Preview mode uses sample quota data and pauses live reads."
        }
        if model.hasPendingSignIn {
            return "Safari approval is waiting. Come back here and Codexex can check again."
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
