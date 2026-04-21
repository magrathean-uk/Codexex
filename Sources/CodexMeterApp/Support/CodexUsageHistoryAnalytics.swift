#if os(macOS)
import Foundation
import SwiftUI
import CodexMeterCore

enum CodexUsageHistorySeries {
    case fiveHour
    case weekly
}

enum CodexUsageInsightTone: Equatable {
    case safe
    case caution
    case danger

    var color: Color {
        switch self {
        case .safe:
            .green
        case .caution:
            .orange
        case .danger:
            .red
        }
    }

    init(_ tone: CodexUsageForecast.Tone) {
        switch tone {
        case .safe:
            self = .safe
        case .caution:
            self = .caution
        case .danger:
            self = .danger
        }
    }
}

struct CodexUsageInsightRow: Equatable {
    let title: String
    let message: String
    let detail: String?
    let tone: CodexUsageInsightTone
}

struct CodexUsageInsights: Equatable {
    let weeklyPace: CodexUsageForecast
    let fiveHourPressure: CodexUsageInsightRow
    let recentPeaks: CodexUsageInsightRow
}

struct CodexUsageHistoryPoint: Identifiable, Equatable {
    let id: String
    let date: Date
    let usedPercent: Double
    let resetsAt: Date?
    let windowDurationMinutes: Int?
}

enum CodexForecastConfidence: Equatable {
    case tooEarly
    case learning
    case estimatedFromHistory
    case stable
    case volatile

    var label: String {
        switch self {
        case .tooEarly:
            return "Too early"
        case .learning:
            return "Learning"
        case .estimatedFromHistory:
            return "Early estimate"
        case .stable:
            return "Stable"
        case .volatile:
            return "Volatile"
        }
    }
}

struct CodexUsageForecast: Equatable {
    enum Tone {
        case safe
        case caution
        case danger

        var color: Color {
            switch self {
            case .safe:
                .green
            case .caution:
                .orange
            case .danger:
                .red
            }
        }
    }

    let message: String
    let tone: Tone
    let confidence: CodexForecastConfidence
    let currentPercent: Double?
    let projectedPercentAtReset: Double?
    let paceVariancePercent: Double?
    let sampleCount: Int
    let resetAt: Date?
    let detail: String?

    init(
        message: String,
        tone: Tone,
        confidence: CodexForecastConfidence,
        currentPercent: Double?,
        projectedPercentAtReset: Double?,
        paceVariancePercent: Double?,
        sampleCount: Int = 0,
        resetAt: Date? = nil,
        detail: String? = nil
    ) {
        self.message = message
        self.tone = tone
        self.confidence = confidence
        self.currentPercent = currentPercent
        self.projectedPercentAtReset = projectedPercentAtReset
        self.paceVariancePercent = paceVariancePercent
        self.sampleCount = sampleCount
        self.resetAt = resetAt
        self.detail = detail
    }
}

enum CodexUsageHistoryAnalytics {
    private struct Observation {
        let date: Date
        let usedPercent: Double
        let resetsAt: Date?
        let windowDurationMinutes: Int?
    }

    private struct HistoricalProjection {
        let projectedPercent: Double
        let cycleCount: Int
    }

    static func insights(
        snapshot: CodexSnapshot?,
        samples: [CodexUsageHistorySample],
        now: Date = Date()
    ) -> CodexUsageInsights? {
        guard let codexLimit = snapshot?.limits.first(where: { $0.bucket == .codex }) else {
            return nil
        }

        return CodexUsageInsights(
            weeklyPace: forecast(from: samples, series: .weekly),
            fiveHourPressure: self.fiveHourPressure(
                from: codexLimit.fiveHourWindow,
                now: now
            ),
            recentPeaks: self.recentPeaks(from: samples, now: now)
        )
    }

    static func points(
        from samples: [CodexUsageHistorySample],
        series: CodexUsageHistorySeries,
        limit: Int = 30
    ) -> [CodexUsageHistoryPoint] {
        guard limit > 0 else { return [] }

        let observations = resolvedObservations(from: samples, series: series)
        guard observations.isEmpty == false else { return [] }

        let calendar = Calendar.autoupdatingCurrent
        let grouped = Dictionary(grouping: observations) { observation in
            calendar.startOfDay(for: observation.date)
        }

        return grouped
            .keys
            .sorted()
            .suffix(limit)
            .compactMap { day in
                guard let dayObservations = grouped[day] else { return nil }
                let selected = dayObservations.max { lhs, rhs in
                    if lhs.usedPercent != rhs.usedPercent {
                        return lhs.usedPercent < rhs.usedPercent
                    }
                    return lhs.date < rhs.date
                }
                guard let selected else { return nil }

                let suffix = series == .fiveHour ? "h" : "w"
                return CodexUsageHistoryPoint(
                    id: "\(day.timeIntervalSince1970)-\(suffix)",
                    date: day,
                    usedPercent: selected.usedPercent,
                    resetsAt: selected.resetsAt,
                    windowDurationMinutes: selected.windowDurationMinutes
                )
            }
    }

