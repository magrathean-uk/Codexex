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
            .background(kind.tint.opacity(0.12), in: Capsule(style: .continuous))
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(kind.tint.opacity(0.22), lineWidth: 1)
            }
            .accessibilityLabel(kind.title)
    }
}

struct CodexPulseRing: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let tint: Color
    @State private var isExpanded = false

    var body: some View {
        ZStack {
            Circle()
                .fill(tint)
                .frame(width: 7, height: 7)

            if reduceMotion == false {
                Circle()
                    .stroke(tint.opacity(isExpanded ? 0 : 0.35), lineWidth: 1)
                    .frame(width: isExpanded ? 20 : 8, height: isExpanded ? 20 : 8)
                    .animation(.easeOut(duration: 1.2).repeatForever(autoreverses: false), value: isExpanded)
            }
        }
        .frame(width: 22, height: 22)
        .onAppear { isExpanded = true }
    }
}

struct CodexPressableScale: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let isPressed: Bool

    func body(content: Content) -> some View {
        content
            .scaleEffect(reduceMotion ? 1 : (isPressed ? 0.985 : 1))
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isPressed)
    }
}

struct CodexDeviceCodeCallout: View {
    let code: String
    let message: String
    let canCheck: Bool
    let openSafari: () -> Void
    let copyCode: () -> Void
    let checkStatus: () -> Void
    let cancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                CodexPulseRing(tint: CodexTheme.amber)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Finish ChatGPT sign-in")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(CodexTheme.text)
                    Text(message)
                        .font(.system(size: 11.5))
                        .foregroundStyle(CodexTheme.dim)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)
                CodexStateBadge(kind: .waiting)
            }

            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Device code")
                        .font(.system(size: 10.5, weight: .semibold))
                        .textCase(.uppercase)
                        .tracking(1.2)
                        .foregroundStyle(CodexTheme.dim)
                    Text(code)
                        .font(.system(size: 20, weight: .semibold, design: .monospaced))
                        .textSelection(.enabled)
                        .foregroundStyle(CodexTheme.text)
                }

                Spacer(minLength: 0)

                Button("Copy", action: copyCode)
                    .buttonStyle(CodexGhostButtonStyle())
                Button("Open Safari", action: openSafari)
                    .buttonStyle(CodexPrimaryButtonStyle())
                Button("Check", action: checkStatus)
                    .buttonStyle(CodexGhostButtonStyle())
                    .disabled(canCheck == false)
                Button("Cancel", action: cancel)
                    .buttonStyle(CodexGhostButtonStyle())
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(
            GlassSurfaceStyle.inset.glass,
            in: .rect(cornerRadius: GlassSurfaceStyle.inset.radius)
        )
    }
}
#endif
