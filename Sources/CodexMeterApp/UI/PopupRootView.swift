#if os(macOS)
import Foundation
import SwiftUI
import CodexMeterCore
import Observation

struct PopupRootView: View {
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @Bindable var model: CodexMenuBarModel
    var onOpenSettings: () -> Void = {}

    var body: some View {
        GlassEffectContainer(spacing: GlassTokens.sectionSpacing) {
            VStack(alignment: .leading, spacing: GlassTokens.contentSpacing) {
                if model.previewModeEnabled {
                    previewBadge
                }

                if model.snapshot != nil {
                    ForEach(primaryLimitPresentations) { presentation in
                        limitCard(for: presentation)
                    }

                    ForEach(activeSecondaryLimitPresentations) { presentation in
                        limitCard(for: presentation)
                    }

                    ForEach(supplementalSections, id: \.self) { section in
                        supplementalCard(for: section)
                    }

                    ForEach(compactSecondaryLimitPresentations) { presentation in
                        limitCard(for: presentation)
                    }
                } else {
                    emptyCard
                }

                footer
            }
            .padding(GlassTokens.pagePadding)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: GlassTokens.popupWidth)
        .onAppear {
            model.setReduceMotionEnabled(accessibilityReduceMotion)
        }
        .onChange(of: accessibilityReduceMotion) { _, newValue in
            model.setReduceMotionEnabled(newValue)
        }
    }

    private var emptyCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                Text(emptyTitle)
                    .font(.headline)

                Text(emptyMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .contentTransition(accessibilityReduceMotion ? .identity : .opacity)
            }
        }
        .transition(accessibilityReduceMotion ? .identity : .opacity)
    }

    private var previewBadge: some View {
        Text("Sample Data")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.white.opacity(0.16), in: Capsule())
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button {
                onOpenSettings()
            } label: {
                Label("Settings", systemImage: "gearshape.fill")
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(.white.opacity(0.18), in: Capsule())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .font(.footnote.weight(.medium))

            Spacer()

            if let lastUpdatedAt = model.lastUpdatedAt {
                Text(updatedText(for: lastUpdatedAt))
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .contentTransition(accessibilityReduceMotion ? .identity : .numericText())
            }
        }
        .padding(.top, 2)
        .contentTransition(accessibilityReduceMotion ? .identity : .opacity)
    }

    private var emptyTitle: String {
        if model.isSigningIn {
            return "Finish sign-in"
        }
        if model.authDeviceCode != nil {
            return "Finish sign-in"
        }
        if model.isSignedIn == false, model.hasResolvedAuthState {
            return "Sign in required"
        }
        return "Waiting for quota data"
    }

    private var emptyMessage: String {
        if let code = model.authDeviceCode {
            return "Use code \(code) in your browser, then refresh."
        }
        return model.lastError ?? model.authStatusMessage
    }

    private func updatedText(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return "Updated \(formatter.string(from: date))"
    }

    private var orderedLimitPresentations: [PopupLimitPresentation] {
        guard let snapshot = model.snapshot else { return [] }
        return PopupPresentation.orderedLimits(snapshot.limits).map(PopupPresentation.presentation(for:))
    }

    private var primaryLimitPresentations: [PopupLimitPresentation] {
        orderedLimitPresentations.filter { $0.limit.bucket != .spark }
    }

    private var secondaryLimitPresentations: [PopupLimitPresentation] {
        guard model.showSparkEnabled else { return [] }
        return orderedLimitPresentations.filter { $0.limit.bucket == .spark }
    }

    private var activeSecondaryLimitPresentations: [PopupLimitPresentation] {
        secondaryLimitPresentations.filter { $0.style != .compact }
    }

    private var compactSecondaryLimitPresentations: [PopupLimitPresentation] {
        secondaryLimitPresentations.filter { $0.style == .compact }
    }

    private var supplementalSections: [PopupSupplementalSection] {
        PopupPresentation.supplementalSections(
            showHistory: model.showHistoryEnabled && model.usageHistory.isEmpty == false,
            showInsights: model.showInsightsEnabled && model.usageInsights != nil
        )
    }

    @ViewBuilder
    private func limitCard(for presentation: PopupLimitPresentation) -> some View {
        switch presentation.style {
        case .compact:
            CompactLimitCardView(presentation: presentation)
        case .hero, .standard:
            LimitCardView(presentation: presentation)
        }
    }

    @ViewBuilder
    private func supplementalCard(for section: PopupSupplementalSection) -> some View {
        switch section {
        case .history:
            UsageHistoryCardView(
                samples: model.usageHistory,
                showsChart: model.showHistoryChartEnabled
            )
        case .insights:
            if let insights = model.usageInsights {
                InsightsCardView(insights: insights)
            }
        }
    }
}

private struct InsightsCardView: View {
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
        guard let projected = insights.weeklyPace.projectedPercentAtReset else {
            return nil
        }
        return "\(Int(projected.rounded()))% by reset"
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

private struct LimitCardView: View {
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    let presentation: PopupLimitPresentation