    static func forecast(
        from samples: [CodexUsageHistorySample],
        series: CodexUsageHistorySeries
    ) -> CodexUsageForecast {
        let observations = currentCycleObservations(from: samples, series: series)
        guard let latest = observations.last else {
            return CodexUsageForecast(
                message: "Need reset data",
                tone: .caution,
                confidence: .tooEarly,
                currentPercent: nil,
                projectedPercentAtReset: nil,
                paceVariancePercent: nil,
                sampleCount: 0,
                resetAt: nil,
                detail: nil
            )
        }

        guard let resetAt = latest.resetsAt else {
            return CodexUsageForecast(
                message: "Need reset data",
                tone: .caution,
                confidence: .tooEarly,
                currentPercent: latest.usedPercent,
                projectedPercentAtReset: nil,
                paceVariancePercent: nil,
                sampleCount: observations.count,
                resetAt: nil,
                detail: nil
            )
        }

        guard let durationMinutes = latest.windowDurationMinutes, durationMinutes > 0 else {
            return CodexUsageForecast(
                message: "Need window data",
                tone: .caution,
                confidence: .tooEarly,
                currentPercent: latest.usedPercent,
                projectedPercentAtReset: nil,
                paceVariancePercent: nil,
                sampleCount: observations.count,
                resetAt: resetAt,
                detail: nil
            )
        }

        let cycleDuration = TimeInterval(durationMinutes * 60)
        let cycleStart = resetAt.addingTimeInterval(-cycleDuration)
        let elapsedSeconds = latest.date.timeIntervalSince(cycleStart)
        let elapsedFraction = (elapsedSeconds / cycleDuration).clamped(to: 0 ... 1)
        let currentPercent = latest.usedPercent.clamped(to: 0 ... 100)

        guard observations.count >= 3, elapsedFraction >= 0.12 else {
            if let historicalProjection = historicalProjection(
                from: samples,
                series: series,
                excludingResetAt: resetAt
            ) {
                let projectedPercentAtReset = max(
                    currentPercent,
                    historicalProjection.projectedPercent.clamped(to: 0 ... 100)
                )
                let cycleWord = historicalProjection.cycleCount == 1 ? "cycle" : "cycles"

                return CodexUsageForecast(
                    message: "Early estimate \(Int(projectedPercentAtReset.rounded()))% by reset",
                    tone: tone(for: projectedPercentAtReset),
                    confidence: .estimatedFromHistory,
                    currentPercent: currentPercent,
                    projectedPercentAtReset: projectedPercentAtReset,
                    paceVariancePercent: nil,
                    sampleCount: observations.count,
                    resetAt: resetAt,
                    detail: "From \(historicalProjection.cycleCount) prior \(cycleWord)"
                )
            }

            let confidence: CodexForecastConfidence = observations.count <= 1 && elapsedFraction < 0.06
                ? .tooEarly
                : .learning
            let message = confidence == .tooEarly ? "Too early to call" : "Learning this cycle"

            return CodexUsageForecast(
                message: message,
                tone: .caution,
                confidence: confidence,
                currentPercent: currentPercent,
                projectedPercentAtReset: nil,
                paceVariancePercent: nil,
                sampleCount: observations.count,
                resetAt: resetAt,
                detail: learningDetail(
                    sampleCount: observations.count,
                    elapsedFraction: elapsedFraction,
                    cycleDuration: cycleDuration
                )
            )
        }

        let projectedPercentAtReset = max(currentPercent, currentPercent / max(elapsedFraction, 0.05))
        let expectedPercentNow = (elapsedFraction * 100).clamped(to: 0 ... 100)
        let variance = currentPercent - expectedPercentNow
        let confidence: CodexForecastConfidence = isVolatile(
            observations: observations,
            cycleStart: cycleStart,
            cycleDuration: cycleDuration
        ) ? .volatile : .stable

        return CodexUsageForecast(
            message: "Projected \(Int(projectedPercentAtReset.rounded()))% by reset",
            tone: tone(for: projectedPercentAtReset),
            confidence: confidence,
            currentPercent: currentPercent,
            projectedPercentAtReset: projectedPercentAtReset,
            paceVariancePercent: variance,
            sampleCount: observations.count,
            resetAt: resetAt,
            detail: paceDetail(
                variance: variance,
                sampleCount: observations.count,
                confidence: confidence
            )
        )
    }

