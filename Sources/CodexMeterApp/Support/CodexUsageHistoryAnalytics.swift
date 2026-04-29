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

struct CodexMonthlyUsageHistory: Equatable {
    let peakPercent: Double
    let averageDailyPeakPercent: Double
    let dayCount: Int
    let sampleCount: Int

    var headline: String {
        "Peak \(Int(peakPercent.rounded()))%"
    }

    var detail: String {
        let dayWord = dayCount == 1 ? "day" : "days"
        return "30d avg \(Int(averageDailyPeakPercent.rounded()))% · \(dayCount) \(dayWord)"
    }
}

enum CodexForecastConfidence: Equatable {
    case tooEarly
    case learning
    case estimatedFromHistory
    case patternMatched
    case machineLearned
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
        case .patternMatched:
            return "Pattern matched"
        case .machineLearned:
            return "ML tuned"
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
    let likelyLowerPercent: Double?
    let likelyUpperPercent: Double?
    let modelReadiness: CodexForecastModelReadiness?

    init(
        message: String,
        tone: Tone,
        confidence: CodexForecastConfidence,
        currentPercent: Double?,
        projectedPercentAtReset: Double?,
        paceVariancePercent: Double?,
        sampleCount: Int = 0,
        resetAt: Date? = nil,
        detail: String? = nil,
        likelyLowerPercent: Double? = nil,
        likelyUpperPercent: Double? = nil,
        modelReadiness: CodexForecastModelReadiness? = nil
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
        self.likelyLowerPercent = likelyLowerPercent
        self.likelyUpperPercent = likelyUpperPercent
        self.modelReadiness = modelReadiness
    }
}

struct CodexForecastModelReadiness: Equatable {
    let historyDays: Int
    let sampleCount: Int
    let cycleCount: Int
    let requiredHistoryDays: Int
    let requiredSamples: Int
    let requiredCycles: Int

    var isReady: Bool {
        historyDays >= requiredHistoryDays
            && sampleCount >= requiredSamples
            && cycleCount >= requiredCycles
    }
}

enum CodexUsageHistoryAnalytics {
    private static let resetSkewTolerance: TimeInterval = 5 * 60
    private static let mlRequiredHistoryDays = 30
    private static let mlRequiredSamples = 40
    private static let mlRequiredWeeklyCycles = 4
    private static let mlRequiredFiveHourCycles = 20

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

    private struct PatternProjection {
        let projectedPercent: Double
    }

    private struct ForecastRange {
        let lowerPercent: Double
        let upperPercent: Double
    }

    private struct MachineLearnedProjection {
        let projectedPercent: Double
        let range: ForecastRange
        let trainingSampleCount: Int
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

    static func monthlyHistory(
        from samples: [CodexUsageHistorySample],
        series: CodexUsageHistorySeries,
        now: Date = Date()
    ) -> CodexMonthlyUsageHistory? {
        let cutoff = now.addingTimeInterval(-(30 * 24 * 60 * 60))
        let observations = resolvedObservations(from: samples, series: series)
            .filter { $0.date >= cutoff && $0.date <= now }

        guard observations.isEmpty == false else { return nil }

        let calendar = Calendar.autoupdatingCurrent
        let dailyPeaks = Dictionary(grouping: observations) { observation in
            calendar.startOfDay(for: observation.date)
        }
        .values
        .compactMap { dayObservations in
            dayObservations
                .map { $0.usedPercent.clamped(to: 0 ... 100) }
                .max()
        }

        guard dailyPeaks.isEmpty == false,
              let peak = dailyPeaks.max() else {
            return nil
        }

        let average = dailyPeaks.reduce(0, +) / Double(dailyPeaks.count)
        return CodexMonthlyUsageHistory(
            peakPercent: peak,
            averageDailyPeakPercent: average,
            dayCount: dailyPeaks.count,
            sampleCount: observations.count
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
        let modelReadiness = self.modelReadiness(from: samples, series: series)
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
                detail: nil,
                modelReadiness: modelReadiness
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
                detail: nil,
                modelReadiness: modelReadiness
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
                detail: nil,
                modelReadiness: modelReadiness
            )
        }

