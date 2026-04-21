#if os(macOS)
import SwiftUI
import CodexMeterCore

struct UsageHistoryCardView: View {
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    let samples: [CodexUsageHistorySample]
    let showsChart: Bool
    let historyMode: PopupHistoryMode
    let showPaceConfidence: Bool
    let onHistoryModeChange: (PopupHistoryMode) -> Void

    private let fiveHourPoints: [CodexUsageHistoryPoint]
    private let weeklyPoints: [CodexUsageHistoryPoint]
    private let currentCycleFiveHourPoints: [CodexUsageHistoryPoint]
    private let currentCycleWeeklyPoints: [CodexUsageHistoryPoint]
    private let fiveHourForecast: CodexUsageForecast
    private let weeklyForecast: CodexUsageForecast

    init(
        samples: [CodexUsageHistorySample],
        showsChart: Bool,
        historyMode: PopupHistoryMode,
        showPaceConfidence: Bool,
        onHistoryModeChange: @escaping (PopupHistoryMode) -> Void
    ) {
        self.samples = samples
        self.showsChart = showsChart
        self.historyMode = historyMode
        self.showPaceConfidence = showPaceConfidence
        self.onHistoryModeChange = onHistoryModeChange
        self.fiveHourPoints = CodexUsageHistoryAnalytics.points(from: samples, series: .fiveHour)
        self.weeklyPoints = CodexUsageHistoryAnalytics.points(from: samples, series: .weekly)
        self.currentCycleFiveHourPoints = CodexUsageHistoryAnalytics.currentCyclePoints(from: samples, series: .fiveHour)
        self.currentCycleWeeklyPoints = CodexUsageHistoryAnalytics.currentCyclePoints(from: samples, series: .weekly)
        self.fiveHourForecast = CodexUsageHistoryAnalytics.forecast(from: samples, series: .fiveHour)
        self.weeklyForecast = CodexUsageHistoryAnalytics.forecast(from: samples, series: .weekly)
    }

    var body: some View {
        GlassCard(style: .secondary) {
            VStack(alignment: .leading, spacing: 10) {
                header
                forecastSummary
                contentSection
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Usage history")
                .font(.headline)

            Spacer()

            Picker("History mode", selection: Binding(
                get: { historyMode },
                set: { onHistoryModeChange($0) }
            )) {
                Text("Peaks").tag(PopupHistoryMode.dailyPeaks)
                Text("Cycle").tag(PopupHistoryMode.thisCycle)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 148)
        }
    }

    private var weeklySeriesColor: Color {
        Color(red: 0.35, green: 0.77, blue: 0.47).opacity(0.86)
    }

    private var forecastSummary: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Weekly pace")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer(minLength: 8)

                Text(weeklyForecast.message)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(forecastMessageColor)
                    .contentTransition(accessibilityReduceMotion ? .identity : .opacity)
                    .lineLimit(1)
            }

            if showPaceConfidence, let detail = weeklyForecast.detail {
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let current = weeklyForecast.currentPercent,
               let projected = weeklyForecast.projectedPercentAtReset {
                ForecastUsageBar(
                    currentPercent: current,
                    projectedPercent: projected
                )

                HStack(spacing: 8) {
                    Text("Now \(Int(current.rounded()))%")
                    Spacer()
                    Text("By reset \(Int(projected.rounded()))%")
                }
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
            }
        }
    }

    private var forecastMessageColor: Color {
        switch weeklyForecast.confidence {
        case .tooEarly, .learning, .estimatedFromHistory:
            return .primary.opacity(0.84)
        case .stable:
            return weeklyForecast.tone.color.opacity(0.9)
        case .volatile:
            return .orange.opacity(0.9)
        }
    }

    @ViewBuilder
    private var contentSection: some View {
        switch historyMode {
        case .dailyPeaks:
            VStack(alignment: .leading, spacing: 10) {
                Text("Last 30 days")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

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
        case .thisCycle:
            VStack(alignment: .leading, spacing: 10) {
                Text("Current cycle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                if showsChart {
                    MiniUsageHistoryGraph(
                        fiveHourPoints: currentCycleFiveHourPoints,
                        weeklyPoints: currentCycleWeeklyPoints,
                        weeklyColor: weeklySeriesColor
                    )
                }

                HStack(spacing: 10) {
                    cycleChip(label: "Confidence", value: weeklyForecast.confidence.label)
                    cycleChip(label: "Samples", value: "\(weeklyForecast.sampleCount)")
                    if let resetAt = weeklyForecast.resetAt {
                        cycleChip(
                            label: "Reset",
                            value: CodexFormatting.relativeResetText(now: .init(), resetAt: resetAt)
                        )
                    }
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
        .background(.white.opacity(0.12), in: Capsule())
    }

    private func cycleChip(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(value)
                .font(.caption.monospacedDigit().weight(.semibold))
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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

                Circle()
                    .fill(Color.white.opacity(0.92))
                    .frame(width: 8, height: 8)
                    .overlay {
                        Circle()
                            .stroke(Color.blue.opacity(0.35), lineWidth: 1)
                    }
                    .offset(x: max(0, currentX - 4))

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
