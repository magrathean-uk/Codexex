#if os(macOS)
import AppKit
import Observation
import SwiftUI

struct SettingsAccountCardView: View {
    @Bindable var model: CodexMenuBarModel

    var body: some View {
        GlassCard(style: .primary) {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Account")
                        .font(.headline)

                    HStack(spacing: 10) {
                        Text(model.accountHeadline)
                            .font(.title3.weight(.semibold))
                        CodexStateBadge(kind: model.designStateBadgeKind)
                    }

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
                    .buttonStyle(SettingsGhostButtonStyle())
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
    }

    private func deviceCodeCard(code: String) -> some View {
        CodexDeviceCodeCallout(
            code: code,
            isCancelling: model.isCancellingPendingSignIn,
            openSafari: { model.openAuthVerificationPage() },
            copyCode: { model.copyAuthCode() },
            cancel: { model.cancelPendingChatGPTSignIn() }
        )
    }

    @ViewBuilder
    private var accountAction: some View {
        if model.isSignedIn, model.previewModeEnabled == false {
            Button("Sign Out") {
                model.signOut()
            }
            .buttonStyle(CodexDestructiveButtonStyle())
        } else if model.authDeviceCode != nil {
            Button(model.isCancellingPendingSignIn ? "Clearing…" : "Clear Code") {
                model.clearAuthCode()
            }
            .buttonStyle(SettingsGhostButtonStyle())
            .disabled(model.isCancellingPendingSignIn)
        } else {
            Button("Sign In with ChatGPT") {
                model.startChatGPTSignIn()
            }
            .buttonStyle(CodexPrimaryButtonStyle())
            .disabled(model.canStartChatGPTSignIn == false)
        }
    }
}
#endif