        let cycleDuration = TimeInterval(durationMinutes * 60)
        let cycleStart = resetAt.addingTimeInterval(-cycleDuration)
        let elapsedSeconds = latest.date.timeIntervalSince(cycleStart)
        let elapsedFraction = (elapsedSeconds / cycleDuration).clamped(to: 0 ... 1)
        let currentPercent = latest.usedPercent.clamped(to: 0 ... 100)
        let expectedPercentNow = (elapsedFraction * 100).clamped(to: 0 ... 100)
        let variance = currentPercent - expectedPercentNow
        let rawPaceProjectedPercentAtReset = max(currentPercent, currentPercent / max(elapsedFraction, 0.05))
        let historicalProjection = historicalProjection(
            from: samples,
            series: series,
            excludingResetAt: resetAt
        )

        guard observations.count >= 3, elapsedFraction >= 0.12 else {
            if let hotStartForecast = earlyHotStartForecast(
                observations: observations,
                currentPercent: currentPercent,
                elapsedFraction: elapsedFraction,
                rawPaceProjection: rawPaceProjectedPercentAtReset,
                historicalProjection: historicalProjection,
                variance: variance,
                resetAt: resetAt,
                modelReadiness: modelReadiness
            ) {
                return hotStartForecast
            }

            if let historicalProjection {
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
                    detail: "From \(historicalProjection.cycleCount) prior \(cycleWord)",
                    likelyLowerPercent: projectedPercentAtReset,
                    likelyUpperPercent: projectedPercentAtReset,
                    modelReadiness: modelReadiness
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
                ),
                modelReadiness: modelReadiness
            )
        }

        let isVolatile = isVolatile(
            observations: observations,
            cycleStart: cycleStart,
            cycleDuration: cycleDuration
        )
        let paceProjectedPercentAtReset = temperedPaceProjection(
            rawProjection: rawPaceProjectedPercentAtReset,
            currentPercent: currentPercent,
            elapsedFraction: elapsedFraction,
            historicalProjection: historicalProjection,
            isVolatile: isVolatile
        )
        let patternProjection = matchingPatternProjection(
            from: samples,
            series: series,
            latest: latest,
            currentResetAt: resetAt,
            currentPercent: currentPercent
        )
        var projectedPercentAtReset = patternAdjustedProjection(
            paceProjection: paceProjectedPercentAtReset,
            patternProjection: patternProjection?.projectedPercent,
            currentPercent: currentPercent
        )
        let mlProjection = machineLearnedProjection(
            from: samples,
            series: series,
            latest: latest,
            currentResetAt: resetAt,
            currentPercent: currentPercent,
            elapsedFraction: elapsedFraction,
            rawPaceProjection: rawPaceProjectedPercentAtReset,
            modelReadiness: modelReadiness
        )
        if let mlProjection {
            projectedPercentAtReset = max(
                currentPercent,
                (mlProjection.projectedPercent * 0.7) + (projectedPercentAtReset * 0.3)
            )
        }
        let confidence: CodexForecastConfidence
        if isVolatile {
            confidence = .volatile
        } else if mlProjection != nil {
            confidence = .machineLearned
        } else if projectedPercentAtReset > paceProjectedPercentAtReset + 1 {
            confidence = .patternMatched
        } else {
            confidence = .stable
        }
        let range = mlProjection?.range ?? forecastRange(
            projection: projectedPercentAtReset,
            currentPercent: currentPercent,
            confidence: confidence
        )

