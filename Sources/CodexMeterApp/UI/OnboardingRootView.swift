#if os(macOS)
import AppKit
import Observation
import SwiftUI

enum OnboardingStep: String { case welcome, subscription, api }

struct OnboardingRootView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Bindable var model: CodexMenuBarModel
    var onDismiss: () -> Void
    @State private var step: OnboardingStep

    init(
        model: CodexMenuBarModel, onDismiss: @escaping () -> Void,
        initialStep: OnboardingStep = .welcome
    ) {
        self.model = model
        self.onDismiss = onDismiss
        _step = State(initialValue: initialStep)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack {
                    if step != .welcome {
                        Button {
                            step = .welcome
                        } label: {
                            Label("Back", systemImage: "chevron.left")
                        }
                        .buttonStyle(.borderless)
                    }
                    Spacer()
                    Text(step == .welcome ? "Step 1 of 2" : "Step 2 of 2")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Group {
                    switch step {
                    case .welcome: welcome
                    case .subscription: subscription
                    case .api: api
                    }
                }
                .id(step)
                .transition(.opacity)
            }
            .padding(32)
            .frame(maxWidth: 560, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .tint(CodexTheme.actionTint)
        .preferredColorScheme(model.appearanceMode.colorScheme)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.16), value: step)
        .onChange(of: model.isSignedIn) { _, signedIn in
            if signedIn && !model.previewModeEnabled { onDismiss() }
        }
        .onAppear { if model.authDeviceCode != nil { step = .subscription } }
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 24) {
            heading("Welcome to Codexex", subtitle: "Choose what you want to monitor.")
            VStack(spacing: 0) {
                Divider()
                choice(
                    "ChatGPT subscription", detail: "Limits and reset times",
                    icon: "gauge.with.dots.needle.bottom.50percent", destination: .subscription)
                Divider()
                choice(
                    "API monitoring", detail: "Access, costs and credits", icon: "chart.bar.xaxis",
                    destination: .api)
                Divider()
            }
            Button("Try with sample data") {
                model.enablePreviewMode()
                onDismiss()
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
        }
    }

    private var subscription: some View {
        VStack(alignment: .leading, spacing: 20) {
            heading("Connect your subscription", subtitle: "Approve access in your browser.")
            if let code = model.authDeviceCode {
                Text("Enter this code").font(.headline)
                Text(code)
                    .font(.system(size: 28, weight: .semibold, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(Color(nsColor: .controlBackgroundColor))
                HStack(spacing: 10) {
                    Button("Open browser") { model.openAuthVerificationPage() }
                        .buttonStyle(.borderedProminent)
                        .tint(CodexTheme.prominentTint)
                        .keyboardShortcut(.defaultAction)
                        .disabled(
                            model.authVerificationURL == nil || model.isCancellingPendingSignIn)
                    Button("Copy code") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(code, forType: .string)
                    }.disabled(model.isCancellingPendingSignIn)
                    Button("Check status") { model.checkPendingChatGPTSignIn() }
                        .disabled(!model.canCheckPendingChatGPTSignIn)
                    Button(model.isCancellingPendingSignIn ? "Cancelling…" : "Cancel") {
                        model.cancelPendingChatGPTSignIn()
                    }
                    .disabled(model.isCancellingPendingSignIn)
                }
                .buttonStyle(.bordered)
                Text(
                    model.isSigningIn
                        ? "Waiting for browser approval…"
                        : "Return here after approval and check status."
                )
                .font(.callout).foregroundStyle(.secondary)
            } else {
                setupStage(
                    1, title: "Sign in", detail: "Use the ChatGPT account you want to monitor.")
                Button(model.isSigningIn ? "Starting…" : "Sign in with ChatGPT") {
                    model.startChatGPTSignIn()
                }
                .buttonStyle(.borderedProminent)
                .tint(CodexTheme.prominentTint)
                .keyboardShortcut(.defaultAction)
                .disabled(!model.canStartChatGPTSignIn)
            }
            if let error = model.lastError {
                Text(error).font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    private var api: some View {
        VStack(alignment: .leading, spacing: 20) {
            heading("Connect API monitoring", subtitle: "Choose the connections you want to use.")
            OpenAIMonitorView(monitor: model.apiMonitor)
            Divider()
            HStack {
                Spacer()
                Button("Continue") {
                    model.completeOnboarding()
                    onDismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(CodexTheme.prominentTint)
                .keyboardShortcut(.defaultAction)
                .disabled(!model.apiMonitor.isValidated)
            }
        }
    }

    private func heading(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 24, weight: .semibold))
            Text(subtitle).font(.callout).foregroundStyle(.secondary)
        }
    }

    private func setupStage(_ number: Int, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number).").font(.headline).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(detail).font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    private func choice(_ title: String, detail: String, icon: String, destination: OnboardingStep)
        -> some View
    {
        Button {
            step = destination
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.title3).foregroundStyle(.secondary).frame(width: 24)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.body.weight(.medium)).foregroundStyle(.primary)
                    Text(detail).font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
            }
            .padding(.vertical, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
#endif
