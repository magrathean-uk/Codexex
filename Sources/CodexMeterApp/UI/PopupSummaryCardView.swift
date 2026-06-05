#if os(macOS)
import SwiftUI

struct PopupSummaryCardView: View {
    let summary: PopupSummaryPresentation
    let performAction: (PopupSummaryAction) -> Void
    var onSnooze: (() -> Void)?

    var body: some View {
        PopupPlainSection {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(summary.title)
                        .font(.system(size: GlassTokens.popupHeadlineFontSize, weight: .semibold))
                        .foregroundStyle(summaryColor)

                    Text(summary.message)
                        .font(.system(size: GlassTokens.popupBodyFontSize))
                        .foregroundStyle(CodexTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
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
            .frame(minHeight: GlassTokens.summaryBannerMinHeight, alignment: .center)
        }
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

}

extension PopupSummaryPresentation {
    var detailLine: String {
        let label = supportingLabel.isEmpty ? nil : supportingLabel
        let value = supportingValue.isEmpty ? nil : supportingValue
        let detail = supportingDetail?.isEmpty == false ? supportingDetail : nil
        return [label, value, detail]
            .compactMap { $0 }
            .joined(separator: " · ")
    }
}

struct CodexGhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: GlassTokens.popupMetaFontSize, weight: .medium))
            .foregroundStyle(CodexTheme.text)
            .padding(.horizontal, 12)
            .frame(minWidth: 68, minHeight: 30)
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
