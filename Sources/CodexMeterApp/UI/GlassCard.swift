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
            return .regular.tint(.white.opacity(0.10))
        case .inset:
            return .clear.tint(.black.opacity(0.08))
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
}

struct GlassCard<Content: View>: View {
    private let style: GlassSurfaceStyle
    @ViewBuilder let content: Content

    init(style: GlassSurfaceStyle = .primary, @ViewBuilder content: () -> Content) {
        self.style = style
        self.content = content()
    }

    var body: some View {
        content
            .padding(GlassTokens.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(style.glass, in: .rect(cornerRadius: style.radius))
    }
}
#endif
