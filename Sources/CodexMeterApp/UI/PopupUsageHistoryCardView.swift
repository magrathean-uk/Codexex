#if os(macOS)
import SwiftUI

struct UsageHistoryCardView: View {
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    let samples: [CodexUsageHistorySample]
    let showsChart: Bool

    private let fiveHourPoints: [CodexUsageHistoryPoint]
    private let weeklyPoints: [CodexUsageHistoryPoint]
    private let fiveHourForecast: CodexUsageForecast
    private let weeklyForecast: CodexUsageForecast

    init(samples: [CodexUsageHistorySample], showsChart: Bool) {
        self.samples = samples
        self.showsChart = showsChart
        self.fiveHourPoints = CodexUsageHistoryAnalytics.points(from: samples, series: .fiveHour)
        self.weeklyPoints = CodexUsageHistoryAnalytics.points(from: samples, series: .weekly)
        self.fiveHourForecast = CodexUsageHistoryAnalytics.forecast(from: samples, series: .fiveHour)
        self.weeklyForecast = CodexUsageHistoryAnalytics.forecast(from: samples, series: .weekly)
    }

    var body: some View {
        GlassCard(style: .secondary) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Usage history")
                        .font(.headline)

                    Spacer()

                    Text("Last 30 days")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                forecastSummary

                if showsChart {
                    MiniUsageHistoryGraph(
                        fiveHourPoints: fiveHourPoints,
                        weeklyPoints: weeklyPoints,
                        weeklyColor: weeklySeriesColor
                    )
                }

                HStack(spacing: 10) {
                    legendItem(
                        label: "5H",
                        value: PopupPresentation.historyLegendValue(for: fiveHourForecast),
                        color: limitAccentColor(for: .codex)
                    )
                    legendItem(
                        label: "Weekly",
                        value: PopupPresentation.historyLegendValue(for: weeklyForecast),
                        color: weeklySeriesColor
                    )
                }
            }
        }
    }

    private var weeklySeriesColor: Color {
        Color.green.opacity(0.82)
    }

    private var forecastSummary: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let current = weeklyForecast.currentPercent,
               let projected = weeklyForecast.projectedPercentAtReset {
                ForecastUsageBar(
                    currentPercent: current,
                    projectedPercent: projected
                )
            }

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(weeklyForecast.message)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(weeklyForecast.tone.color)
                    .contentTransition(accessibilityReduceMotion ? .identity : .opacity)

                if let detail = weeklyForecast.detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }

    private func legendItem(label: String, value: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)

            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(value)
                .font(.footnote.weight(.medium))
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.white.opacity(0.16), in: Capsule())
    }
}

private struct MiniUsageHistoryGraph: View {
    let fiveHourPoints: [CodexUsageHistoryPoint]
    let weeklyPoints: [CodexUsageHistoryPoint]
    let weeklyColor: Color

    var body: some View {
        Canvas { context, size in
            drawFiveHourBars(in: &context, size: size)
            drawWeeklyLine(in: &context, size: size)
        }
        .frame(height: 42)
        .allowsHitTesting(false)
    }

    private func drawFiveHourBars(in context: inout GraphicsContext, size: CGSize) {
        let points = fiveHourPoints
        guard points.isEmpty == false else { return }

        for (index, point) in points.enumerated() {
            let rect = PopupPresentation.historyBarRect(
                usedPercent: point.usedPercent,
                index: index,
                count: points.count,
                size: size
            )
            let path = Path(
                roundedRect: rect,
                cornerRadius: min(2.5, rect.width / 2)
            )
            context.fill(path, with: .color(limitAccentColor(for: .codex).opacity(0.45)))
        }
    }

    private func drawWeeklyLine(in context: inout GraphicsContext, size: CGSize) {
        let points = weeklyPoints
        guard points.count >= 2, size.width > 0, size.height > 0 else { return }

        var path = Path()
        for (index, point) in points.enumerated() {
            let x = CGFloat(index) / CGFloat(points.count - 1) * size.width
            let clamped = min(max(point.usedPercent, 0), 100)
            let y = size.height - (size.height * CGFloat(clamped / 100))
            let cgPoint = CGPoint(x: x, y: y)

            if index == 0 {
                path.move(to: cgPoint)
            } else {
                path.addLine(to: cgPoint)
            }
        }

        context.stroke(
            path,
            with: .color(weeklyColor),
            style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round)
        )
    }
}

private struct ForecastUsageBar: View {
    let currentPercent: Double
    let projectedPercent: Double

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let currentX = width * (currentPercent / 100).clamped(to: 0...1)
            let projectedX = width * (projectedPercent / 100).clamped(to: 0...1)

            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(limitTrackColor(for: .codex))

                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: limitGradient(for: .codex),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(10, currentX))

                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.white.opacity(0.85))
                    .frame(width: 2, height: 12)
                    .offset(x: max(0, projectedX - 1))
            }
        }
        .frame(height: 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Projected usage by reset")
        .accessibilityValue("\(Int(currentPercent.rounded()))% used, projected \(Int(projectedPercent.rounded()))% by reset")
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
#endif
