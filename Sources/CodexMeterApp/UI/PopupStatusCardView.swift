#if os(macOS)
import AppKit
import Observation
import SwiftUI

struct PopupStatusCardView: View {
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @Bindable var model: CodexMenuBarModel

    var body: some View {
        GlassCard(style: model.snapshot == nil ? .primary : .secondary) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(model.statusCardTitle)
                            .font(.headline)

                        Text(model.statusCardMessage)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 0)
                    CodexStateBadge(kind: model.designStateBadgeKind)
                }

                if let code = model.authDeviceCode {
                    CodexDeviceCodeCallout(
                        code: code,
                        message: model.authStatusMessage,
                        canCheck: model.canCheckPendingChatGPTSignIn,
                        openSafari: { model.openAuthVerificationPage() },
                        copyCode: { model.copyAuthCode() },
                        checkStatus: { model.checkPendingChatGPTSignIn() },
                        cancel: { model.cancelPendingChatGPTSignIn() }
                    )
                }

                actionRow
            }
        }
        .transition(accessibilityReduceMotion ? .identity : .opacity.combined(with: .scale(scale: 0.985)))
    }

    @ViewBuilder
    private var actionRow: some View {
        if model.authDeviceCode != nil {
            EmptyView()
        } else if model.previewModeEnabled {
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
                Label(model.isRefreshing ? "Refreshing" : "Refresh Now", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(model.isRefreshing)
        }
    }
}
#endif
