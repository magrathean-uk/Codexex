#if os(macOS)
import AppKit
import Observation
import SwiftUI

struct SettingsAccountCardView: View {
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @Bindable var model: CodexMenuBarModel

    var body: some View {
        GlassCard(style: .primary) {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Account")
                        .font(.headline)

                    Text(model.accountHeadline)
                        .font(.title3.weight(.semibold))

                    if let detail = model.accountDetail {
                        Text(detail)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                HStack(spacing: 10) {
                    accountAction
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Button(model.previewModeEnabled ? "Leave Sample Data" : "Use Sample Data") {
                        if model.previewModeEnabled {
                            model.disablePreviewMode()
                        } else {
                            model.enablePreviewMode()
                        }
                    }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Divider()

                Text(model.previewModeEnabled ? "Sample data is active." : "Sample data lets you inspect the UI without touching live usage.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let code = model.authDeviceCode {
                    deviceCodeCard(code: code)
                }
            }
        }
        .animation(accessibilityReduceMotion ? nil : .easeInOut(duration: 0.18), value: model.authDeviceCode)
        .animation(accessibilityReduceMotion ? nil : .easeInOut(duration: 0.18), value: model.isSigningIn)
        .animation(accessibilityReduceMotion ? nil : .easeInOut(duration: 0.18), value: model.isSignedIn)
    }

    private func deviceCodeCard(code: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Device code")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(code)
                .textSelection(.enabled)
                .font(.system(.title3, weight: .semibold))

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

    @ViewBuilder
    private var accountAction: some View {
        if model.isSignedIn, model.previewModeEnabled == false {
            Button("Sign Out") {
                model.signOut()
            }
            .buttonStyle(.borderedProminent)
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
            .disabled(model.canStartChatGPTSignIn == false)
        }
    }
}
#endif
