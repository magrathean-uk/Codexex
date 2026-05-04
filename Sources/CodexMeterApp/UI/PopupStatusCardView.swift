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

                    if model.isSigningIn {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                if let code = model.authDeviceCode {
                    deviceCodePanel(code: code)
                }

                actionRow
            }
        }
        .transition(accessibilityReduceMotion ? .identity : .opacity.combined(with: .scale(scale: 0.985)))
    }

    @ViewBuilder
    private var actionRow: some View {
        if model.authDeviceCode != nil {
            HStack(spacing: 8) {
                Button("Open Safari") {
                    model.openAuthVerificationPage()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(model.authVerificationURL == nil)

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
        } else if model.previewModeEnabled {
            HStack(spacing: 8) {
                Button("Leave Preview") {
                    model.disablePreviewMode()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)

                Button("Refresh Live Quota") {
                    Task { await model.refreshNow() }
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
                Task { await model.refreshNow() }
            } label: {
                Label(model.isRefreshing ? "Refreshing" : "Refresh Now", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(model.isRefreshing)
        }
    }

    private func deviceCodePanel(code: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Device code")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(code)
                    .font(.system(.title3, weight: .semibold))
                    .textSelection(.enabled)

                Spacer(minLength: 0)

                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(code, forType: .string)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(
            GlassSurfaceStyle.inset.glass,
            in: .rect(cornerRadius: GlassSurfaceStyle.inset.radius)
        )
    }
}
#endif
