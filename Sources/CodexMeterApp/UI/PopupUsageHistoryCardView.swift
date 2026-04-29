#if os(macOS)
import SwiftUI
import CodexMeterCore

struct UsageHistoryCardView: View {
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    let samples: [CodexUsageHistorySample]
    let showsChart: Bool
    let historyMode: PopupHistoryMode
    let showPaceConfidence: Bool
    let resetDisplayStyle: CodexResetDisplayStyle
    let onHistoryModeChange: (PopupHistoryMode) -> Void

    private let fiveHourPoints: [CodexUsageHistoryPoint]
    private let weeklyPoints: [CodexUsageHistoryPoint]
    private let currentCycleFiveHourPoints: [CodexUsageHistoryPoint]
    private let currentCycleWeeklyPoints: [CodexUsageHistoryPoint]
    private let fiveHourForecast: CodexUsageForecast
    private let weeklyForecast: CodexUsageForecast
    private let monthlyHistory: CodexMonthlyUsageHistory?

    init(
        samples: [CodexUsageHistorySample],
        showsChart: Bool,
        historyMode: PopupHistoryMode,
        showPaceConfidence: Bool,
        resetDisplayStyle: CodexResetDisplayStyle,
        onHistoryModeChange: @escaping (PopupHistoryMode) -> Void
    ) {
        self.samples = samples
        self.showsChart = showsChart
        self.historyMode = historyMode
        self.showPaceConfidence = showPaceConfidence
        self.resetDisplayStyle = resetDisplayStyle
        self.onHistoryModeChange = onHistoryModeChange
        self.fiveHourPoints = CodexUsageHistoryAnalytics.points(from: samples, series: .fiveHour)
        self.weeklyPoints = CodexUsageHistoryAnalytics.points(from: samples, series: .weekly)
        self.currentCycleFiveHourPoints = CodexUsageHistoryAnalytics.currentCyclePoints(from: samples, series: .fiveHour)
        self.currentCycleWeeklyPoints = CodexUsageHistoryAnalytics.currentCyclePoints(from: samples, series: .weekly)
        self.fiveHourForecast = CodexUsageHistoryAnalytics.forecast(from: samples, series: .fiveHour)
        self.weeklyForecast = CodexUsageHistoryAnalytics.forecast(from: samples, series: .weekly)
        self.monthlyHistory = CodexUsageHistoryAnalytics.monthlyHistory(from: samples, series: .weekly)
    }

    var body: some View {
        GlassCard(style: .secondary) {
            VStack(alignment: .leading, spacing: 13) {
                header
                forecastSummary
                contentSection
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Usage history")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(CodexTheme.text)

            Spacer()

            Picker("History mode", selection: Binding(
                get: { historyMode },
                set: { onHistoryModeChange($0) }
            )) {
                Text("Peaks").tag(PopupHistoryMode.dailyPeaks)
                Text("Cycle").tag(PopupHistoryMode.thisCycle)
                Text("Month").tag(PopupHistoryMode.monthly)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 198)
        }
    }

    private var weeklySeriesColor: Color {
        Color(red: 0.35, green: 0.77, blue: 0.47).opacity(0.86)
    }

    private var forecastSummary: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Weekly pace")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(CodexTheme.muted)

                Spacer(minLength: 8)

                Text(forecastHeadline(for: weeklyForecast))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(forecastMessageColor)
                    .contentTransition(accessibilityReduceMotion ? .identity : .opacity)
                    .lineLimit(1)
            }

