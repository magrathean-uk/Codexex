#if os(macOS)
import Foundation
import CodexMeterCore

struct CodexLocalIntelligenceSummary: Equatable {
    let severity: CodexQuotaSeverity
    let title: String
    let message: String
    let supportingLabel: String
    let supportingValue: String
    let supportingDetail: String?
}

enum CodexLocalIntelligence {
    static func summary(
        insights: CodexUsageInsights?,
        localUsage: CodexLocalUsageSummary?
    ) -> CodexLocalIntelligenceSummary? {
        let weekly = insights?.weeklyPace
        let burnSignal = localUsage.flatMap(strongestBurnSignal)

        guard weekly != nil || burnSignal != nil else {
            return nil
        }

        let forecastSeverity = weekly.map { CodexQuotaSeverity.from($0.tone) } ?? .safe
        let severity = burnSignal == nil
            ? forecastSeverity
            : maxSeverity(forecastSeverity, .watch)

        let riskTitle = switch severity {
        case .risk:
            "Danger"
        case .watch:
            "Watch"
        case .safe:
            "Safe"
        case .tooEarly:
            "Learning"
        }

        let rangeText = weekly.flatMap(likelyRangeText)
        let forecastSentence: String
        if let weekly, isZeroPressureForecast(weekly) {
            forecastSentence = "No weekly pressure yet."
        } else if let rangeText {
            forecastSentence = "Likely \(rangeText) by reset."
        } else if let weekly {
            forecastSentence = weekly.message.hasSuffix(".") ? weekly.message : "\(weekly.message)."
        } else {
            forecastSentence = "Local burn pattern needs attention."
        }

        let burnSentence = burnSignal.map { "\($0.title) detected." }
        let message = [forecastSentence, burnSentence]
            .compactMap { $0 }
            .joined(separator: " ")

        return CodexLocalIntelligenceSummary(
            severity: severity,
            title: riskTitle,
            message: message,
            supportingLabel: "Local AI",
            supportingValue: supportingValue(rangeText: rangeText, weekly: weekly, burnSignal: burnSignal),
            supportingDetail: burnSignal?.detail ?? weekly?.detail
        )
    }

    static func popupSummary(
        insights: CodexUsageInsights?,
        localUsage: CodexLocalUsageSummary?,
        fallback: PopupSummaryPresentation?
    ) -> PopupSummaryPresentation? {
        guard let summary = summary(insights: insights, localUsage: localUsage) else {
            return fallback
        }

        let action = fallback?.action
        return PopupSummaryPresentation(
            severity: summary.severity,
            title: summary.title,
            message: summary.message,
            supportingLabel: summary.supportingLabel,
            supportingValue: summary.supportingValue,
            supportingDetail: summary.supportingDetail,
            action: action
        )
    }

    private static func likelyRangeText(_ forecast: CodexUsageForecast) -> String? {
        guard isZeroPressureForecast(forecast) == false else {
            return nil
        }
        if let lower = forecast.likelyLowerPercent,
           let upper = forecast.likelyUpperPercent {
            let roundedLower = Int(lower.rounded())
            let roundedUpper = Int(upper.rounded())
            if abs(roundedUpper - roundedLower) >= 2 {
                return "\(roundedLower)-\(roundedUpper)%"
            }
            return "\(roundedUpper)%"
        }

        if let projection = forecast.projectedPercentAtReset {
            return "\(Int(projection.rounded()))%"
        }

        return nil
    }

    private static func supportingValue(
        rangeText: String?,
        weekly: CodexUsageForecast?,
        burnSignal: CodexLocalWasteSignal?
    ) -> String {
        if let weekly, isZeroPressureForecast(weekly) {
            return "Low"
        }
        return rangeText ?? burnSignal?.title ?? weekly?.confidence.label ?? "Learning"
    }

    private static func isZeroPressureForecast(_ forecast: CodexUsageForecast) -> Bool {
        let current = forecast.currentPercent ?? 0
        let projected = forecast.projectedPercentAtReset ?? 0
        let upper = forecast.likelyUpperPercent ?? projected
        return max(current, projected, upper) < 0.5
    }

    private static func strongestBurnSignal(from summary: CodexLocalUsageSummary) -> CodexLocalWasteSignal? {
        summary.wasteSignals.max { lhs, rhs in
            signalPriority(lhs.kind) < signalPriority(rhs.kind)
        }
    }

    private static func signalPriority(_ kind: CodexLocalWasteSignalKind) -> Int {
        switch kind {
        case .heavySession:
            return 50
        case .suddenSpike:
            return 40
        case .modelOverkill:
            return 30
        case .toolLoop:
            return 20
        case .highCacheRead:
            return 10
        }
    }

    private static func maxSeverity(
        _ lhs: CodexQuotaSeverity,
        _ rhs: CodexQuotaSeverity
    ) -> CodexQuotaSeverity {
        lhs.rawValue >= rhs.rawValue ? lhs : rhs
    }
}
#endif
