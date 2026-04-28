import Foundation

public enum CodexQuotaPresentationStyle: Sendable, Equatable {
    case hero
    case standard
    case compact
}

public enum CodexQuotaResetTextStyle: Sendable, Equatable {
    case relative
    case absolute(prefix: String)
}

public struct CodexQuotaLimitPresentation: Sendable, Equatable, Identifiable {
    public let limit: CodexLimit
    public let style: CodexQuotaPresentationStyle
    public let visibleCredits: CodexCredits?
    public let isIdle: Bool

    public var id: String { limit.id }

    public init(
        limit: CodexLimit,
        style: CodexQuotaPresentationStyle,
        visibleCredits: CodexCredits?,
        isIdle: Bool
    ) {
        self.limit = limit
        self.style = style
        self.visibleCredits = visibleCredits
        self.isIdle = isIdle
    }
}

public enum CodexQuotaPresentationRules {
    public static func orderedLimits(_ limits: [CodexLimit]) -> [CodexLimit] {
        limits.sorted { lhs, rhs in
            let leftRank = sortRank(for: lhs)
            let rightRank = sortRank(for: rhs)
            if leftRank != rightRank {
                return leftRank < rightRank
            }
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
    }

    public static func presentation(for limit: CodexLimit) -> CodexQuotaLimitPresentation {
        let visibleCredits = visibleCredits(limit.credits)
        let idle = isIdle(limit)
        return CodexQuotaLimitPresentation(
            limit: limit,
            style: style(for: limit, visibleCredits: visibleCredits, isIdle: idle),
            visibleCredits: visibleCredits,
            isIdle: idle
        )
    }

    public static func shouldShow(
        _ limit: CodexLimit,
        showSpark: Bool,
        hideIdleSecondaryLimits: Bool
    ) -> Bool {
        guard limit.bucket == .spark else { return true }
        guard showSpark else { return false }
        if hideIdleSecondaryLimits, isIdle(limit) {
            return false
        }
        return true
    }

    public static func isIdle(_ limit: CodexLimit) -> Bool {
        [limit.fiveHourWindow, limit.weeklyWindow]
            .compactMap { $0?.clampedUsedPercent }
            .allSatisfy { $0 < 0.5 }
    }

    public static func visibleCredits(_ credits: CodexCredits?) -> CodexCredits? {
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

    public static func resetText(
        style: CodexQuotaResetTextStyle,
        now: Date,
        resetAt: Date?
    ) -> String {
        switch style {
        case .relative:
            return CodexFormatting.relativeResetText(now: now, resetAt: resetAt)
        case .absolute(let prefix):
            guard let resetAt else { return "Reset unknown" }
            let formatter = DateFormatter()
            formatter.locale = Locale.autoupdatingCurrent
            formatter.timeZone = .current
            formatter.dateStyle = Calendar.autoupdatingCurrent.isDate(resetAt, inSameDayAs: now) ? .none : .short
            formatter.timeStyle = .short
            return "\(prefix) \(formatter.string(from: resetAt))"
        }
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
        visibleCredits: CodexCredits?,
        isIdle: Bool
    ) -> CodexQuotaPresentationStyle {
        if limit.bucket == .spark, isIdle, visibleCredits == nil {
            return .compact
        }
        if limit.bucket == .codex {
            return .hero
        }
        return .standard
    }

    private static func normalizedNumber(from text: String) -> Double? {
        let cleaned = text.replacingOccurrences(of: ",", with: "")
        return Double(cleaned)
    }
}