    private var limit: CodexLimit { presentation.limit }
    private var cardStyle: GlassSurfaceStyle {
        presentation.style == .hero ? .primary : .secondary
    }
    private var headlineFont: Font {
        presentation.style == .hero
            ? .title3.monospacedDigit().weight(.bold)
            : .headline.monospacedDigit().weight(.semibold)
    }
    private var contentSpacing: CGFloat { 8 }

    var body: some View {
        GlassCard(style: cardStyle) {
            VStack(alignment: .leading, spacing: contentSpacing) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(limit.displayName)
                        .font(.headline)

                    Spacer()

                    if let headlineWindow = limit.primary ?? limit.secondary {
                        Text(headlineWindow.usedPercentText)
                            .font(headlineFont)
                            .contentTransition(
                                accessibilityReduceMotion
                                    ? .identity
                                    : .numericText(value: headlineWindow.clampedUsedPercent)
                            )
                    }
                }

                if let fiveHour = limit.fiveHourWindow ?? limit.primary {
                    windowRow(
                        title: fiveHour.windowDurationMinutes == 300 ? "5H" : fiveHour.windowText,
                        window: fiveHour
                    )
                }

                if let weekly = limit.weeklyWindow,
                   weekly != limit.fiveHourWindow
                {
                    windowRow(
                        title: weekly.windowDurationMinutes == 10_080 ? "Weekly" : weekly.windowText,
                        window: weekly
                    )
                }

                if let credits = presentation.visibleCredits {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("Credits")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        Spacer()

                        Text(credits.displayText)
                            .font(.caption.monospacedDigit().weight(.semibold))
                            .foregroundStyle(credits.isNegativeBalance ? Color.red : .secondary)
                    }
                    .padding(.top, 2)
                }
            }
        }
        .transition(accessibilityReduceMotion ? .identity : .opacity.combined(with: .scale(scale: 0.985)))
    }

    private func windowRow(title: String, window: CodexQuotaWindow) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                Text(window.usedPercentText)
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .contentTransition(
                        accessibilityReduceMotion
                            ? .identity
                            : .numericText(value: window.clampedUsedPercent)
                    )

                Text(CodexFormatting.relativeResetText(now: .init(), resetAt: window.resetsAt))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            UsageBar(
                progress: window.clampedUsedPercent / 100,
                bucket: limit.bucket
            )
        }
    }
}

private struct CompactLimitCardView: View {
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    let presentation: PopupLimitPresentation

    var body: some View {
        GlassCard(style: .secondary) {
            HStack(spacing: 10) {
                Circle()
                    .fill(limitAccentColor(for: presentation.limit.bucket))
                    .frame(width: 8, height: 8)

                Text(presentation.limit.displayName)
                    .font(.subheadline.weight(.semibold))

                Spacer()

                Text("Idle")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
        .transition(accessibilityReduceMotion ? .identity : .opacity)
    }
}

private struct UsageBar: View {
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    let progress: Double
    let bucket: CodexLimitBucket

    var body: some View {
        GeometryReader { proxy in
            let clamped = progress.clamped(to: 0 ... 1)
            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(limitTrackColor(for: bucket))

                if clamped > 0 {
                    Capsule(style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: limitGradient(for: bucket),
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(6, proxy.size.width * clamped))
                }
            }
        }
        .frame(height: 6)
        .allowsHitTesting(false)
        .animation(accessibilityReduceMotion ? nil : .easeInOut(duration: 0.18), value: progress)
    }
}

private struct UsageHistoryCardView: View {
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
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Usage history")
                        .font(.headline)

                    Spacer()

                    Text("30 days")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                weeklyForecastSummary

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

    @ViewBuilder
    private var weeklyForecastSummary: some View {
        if let current = weeklyForecast.currentPercent,
           let projected = weeklyForecast.projectedPercentAtReset {
            VStack(alignment: .leading, spacing: 5) {
                ForecastUsageBar(
                    current: current / 100,
                    projected: projected / 100
                )

                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("\(Int(current.rounded()))% used")
                        .font(.caption.weight(.semibold))

                    Text(forecastDeltaText(current: current, projected: projected))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func forecastDeltaText(current: Double, projected: Double) -> String {
        let delta = Int((weeklyForecast.paceVariancePercent ?? 0).rounded())
        if delta > 0 { return "\(delta)% over pace" }
        if delta < 0 { return "\(-delta)% under pace" }
        return "On pace"
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
    let current: Double
    let projected: Double

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let currentX = width * current.clamped(to: 0...1)

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
            }
        }
        .frame(height: 7)
    }
}

private func limitAccentColor(for bucket: CodexLimitBucket) -> Color {
    switch bucket {
    case .spark:
        return .purple
    case .codex, .other:
        return .blue
    }
}

private func limitGradient(for bucket: CodexLimitBucket) -> [Color] {
    switch bucket {
    case .spark:
        return [Color.indigo.opacity(0.9), Color.purple.opacity(0.85)]
    case .codex, .other:
        return [Color.blue.opacity(0.92), Color.cyan.opacity(0.8)]
    }
}

private func limitTrackColor(for bucket: CodexLimitBucket) -> Color {
    switch bucket {
    case .spark:
        return Color.purple.opacity(0.10)
    case .codex, .other:
        return Color.blue.opacity(0.10)
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
#endif
