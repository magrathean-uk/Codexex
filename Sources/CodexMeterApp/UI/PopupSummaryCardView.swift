#if os(macOS)
import SwiftUI

struct PopupSummaryCardView: View {
    let summary: PopupSummaryPresentation
    let performAction: (PopupSummaryAction) -> Void

    var body: some View {
        GlassCard(style: .primary) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Label(summary.title, systemImage: symbolName)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(summary.severity.color)

                    Spacer()
                }

                Text(summary.message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if summary.supportingLabel.isEmpty == false {
                    supportingMetric
                }

                if let action = summary.action {
                    Button {
                        performAction(action)
                    } label: {
                        Label(action.title, systemImage: action.systemImage)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private var symbolName: String {
        switch summary.severity {
        case .tooEarly:
            return "clock.badge.questionmark"
        case .safe:
            return "checkmark.circle.fill"
        case .watch:
            return "exclamationmark.circle.fill"
        case .risk:
            return "exclamationmark.triangle.fill"
        }
    }

    private var supportingMetric: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(summary.supportingLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer(minLength: 8)

                Text(summary.supportingValue)
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(.primary.opacity(0.92))
            }

            if let supportingDetail = summary.supportingDetail, supportingDetail.isEmpty == false {
                Text(supportingDetail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
#endif
