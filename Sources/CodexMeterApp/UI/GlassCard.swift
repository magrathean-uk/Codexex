#if os(macOS)
import AppKit
import SwiftUI

enum CodexTheme {
    static let windowNSColor = adaptiveNS(light: ns(0xEEF5FF), dark: ns(0x060914))

    static let desktopTop = color(light: ns(0xF4F8FF), dark: ns(0x060914))
    static let desktopBottom = color(light: ns(0xF4F8FF), dark: ns(0x05141F))
    static let window = Color(nsColor: windowNSColor)
    static let titlebar = color(light: ns(0xF8FBFF), dark: ns(0x081021))
    static let sidebar = color(light: ns(0xEDF4FF), dark: ns(0x050D1A))
    static let surface = color(light: ns(0xFFFFFF).withAlphaComponent(0.76), dark: ns(0x081021).withAlphaComponent(0.88))
    static let surfaceRaised = color(light: ns(0xFFFFFF).withAlphaComponent(0.84), dark: ns(0x0A1426))
    static let control = color(light: ns(0xFFFFFF).withAlphaComponent(0.62), dark: ns(0x0F1A2E))
    static let hairline = color(light: ns(0x3156B8).withAlphaComponent(0.16), dark: ns(0x5FAAFF).withAlphaComponent(0.12))
    static let hairlineStrong = color(light: ns(0x3156B8).withAlphaComponent(0.24), dark: ns(0x5FAAFF).withAlphaComponent(0.20))
    static let text = color(light: ns(0x101727).withAlphaComponent(0.94), dark: ns(0xFFFFFF).withAlphaComponent(0.94))
    static let muted = color(light: ns(0x101727).withAlphaComponent(0.62), dark: ns(0xFFFFFF).withAlphaComponent(0.62))
    static let dim = color(light: ns(0x101727).withAlphaComponent(0.44), dark: ns(0xFFFFFF).withAlphaComponent(0.42))
    static let accent = Color(red: 0.10, green: 0.15, blue: 1.00)
    static let accent2 = Color(red: 0.13, green: 0.84, blue: 0.91)
    static let spark = Color(red: 0.42, green: 0.85, blue: 1.00)
    static let spark2 = Color(red: 0.13, green: 0.84, blue: 0.91)
    static let amber = Color(red: 1.00, green: 0.65, blue: 0.08)
    static let danger = Color(red: 1.00, green: 0.27, blue: 0.32)
    static let success = Color(red: 0.35, green: 0.82, blue: 0.44)
    static let shadow = color(light: ns(0x5C6F93).withAlphaComponent(0.16), dark: ns(0x000000).withAlphaComponent(0.32))
    static let popupShadow = color(light: ns(0x5C6F93).withAlphaComponent(0.24), dark: ns(0x000000).withAlphaComponent(0.42))

    static let desktopGradient = LinearGradient(
        colors: [desktopTop, desktopBottom],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static func windowNSColor(for appearance: NSAppearance) -> NSColor {
        let match = appearance.bestMatch(from: [.aqua, .darkAqua])
        return match == .darkAqua ? ns(0x060914) : ns(0xEEF5FF)
    }

    private static func ns(_ hex: UInt32) -> NSColor {
        NSColor(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }

    private static func color(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: adaptiveNS(light: light, dark: dark))
    }

    private static func adaptiveNS(light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            let match = appearance.bestMatch(from: [.aqua, .darkAqua])
            return match == .darkAqua ? dark : light
        }
    }
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
            return CodexTheme.surface.opacity(0.88)
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
                .overlay {
                    shape.strokeBorder(style.border, lineWidth: 1)
                }
        }
    }
}

struct PopupPlainSection<Content: View>: View {
    @ViewBuilder let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: GlassTokens.cardRadius, style: .continuous)

        content
            .padding(GlassTokens.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(CodexTheme.surface.opacity(0.72), in: shape)
            .overlay {
                shape.strokeBorder(CodexTheme.hairlineStrong, lineWidth: 1)
            }
            .glassEffect(.regular.tint(CodexTheme.surface.opacity(0.52)), in: shape)
    }
}
#endif
