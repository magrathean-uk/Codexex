#if os(macOS)
import AppKit
import Observation
import SwiftUI

struct OnboardingRootView: View {
    @Bindable var model: CodexMenuBarModel
    var onDismiss: () -> Void

    var body: some View {
        GlassEffectContainer(spacing: GlassTokens.sectionSpacing) {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Welcome to Codexex")
                        .font(.largeTitle.weight(.bold))

                    Text("Pick how you want to start. You can change this later in Settings.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }

                actionCard

                if let code = model.authDeviceCode {
                    deviceCodeCard(code: code)
                }

                if let message = messageText {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(24)
            .frame(width: 560)
        }
        .onChange(of: model.isSignedIn) { _, isSignedIn in
            if isSignedIn && model.previewModeEnabled == false {
                onDismiss()
            }
        }
    }

    private var actionCard: some View {
        GlassCard(style: .primary) {
            VStack(alignment: .leading, spacing: 16) {
                Button("Sign In with ChatGPT") {
                    model.startChatGPTSignIn()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(model.isSigningIn)

                Divider()

                Button("Preview Mode") {
                    model.enablePreviewMode()
                    onDismiss()
                }
                .buttonStyle(.bordered)

                Text("Preview Mode uses local sample data for App Review and first look.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func deviceCodeCard(code: String) -> some View {
        GlassCard(style: .secondary) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Device code")
                    .font(.headline)

                Text(code)
                    .font(.system(.title2, design: .monospaced, weight: .bold))
                    .textSelection(.enabled)

                HStack(spacing: 10) {
                    Button("Open Safari") {
                        model.openAuthVerificationPage()
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.authVerificationURL == nil)

                    Button("Copy Code") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(code, forType: .string)
                    }
                    .buttonStyle(.bordered)

                    Button("Check Status") {
                        model.checkPendingChatGPTSignIn()
                    }
                    .buttonStyle(.bordered)
                    .disabled(model.canCheckPendingChatGPTSignIn == false)

                    Button("Cancel") {
                        model.cancelPendingChatGPTSignIn()
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private var messageText: String? {
        if model.authDeviceCode != nil {
            if model.isSigningIn {
                return "Waiting for approval from Safari."
            }
            return "Copy the code, approve sign-in in Safari, then check status here."
        }
        if model.lastError != nil {
            return model.lastError
        }
        return nil
    }
}
#endif