        return CodexUsageForecast(
            message: "Projected \(Int(projectedPercentAtReset.rounded()))% by reset",
            tone: tone(for: projectedPercentAtReset),
            confidence: confidence,
            currentPercent: currentPercent,
            projectedPercentAtReset: projectedPercentAtReset,
            paceVariancePercent: variance,
            sampleCount: observations.count,
            resetAt: resetAt,
            detail: forecastDetail(
                variance: variance,
                sampleCount: observations.count,
                confidence: confidence,
                mlProjection: mlProjection
            ),
            likelyLowerPercent: range.lowerPercent,
            likelyUpperPercent: range.upperPercent,
            modelReadiness: modelReadiness
        )
    }

    private static func earlyHotStartForecast(
        observations: [Observation],
        currentPercent: Double,
        elapsedFraction: Double,
        rawPaceProjection: Double,
        historicalProjection: HistoricalProjection?,
        variance: Double,
        resetAt: Date,
        modelReadiness: CodexForecastModelReadiness
    ) -> CodexUsageForecast? {
        let minimumCoverage = 0.04
        let minimumCurrentPercent = 12.0
        let minimumVariance = 8.0

        guard observations.count >= 3,
              elapsedFraction >= minimumCoverage,
              currentPercent >= minimumCurrentPercent,
              variance >= minimumVariance else {
            return nil
        }

        let projectedPercentAtReset = temperedPaceProjection(
            rawProjection: rawPaceProjection,
            currentPercent: currentPercent,
            elapsedFraction: elapsedFraction,
            historicalProjection: historicalProjection,
            isVolatile: false
        )

        guard tone(for: projectedPercentAtReset) != .safe else {
            return nil
        }

        let confidence = CodexForecastConfidence.volatile
        let range = forecastRange(
            projection: projectedPercentAtReset,
            currentPercent: currentPercent,
            confidence: confidence
        )

        return CodexUsageForecast(
            message: "Projected \(Int(projectedPercentAtReset.rounded()))% by reset",
            tone: tone(for: projectedPercentAtReset),
            confidence: confidence,
            currentPercent: currentPercent,
            projectedPercentAtReset: projectedPercentAtReset,
            paceVariancePercent: variance,
            sampleCount: observations.count,
            resetAt: resetAt,
            detail: forecastDetail(
                variance: variance,
                sampleCount: observations.count,
                confidence: confidence
            ),
            likelyLowerPercent: range.lowerPercent,
            likelyUpperPercent: range.upperPercent,
            modelReadiness: modelReadiness
        )
    }

    static func modelReadiness(
        from samples: [CodexUsageHistorySample],
        series: CodexUsageHistorySeries
    ) -> CodexForecastModelReadiness {
        let observations = resolvedObservations(from: samples, series: series)
        let dates = observations.map(\.date)
        let historyDays: Int
        if let first = dates.min(), let last = dates.max() {
            historyDays = max(0, Int((last.timeIntervalSince(first) / 86_400).rounded(.down)))
        } else {
            historyDays = 0
        }

        let cycleCount = Set(observations.compactMap(\.resetsAt)).count
        let requiredCycles = series == .weekly ? mlRequiredWeeklyCycles : mlRequiredFiveHourCycles
        return CodexForecastModelReadiness(
            historyDays: historyDays,
            sampleCount: observations.count,
            cycleCount: cycleCount,
            requiredHistoryDays: mlRequiredHistoryDays,
            requiredSamples: mlRequiredSamples,
            requiredCycles: requiredCycles
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
        return observations.filter { resetTimesMatch($0.resetsAt, latestReset) }
    }

    private static func forecastDetail(
        variance: Double,
        sampleCount: Int,
        confidence: CodexForecastConfidence,
        mlProjection: MachineLearnedProjection? = nil
    ) -> String {
        if let mlProjection {
            return "ML tuned · \(mlProjection.trainingSampleCount) samples · \(mlProjection.cycleCount) cycles"
        }

        if confidence == .patternMatched {
            return "Pattern matched · \(sampleCount) samples"
        }

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
                guard resetTimesMatch(resetAt, currentResetAt) == false else { return nil }
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

    private static func temperedPaceProjection(
        rawProjection: Double,
        currentPercent: Double,
        elapsedFraction: Double,
        historicalProjection: HistoricalProjection?,
        isVolatile: Bool
    ) -> Double {
        var projection = rawProjection

        if let historicalProjection,
           historicalProjection.projectedPercent < rawProjection {
            let historicalFloor = max(currentPercent, historicalProjection.projectedPercent.clamped(to: 0 ... 100))
            let paceWeight = (elapsedFraction * 1.4).clamped(to: 0.35 ... 0.75)
            projection = (rawProjection * paceWeight) + (historicalFloor * (1 - paceWeight))
        } else if isVolatile {
            projection = currentPercent + ((rawProjection - currentPercent) * 0.85)
        }

        return max(currentPercent, projection)
    }

    private static func patternAdjustedProjection(
        paceProjection: Double,
        patternProjection: Double?,
        currentPercent: Double
    ) -> Double {
        guard let patternProjection,
              patternProjection > paceProjection else {
            return max(currentPercent, paceProjection)
        }

        let weightedPatternProjection = paceProjection + ((patternProjection - paceProjection) * 0.75)
        return max(currentPercent, weightedPatternProjection)
    }

    private static func forecastRange(
        projection: Double,
        currentPercent: Double,
        confidence: CodexForecastConfidence
    ) -> ForecastRange {
        let margin = switch confidence {
        case .machineLearned:
            7.0
        case .patternMatched:
            9.0
        case .volatile:
            18.0
        case .stable:
            8.0
        case .estimatedFromHistory:
            12.0
        case .tooEarly, .learning:
            0.0
        }

        return ForecastRange(
            lowerPercent: max(currentPercent, projection - margin).clamped(to: 0 ... 140),
            upperPercent: max(currentPercent, projection + margin).clamped(to: 0 ... 140)
        )
    }

    private static func machineLearnedProjection(
        from samples: [CodexUsageHistorySample],
        series: CodexUsageHistorySeries,
        latest: Observation,
        currentResetAt: Date,
        currentPercent: Double,
        elapsedFraction: Double,
        rawPaceProjection: Double,
        modelReadiness: CodexForecastModelReadiness
    ) -> MachineLearnedProjection? {
        guard series == .weekly, modelReadiness.isReady else { return nil }
        guard let windowDurationMinutes = latest.windowDurationMinutes else { return nil }

        let observations = resolvedObservations(from: samples, series: series)
            .filter { observation in
                observation.resetsAt != nil
                    && resetTimesMatch(observation.resetsAt, currentResetAt) == false
                    && observation.windowDurationMinutes == windowDurationMinutes
            }
        let grouped = Dictionary(grouping: observations, by: \.resetsAt)
        var trainingRows: [[Double]] = []
        var trainingTargets: [Double] = []
        var cycleCount = 0

        for (resetAt, cycleObservations) in grouped {
            guard let resetAt, cycleObservations.count >= 3 else { continue }
            let targetPercent = cycleObservations
                .map { $0.usedPercent.clamped(to: 0 ... 100) }
                .max() ?? 0
            guard targetPercent > 0 else { continue }

            let cycleDuration = TimeInterval(windowDurationMinutes * 60)
            let cycleStart = resetAt.addingTimeInterval(-cycleDuration)
            cycleCount += 1

            for observation in cycleObservations {
                let elapsed = (observation.date.timeIntervalSince(cycleStart) / cycleDuration).clamped(to: 0 ... 1)
                guard elapsed >= 0.06, elapsed <= 0.96 else { continue }
                let used = observation.usedPercent.clamped(to: 0 ... 100)
                let naiveProjection = max(used, used / max(elapsed, 0.05)).clamped(to: 0 ... 140)
                trainingRows.append(regressionFeatures(
                    currentPercent: used,
                    elapsedFraction: elapsed,
                    rawPaceProjection: naiveProjection
                ))
                trainingTargets.append(targetPercent / 100)
            }
        }

        guard cycleCount >= mlRequiredWeeklyCycles,
              trainingRows.count >= mlRequiredSamples,
              let weights = ridgeRegressionWeights(rows: trainingRows, targets: trainingTargets) else {
            return nil
        }

        let features = regressionFeatures(
            currentPercent: currentPercent,
            elapsedFraction: elapsedFraction,
            rawPaceProjection: rawPaceProjection.clamped(to: 0 ... 140)
        )
        let predicted = dot(weights, features) * 100
        let residuals = zip(trainingRows, trainingTargets).map { row, target in
            (dot(weights, row) - target) * 100
        }
        let rmse = sqrt(residuals.map { $0 * $0 }.reduce(0, +) / Double(max(residuals.count, 1)))
        guard rmse.isFinite, rmse <= 18 else { return nil }

        let projectedPercent = predicted.clamped(to: currentPercent ... 120)
        let margin = max(6, min(18, rmse * 1.4))
        return MachineLearnedProjection(
            projectedPercent: projectedPercent,
            range: ForecastRange(
                lowerPercent: max(currentPercent, projectedPercent - margin).clamped(to: 0 ... 140),
                upperPercent: max(currentPercent, projectedPercent + margin).clamped(to: 0 ... 140)
            ),
            trainingSampleCount: trainingRows.count,
            cycleCount: cycleCount
        )
    }

    private static func regressionFeatures(
        currentPercent: Double,
        elapsedFraction: Double,
        rawPaceProjection: Double
    ) -> [Double] {
        [
            1,
            currentPercent.clamped(to: 0 ... 100) / 100,
            elapsedFraction.clamped(to: 0 ... 1),
            rawPaceProjection.clamped(to: 0 ... 140) / 100
        ]
    }

    private static func ridgeRegressionWeights(rows: [[Double]], targets: [Double]) -> [Double]? {
        guard let featureCount = rows.first?.count,
              rows.allSatisfy({ $0.count == featureCount }),
              rows.count == targets.count else {
            return nil
        }

        let lambda = 0.08
        var matrix = Array(
            repeating: Array(repeating: 0.0, count: featureCount),
            count: featureCount
        )
        var vector = Array(repeating: 0.0, count: featureCount)

        for (row, target) in zip(rows, targets) {
            for i in 0..<featureCount {
                vector[i] += row[i] * target
                for j in 0..<featureCount {
                    matrix[i][j] += row[i] * row[j]
                }
            }
        }

        for index in 0..<featureCount {
            matrix[index][index] += lambda
        }

        return solveLinearSystem(matrix: matrix, vector: vector)
    }

    private static func solveLinearSystem(matrix: [[Double]], vector: [Double]) -> [Double]? {
        let count = vector.count
        guard matrix.count == count,
              matrix.allSatisfy({ $0.count == count }) else {
            return nil
        }

        var augmented = matrix.enumerated().map { index, row in
            row + [vector[index]]
        }

        for pivotIndex in 0..<count {
            var bestRow = pivotIndex
            for rowIndex in pivotIndex..<count where abs(augmented[rowIndex][pivotIndex]) > abs(augmented[bestRow][pivotIndex]) {
                bestRow = rowIndex
            }
            guard abs(augmented[bestRow][pivotIndex]) > 0.000_001 else { return nil }
            if bestRow != pivotIndex {
                augmented.swapAt(bestRow, pivotIndex)
            }

            let pivot = augmented[pivotIndex][pivotIndex]
            for columnIndex in pivotIndex...count {
                augmented[pivotIndex][columnIndex] /= pivot
            }

            for rowIndex in 0..<count where rowIndex != pivotIndex {
                let factor = augmented[rowIndex][pivotIndex]
                guard factor != 0 else { continue }
                for columnIndex in pivotIndex...count {
                    augmented[rowIndex][columnIndex] -= factor * augmented[pivotIndex][columnIndex]
                }
            }
        }

        return augmented.map { $0[count] }
    }

    private static func dot(_ lhs: [Double], _ rhs: [Double]) -> Double {
        zip(lhs, rhs).map(*).reduce(0, +)
    }

    private static func matchingPatternProjection(
        from samples: [CodexUsageHistorySample],
        series: CodexUsageHistorySeries,
        latest: Observation,
        currentResetAt: Date,
        currentPercent: Double
    ) -> PatternProjection? {
        guard series == .weekly else { return nil }
        guard let windowDurationMinutes = latest.windowDurationMinutes else { return nil }

        let calendar = Calendar.autoupdatingCurrent
        let latestComponents = calendar.dateComponents([.weekday, .hour], from: latest.date)
        guard let latestWeekday = latestComponents.weekday,
              let latestHour = latestComponents.hour else {
            return nil
        }

        let observations = resolvedObservations(from: samples, series: series)
            .filter { observation in
                observation.resetsAt != nil
                    && resetTimesMatch(observation.resetsAt, currentResetAt) == false
                    && observation.windowDurationMinutes == windowDurationMinutes
            }

        let priorCyclePeaks = Dictionary(grouping: observations, by: \.resetsAt)
            .compactMap { _, cycleObservations -> Double? in
                let hasMatchingTime = cycleObservations.contains { observation in
                    let components = calendar.dateComponents([.weekday, .hour], from: observation.date)
                    guard components.weekday == latestWeekday,
                          let hour = components.hour else {
                        return false
                    }
                    return hourDistance(hour, latestHour) <= 2
                }
                guard hasMatchingTime else { return nil }
                return cycleObservations.map(\.usedPercent).max()
            }

        guard priorCyclePeaks.count >= 2 else { return nil }

        return PatternProjection(
            projectedPercent: max(currentPercent, median(priorCyclePeaks).clamped(to: 0 ... 100))
        )
    }

    private static func hourDistance(_ lhs: Int, _ rhs: Int) -> Int {
        let rawDistance = abs(lhs - rhs)
        return min(rawDistance, 24 - rawDistance)
    }

    private static func resetTimesMatch(_ lhs: Date?, _ rhs: Date) -> Bool {
        guard let lhs else { return false }
        return abs(lhs.timeIntervalSince(rhs)) <= resetSkewTolerance
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
