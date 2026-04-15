#if os(macOS)
import AppKit
import Foundation
import SwiftUI
import Observation

struct SettingsRootView: View {
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @Bindable var model: CodexMenuBarModel

    var body: some View {
        GlassEffectContainer(spacing: GlassTokens.sectionSpacing) {
            ScrollView {
                ViewThatFits(in: .horizontal) {
                    wideLayout
                    stackedLayout
                }
                .padding(GlassTokens.pagePadding)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .scrollIndicators(.hidden)
        }
        .onAppear {
            model.setReduceMotionEnabled(accessibilityReduceMotion)
        }
        .onChange(of: accessibilityReduceMotion) { _, newValue in
            model.setReduceMotionEnabled(newValue)
        }
    }

    private var wideLayout: some View {
        HStack(alignment: .top, spacing: GlassTokens.sectionSpacing) {
            VStack(alignment: .leading, spacing: GlassTokens.sectionSpacing) {
                accountCard
                behaviorCard
            }
            .frame(maxWidth: 372, alignment: .topLeading)

            VStack(alignment: .leading, spacing: GlassTokens.sectionSpacing) {
                displayCard
                SettingsAboutCard()
            }
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private var stackedLayout: some View {
        VStack(alignment: .leading, spacing: GlassTokens.sectionSpacing) {
            accountCard
            behaviorCard
            displayCard
            SettingsAboutCard()
        }
    }

    private var accountCard: some View {
        GlassCard(style: .primary) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Account")
                            .font(.headline)

                        Text(accountHeadline)
                            .font(.title3.weight(.semibold))

                if let detail = accountDetail {
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

                    Spacer(minLength: 0)

                    accountAction
                }

                HStack(spacing: 12) {
                    Button(model.previewModeEnabled ? "Leave Preview" : "Use Sample Data") {
                        if model.previewModeEnabled {
                            model.disablePreviewMode()
                        } else {
                            model.enablePreviewMode()
                        }
                    }
                    .buttonStyle(.bordered)

                    Text(model.previewModeEnabled ? "Sample data is active." : "App Review can use sample data here.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if let code = model.authDeviceCode {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Device code")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        Text(code)
                            .textSelection(.enabled)
                            .font(.system(.title3, design: .monospaced, weight: .semibold))

                        HStack(spacing: 10) {
                            Button("Open Safari") {
                                model.openAuthVerificationPage()
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(model.authVerificationURL == nil)

                            Button("Copy Code") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(code, forType: .string)
                            }
                            .buttonStyle(.bordered)
                        }
                        .padding(.top, 4)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassEffect(
                        GlassSurfaceStyle.inset.glass,
                        in: .rect(cornerRadius: GlassSurfaceStyle.inset.radius)
                    )
                    .contentTransition(accessibilityReduceMotion ? .identity : .opacity)
                    .transition(accessibilityReduceMotion ? .identity : .opacity)
                }

            }
        }
        .animation(accessibilityReduceMotion ? nil : .easeInOut(duration: 0.18), value: model.authDeviceCode)
        .animation(accessibilityReduceMotion ? nil : .easeInOut(duration: 0.18), value: model.isSigningIn)
        .animation(accessibilityReduceMotion ? nil : .easeInOut(duration: 0.18), value: model.isSignedIn)
    }

    private var behaviorCard: some View {
        GlassCard(style: .secondary) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Behavior")
                    .font(.headline)

                Toggle("Launch at login", isOn: Binding(
                    get: { model.launchAtLoginEnabled },
                    set: { model.setLaunchAtLoginEnabled($0) }
                ))

                if let launchAtLoginStatusMessage = model.launchAtLoginStatusMessage {
                    Text(launchAtLoginStatusMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Toggle("Auto-refresh", isOn: Binding(
                    get: { model.autoRefreshEnabled },
                    set: { model.setAutoRefreshEnabled($0) }
                ))

                VStack(alignment: .leading, spacing: 10) {
                    Text("Refresh every")
                        .font(.subheadline.weight(.medium))

                    Picker("Refresh every", selection: Binding(
                        get: { model.refreshIntervalSeconds },
                        set: { model.setRefreshIntervalSeconds($0) }
                    )) {
                        Text("5 min").tag(300)
                        Text("10 min").tag(600)
                        Text("60 min").tag(3600)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .disabled(model.autoRefreshEnabled == false)
                }

                Button {
                    Task { await model.refreshNow() }
                } label: {
                    Label(model.isRefreshing ? "Refreshing" : "Refresh Now", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.isRefreshing)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var displayCard: some View {
        GlassCard(style: .secondary) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Display")
                    .font(.headline)

                settingsGroup(title: "Popup") {
                    Toggle("Show Codex Spark", isOn: Binding(
                        get: { model.showSparkEnabled },
                        set: { model.setShowSparkEnabled($0) }
                    ))

                    Toggle("Show insights", isOn: Binding(
                        get: { model.showInsightsEnabled },
                        set: { model.setShowInsightsEnabled($0) }
                    ))

                    Toggle("Show history", isOn: Binding(
                        get: { model.showHistoryEnabled },
                        set: { model.setShowHistoryEnabled($0) }
                    ))

                    Toggle("Show history chart", isOn: Binding(
                        get: { model.showHistoryChartEnabled },
                        set: { model.setShowHistoryChartEnabled($0) }
                    ))
                    .disabled(model.showHistoryEnabled == false)
                }

                settingsGroup(title: "Menu bar") {
                    Toggle("Show 5H", isOn: Binding(
                        get: { model.showFiveHourInMenubar },
                        set: { model.setShowFiveHourInMenubar($0) }
                    ))

                    Toggle("Show W", isOn: Binding(
                        get: { model.showWeeklyInMenubar },
                        set: { model.setShowWeeklyInMenubar($0) }
                    ))
                }
            }
        }
    }

    private func settingsGroup<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        GlassCard(style: .inset) {
            VStack(alignment: .leading, spacing: 10) {
                Text(title)
                    .font(.subheadline.weight(.semibold))

                content()
            }
        }
    }

    @ViewBuilder
    private var accountAction: some View {
        if model.isSignedIn {
            Button("Sign Out") {
                model.signOut()
            }
            .buttonStyle(.bordered)
        } else if model.authDeviceCode != nil {
            Button("Clear Code") {
                model.clearAuthCode()
            }
            .buttonStyle(.bordered)
        } else {
            Button("Sign In with ChatGPT") {
                model.startChatGPTSignIn()
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.isSigningIn || model.hasResolvedAuthState == false && model.isRefreshing)
        }
    }

    private var accountHeadline: String {
        if model.isSigningIn {
            return "Signing in"
        }
        if model.previewModeEnabled {
            return "Preview Mode"
        }
        if model.authDeviceCode != nil {
            return "Open Safari"
        }
        if let snapshot = model.snapshot,
           let email = snapshot.account.email,
           email.isEmpty == false {
            return email
        }
        if model.isSignedIn {
            return "Signed in"
        }
        if model.hasResolvedAuthState {
            return "Not signed in"
        }
        return "Checking"
    }

    private var accountDetail: String? {
        if model.isSigningIn {
            return "Use the code in your browser."
        }
        if model.previewModeEnabled {
            return "SAMPLE DATA · Preview"
        }
        if let deviceCode = model.authDeviceCode {
            if model.isSigningIn {
                return "Code \(deviceCode) · Waiting for approval from Safari."
            }
            return "Code \(deviceCode) · Open Safari and approve sign-in there."
        }
        if let snapshot = model.snapshot {
            let auth = "OAuth"
            let plan = snapshot.account.planType?.uppercased()
            return [plan, auth].compactMap { $0 }.joined(separator: " · ")
        }
        if model.hasResolvedAuthState {
            return "Sign in to load quota."
        }
        return nil
    }
}
#endif