            if showPaceConfidence, let detail = forecastDetail(for: weeklyForecast) {
                Text(detail)
                    .font(.system(size: 11.5))
                    .foregroundStyle(CodexTheme.dim)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if showPaceConfidence,
               historyMode == .dailyPeaks,
               let rangeText = likelyRangeText(for: weeklyForecast) {
                Text(rangeText)
                    .font(.system(size: 11.5))
                    .foregroundStyle(CodexTheme.dim)
                    .lineLimit(1)
                    .contentTransition(accessibilityReduceMotion ? .identity : .opacity)
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
                .foregroundStyle(CodexTheme.dim)
            }

        }
    }

    private var forecastMessageColor: Color {
        switch weeklyForecast.confidence {
        case .tooEarly, .learning, .estimatedFromHistory:
            return CodexTheme.text.opacity(0.84)
        case .patternMatched, .machineLearned, .stable:
            return weeklyForecast.tone.color.opacity(0.95)
        case .volatile:
            return CodexTheme.amber
        }
    }

    private func likelyRangeText(for forecast: CodexUsageForecast) -> String? {
        guard let lower = forecast.likelyLowerPercent,
              let upper = forecast.likelyUpperPercent,
              upper - lower >= 2 else {
            return nil
        }

        return "Likely \(Int(lower.rounded()))-\(Int(upper.rounded()))% by reset"
    }

    private func forecastHeadline(for forecast: CodexUsageForecast) -> String {
        switch forecast.confidence {
        case .tooEarly, .learning, .estimatedFromHistory:
            return forecast.message
        case .patternMatched:
            return "Pattern matched"
        case .machineLearned:
            return "ML tuned"
        case .stable:
            return "Stable forecast"
        case .volatile:
            return "Volatile forecast"
        }
    }

    private func forecastDetail(for forecast: CodexUsageForecast) -> String? {
        guard let detail = forecast.detail else { return nil }
        let parts = detail
            .components(separatedBy: " · ")
            .filter { part in
                part != forecast.confidence.label
                    && part.hasSuffix("samples") == false
                    && part.hasSuffix("cycles") == false
            }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var contentSection: some View {
        switch historyMode {
        case .dailyPeaks:
            VStack(alignment: .leading, spacing: 10) {
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
                if showsChart {
                    MiniUsageHistoryGraph(
                        fiveHourPoints: currentCycleFiveHourPoints,
                        weeklyPoints: currentCycleWeeklyPoints,
                        weeklyColor: weeklySeriesColor
                    )
                }

                HStack(spacing: 10) {
                    if let range = likelyRangeChipValue(for: weeklyForecast) {
                        cycleChip(label: "Range", value: range)
                    }
                    cycleChip(label: "Data", value: "\(weeklyForecast.sampleCount) samples")
                    if let resetAt = weeklyForecast.resetAt {
                        cycleChip(
                            label: "Reset",
                            value: resetChipValue(for: resetAt)
                        )
                    }
                }
            }
        case .monthly:
            VStack(alignment: .leading, spacing: 10) {
                if showsChart {
                    MiniUsageHistoryGraph(
                        fiveHourPoints: [],
                        weeklyPoints: weeklyPoints,
                        weeklyColor: weeklySeriesColor
                    )
                }

                HStack(spacing: 10) {
                    if let monthlyHistory {
                        cycleChip(label: "Peak", value: "\(Int(monthlyHistory.peakPercent.rounded()))%")
                        cycleChip(label: "Average", value: "\(Int(monthlyHistory.averageDailyPeakPercent.rounded()))%")
                        cycleChip(label: "Data", value: "\(monthlyHistory.dayCount) days")
                    } else {
                        cycleChip(label: "Data", value: "No samples")
                    }
                }
            }
        }
    }

    private func likelyRangeChipValue(for forecast: CodexUsageForecast) -> String? {
        guard let lower = forecast.likelyLowerPercent,
              let upper = forecast.likelyUpperPercent,
              upper - lower >= 2 else {
            return nil
        }
        return "\(Int(lower.rounded()))-\(Int(upper.rounded()))%"
    }

    private func legendItem(label: String, value: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)

            Text(label)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(CodexTheme.muted)
                .lineLimit(1)

            Text(value)
                .font(.system(size: 11.5, weight: .semibold).monospacedDigit())
                .foregroundStyle(CodexTheme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
        .padding(.horizontal, 10)
        .frame(height: GlassTokens.pillHeight)
        .background(CodexTheme.control, in: RoundedRectangle(cornerRadius: GlassTokens.pillRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: GlassTokens.pillRadius, style: .continuous)
                .strokeBorder(CodexTheme.hairlineStrong, lineWidth: 1)
        }
    }

    private func cycleChip(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(CodexTheme.dim)
                .textCase(.uppercase)
                .tracking(0.9)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .allowsTightening(true)

            Text(value)
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(CodexTheme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .allowsTightening(true)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, minHeight: GlassTokens.infoChipHeight, alignment: .leading)
        .background(CodexTheme.control, in: RoundedRectangle(cornerRadius: GlassTokens.infoChipRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: GlassTokens.infoChipRadius, style: .continuous)
                .strokeBorder(CodexTheme.hairlineStrong, lineWidth: 1)
        }
    }

    private func resetChipValue(for resetAt: Date) -> String {
        let text = resetDisplayStyle.resetText(now: .init(), resetAt: resetAt)
        let prefix = "resets "
        if text.hasPrefix(prefix) {
            return String(text.dropFirst(prefix.count))
        }
        return text
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
                    .fill(Color.white.opacity(0.06))

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
                    .fill(Color.white.opacity(0.96))
                    .frame(width: 12, height: 12)
                    .overlay {
                        Circle()
                            .stroke(CodexTheme.accent, lineWidth: 2)
                    }
                    .shadow(color: .black.opacity(0.36), radius: 3, y: 1)
                    .offset(x: max(0, currentX - 6))

                RoundedRectangle(cornerRadius: 1)
                    .fill(CodexTheme.amber)
                    .frame(width: 2, height: 12)
                    .shadow(color: CodexTheme.amber.opacity(0.7), radius: 6)
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
