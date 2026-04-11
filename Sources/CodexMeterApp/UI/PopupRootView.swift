#if os(macOS)
import Charts
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

                if let snapshot = model.snapshot {
                    ForEach(snapshot.limits) { limit in
                        LimitCardView(limit: limit)
                    }

                    if model.showHistoryEnabled, model.usageHistory.isEmpty == false {
                        UsageHistoryCardView(samples: model.usageHistory)
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
            .background(.white.opacity(0.08), in: Capsule())
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button("Settings") {
                onOpenSettings()
            }
            .buttonStyle(.bordered)
            .tint(.secondary)

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
}

private struct LimitCardView: View {
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    let limit: CodexLimit

    var body: some View {
        GlassCard(style: .primary) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(limit.displayName)
                        .font(.headline)

                    Spacer()

                    if let headlineWindow = limit.primary ?? limit.secondary {
                        Text(headlineWindow.usedPercentText)
                            .font(.title3.monospacedDigit().weight(.semibold))
                            .contentTransition(
                                accessibilityReduceMotion
                                    ? .identity
                                    : .numericText(value: headlineWindow.clampedUsedPercent)
                            )
                    }
                }

                if let fiveHour = limit.fiveHourWindow ?? limit.primary {
                    windowRow(
                        title: fiveHour.windowDurationMinutes == 300 ? "5-hour" : fiveHour.windowText,
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

                if let credits = limit.credits {
                    Divider()
                        .opacity(0.35)

                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("Credits")
                            .font(.subheadline.weight(.semibold))

                        Spacer()

                        Text(credits.displayText)
                            .font(.subheadline.monospacedDigit().weight(.semibold))
                            .foregroundStyle(credits.isNegativeBalance ? Color.red : .secondary)
                    }
                }
            }
        }
        .transition(accessibilityReduceMotion ? .identity : .opacity.combined(with: .scale(scale: 0.985)))
    }

    private func windowRow(title: String, window: CodexQuotaWindow) -> some View {
        GlassCard(style: .inset) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))

                    Spacer()

                    Text(window.usedPercentText)
                        .font(.subheadline.monospacedDigit().weight(.semibold))
                        .contentTransition(
                            accessibilityReduceMotion
                                ? .identity
                                : .numericText(value: window.clampedUsedPercent)
                        )

                    Text(CodexFormatting.relativeResetText(now: .init(), resetAt: window.resetsAt))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                UsageBar(progress: window.clampedUsedPercent / 100)
            }
        }
    }
}

private struct UsageBar: View {
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    let progress: Double

    var body: some View {
        GeometryReader { proxy in
            let clamped = progress.clamped(to: 0 ... 1)
            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(.white.opacity(0.08))

                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.blue, Color.cyan.opacity(0.8)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(10, proxy.size.width * clamped))
            }
        }
        .frame(height: 8)
        .allowsHitTesting(false)
        .animation(accessibilityReduceMotion ? nil : .easeInOut(duration: 0.18), value: progress)
    }
}

private struct UsageHistoryCardView: View {
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    let samples: [CodexUsageHistorySample]

    private let fiveHourPoints: [CodexUsageHistoryPoint]
    private let weeklyPoints: [CodexUsageHistoryPoint]
    private let fiveHourForecast: CodexUsageForecast
    private let weeklyForecast: CodexUsageForecast

    init(samples: [CodexUsageHistorySample]) {
        self.samples = samples
        self.fiveHourPoints = CodexUsageHistoryAnalytics.points(from: samples, series: .fiveHour)
        self.weeklyPoints = CodexUsageHistoryAnalytics.points(from: samples, series: .weekly)
        self.fiveHourForecast = CodexUsageHistoryAnalytics.forecast(from: samples, series: .fiveHour)
        self.weeklyForecast = CodexUsageHistoryAnalytics.forecast(from: samples, series: .weekly)
    }

    var body: some View {
        GlassCard(style: .secondary) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Usage history")
                        .font(.headline)

                    Spacer()

                    Text("30 days")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                weeklyForecastSummary

                Chart {
                    ForEach(fiveHourPoints) { point in
                        BarMark(
                            x: .value("Date", point.date),
                            y: .value("Used", point.usedPercent)
                        )
                        .foregroundStyle(Color.blue.opacity(0.75))
                        .cornerRadius(3)
                    }

                    ForEach(weeklyPoints) { point in
                        LineMark(
                            x: .value("Date", point.date),
                            y: .value("Used", point.usedPercent)
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(Color.green)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                    }
                }
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .chartYScale(domain: 0...100)
                .frame(height: 84)

                HStack(spacing: 10) {
                    forecastPill(label: "5 Hourly", forecast: fiveHourForecast)
                    forecastPill(label: "Weekly", forecast: weeklyForecast)
                }
            }
        }
    }

    private func forecastPill(label: String, forecast: CodexUsageForecast) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(forecast.tone.color)
                .frame(width: 8, height: 8)

            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(forecast.message)
                .font(.footnote.weight(.medium))
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.white.opacity(0.06), in: Capsule())
    }

    @ViewBuilder
    private var weeklyForecastSummary: some View {
        if let current = weeklyForecast.currentPercent,
           let projected = weeklyForecast.projectedPercentAtReset {
            VStack(alignment: .leading, spacing: 8) {
                ForecastUsageBar(
                    current: current / 100,
                    projected: projected / 100,
                    tone: weeklyForecast.tone
                )

                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("\(Int(current.rounded()))% used")
                        .font(.subheadline.weight(.medium))

                    Text(forecastDeltaText(current: current, projected: projected))
                        .font(.subheadline)
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

private struct ForecastUsageBar: View {
    let current: Double
    let projected: Double
    let tone: CodexUsageForecast.Tone

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let currentX = width * current.clamped(to: 0...1)
            let projectedX = width * projected.clamped(to: 0...1)

            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(.white.opacity(0.08))

                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.blue.opacity(0.7), Color.cyan.opacity(0.8)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(10, currentX))

                Rectangle()
                    .fill(tone.color)
                    .frame(width: 3, height: 12)
                    .offset(x: max(0, projectedX - 1.5))
            }
        }
        .frame(height: 12)
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
#endif
