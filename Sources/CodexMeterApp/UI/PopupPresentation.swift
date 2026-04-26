import Foundation
import CoreGraphics
import SwiftUI
import CodexMeterCore

enum PopupLimitCardStyle: Equatable {
    case hero
    case standard
    case compact
}

struct PopupLimitPresentation: Equatable, Identifiable {
    let limit: CodexLimit
    let style: PopupLimitCardStyle
    let visibleCredits: CodexCredits?

    var id: String { limit.id }
}

enum PopupSummaryAction: Equatable {
    case openSettings
    case refresh
    case useSampleData

    var title: String {
        switch self {
        case .openSettings:
            return "Open Settings"
        case .refresh:
            return "Refresh"
        case .useSampleData:
            return "Use Sample Data"
        }
    }

    var systemImage: String {
        switch self {
        case .openSettings:
            return "slider.horizontal.3"
        case .refresh:
            return "arrow.clockwise"
        case .useSampleData:
            return "wand.and.stars"
        }
    }
}

enum CodexQuotaSeverity: Int, Equatable {
    case tooEarly = 0
    case safe = 1
    case watch = 2
    case risk = 3

    var title: String {
        switch self {
        case .tooEarly:
            return "Too early"
        case .safe:
            return "Safe"
        case .watch:
            return "Watch"
        case .risk:
            return "Risk"
        }
    }

    var color: Color {
        switch self {
        case .tooEarly:
            return .secondary
        case .safe:
            return .green
        case .watch:
            return .orange
        case .risk:
            return .red
        }
    }

    static func from(_ tone: CodexUsageForecast.Tone) -> CodexQuotaSeverity {
        switch tone {
        case .safe:
            return .safe
        case .caution:
            return .watch
        case .danger:
            return .risk
        }
    }

    static func from(_ tone: CodexUsageInsightTone) -> CodexQuotaSeverity {
        switch tone {
        case .safe:
            return .safe
        case .caution:
            return .watch
        case .danger:
            return .risk
        }
    }
}

struct PopupSummaryPresentation: Equatable {
    let severity: CodexQuotaSeverity
    let title: String
    let message: String
    let supportingLabel: String
    let supportingValue: String
    let supportingDetail: String?
    let action: PopupSummaryAction?
}

enum PopupPresentation {
    static func historyLegendValue(for forecast: CodexUsageForecast) -> String {
        guard let currentPercent = forecast.currentPercent else {
            return forecast.confidence.label
        }
        return "\(Int(currentPercent.rounded()))%"
    }

    static func summary(
        snapshot: CodexSnapshot?,
        insights: CodexUsageInsights?,
        previewModeEnabled: Bool,
        hasRefreshIssue: Bool
    ) -> PopupSummaryPresentation? {
        guard snapshot != nil, let insights else { return nil }

        let weekly = insights.weeklyPace
        let refreshAction: PopupSummaryAction? = hasRefreshIssue ? .refresh : nil

        if weekly.confidence == .tooEarly || weekly.confidence == .learning {
            return PopupSummaryPresentation(
                severity: .tooEarly,
                title: CodexQuotaSeverity.tooEarly.title,
                message: weekly.confidence == .tooEarly
                    ? "Not enough cycle data yet."
                    : "Still learning this cycle.",
                supportingLabel: "Weekly pace",
                supportingValue: weekly.message,
                supportingDetail: weekly.detail,
                action: refreshAction
            )
        }

        let weeklySeverity = CodexQuotaSeverity.from(weekly.tone)
        let fiveHourSeverity = CodexQuotaSeverity.from(insights.fiveHourPressure.tone)
        let severity = fiveHourSeverity.rawValue > weeklySeverity.rawValue
            ? fiveHourSeverity
            : weeklySeverity
        let usesFiveHourPressure = fiveHourSeverity.rawValue > weeklySeverity.rawValue

        let weeklySupport = weeklySupporting(forecast: weekly)

        switch severity {
        case .safe:
            return PopupSummaryPresentation(
                severity: .safe,
                title: CodexQuotaSeverity.safe.title,
                message: "You are on track for this cycle.",
                supportingLabel: weeklySupport.label,
                supportingValue: weeklySupport.value,
                supportingDetail: weeklySupport.detail,
                action: previewModeEnabled ? nil : refreshAction
            )
        case .watch:
            return PopupSummaryPresentation(
                severity: .watch,
                title: CodexQuotaSeverity.watch.title,
                message: usesFiveHourPressure
                    ? "Short-term pressure is building."
                    : "Usage is rising faster than planned.",
                supportingLabel: usesFiveHourPressure ? insights.fiveHourPressure.title : weeklySupport.label,
                supportingValue: usesFiveHourPressure ? insights.fiveHourPressure.message : weeklySupport.value,
                supportingDetail: usesFiveHourPressure
                    ? insights.fiveHourPressure.detail
                    : weeklySupport.detail,
                action: previewModeEnabled ? nil : refreshAction
            )
        case .risk:
            return PopupSummaryPresentation(
                severity: .risk,
                title: CodexQuotaSeverity.risk.title,
                message: usesFiveHourPressure
                    ? "Short-term pressure is unusually high."
                    : "You are likely to hit the weekly limit.",
                supportingLabel: usesFiveHourPressure ? insights.fiveHourPressure.title : weeklySupport.label,
                supportingValue: usesFiveHourPressure ? insights.fiveHourPressure.message : weeklySupport.value,
                supportingDetail: usesFiveHourPressure
                    ? insights.fiveHourPressure.detail
                    : weeklySupport.detail,
                action: previewModeEnabled ? nil : refreshAction
            )
        case .tooEarly:
            return nil
        }
    }

