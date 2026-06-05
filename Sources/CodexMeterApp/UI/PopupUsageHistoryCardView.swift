#if os(macOS)
import SwiftUI
import CodexMeterCore

struct UsageHistoryCardView: View {
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
        PopupPlainSection {
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
                .font(.system(size: GlassTokens.popupBodyFontSize, weight: .semibold))
                .foregroundStyle(CodexTheme.text)

            Spacer()

            HStack(spacing: 3) {
                ForEach(PopupHistoryMode.allCases, id: \.self) { mode in
                    Button {
                        onHistoryModeChange(mode)
                    } label: {
                        Text(compactTitle(for: mode))
                            .font(.system(size: GlassTokens.popupMetaFontSize, weight: mode == historyMode ? .semibold : .medium))
                            .foregroundStyle(mode == historyMode ? CodexTheme.text : CodexTheme.muted)
                            .padding(.horizontal, 8)
                            .frame(height: 24)
                            .background(
                                mode == historyMode ? CodexTheme.control.opacity(0.95) : Color.clear,
                                in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3)
            .background(CodexTheme.control.opacity(0.58), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private func compactTitle(for mode: PopupHistoryMode) -> String {
        switch mode {
        case .dailyPeaks:
            return "Peaks"
        case .thisCycle:
            return "Cycle"
        case .monthly:
            return "Month"
        }
    }

    private var weeklySeriesColor: Color {
        Color(red: 0.35, green: 0.77, blue: 0.47).opacity(0.86)
    }

    private var forecastSummary: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Weekly pace")
                    .font(.system(size: GlassTokens.popupMetaFontSize, weight: .medium))
                    .foregroundStyle(CodexTheme.muted)

                Spacer(minLength: 8)

                Text(forecastHeadline(for: weeklyForecast))
                    .font(.system(size: GlassTokens.popupMetaFontSize, weight: .semibold))
                    .foregroundStyle(forecastMessageColor)
                    .lineLimit(1)
            }

            if showPaceConfidence, let detail = forecastDetail(for: weeklyForecast) {
                Text(detail)
                    .font(.system(size: GlassTokens.popupMetaFontSize))
                    .foregroundStyle(CodexTheme.dim)
                    .lineLimit(1)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if showPaceConfidence,
               historyMode == .dailyPeaks,
               let rangeText = likelyRangeText(for: weeklyForecast) {
                Text(rangeText)
                    .font(.system(size: GlassTokens.popupMetaFontSize))
                    .foregroundStyle(CodexTheme.dim)
                    .lineLimit(1)
            }

            if historyMode != .dailyPeaks,
               let current = weeklyForecast.currentPercent,
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
                .font(.system(size: GlassTokens.popupMetaFontSize))
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
            VStack(alignment: .leading, spacing: 9) {
                if showsChart {
                    MiniUsageHistoryGraph(
                        fiveHourPoints: fiveHourPoints,
                        weeklyPoints: weeklyPoints,
                        weeklyColor: weeklySeriesColor
                    )
                }

                HStack(spacing: 8) {
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
            VStack(alignment: .leading, spacing: 9) {
                if showsChart {
                    MiniUsageHistoryGraph(
                        fiveHourPoints: currentCycleFiveHourPoints,
                        weeklyPoints: currentCycleWeeklyPoints,
                        weeklyColor: weeklySeriesColor
                    )
                }

                HStack(spacing: 8) {
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
            VStack(alignment: .leading, spacing: 9) {
                if showsChart {
                    MiniUsageHistoryGraph(
                        fiveHourPoints: [],
                        weeklyPoints: weeklyPoints,
                        weeklyColor: weeklySeriesColor
                    )
                }

                HStack(spacing: 8) {
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
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: GlassTokens.popupMetaFontSize, weight: .semibold))
                .foregroundStyle(color)
                .lineLimit(1)

            Text(value)
                .font(.system(size: GlassTokens.popupMetaFontSize, weight: .semibold))
                .foregroundStyle(CodexTheme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
        .frame(height: GlassTokens.pillHeight)
    }

    private func cycleChip(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: GlassTokens.popupMetaFontSize, weight: .semibold))
                .foregroundStyle(CodexTheme.dim)
                .textCase(.uppercase)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .allowsTightening(true)

            Text(value)
                .font(.system(size: GlassTokens.popupBodyFontSize, weight: .semibold))
                .foregroundStyle(CodexTheme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .allowsTightening(true)
        }
        .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
    }

    private func resetChipValue(for resetAt: Date) -> String {
        let text = CodexResetTextFormatting.resetText(style: resetDisplayStyle, now: Date(), resetAt: resetAt)
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
        HStack(alignment: .top, spacing: 6) {
            VStack(alignment: .trailing, spacing: 0) {
                Text("100%")
                Spacer()
                Text("50%")
                Spacer()
                Text("0%")
            }
                .font(.system(size: GlassTokens.popupMetaFontSize, weight: .medium))
                .foregroundStyle(CodexTheme.dim)
                .frame(width: 34, height: GlassTokens.historyGraphHeight - 22)

            VStack(spacing: 3) {
                Canvas { context, size in
                    drawGrid(in: &context, size: size)
                    drawFiveHourBars(in: &context, size: size)
                    drawWeeklyLine(in: &context, size: size)
                }
                .frame(height: GlassTokens.historyGraphHeight - 22)
                .allowsHitTesting(false)

                HStack {
                    ForEach(["7d", "6d", "5d", "4d", "3d", "2d", "1d", "Today"], id: \.self) { label in
                        Text(label)
                            .frame(maxWidth: .infinity)
                    }
                }
                .font(.system(size: GlassTokens.popupMetaFontSize, weight: .medium))
                .foregroundStyle(CodexTheme.dim)
            }
        }
        .frame(height: GlassTokens.historyGraphHeight)
    }

    private func drawGrid(in context: inout GraphicsContext, size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }

        for ratio in [0.0, 0.5, 1.0] {
            let y = size.height * CGFloat(ratio)
            var path = Path()
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: size.width, y: y))
            context.stroke(
                path,
                with: .color(CodexTheme.hairline),
                style: StrokeStyle(lineWidth: 1)
            )
        }
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
            context.fill(
                path,
                with: .linearGradient(
                    Gradient(colors: [
                        limitAccentColor(for: .codex).opacity(0.72),
                        CodexTheme.spark.opacity(0.48)
                    ]),
                    startPoint: CGPoint(x: rect.midX, y: rect.minY),
                    endPoint: CGPoint(x: rect.midX, y: rect.maxY)
                )
            )
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
            with: .color(weeklyColor.opacity(0.86)),
            style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round)
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
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(CodexTheme.control.opacity(0.72))

                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: limitGradient(for: .codex),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(10, currentX))

                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(CodexTheme.window)
                    .frame(width: 12, height: 12)
                    .overlay {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .stroke(CodexTheme.accent, lineWidth: 2)
                    }
                    .offset(x: max(0, currentX - 6))

                RoundedRectangle(cornerRadius: 1)
                    .fill(CodexTheme.amber)
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
