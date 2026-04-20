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
    let currentPercent: Double?
    let projectedPercentAtReset: Double?
    let paceVariancePercent: Double?
    let detail: String?

    init(
        message: String,
        tone: Tone,
        currentPercent: Double?,
        projectedPercentAtReset: Double?,
        paceVariancePercent: Double?,
        detail: String? = nil
    ) {
        self.message = message
        self.tone = tone
        self.currentPercent = currentPercent
        self.projectedPercentAtReset = projectedPercentAtReset
        self.paceVariancePercent = paceVariancePercent
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
                currentPercent: nil,
                projectedPercentAtReset: nil,
                paceVariancePercent: nil,
                detail: nil
            )
        }

        guard let resetAt = latest.resetsAt else {
            return CodexUsageForecast(
                message: "Need reset data",
                tone: .caution,
                currentPercent: latest.usedPercent,
                projectedPercentAtReset: nil,
                paceVariancePercent: nil,
                detail: nil
            )
        }

        guard let durationMinutes = latest.windowDurationMinutes, durationMinutes > 0 else {
            return CodexUsageForecast(
                message: "Need window data",
                tone: .caution,
                currentPercent: latest.usedPercent,
                projectedPercentAtReset: nil,
                paceVariancePercent: nil,
                detail: nil
            )
        }

        let cycleDuration = TimeInterval(durationMinutes * 60)
        let cycleStart = resetAt.addingTimeInterval(-cycleDuration)
        let elapsedSeconds = latest.date.timeIntervalSince(cycleStart)
        let elapsedFraction = (elapsedSeconds / cycleDuration).clamped(to: 0 ... 1)
        let currentPercent = latest.usedPercent.clamped(to: 0 ... 100)

        guard observations.count >= 3, elapsedFraction >= 0.12 else {
            return CodexUsageForecast(
                message: "Learning this cycle",
                tone: .caution,
                currentPercent: currentPercent,
                projectedPercentAtReset: nil,
                paceVariancePercent: nil,
                detail: "Waiting for a few more samples"
            )
        }

        let projectedPercentAtReset = max(currentPercent, currentPercent / max(elapsedFraction, 0.05))
        let expectedPercentNow = (elapsedFraction * 100).clamped(to: 0 ... 100)
        let variance = currentPercent - expectedPercentNow
        let tone: CodexUsageForecast.Tone
        if projectedPercentAtReset > 100 {
            tone = .danger
        } else if projectedPercentAtReset >= 85 {
            tone = .caution
        } else {
            tone = .safe
        }

        return CodexUsageForecast(
            message: "Projected \(Int(projectedPercentAtReset.rounded()))% by reset",
            tone: tone,
            currentPercent: currentPercent,
            projectedPercentAtReset: projectedPercentAtReset,
            paceVariancePercent: variance,
            detail: paceDetail(variance: variance, sampleCount: observations.count)
        )
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

    private static func paceDetail(variance: Double, sampleCount: Int) -> String {
        let roundedVariance = Int(variance.rounded())
        let paceText: String
        if roundedVariance > 0 {
            paceText = "\(roundedVariance)% over pace"
        } else if roundedVariance < 0 {
            paceText = "\(-roundedVariance)% under pace"
        } else {
            paceText = "On pace"
        }
        return "\(paceText) · \(sampleCount) samples"
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
