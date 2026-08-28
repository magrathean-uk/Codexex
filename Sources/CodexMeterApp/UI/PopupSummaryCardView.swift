#if os(macOS)
import SwiftUI

struct PopupSummaryCardView: View {
    let summary: PopupSummaryPresentation
    let performAction: (PopupSummaryAction) -> Void
    var onSnooze: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(summary.title)
                        .font(.system(size: GlassTokens.popupHeadlineFontSize, weight: .semibold))
                        .foregroundStyle(summaryColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)

                    Text(primaryMessage)
                        .font(.system(size: GlassTokens.popupBodyFontSize, weight: .medium))
                        .foregroundStyle(CodexTheme.muted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.76)
                        .allowsTightening(true)
                }

                if secondaryLine.isEmpty == false {
                    Text(secondaryLine)
                        .font(.system(size: GlassTokens.popupMetaFontSize, weight: .medium))
                        .foregroundStyle(CodexTheme.dim)
                        .lineLimit(1)
                        .minimumScaleFactor(0.74)
                        .allowsTightening(true)
                }
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 6) {
                if let action = summary.action {
                    Button(action.title) {
                        performAction(action)
                    }
                    .buttonStyle(CodexGhostButtonStyle())
                }

                if canSnooze, let onSnooze {
                    Button("Snooze", action: onSnooze)
                        .buttonStyle(CodexGhostButtonStyle())
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: GlassTokens.summaryBannerMinHeight, alignment: .center)
    }

    private var canSnooze: Bool {
        summary.severity == .watch || summary.severity == .risk
    }

    private var summaryColor: Color {
        switch summary.severity {
        case .tooEarly:
            return CodexTheme.dim
        case .safe:
            return CodexTheme.success
        case .watch:
            return CodexTheme.amber
        case .risk:
            return CodexTheme.danger
        }
    }

    private var detailLine: String {
        summary.popupHeaderText.secondary
    }

    private var primaryMessage: String {
        summary.popupHeaderText.primary
    }

    private var secondaryLine: String {
        detailLine
    }

}

struct PopupSummaryHeaderText: Equatable {
    let primary: String
    let secondary: String
}

extension PopupSummaryPresentation {
    var popupHeaderText: PopupSummaryHeaderText {
        let messageParts = messageSentenceParts
        let supportLine = compactSupportLine
        let secondary = if messageParts.secondary.isEmpty {
            supportLine
        } else if supportLine.isEmpty {
            messageParts.secondary
        } else {
            "\(messageParts.secondary) · \(supportLine)"
        }

        return PopupSummaryHeaderText(primary: messageParts.primary, secondary: secondary)
    }

    private var compactSupportLine: String {
        let label = supportingLabel.isEmpty ? nil : supportingLabel
        let value = supportingValue.isEmpty || message.localizedCaseInsensitiveContains(supportingValue)
            ? nil
            : supportingValue
        return [label, value]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    private var messageSentenceParts: (primary: String, secondary: String) {
        guard let range = message.range(of: ". ") else {
            return (message, "")
        }
        let first = String(message[..<range.upperBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        let rest = String(message[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        return (first, rest)
    }
}

struct CodexGhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: GlassTokens.popupMetaFontSize, weight: .medium))
            .foregroundStyle(CodexTheme.text)
            .padding(.horizontal, 10)
            .frame(minWidth: 74, minHeight: GlassTokens.pillHeight)
            .background(
                configuration.isPressed ? CodexTheme.control.opacity(0.82) : CodexTheme.control,
                in: RoundedRectangle(cornerRadius: GlassTokens.pillRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: GlassTokens.pillRadius, style: .continuous)
                    .strokeBorder(CodexTheme.hairlineStrong, lineWidth: 1)
            }
    }
}
#endif
