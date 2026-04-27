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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                accountCard
                previewCard
                displayCard
                refreshCard
                privacyCard
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 20)
            .frame(maxWidth: 760, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CodexiOSTheme.background.ignoresSafeArea())
        .navigationTitle("Settings")
        .preferredColorScheme(.dark)
    }

    private var previewCard: some View {
        settingsCard {
            VStack(alignment: .leading, spacing: 14) {
                cardHeader("Preview", systemImage: "sparkles")

                Text(model.previewModeEnabled ? "Sample quota is active." : "Use local sample data to test the UI without signing in.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button(model.previewModeEnabled ? "Leave Preview Mode" : "Use Preview Mode") {
                    if model.previewModeEnabled {
                        model.disablePreviewMode()
                    } else {
                        model.enablePreviewMode()
                    }
                }
                .buttonStyle(CodexiOSPreviewButtonStyle(isProminent: model.previewModeEnabled == false))
            }
        }
    }

    private var accountCard: some View {
        settingsCard {
            VStack(alignment: .leading, spacing: 14) {
                cardHeader("Account", systemImage: "person.crop.circle.badge.checkmark")

                Text(accountText)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                FlowLayout(spacing: 10) {
                    if model.previewModeEnabled {
                        Button("Leave Preview") { model.disablePreviewMode() }
                            .buttonStyle(.bordered)
                    } else if model.flowID != nil {
                        Button("Open Safari") { model.openSignInPage() }
                            .buttonStyle(.borderedProminent)
                        Button("Check Now") { model.checkSignIn() }
                            .buttonStyle(.bordered)
                            .disabled(model.isSigningIn)
                    } else if model.isSignedIn {
                        Button("Refresh Now") { Task { await model.refresh() } }
                            .buttonStyle(.borderedProminent)
                        Button("Sign Out") { model.signOut() }
                            .buttonStyle(.bordered)
                    } else {
                        Button("Sign In") { model.beginSignIn() }
                            .buttonStyle(.borderedProminent)
                            .disabled(model.isSigningIn)
                    }
                }
            }
        }
    }

    private var displayCard: some View {
        settingsCard {
            VStack(alignment: .leading, spacing: 0) {
                cardHeader("Display", systemImage: "slider.horizontal.3")
                    .padding(.bottom, 10)

                settingsRow(
                    title: "Codex Spark",
                    detail: "Show the Spark meter when it has useful usage."
                ) {
                    Toggle("", isOn: $showSpark)
                        .labelsHidden()
                }

                Divider().overlay(.white.opacity(0.08))

                settingsRow(
                    title: "Usage history",
                    detail: "Show the radar card under the account area."
                ) {
                    Toggle("", isOn: $showHistory)
                        .labelsHidden()
                }

                Divider().overlay(.white.opacity(0.08))

                settingsRow(
                    title: "Reset times",
                    detail: "Choose countdown or clock time."
                ) {
                    Picker("Reset times", selection: $resetDisplayStyle) {
                        ForEach(CodexiOSResetDisplayStyle.allCases) { style in
                            Text(style.title).tag(style.rawValue)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 230)
                }
            }
        }
    }

    private var refreshCard: some View {
        settingsCard {
            VStack(alignment: .leading, spacing: 0) {
                cardHeader("Refresh", systemImage: "arrow.clockwise")
                    .padding(.bottom, 10)

                settingsRow(
                    title: "After Safari login",
                    detail: "Check status as soon as you return to Codexex."
                ) {
                    Toggle("", isOn: $autoCheckSignInOnReturn)
                        .labelsHidden()
                }

                Divider().overlay(.white.opacity(0.08))

                settingsRow(
                    title: "When app opens",
                    detail: "Refresh quota when Codexex becomes active."
                ) {
                    Toggle("", isOn: $refreshWhenActive)
                        .labelsHidden()
                }

                Divider().overlay(.white.opacity(0.08))

                settingsRow(
                    title: "Update interval",
                    detail: "Same default as Mac: every 5 minutes."
                ) {
                    Picker("Update interval", selection: refreshIntervalBinding) {
                        Text("5 min").tag(300)
                        Text("10 min").tag(600)
                        Text("1 hour").tag(3600)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 250)
                    .disabled(refreshWhenActive == false)
                }
            }
        }
    }

    private var privacyCard: some View {
        settingsCard {
            VStack(alignment: .leading, spacing: 12) {
                cardHeader("Privacy", systemImage: "lock.shield.fill")

                Text("No server, no Mac bridge, no browser cookies. Tokens stay in Keychain and quota checks run from this device.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var accountText: String {
        if model.previewModeEnabled {
            return "Preview mode is active. Live quota is paused."
        }
        if model.flowID != nil {
            return "Safari approval is pending. Come back here and Codexex will check automatically."
        }
        if model.isSignedIn {
            return "Signed in. Quota reads stay local to this device."
        }
        return "Sign in with ChatGPT to read Codex quota on this device."
    }

    private var refreshIntervalBinding: Binding<Int> {
        Binding(
            get: { max(refreshIntervalSeconds, 300) },
            set: { refreshIntervalSeconds = max($0, 300) }
        )
    }

    private func cardHeader(_ title: String, systemImage: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.title3.weight(.bold))
                .foregroundStyle(.cyan)
            Text(title)
                .font(.title3.weight(.bold))
        }
    }

    private func settingsRow<Accessory: View>(
        title: String,
        detail: String,
        @ViewBuilder accessory: () -> Accessory
    ) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 16) {
                rowText(title: title, detail: detail)
                Spacer(minLength: 12)
                accessory()
            }

            VStack(alignment: .leading, spacing: 12) {
                rowText(title: title, detail: detail)
                accessory()
            }
        }
        .padding(.vertical, 14)
    }

    private func rowText(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.headline)
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func settingsCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(CodexiOSTheme.card, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .strokeBorder(.white.opacity(0.12), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.28), radius: 22, y: 12)
    }
}

private struct CodexiOSPreviewButtonStyle: ButtonStyle {
    let isProminent: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline.weight(.semibold))
            .foregroundStyle(isProminent ? .white : .primary)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(background(isPressed: configuration.isPressed), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(.white.opacity(isProminent ? 0 : 0.12), lineWidth: 1)
            }
    }

    private func background(isPressed: Bool) -> Color {
        if isProminent {
            return Color.cyan.opacity(isPressed ? 0.72 : 1)
        }
        return Color.white.opacity(isPressed ? 0.05 : 0.09)
    }
}
