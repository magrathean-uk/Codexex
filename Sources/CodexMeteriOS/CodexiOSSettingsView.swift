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
            VStack(alignment: .leading, spacing: 18) {
                heroCard
                accessCard
                displayCard
                refreshCard
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 20)
            .frame(maxWidth: 760, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CodexiOSTheme.background.ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
    }

    private var heroCard: some View {
        settingsCard {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.07))
                            .frame(width: 48, height: 48)
                        Image(systemName: "gearshape.fill")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(.white)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Settings")
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                        Text("Keep quota updates local, calm, and useful.")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 12)
                    statusBadge
                }

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) {
                        summaryPill(title: "Mode", value: model.previewModeEnabled ? "Preview" : "Live")
                        summaryPill(title: "Refresh", value: refreshSummary)
                        summaryPill(title: "Privacy", value: "On device")
                    }

                    VStack(spacing: 12) {
                        summaryPill(title: "Mode", value: model.previewModeEnabled ? "Preview" : "Live")
                        summaryPill(title: "Refresh", value: refreshSummary)
                        summaryPill(title: "Privacy", value: "On device")
                    }
                }

                Text("No server in the middle. Tokens stay in Keychain and quota checks run only on this device.")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var accessCard: some View {
        settingsCard {
            VStack(alignment: .leading, spacing: 14) {
                sectionHeader(
                    eyebrow: "Access",
                    title: "Sign-in and preview",
                    detail: accountText
                )

                insetPanel {
                    VStack(alignment: .leading, spacing: 0) {
                        settingsRow(
                            title: "Preview mode",
                            detail: model.previewModeEnabled ? "Sample quota is active for testing." : "Use sample quota data without signing in."
                        ) {
                            Toggle("", isOn: previewModeBinding)
                                .labelsHidden()
                        }

                        subtleDivider

                        settingsRow(
                            title: "Return from Safari",
                            detail: "Check login state when you come back."
                        ) {
                            Toggle("", isOn: $autoCheckSignInOnReturn)
                                .labelsHidden()
                        }
                    }
                }

                actionStrip
            }
        }
    }

    private var displayCard: some View {
        settingsCard {
            VStack(alignment: .leading, spacing: 14) {
                sectionHeader(
                    eyebrow: "Display",
                    title: "What people see",
                    detail: "Keep the main screen focused and readable."
                )

                insetPanel {
                    VStack(alignment: .leading, spacing: 0) {
                        settingsRow(
                            title: "Codex Spark",
                            detail: "Show Spark only when it has meaningful usage."
                        ) {
                            Toggle("", isOn: $showSpark)
                                .labelsHidden()
                        }

                        subtleDivider

                        settingsRow(
                            title: "Usage history",
                            detail: "Show the radar card under the quota cards."
                        ) {
                            Toggle("", isOn: $showHistory)
                                .labelsHidden()
                        }

                        subtleDivider

                        settingsRow(
                            title: "Reset time style",
                            detail: "Pick countdown or wall clock time."
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
        }
    }

    private var refreshCard: some View {
        settingsCard {
            VStack(alignment: .leading, spacing: 14) {
                sectionHeader(
                    eyebrow: "Refresh",
                    title: "Update rhythm",
                    detail: "Same default as Mac: refresh every 5 minutes while active."
                )

                insetPanel {
                    VStack(alignment: .leading, spacing: 0) {
                        settingsRow(
                            title: "When app opens",
                            detail: "Refresh quota when Codexex becomes active."
                        ) {
                            Toggle("", isOn: $refreshWhenActive)
                                .labelsHidden()
                        }

                        subtleDivider

                        settingsRow(
                            title: "Update interval",
                            detail: "Choose how often live quota refreshes."
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

                Text("Private by default. No browser cookies, no Mac bridge, no background relay.")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var actionStrip: some View {
        FlowLayout(spacing: 10) {
            if model.previewModeEnabled {
                actionButton("Leave Preview", prominence: .secondary) {
                    model.disablePreviewMode()
                }
            } else if model.flowID != nil {
                actionButton("Open Safari", prominence: .primary) {
                    model.openSignInPage()
                }
                actionButton("Check Now", prominence: .secondary) {
                    model.checkSignIn()
                }
                .disabled(model.isSigningIn)
            } else if model.isSignedIn {
                actionButton("Refresh Now", prominence: .primary) {
                    Task { await model.refresh() }
                }
                actionButton("Sign Out", prominence: .secondary) {
                    model.signOut()
                }
            } else {
                actionButton("Sign In", prominence: .primary) {
                    model.beginSignIn()
                }
                .disabled(model.isSigningIn)
            }
        }
    }

    private var statusBadge: some View {
        Text(model.previewModeEnabled ? "Preview" : "Local")
            .font(.caption.weight(.bold))
            .foregroundStyle(model.previewModeEnabled ? .black : .white)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                model.previewModeEnabled ? Color(red: 0.98, green: 0.74, blue: 0.22) : Color.white.opacity(0.10),
                in: Capsule()
            )
            .overlay {
                Capsule()
                    .strokeBorder(.white.opacity(model.previewModeEnabled ? 0 : 0.12), lineWidth: 1)
            }
    }

    private var refreshSummary: String {
        guard refreshWhenActive else { return "Manual" }
        let minutes = max(refreshIntervalSeconds, 300) / 60
        return "\(minutes)m"
    }

    private func summaryPill(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.caption.weight(.bold))
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.headline.monospacedDigit())
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CodexiOSTheme.inset, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func sectionHeader(eyebrow: String, title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(eyebrow.uppercased())
                .font(.caption.weight(.bold))
                .foregroundStyle(.tertiary)
            Text(title)
                .font(.title3.weight(.bold))
            Text(detail)
                .font(.body.weight(.semibold))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var accountText: String {
        if model.previewModeEnabled {
            return "Preview mode is on. Live quota reads stay paused until you leave it."
        }
        if model.flowID != nil {
            return "Safari approval is waiting. Come back here and Codexex can check again."
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

    private func actionButton(_ title: String, prominence: CodexActionProminence, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(.headline)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(prominence.background, in: Capsule())
            .foregroundStyle(prominence.foreground)
            .overlay {
                Capsule()
                    .strokeBorder(prominence.border, lineWidth: prominence.borderWidth)
            }
            .buttonStyle(.plain)
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

    private func insetPanel<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(.horizontal, 14)
            .background(CodexiOSTheme.inset, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(.white.opacity(0.08), lineWidth: 1)
            }
    }

    private var subtleDivider: some View {
        Divider()
            .overlay(.white.opacity(0.08))
    }
}

private enum CodexActionProminence {
    case primary
    case secondary

    var background: Color {
        switch self {
        case .primary:
            return Color.white.opacity(0.12)
        case .secondary:
            return Color.white.opacity(0.06)
        }
    }

    var foreground: Color {
        switch self {
        case .primary:
            return .white
        case .secondary:
            return Color.white.opacity(0.86)
        }
    }

    var border: Color {
        .white
    }

    var borderWidth: CGFloat {
        switch self {
        case .primary:
            return 0
        case .secondary:
            return 1
        }
    }
}
