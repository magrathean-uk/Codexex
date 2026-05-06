#if os(macOS)
import SwiftUI

struct PopupSummaryCardView: View {
    let summary: PopupSummaryPresentation
    let performAction: (PopupSummaryAction) -> Void
    var onSnooze: (() -> Void)?

    var body: some View {
        GlassCard(style: .primary) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: symbolName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(summaryColor)
                    .frame(width: 24, height: 24)
                    .background(summaryColor.opacity(0.16), in: Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text(summary.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(summaryColor)

                    Text(summary.message)
                        .font(.system(size: 12.5))
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

    private var symbolName: String {
        switch summary.severity {
        case .tooEarly:
            return "clock.badge.questionmark"
        case .safe:
            return "checkmark.circle.fill"
        case .watch:
            return "exclamationmark.triangle"
        case .risk:
            return "exclamationmark.triangle.fill"
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
            .font(.system(size: 12.5, weight: .medium))
            .foregroundStyle(CodexTheme.text)
            .padding(.horizontal, 12)
            .frame(minWidth: 68, minHeight: GlassTokens.pillHeight)
            .background(
                configuration.isPressed ? CodexTheme.control.opacity(0.82) : CodexTheme.control,
                in: RoundedRectangle(cornerRadius: GlassTokens.pillRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: GlassTokens.pillRadius, style: .continuous)
                    .strokeBorder(CodexTheme.hairlineStrong, lineWidth: 1)
            }
            .modifier(CodexPressableScale(isPressed: configuration.isPressed))
    }
}
#endif
