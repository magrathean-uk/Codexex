#if os(macOS)
import SwiftUI

enum GlassSurfaceStyle {
    case primary
    case secondary
    case inset

    var glass: Glass {
        switch self {
        case .primary:
            return .regular.tint(.white.opacity(0.18))
        case .secondary:
            return .regular.tint(.white.opacity(0.14))
        case .inset:
            return .clear.tint(.clear)
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
        case .primary:
            return Color.white.opacity(0.18)
        case .secondary:
            return Color.white.opacity(0.12)
        case .inset:
            return Color.clear
        }
    }

    var border: Color {
        switch self {
        case .primary:
            return Color.white.opacity(0.22)
        case .secondary:
            return Color.white.opacity(0.16)
        case .inset:
            return Color.primary.opacity(0.035)
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
                .overlay {
                    shape.strokeBorder(style.border, lineWidth: 1)
                }
        }
    }
}
#endif
