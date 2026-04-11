#if os(macOS)
import Foundation
import SwiftUI
import CodexMeterCore

enum CodexUsageHistorySeries {
    case fiveHour
    case weekly
}

struct CodexUsageHistoryPoint: Identifiable, Equatable {
    let id: String
    let date: Date
    let usedPercent: Double
    let resetsAt: Date?
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
}

enum CodexUsageHistoryAnalytics {
    static func points(
        from samples: [CodexUsageHistorySample],
        series: CodexUsageHistorySeries,
        limit: Int = 30
    ) -> [CodexUsageHistoryPoint] {
        let resolved = samples.compactMap { sample -> CodexUsageHistoryPoint? in
            let window = switch series {
            case .fiveHour:
                sample.fiveHour
            case .weekly:
                sample.weekly
            }

            guard let window else { return nil }
            let suffix = series == .fiveHour ? "h" : "w"
            return CodexUsageHistoryPoint(
                id: "\(sample.capturedAt.timeIntervalSince1970)-\(suffix)",
                date: sample.capturedAt,
                usedPercent: window.usedPercent,
                resetsAt: window.resetsAt
            )
        }

        if resolved.count <= limit {
            return resolved
        }
        return Array(resolved.suffix(limit))
    }

    static func forecast(
        from samples: [CodexUsageHistorySample],
        series: CodexUsageHistorySeries
    ) -> CodexUsageForecast {
        let points = self.points(from: samples, series: series)
        guard let latestReset = points.compactMap(\.resetsAt).last else {
            return CodexUsageForecast(message: "Need reset data", tone: .caution, currentPercent: nil, projectedPercentAtReset: nil, paceVariancePercent: nil)
        }

        let cycle = points.filter { $0.resetsAt == latestReset }
        guard cycle.count >= 3, let latest = cycle.last else {
            return CodexUsageForecast(message: "Learning pattern", tone: .caution, currentPercent: cycle.last?.usedPercent, projectedPercentAtReset: nil, paceVariancePercent: nil)
        }

        let firstDate = cycle[0].date
        let xs = cycle.map { $0.date.timeIntervalSince(firstDate) / 3600 }
        let ys = cycle.map(\.usedPercent)
        let slope = self.linearRegressionSlope(xs: xs, ys: ys)
        let currentPercent = latest.usedPercent

        guard slope > 0.01 else {
            return CodexUsageForecast(
                message: "On a safe pace",
                tone: .safe,
                currentPercent: currentPercent,
                projectedPercentAtReset: currentPercent,
                paceVariancePercent: 0
            )
        }

        let hoursToFull = max(0, (100 - latest.usedPercent) / slope)
        let secondsToFull = Int(hoursToFull * 3600)
        if let resetAt = latest.resetsAt {
            let secondsToReset = Int(resetAt.timeIntervalSince(latest.date))
            let projectedPercentAtReset = max(
                currentPercent,
                min(100, currentPercent + slope * (Double(secondsToReset) / 3600))
            )
            let cycleDuration = resetAt.timeIntervalSince(firstDate)
            let elapsed = latest.date.timeIntervalSince(firstDate)
            let expectedPercentNow = cycleDuration > 0
                ? max(0, min(100, (elapsed / cycleDuration) * 100))
                : currentPercent
            let variance = currentPercent - expectedPercentNow
            if secondsToFull > secondsToReset {
                return CodexUsageForecast(
                    message: "\(Int(currentPercent.rounded()))% used",
                    tone: .safe,
                    currentPercent: currentPercent,
                    projectedPercentAtReset: projectedPercentAtReset,
                    paceVariancePercent: variance
                )
            }

            if secondsToFull < 6 * 3600 {
                return CodexUsageForecast(
                    message: "Likely over in \(CodexFormatting.compactDuration(seconds: secondsToFull))",
                    tone: .danger,
                    currentPercent: currentPercent,
                    projectedPercentAtReset: projectedPercentAtReset,
                    paceVariancePercent: variance
                )
            }

            return CodexUsageForecast(
                message: "Likely over in \(CodexFormatting.compactDuration(seconds: secondsToFull))",
                tone: .caution,
                currentPercent: currentPercent,
                projectedPercentAtReset: projectedPercentAtReset,
                paceVariancePercent: variance
            )
        }

        return CodexUsageForecast(
            message: "Likely over in \(CodexFormatting.compactDuration(seconds: secondsToFull))",
            tone: .caution,
            currentPercent: currentPercent,
            projectedPercentAtReset: nil,
            paceVariancePercent: nil
        )
    }

    private static func linearRegressionSlope(xs: [Double], ys: [Double]) -> Double {
        guard xs.count == ys.count, xs.count >= 2 else { return 0 }
        let meanX = xs.reduce(0, +) / Double(xs.count)
        let meanY = ys.reduce(0, +) / Double(ys.count)
        let numerator = zip(xs, ys).reduce(0) { partial, pair in
            partial + ((pair.0 - meanX) * (pair.1 - meanY))
        }
        let denominator = xs.reduce(0) { partial, x in
            partial + pow(x - meanX, 2)
        }
        guard denominator > 0 else { return 0 }
        return numerator / denominator
    }
}
#endif
