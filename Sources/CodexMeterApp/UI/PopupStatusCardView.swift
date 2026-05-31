#if os(macOS)
import AppKit
import Observation
import SwiftUI

struct PopupStatusCardView: View {
    @Bindable var model: CodexMenuBarModel

    var body: some View {
        PopupPlainSection {
            if let code = model.authDeviceCode {
                CodexDeviceCodeCallout(
                    code: code,
                    openSafari: { model.openAuthVerificationPage() },
                    copyCode: { model.copyAuthCode() },
                    cancel: { model.cancelPendingChatGPTSignIn() }
                )
            } else {
                VStack(alignment: .leading, spacing: 7) {
                    HStack(alignment: .firstTextBaseline, spacing: 9) {
                        Text(model.statusCardTitle)
                            .font(.system(size: 15.5, weight: .semibold))
                            .foregroundStyle(statusTint)
                            .lineLimit(1)

                        Text(model.statusCardMessage)
                            .font(.system(size: 13.5))
                            .foregroundStyle(CodexTheme.muted)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)

                        Spacer(minLength: 0)
                    }

                    actionRow
                }
            }
        }
    }

    private var statusTint: Color {
        model.designStateBadgeKind.tint
    }

    @ViewBuilder
    private var actionRow: some View {
        if model.previewModeEnabled {
            HStack(spacing: 8) {
                Button("Leave Preview") {
                    model.disablePreviewMode()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)

                Button("Refresh Live Quota") {
                    Task { await model.refreshNow(manual: true) }
                }
                .buttonStyle(.bordered)
                .disabled(model.isRefreshing)
            }
        } else if model.isSignedIn == false {
            HStack(spacing: 8) {
                Button("Sign In with ChatGPT") {
                    model.startChatGPTSignIn()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(model.canStartChatGPTSignIn == false)

                Button("Use Sample Data") {
                    model.enablePreviewMode()
                }
                .buttonStyle(.bordered)
            }
        } else if model.lastError != nil || model.snapshot == nil {
            Button {
                Task { await model.refreshNow(manual: true) }
            } label: {
                Text(model.isRefreshing ? "Refreshing" : "Refresh Now")
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(model.isRefreshing)
        }
    }
}
#endif
