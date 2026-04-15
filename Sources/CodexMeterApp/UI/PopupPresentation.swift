import Foundation
import CoreGraphics
import CodexMeterCore

enum PopupLimitCardStyle: Equatable {
    case hero
    case standard
    case compact
}

enum PopupSupplementalSection: Hashable {
    case history
    case insights
}

struct PopupLimitPresentation: Equatable, Identifiable {
    let limit: CodexLimit
    let style: PopupLimitCardStyle
    let visibleCredits: CodexCredits?

    var id: String { limit.id }
}

enum PopupPresentation {
    static func supplementalSections(
        showHistory: Bool,
        showInsights: Bool
    ) -> [PopupSupplementalSection] {
        var sections: [PopupSupplementalSection] = []
        if showHistory {
            sections.append(.history)
        }
        if showInsights {
            sections.append(.insights)
        }
        return sections
    }

    static func historyLegendValue(for forecast: CodexUsageForecast) -> String {
        guard let currentPercent = forecast.currentPercent else {
            return "Learning"
        }
        return "\(Int(currentPercent.rounded()))%"
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

    private static func isIdle(_ limit: CodexLimit) -> Bool {
        [limit.fiveHourWindow, limit.weeklyWindow]
            .compactMap { $0?.clampedUsedPercent }
            .allSatisfy { $0 < 0.5 }
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
}
