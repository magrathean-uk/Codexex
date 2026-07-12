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
        if model.previewModeEnabled || model.lastError != nil {
            return true
        }
        if model.isSignedIn == false {
            return true
        }
        if model.snapshot == nil {
            return model.isRefreshing == false
        }
        return false
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
        } else if model.lastError != nil || (model.snapshot == nil && model.hasResolvedAuthState == false) {
            HStack(spacing: 8) {
                PopupActionButton(title: model.isRefreshing ? "Refreshing" : "Refresh", tone: .primary) {
                    Task { await model.refreshNow(manual: true) }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(model.isRefreshing)

                PopupActionButton(title: "Sample Data", tone: .secondary) {
                    model.enablePreviewMode()
                }
            }
        } else if model.isSignedIn == false {
            HStack(spacing: 8) {
                PopupActionButton(title: "Sign In", tone: .primary) {
                    model.startChatGPTSignIn()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(model.canStartChatGPTSignIn == false)

                PopupActionButton(title: "Sample Data", tone: .secondary) {
                    model.enablePreviewMode()
                }
            }
        } else if model.snapshot == nil {
            HStack(spacing: 8) {
                PopupActionButton(title: model.isRefreshing ? "Refreshing" : "Refresh", tone: .primary) {
                    Task { await model.refreshNow(manual: true) }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(model.isRefreshing)

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
        Button(action: action) {
            Text(title)
                .font(.system(size: GlassTokens.popupMetaFontSize, weight: .semibold))
                .foregroundStyle(foreground)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .allowsTightening(true)
                .padding(.horizontal, 12)
                .frame(minWidth: minimumWidth)
                .frame(height: GlassTokens.pillHeight)
                .background {
                    buttonBackground
                }
                .overlay {
                    if tone == .secondary {
                        RoundedRectangle(cornerRadius: GlassTokens.pillRadius, style: .continuous)
                            .strokeBorder(CodexTheme.hairlineStrong, lineWidth: 1)
                    }
                }
                .opacity(isEnabled ? 1 : 0.72)
                .unredacted()
        }
        .buttonStyle(.plain)
        .disabled(isEnabled == false)
        .accessibilityLabel(title)
    }

    private var foreground: Color {
        switch tone {
        case .primary:
            return .white
        case .secondary:
            return CodexTheme.text
        }
    }

    private var minimumWidth: CGFloat {
        switch tone {
        case .primary:
            return 76
        case .secondary:
            return 86
        }
    }

    @ViewBuilder
    private var buttonBackground: some View {
        let shape = RoundedRectangle(cornerRadius: GlassTokens.pillRadius, style: .continuous)
        switch tone {
        case .primary:
            shape.fill(CodexTheme.accent)
        case .secondary:
            shape.fill(CodexTheme.control)
        }
    }
}
#endif