    static func historyBarRect(
        usedPercent: Double,
        index: Int,
        count: Int,
        size: CGSize
    ) -> CGRect {
        guard count > 0, size.width > 0, size.height > 0 else {
            return .zero
        }

        let spacing: CGFloat = count > 18 ? 4 : 5
        let totalSpacing = spacing * CGFloat(max(count - 1, 0))
        let barWidth = max(3, (size.width - totalSpacing) / CGFloat(count))
        let clamped = min(max(usedPercent, 0), 100)
        let barHeight = max(2, size.height * CGFloat(clamped / 100))
        let x = CGFloat(index) * (barWidth + spacing)

        return CGRect(
            x: x,
            y: size.height - barHeight,
            width: barWidth,
            height: barHeight
        )
    }

    static func orderedLimits(_ limits: [CodexLimit]) -> [CodexLimit] {
        limits.sorted { lhs, rhs in
            let leftRank = sortRank(for: lhs)
            let rightRank = sortRank(for: rhs)
            if leftRank != rightRank {
                return leftRank < rightRank
            }
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
    }

    static func presentation(for limit: CodexLimit) -> PopupLimitPresentation {
        let visibleCredits = visibleCredits(for: limit.credits)
        return PopupLimitPresentation(
            limit: limit,
            style: style(for: limit, visibleCredits: visibleCredits),
            visibleCredits: visibleCredits
        )
    }

    private static func sortRank(for limit: CodexLimit) -> Int {
        switch limit.bucket {
        case .codex:
            return 0
        case .other:
            return 1
        case .spark:
            return 2
        }
    }

    static func isIdle(_ limit: CodexLimit) -> Bool {
        [limit.fiveHourWindow, limit.weeklyWindow]
            .compactMap { $0?.clampedUsedPercent }
            .allSatisfy { $0 < 0.5 }
    }

    private static func style(
        for limit: CodexLimit,
        visibleCredits: CodexCredits?
    ) -> PopupLimitCardStyle {
        if limit.bucket == .spark, isIdle(limit), visibleCredits == nil {
            return .compact
        }
        if limit.bucket == .codex {
            return .hero
        }
        return .standard
    }

    private static func visibleCredits(for credits: CodexCredits?) -> CodexCredits? {
        guard let credits else { return nil }
        guard credits.unlimited == false else { return nil }

        let text = credits.displayText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.isEmpty == false else { return nil }
        guard text.caseInsensitiveCompare("None") != .orderedSame else { return nil }

        if let numericValue = normalizedNumber(from: text), numericValue == 0 {
            return nil
        }

        return credits
    }

    private static func normalizedNumber(from text: String) -> Double? {
        let cleaned = text.replacingOccurrences(of: ",", with: "")
        return Double(cleaned)
    }

    private static func weeklySupporting(
        forecast: CodexUsageForecast
    ) -> (label: String, value: String, detail: String?) {
        return (
            label: "Weekly forecast",
            value: summaryForecastValue(forecast),
            detail: summaryForecastDetail(forecast)
        )
    }

    private static func summaryForecastValue(_ forecast: CodexUsageForecast) -> String {
        switch forecast.confidence {
        case .tooEarly, .learning, .estimatedFromHistory:
            return forecast.message
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

    private static func summaryForecastDetail(_ forecast: CodexUsageForecast) -> String? {
        switch forecast.confidence {
        case .tooEarly, .learning:
            return forecast.detail
        case .estimatedFromHistory:
            return "Based on history"
        case .patternMatched, .machineLearned, .stable, .volatile:
            guard let projected = forecast.projectedPercentAtReset else {
                return nil
            }
            guard let range = rangeSummary(for: forecast) else {
                return "\(Int(projected.rounded()))% by reset"
            }
            return "\(Int(projected.rounded()))% by reset · \(range)"
        }
    }

    private static func rangeSummary(for forecast: CodexUsageForecast) -> String? {
        guard let lower = forecast.likelyLowerPercent,
              let upper = forecast.likelyUpperPercent,
              upper - lower >= 2 else {
            return nil
        }
        return "likely \(Int(lower.rounded()))-\(Int(upper.rounded()))%"
    }

}
