#if os(macOS)
import SwiftUI

enum CodexStateBadgeKind: Equatable {
    case live
    case preview
    case waiting
    case signedOut
    case stale
    case error

    var title: String {
        switch self {
        case .live: return "Live"
        case .preview: return "Preview"
        case .waiting: return "Waiting"
        case .signedOut: return "Signed Out"
        case .stale: return "Stale"
        case .error: return "Issue"
        }
    }

    var systemImage: String {
        switch self {
        case .live: return "checkmark.circle.fill"
        case .preview: return "wand.and.stars"
        case .waiting: return "clock.fill"
        case .signedOut: return "person.crop.circle.badge.xmark"
        case .stale: return "clock.badge.exclamationmark.fill"
        case .error: return "exclamationmark.triangle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .live: return CodexTheme.success
        case .preview: return CodexTheme.accent2
        case .waiting: return CodexTheme.amber
        case .signedOut: return CodexTheme.muted
        case .stale: return CodexTheme.amber
        case .error: return CodexTheme.danger
        }
    }
}

struct CodexStateBadge: View {
    let kind: CodexStateBadgeKind
    var monochrome = false

    var body: some View {
        Label(kind.title, systemImage: kind.systemImage)
            .font(.system(size: 11, weight: .semibold))
            .labelStyle(.titleAndIcon)
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(background, in: RoundedRectangle(cornerRadius: GlassTokens.pillRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: GlassTokens.pillRadius, style: .continuous)
                    .strokeBorder(border, lineWidth: 1)
            }
            .accessibilityLabel(kind.title)
    }

    private var tint: Color {
        monochrome ? .primary : kind.tint
    }

    private var background: Color {
        monochrome ? Color.primary.opacity(0.12) : kind.tint.opacity(0.12)
    }

    private var border: Color {
        monochrome ? Color.primary.opacity(0.22) : kind.tint.opacity(0.22)
    }
}

struct CodexPressableScale: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let isPressed: Bool

    func body(content: Content) -> some View {
        content
    }
}

struct CodexDeviceCodeCallout: View {
    let code: String
    var message: String? = nil
    var isCancelling = false
    let openSafari: () -> Void
    let copyCode: () -> Void
    let cancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Device code")
                .font(.system(size: 10.5, weight: .semibold))
                .textCase(.uppercase)
                .tracking(1.2)
                .foregroundStyle(CodexTheme.dim)

            Text(code)
                .font(.system(size: 28, weight: .bold, design: .monospaced))
                .minimumScaleFactor(0.78)
                .lineLimit(1)
                .textSelection(.enabled)
                .foregroundStyle(CodexTheme.text)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(CodexTheme.window, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(CodexTheme.hairline, lineWidth: 1)
                }

            if let message, message.isEmpty == false {
                Text(message)
                    .font(.system(size: GlassTokens.popupMetaFontSize))
                    .foregroundStyle(CodexTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                Button("Open", action: openSafari)
                    .buttonStyle(CodexPrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
                    .disabled(isCancelling)
                Button("Copy", action: copyCode)
                    .buttonStyle(CodexGhostButtonStyle())
                    .disabled(isCancelling)

                Spacer(minLength: 0)

                Button(isCancelling ? "Cancelling…" : "Cancel", action: cancel)
                    .buttonStyle(CodexGhostButtonStyle())
                    .disabled(isCancelling)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
#endif
