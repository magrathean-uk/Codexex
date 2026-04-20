#if os(macOS)
import SwiftUI

struct InsightsCardView: View {
    let insights: CodexUsageInsights

    var body: some View {
        GlassCard(style: .secondary) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Insights")
                    .font(.headline)

                insightRow(
                    title: "Weekly pace",
                    message: insights.weeklyPace.message,
                    detail: weeklyDetail,
                    tone: CodexUsageInsightTone(insights.weeklyPace.tone)
                )

                insightRow(
                    title: insights.fiveHourPressure.title,
                    message: insights.fiveHourPressure.message,
                    detail: insights.fiveHourPressure.detail,
                    tone: insights.fiveHourPressure.tone
                )

                insightRow(
                    title: insights.recentPeaks.title,
                    message: insights.recentPeaks.message,
                    detail: insights.recentPeaks.detail,
                    tone: insights.recentPeaks.tone
                )
            }
        }
    }

    private var weeklyDetail: String? {
        var parts: [String] = []
        if let projected = insights.weeklyPace.projectedPercentAtReset {
            parts.append("\(Int(projected.rounded()))% by reset")
        }
        if let detail = insights.weeklyPace.detail, detail.isEmpty == false {
            parts.append(detail)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    @ViewBuilder
    private func insightRow(
        title: String,
        message: String,
        detail: String?,
        tone: CodexUsageInsightTone
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Circle()
                .fill(tone.color)
                .frame(width: 7, height: 7)

            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            if let detail, detail.isEmpty == false {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Text(message)
                .font(.caption.monospacedDigit().weight(.semibold))
                .multilineTextAlignment(.trailing)
                .lineLimit(1)
        }
        .padding(.vertical, 1)
    }
}
#endif