    static func currentCyclePoints(
        from samples: [CodexUsageHistorySample],
        series: CodexUsageHistorySeries
    ) -> [CodexUsageHistoryPoint] {
        currentCycleObservations(from: samples, series: series).map { observation in
            let suffix = series == .fiveHour ? "hc" : "wc"
            return CodexUsageHistoryPoint(
                id: "\(observation.date.timeIntervalSince1970)-\(suffix)",
                date: observation.date,
                usedPercent: observation.usedPercent,
                resetsAt: observation.resetsAt,
                windowDurationMinutes: observation.windowDurationMinutes
            )
        }
    }

    private static func resolvedObservations(
        from samples: [CodexUsageHistorySample],
        series: CodexUsageHistorySeries
    ) -> [Observation] {
        samples.compactMap { sample -> Observation? in
            let window = switch series {
            case .fiveHour:
                sample.fiveHour
            case .weekly:
                sample.weekly
            }

            guard let window else { return nil }
            return Observation(
                date: sample.capturedAt,
                usedPercent: window.usedPercent,
                resetsAt: window.resetsAt,
                windowDurationMinutes: window.windowDurationMinutes
            )
        }
        .sorted { $0.date < $1.date }
    }

    private static func currentCycleObservations(
        from samples: [CodexUsageHistorySample],
        series: CodexUsageHistorySeries
    ) -> [Observation] {
        let observations = resolvedObservations(from: samples, series: series)
        guard let latestReset = observations.compactMap(\.resetsAt).last else {
            return []
        }
        return observations.filter { $0.resetsAt == latestReset }
    }

    private static func paceDetail(
        variance: Double,
        sampleCount: Int,
        confidence: CodexForecastConfidence
    ) -> String {
        let roundedVariance = Int(variance.rounded())
        let paceText: String
        if roundedVariance > 0 {
            paceText = "\(roundedVariance)% over pace"
        } else if roundedVariance < 0 {
            paceText = "\(-roundedVariance)% under pace"
        } else {
            paceText = "On pace"
        }
        if confidence == .volatile {
            return "Volatile · \(paceText.lowercased()) · \(sampleCount) samples"
        }
        return "\(paceText) · \(sampleCount) samples"
    }

    private static func learningDetail(
        sampleCount: Int,
        elapsedFraction: Double,
        cycleDuration: TimeInterval
    ) -> String {
        let minimumSamples = 3
        let minimumCoverage = 0.12
        let missingSamples = max(0, minimumSamples - sampleCount)
        let missingCoverageSeconds = max(0, minimumCoverage - elapsedFraction) * cycleDuration

        let coverageText: String? = missingCoverageSeconds > 0
            ? "\(compactDuration(seconds: missingCoverageSeconds)) more cycle data"
            : nil

        if missingSamples > 0, let coverageText {
            return "Need \(missingSamples) more samples or \(coverageText)"
        }
        if missingSamples > 0 {
            return "Need \(missingSamples) more samples"
        }
        if let coverageText {
            return "Need \(coverageText)"
        }

        return "Waiting for a few more samples"
    }

    private static func historicalProjection(
        from samples: [CodexUsageHistorySample],
        series: CodexUsageHistorySeries,
        excludingResetAt currentResetAt: Date
    ) -> HistoricalProjection? {
        let observations = resolvedObservations(from: samples, series: series)

        let priorCyclePeaks = Dictionary(
            grouping: observations.compactMap { observation -> (Date, Double)? in
                guard let resetAt = observation.resetsAt else { return nil }
                guard resetAt != currentResetAt else { return nil }
                return (resetAt, observation.usedPercent)
            },
            by: \.0
        )
        .compactMap { _, cycleObservations in
            cycleObservations.map(\.1).max()
        }

        guard priorCyclePeaks.count >= 2 else {
            return nil
        }

        return HistoricalProjection(
            projectedPercent: median(priorCyclePeaks),
            cycleCount: priorCyclePeaks.count
        )
    }

