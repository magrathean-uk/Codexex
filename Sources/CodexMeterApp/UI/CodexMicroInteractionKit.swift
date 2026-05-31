#if os(macOS)
import SwiftUI

enum CodexStateBadgeKind: Equatable {
    case live
    case preview
    case waiting
    case stale
    case error

    var title: String {
        switch self {
        case .live: return "Live"
        case .preview: return "Preview"
        case .waiting: return "Waiting"
        case .stale: return "Stale"
        case .error: return "Issue"
        }
    }

    var systemImage: String {
        switch self {
        case .live: return "checkmark.circle.fill"
        case .preview: return "wand.and.stars"
        case .waiting: return "clock.fill"
        case .stale: return "exclamationmark.clock.fill"
        case .error: return "exclamationmark.triangle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .live: return CodexTheme.success
        case .preview: return CodexTheme.accent2
        case .waiting: return CodexTheme.amber
        case .stale: return CodexTheme.amber
        case .error: return CodexTheme.danger
        }
    }
}

struct CodexStateBadge: View {
    let kind: CodexStateBadgeKind

    var body: some View {
        Label(kind.title, systemImage: kind.systemImage)
            .font(.system(size: 11, weight: .semibold))
            .labelStyle(.titleAndIcon)
            .foregroundStyle(kind.tint)
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(kind.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: GlassTokens.pillRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: GlassTokens.pillRadius, style: .continuous)
                    .strokeBorder(kind.tint.opacity(0.22), lineWidth: 1)
            }
            .accessibilityLabel(kind.title)
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

            HStack(spacing: 8) {
                Button("Open", action: openSafari)
                    .buttonStyle(CodexPrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
                Button("Copy", action: copyCode)
                    .buttonStyle(CodexGhostButtonStyle())

                Spacer(minLength: 0)

                Button("Cancel", action: cancel)
                    .buttonStyle(CodexGhostButtonStyle())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
#endif
