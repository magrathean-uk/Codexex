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
    private let fiveHourForecast: CodexUsageForecast?
    private let weeklyForecast: CodexUsageForecast
    private let monthlyHistory: CodexMonthlyUsageHistory?

    init(
        samples: [CodexUsageHistorySample],
        showsChart: Bool,
        historyMode: PopupHistoryMode,
        showPaceConfidence: Bool,
        showFiveHour: Bool,
        resetDisplayStyle: CodexResetDisplayStyle,
        onHistoryModeChange: @escaping (PopupHistoryMode) -> Void
    ) {
        self.samples = samples
        self.showsChart = showsChart
        self.historyMode = historyMode
        self.showPaceConfidence = showPaceConfidence
        self.resetDisplayStyle = resetDisplayStyle
        self.onHistoryModeChange = onHistoryModeChange
        let visibleSeries = PopupPresentation.visibleHistorySeries(showFiveHour: showFiveHour)
        let includesFiveHour = visibleSeries.contains { series in
            if case .fiveHour = series { return true }
            return false
        }
        self.fiveHourPoints = includesFiveHour
            ? CodexUsageHistoryAnalytics.points(from: samples, series: .fiveHour)
            : []
        self.weeklyPoints = CodexUsageHistoryAnalytics.points(from: samples, series: .weekly)
        self.currentCycleFiveHourPoints = includesFiveHour
            ? CodexUsageHistoryAnalytics.currentCyclePoints(from: samples, series: .fiveHour)
            : []
        self.currentCycleWeeklyPoints = CodexUsageHistoryAnalytics.currentCyclePoints(from: samples, series: .weekly)
        self.fiveHourForecast = includesFiveHour
            ? CodexUsageHistoryAnalytics.forecast(from: samples, series: .fiveHour)
            : nil
        self.weeklyForecast = CodexUsageHistoryAnalytics.forecast(from: samples, series: .weekly)
        self.monthlyHistory = CodexUsageHistoryAnalytics.monthlyHistory(from: samples, series: .weekly)
    }

    var body: some View {
        PopupPlainSection {
            VStack(alignment: .leading, spacing: 6) {
                forecastSummary
                contentSection
            }
        }
    }

    private var weeklySeriesColor: Color {
        Color(red: 0.35, green: 0.77, blue: 0.47).opacity(0.86)
    }

    private var forecastSummary: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Pace")
                    .font(.system(size: GlassTokens.popupMetaFontSize - 1, weight: .medium))
                    .foregroundStyle(CodexTheme.dim)
                    .textCase(.uppercase)

                Text(forecastHeadline(for: weeklyForecast))
                    .font(.system(size: GlassTokens.popupMetaFontSize, weight: .semibold))
                    .foregroundStyle(forecastMessageColor)
                    .lineLimit(1)

                if let context = compactForecastContext(for: weeklyForecast) {
                    Text(context)
                        .font(.system(size: GlassTokens.popupMetaFontSize - 1, weight: .medium))
                        .foregroundStyle(CodexTheme.dim)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                }

                Spacer(minLength: 6)

                PopupHistoryModeSelector(
                    historyMode: historyMode,
                    onHistoryModeChange: onHistoryModeChange
                )
            }
            .lineLimit(1)

            if shouldShowProjectionBar(for: weeklyForecast),
               historyMode != .dailyPeaks,
               let current = weeklyForecast.currentPercent,
               let projected = weeklyForecast.projectedPercentAtReset {
                ForecastUsageBar(
                    currentPercent: current,
                    projectedPercent: projected
                )

                Text("\(Int(current.rounded()))% now · \(Int(projected.rounded()))% reset")
                    .font(.system(size: GlassTokens.popupMetaFontSize - 1, weight: .medium))
                    .foregroundStyle(CodexTheme.dim)
                    .lineLimit(1)
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

    private func compactForecastContext(for forecast: CodexUsageForecast) -> String? {
        guard showPaceConfidence else { return nil }
        if historyMode == .dailyPeaks, let rangeText = compactLikelyRangeText(for: forecast) {
            return rangeText
        }
        return forecastDetail(for: forecast)
    }

    private func compactLikelyRangeText(for forecast: CodexUsageForecast) -> String? {
        guard let lower = forecast.likelyLowerPercent,
              let upper = forecast.likelyUpperPercent,
              upper - lower >= 2 else {
            return nil
        }

        return "\(Int(lower.rounded()))-\(Int(upper.rounded()))% reset"
    }

    private func forecastHeadline(for forecast: CodexUsageForecast) -> String {
        if isZeroPressureForecast(forecast) {
            return "No pressure"
        }
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
        if isZeroPressureForecast(forecast) {
            return nil
        }
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

    private func shouldShowProjectionBar(for forecast: CodexUsageForecast) -> Bool {
        isZeroPressureForecast(forecast) == false
    }

    private func isZeroPressureForecast(_ forecast: CodexUsageForecast) -> Bool {
        let current = forecast.currentPercent ?? 0
        let projected = forecast.projectedPercentAtReset ?? 0
        let upper = forecast.likelyUpperPercent ?? projected
        return max(current, projected, upper) < 0.5
    }

    @ViewBuilder
    private var contentSection: some View {
        switch historyMode {
        case .dailyPeaks:
            VStack(alignment: .leading, spacing: 6) {
                if showsChart {
                    MiniUsageHistoryGraph(
                        fiveHourPoints: fiveHourPoints,
                        weeklyPoints: weeklyPoints,
                        weeklyColor: weeklySeriesColor,
                        axisStartLabel: "30d",
                        axisMiddleLabel: "15d",
                        axisEndLabel: "Today"
                    )
                }

                HStack(spacing: 8) {
                    if let fiveHourForecast {
                        legendItem(
                            label: "5H",
                            value: PopupPresentation.historyLegendValue(for: fiveHourForecast),
                            color: limitAccentColor(for: .codex)
                        )
                    }
                    legendItem(
                        label: "Weekly",
                        value: PopupPresentation.historyLegendValue(for: weeklyForecast),
                        color: weeklySeriesColor
                    )
                }
            }
        case .thisCycle:
            VStack(alignment: .leading, spacing: 6) {
                if showsChart {
                    MiniUsageHistoryGraph(
                        fiveHourPoints: currentCycleFiveHourPoints,
                        weeklyPoints: currentCycleWeeklyPoints,
                        weeklyColor: weeklySeriesColor,
                        axisStartLabel: "Start",
                        axisMiddleLabel: "Mid",
                        axisEndLabel: "Now"
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
            VStack(alignment: .leading, spacing: 6) {
                if showsChart {
                    MiniUsageHistoryGraph(
                        fiveHourPoints: [],
                        weeklyPoints: weeklyPoints,
                        weeklyColor: weeklySeriesColor,
                        axisStartLabel: "30d",
                        axisMiddleLabel: "15d",
                        axisEndLabel: "Today"
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
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 5, height: 5)

            Text(label)
                .font(.system(size: GlassTokens.popupMetaFontSize - 1, weight: .medium))
                .foregroundStyle(CodexTheme.muted)
                .lineLimit(1)

            Text(value)
                .font(.system(size: GlassTokens.popupMetaFontSize - 1, weight: .medium))
                .foregroundStyle(CodexTheme.dim)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
        .frame(height: 16)
    }

    private func cycleChip(label: String, value: String) -> some View {
        HStack(spacing: 3) {
            Text(label.uppercased())
                .font(.system(size: GlassTokens.popupMetaFontSize - 2, weight: .semibold))
                .foregroundStyle(CodexTheme.dim)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .allowsTightening(true)

            Text(value)
                .font(.system(size: GlassTokens.popupMetaFontSize - 1, weight: .medium))
                .foregroundStyle(CodexTheme.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .allowsTightening(true)
        }
        .frame(height: 16, alignment: .leading)
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

struct PopupHistoryModeSelector: View {
    let historyMode: PopupHistoryMode
    let onHistoryModeChange: (PopupHistoryMode) -> Void

    var body: some View {
        Menu {
            ForEach(PopupHistoryMode.allCases, id: \.self) { mode in
                Button {
                    onHistoryModeChange(mode)
                } label: {
                    if mode == historyMode {
                        Label(mode.title, systemImage: "checkmark")
                    } else {
                        Text(mode.title)
                    }
                }
                .accessibilityLabel(mode.title)
                .accessibilityValue(mode == historyMode ? "Selected" : "")
            }
        } label: {
            HStack(spacing: 5) {
                Text("View:")
                    .font(.system(size: GlassTokens.popupMetaFontSize - 1, weight: .medium))
                    .foregroundStyle(CodexTheme.dim)

                Text(historyMode.popupCompactTitle)
                    .font(.system(size: GlassTokens.popupMetaFontSize, weight: .semibold))
                    .foregroundStyle(CodexTheme.accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(CodexTheme.muted)
            }
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background {
                RoundedRectangle(cornerRadius: GlassTokens.pillRadius, style: .continuous)
                    .fill(CodexTheme.control.opacity(0.52))
            }
            .overlay {
                RoundedRectangle(cornerRadius: GlassTokens.pillRadius, style: .continuous)
                    .stroke(CodexTheme.accent.opacity(0.32), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .fixedSize(horizontal: true, vertical: true)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("History mode")
        .accessibilityValue(historyMode.title)
    }
}

private extension PopupHistoryMode {
    var popupCompactTitle: String {
        switch self {
        case .dailyPeaks:
            return "Peaks"
        case .thisCycle:
            return "Cycle"
        case .monthly:
            return "Month"
        }
    }
}

private struct MiniUsageHistoryGraph: View {
    let fiveHourPoints: [CodexUsageHistoryPoint]
    let weeklyPoints: [CodexUsageHistoryPoint]
    let weeklyColor: Color
    let axisStartLabel: String
    let axisMiddleLabel: String
    let axisEndLabel: String

    var body: some View {
        VStack(spacing: 2) {
            Canvas { context, size in
                drawGrid(in: &context, size: size)
                drawFiveHourBars(in: &context, size: size)
                drawWeeklyLine(in: &context, size: size)
            }
            .frame(height: chartHeight)
            .allowsHitTesting(false)

            HStack {
                Text(axisStartLabel)
                Spacer()
                Text(axisMiddleLabel)
                Spacer()
                Text(axisEndLabel)
            }
            .font(.system(size: GlassTokens.popupMetaFontSize - 2, weight: .medium))
            .foregroundStyle(CodexTheme.dim)
        }
        .frame(height: GlassTokens.historyGraphHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            PopupUsageHistoryAccessibility.graphAccessibilityLabel(
                fiveHourPoints: fiveHourPoints,
                weeklyPoints: weeklyPoints
            )
        )
        .accessibilityValue(
            PopupUsageHistoryAccessibility.graphAccessibilityValue(
                fiveHourPoints: fiveHourPoints,
                weeklyPoints: weeklyPoints,
                axisStartLabel: axisStartLabel,
                axisEndLabel: axisEndLabel
            )
        )
        .accessibilityIdentifier("mac.popup.history.graph")
    }

    private var chartHeight: CGFloat {
        max(30, GlassTokens.historyGraphHeight - 12)
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

enum PopupUsageHistoryAccessibility {
    static func graphAccessibilityLabel(
        fiveHourPoints: [CodexUsageHistoryPoint],
        weeklyPoints: [CodexUsageHistoryPoint]
    ) -> String {
        fiveHourPoints.isEmpty ? "Weekly usage history" : "5-hour and weekly usage history"
    }

    static func graphAccessibilityValue(
        fiveHourPoints: [CodexUsageHistoryPoint],
        weeklyPoints: [CodexUsageHistoryPoint],
        axisStartLabel: String,
        axisEndLabel: String
    ) -> String {
        let range = "\(axisStartLabel) to \(axisEndLabel)"
        let summaries = [
            seriesSummary(name: "5-hour", points: fiveHourPoints),
            seriesSummary(name: "Weekly", points: weeklyPoints)
        ].compactMap { $0 }

        guard summaries.isEmpty == false else {
            return "\(range). No usage data."
        }

        return ([range] + summaries).joined(separator: ". ") + "."
    }

    private static func seriesSummary(name: String, points: [CodexUsageHistoryPoint]) -> String? {
        guard let latest = points.max(by: { $0.date < $1.date }),
              let peak = points.max(by: { $0.usedPercent < $1.usedPercent }) else {
            return nil
        }

        return "\(name) latest \(percentText(latest.usedPercent)), peak \(percentText(peak.usedPercent))"
    }

    private static func percentText(_ percent: Double) -> String {
        "\(Int(percent.rounded()))%"
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