    private static func isVolatile(
        observations: [Observation],
        cycleStart: Date,
        cycleDuration: TimeInterval
    ) -> Bool {
        let projections = observations.compactMap { observation -> Double? in
            let elapsedSeconds = observation.date.timeIntervalSince(cycleStart)
            let elapsedFraction = (elapsedSeconds / cycleDuration).clamped(to: 0.12 ... 1)
            guard elapsedFraction.isFinite else { return nil }
            return max(
                observation.usedPercent.clamped(to: 0 ... 100),
                observation.usedPercent.clamped(to: 0 ... 100) / max(elapsedFraction, 0.05)
            )
        }

        guard projections.count >= 4,
              let minProjection = projections.min(),
              let maxProjection = projections.max() else {
            return false
        }

        return (maxProjection - minProjection) >= 18
    }

    private static func tone(for projectedPercentAtReset: Double) -> CodexUsageForecast.Tone {
        if projectedPercentAtReset > 100 {
            return .danger
        }
        if projectedPercentAtReset >= 85 {
            return .caution
        }
        return .safe
    }

    private static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        let midpoint = sorted.count / 2

        if sorted.count.isMultiple(of: 2) {
            return (sorted[midpoint - 1] + sorted[midpoint]) / 2
        }
        return sorted[midpoint]
    }

    private static func compactDuration(seconds: TimeInterval) -> String {
        let roundedMinutes = max(1, Int((seconds / 60).rounded(.up)))
        if roundedMinutes >= 60 {
            let roundedHours = Int((Double(roundedMinutes) / 60).rounded(.up))
            return "\(roundedHours)h"
        }
        return "\(roundedMinutes)m"
    }

    private static func fiveHourPressure(
        from window: CodexQuotaWindow?,
        now: Date
    ) -> CodexUsageInsightRow {
        guard let window else {
            return CodexUsageInsightRow(
                title: "5-hour pressure",
                message: "Building history",
                detail: nil,
                tone: .caution
            )
        }

        let usedPercent = window.clampedUsedPercent
        guard let resetAt = window.resetsAt else {
            return CodexUsageInsightRow(
                title: "5-hour pressure",
                message: "\(Int(usedPercent.rounded()))% used",
                detail: CodexFormatting.relativeResetText(now: now, resetAt: nil),
                tone: .caution
            )
        }

        let secondsToReset = Int(resetAt.timeIntervalSince(now).rounded())
        let tone: CodexUsageInsightTone

        if secondsToReset <= 0 {
            tone = .caution
        } else if (usedPercent >= 90 && secondsToReset > 30 * 60) || (usedPercent >= 80 && secondsToReset > 120 * 60) {
            tone = .danger
        } else if (usedPercent >= 70 && secondsToReset > 30 * 60) || (usedPercent >= 50 && secondsToReset > 120 * 60) {
            tone = .caution
        } else {
            tone = .safe
        }

        return CodexUsageInsightRow(
            title: "5-hour pressure",
            message: "\(Int(usedPercent.rounded()))% used",
            detail: CodexFormatting.relativeResetText(now: now, resetAt: resetAt),
            tone: tone
        )
    }

    private static func recentPeaks(
        from samples: [CodexUsageHistorySample],
        now: Date
    ) -> CodexUsageInsightRow {
        let fiveHourCutoff = now.addingTimeInterval(-(24 * 60 * 60))
        let weeklyCutoff = now.addingTimeInterval(-(7 * 24 * 60 * 60))

        let fiveHourPeak = samples
            .filter { $0.capturedAt >= fiveHourCutoff }
            .compactMap(\.fiveHour?.usedPercent)
            .max()

        let weeklyPeak = samples
            .filter { $0.capturedAt >= weeklyCutoff }
            .compactMap(\.weekly?.usedPercent)
            .max()

        guard let fiveHourPeak, let weeklyPeak else {
            return CodexUsageInsightRow(
                title: "Recent peaks",
                message: "Building history",
                detail: nil,
                tone: .caution
            )
        }

        let maxPeak = max(fiveHourPeak, weeklyPeak)
        let tone: CodexUsageInsightTone
        if maxPeak >= 90 {
            tone = .danger
        } else if maxPeak >= 70 {
            tone = .caution
        } else {
            tone = .safe
        }

        return CodexUsageInsightRow(
            title: "Recent peaks",
            message: "5H \(Int(fiveHourPeak.rounded()))% · W \(Int(weeklyPeak.rounded()))%",
            detail: "Last 24h / 7d",
            tone: tone
        )
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
#endif
