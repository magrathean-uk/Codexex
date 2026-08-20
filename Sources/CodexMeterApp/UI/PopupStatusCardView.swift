#if os(macOS)
import AppKit
import Observation
import SwiftUI

struct PopupStatusCardView: View {
    @Bindable var model: CodexMenuBarModel

    var body: some View {
        if let code = model.authDeviceCode {
            PopupPlainSection {
                CodexDeviceCodeCallout(
                    code: code,
                    openSafari: { model.openAuthVerificationPage() },
                    copyCode: { model.copyAuthCode() },
                    cancel: { model.cancelPendingChatGPTSignIn() }
                )
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center, spacing: 8) {
                    Text(model.statusCardTitle)
                        .font(.system(size: GlassTokens.popupHeadlineFontSize, weight: .semibold))
                        .foregroundStyle(statusTint)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)

                    Spacer(minLength: 8)

                    CodexStateBadge(kind: model.designStateBadgeKind)
                }

                Text(model.statusCardMessage)
                    .font(.system(size: GlassTokens.popupBodyFontSize))
                    .foregroundStyle(CodexTheme.muted)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)

                if model.isRefreshing {
                    PopupLoadingBar()
                        .padding(.top, 1)
                        .accessibilityLabel("Loading quota")
                }

                if shouldShowActionRow {
                    actionRow
                        .padding(.top, 1)
                }
            }
        }
    }

    private var statusTint: Color {
        model.designStateBadgeKind.tint
    }

    private var shouldShowActionRow: Bool {
        model.previewModeEnabled || (
            model.isSignedIn == false
                && model.hasResolvedAuthState
                && model.authDeviceCode == nil
                && model.isSigningIn == false
        )
    }

    @ViewBuilder
    private var actionRow: some View {
        if model.previewModeEnabled {
            HStack(spacing: 8) {
                PopupActionButton(title: "Leave Preview", tone: .primary) {
                    model.disablePreviewMode()
                }
                .keyboardShortcut(.defaultAction)

                PopupActionButton(title: "Refresh", tone: .secondary) {
                    Task { await model.refreshNow(manual: true) }
                }
                .disabled(model.isRefreshing)
            }
        } else if model.isSignedIn == false {
            HStack(spacing: 8) {
                PopupActionButton(title: "Sign In", tone: .secondary) {
                    model.startChatGPTSignIn()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(model.canStartChatGPTSignIn == false)

                PopupActionButton(title: "Sample Data", tone: .secondary) {
                    model.enablePreviewMode()
                }
            }
        }
    }
}

private struct PopupActionButton: View {
    enum Tone {
        case primary
        case secondary
    }

    @Environment(\.isEnabled) private var isEnabled
    let title: String
    let tone: Tone
    let action: () -> Void

    var body: some View {
        PopupAppKitButton(
            title: title,
            systemImage: nil,
            tone: tone == .primary ? .primary : .secondary,
            minimumWidth: 92,
            accessibilityIdentifier: nil,
            isEnabled: isEnabled,
            action: action
        )
        .frame(maxWidth: .infinity, minHeight: GlassTokens.pillHeight)
    }
}
#endif
