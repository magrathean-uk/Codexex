#if os(macOS)
import SwiftUI

enum CodexTheme {
    static let desktopTop = Color(red: 0.02, green: 0.04, blue: 0.08)
    static let desktopBottom = Color(red: 0.02, green: 0.08, blue: 0.12)
    static let window = Color(red: 0.02, green: 0.04, blue: 0.08)
    static let titlebar = Color(red: 0.03, green: 0.06, blue: 0.13)
    static let sidebar = Color(red: 0.02, green: 0.05, blue: 0.10)
    static let surface = Color(red: 0.03, green: 0.06, blue: 0.13)
    static let surfaceRaised = Color(red: 0.04, green: 0.08, blue: 0.15)
    static let control = Color(red: 0.06, green: 0.10, blue: 0.18)
    static let hairline = Color(red: 0.37, green: 0.67, blue: 1.00).opacity(0.12)
    static let hairlineStrong = Color(red: 0.37, green: 0.67, blue: 1.00).opacity(0.20)
    static let text = Color.white.opacity(0.94)
    static let muted = Color.white.opacity(0.62)
    static let dim = Color.white.opacity(0.42)
    static let accent = Color(red: 0.10, green: 0.15, blue: 1.00)
    static let accent2 = Color(red: 0.13, green: 0.84, blue: 0.91)
    static let spark = Color(red: 0.42, green: 0.85, blue: 1.00)
    static let spark2 = Color(red: 0.13, green: 0.84, blue: 0.91)
    static let amber = Color(red: 1.00, green: 0.65, blue: 0.08)
    static let danger = Color(red: 1.00, green: 0.27, blue: 0.32)
    static let success = Color(red: 0.35, green: 0.82, blue: 0.44)

    static let desktopGradient = LinearGradient(
        colors: [desktopTop, desktopBottom],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

enum GlassSurfaceStyle {
    case primary
    case secondary
    case inset

    var glass: Glass {
        switch self {
        case .primary, .secondary:
            return .regular.tint(CodexTheme.surface.opacity(0.86))
        case .inset:
            return .regular.tint(CodexTheme.control.opacity(0.74))
        }
    }

    var radius: CGFloat {
        switch self {
        case .primary, .secondary:
            return GlassTokens.cardRadius
        case .inset:
            return GlassTokens.insetRadius
        }
    }

    var padding: CGFloat {
        switch self {
        case .primary, .secondary:
            return GlassTokens.cardPadding
        case .inset:
            return GlassTokens.insetPadding
        }
    }

    var fill: Color {
        switch self {
        case .primary, .secondary:
            return CodexTheme.surface.opacity(0.96)
        case .inset:
            return CodexTheme.control.opacity(0.82)
        }
    }

    var border: Color {
        switch self {
        case .primary:
            return CodexTheme.hairlineStrong
        case .secondary:
            return CodexTheme.hairlineStrong
        case .inset:
            return CodexTheme.hairline
        }
    }
}

struct GlassCard<Content: View>: View {
    private let style: GlassSurfaceStyle
    @ViewBuilder let content: Content

    init(style: GlassSurfaceStyle = .primary, @ViewBuilder content: () -> Content) {
        self.style = style
        self.content = content()
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: style.radius, style: .continuous)

        switch style {
        case .inset:
            content
                .padding(style.padding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(style.fill, in: shape)
                .overlay {
                    shape.strokeBorder(style.border, lineWidth: 1)
                }
        case .primary, .secondary:
            content
                .padding(style.padding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(style.fill, in: shape)
                .glassEffect(style.glass, in: .rect(cornerRadius: style.radius))
                .shadow(color: .black.opacity(0.32), radius: 18, y: 10)
                .overlay {
                    shape.strokeBorder(style.border, lineWidth: 1)
                }
        }
    }
}
#endif
