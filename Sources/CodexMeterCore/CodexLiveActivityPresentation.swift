import Foundation

#if os(iOS) && canImport(ActivityKit)
import ActivityKit
#endif

/// Small, local-only payload shared by the app and WidgetKit extension.
public struct CodexLiveActivityAttributes: Codable, Hashable, Sendable {
    public struct ContentState: Codable, Hashable, Sendable {
        public let weeklyPercentLeft: Int
        public let weeklyUsedFraction: Double
        public let weeklyResetAt: Date?
        public let fiveHourPercentLeft: Int?
        public let fiveHourResetAt: Date?
        public let isStale: Bool
        /// Optional for decoding Live Activities created before the display-mode setting existed.
        public let showsUsedQuota: Bool?

        public var displaysUsedQuota: Bool { showsUsedQuota ?? false }

        public var displayedWeeklyPercent: Int {
            displaysUsedQuota ? max(0, min(100, 100 - weeklyPercentLeft)) : weeklyPercentLeft
        }

        public var displayedWeeklyFraction: Double {
            let used = max(0, min(1, weeklyUsedFraction))
            return displaysUsedQuota ? used : 1 - used
        }

        public var weeklyDisplayDescription: String {
            "\(displayedWeeklyPercent)% \(displaysUsedQuota ? "used" : "left") of weekly quota"
        }

        public var displayedFiveHourPercent: Int? {
            fiveHourPercentLeft.map { percentLeft in
                displaysUsedQuota ? max(0, min(100, 100 - percentLeft)) : max(0, min(100, percentLeft))
            }
        }

        public var fiveHourDisplayDescription: String? {
            displayedFiveHourPercent.map {
                "\($0)% \(displaysUsedQuota ? "used" : "left") of 5-hour quota"
            }
        }

        public var freshnessDescription: String {
            isStale ? "Update needed" : "Up to date"
        }

        public var accessibilityDescription: String {
            accessibilityDescription(isStale: isStale)
        }

        public func accessibilityDescription(isStale resolvedIsStale: Bool) -> String {
            [
                weeklyDisplayDescription,
                fiveHourDisplayDescription,
                resolvedIsStale ? "Update needed" : "Up to date"
            ]
                .compactMap { $0 }
                .joined(separator: ". ")
        }

        public init(
            weeklyPercentLeft: Int,
            weeklyUsedFraction: Double,
            weeklyResetAt: Date?,
            fiveHourPercentLeft: Int?,
            fiveHourResetAt: Date?,
            isStale: Bool,
            showsUsedQuota: Bool = false
        ) {
            self.weeklyPercentLeft = weeklyPercentLeft
            self.weeklyUsedFraction = weeklyUsedFraction
            self.weeklyResetAt = weeklyResetAt
            self.fiveHourPercentLeft = fiveHourPercentLeft
            self.fiveHourResetAt = fiveHourResetAt
            self.isStale = isStale
            self.showsUsedQuota = showsUsedQuota
        }
    }

    public let name: String
    public init(name: String = "Codex") { self.name = name }
}

#if os(iOS) && canImport(ActivityKit)
extension CodexLiveActivityAttributes: ActivityAttributes {}
#endif

public enum CodexLiveActivityPresentation {
    public static let minimumStaleInterval: TimeInterval = 30 * 60

    public static func resolvedStaleness(
        systemIsStale: Bool,
        contentStateIsStale: Bool
    ) -> Bool {
        systemIsStale || contentStateIsStale
    }

    public static func state(
        snapshot: CodexSnapshot,
        showFiveHour: Bool,
        showUsedQuota: Bool = false,
        stale: Bool = false
    ) -> CodexLiveActivityAttributes.ContentState? {
        guard let limit = snapshot.codexLimit,
              let weekly = exactWindow(minutes: 10_080, in: limit)
                ?? legacyUntaggedWeeklyWindow(in: limit) else {
            return nil
        }
        let fiveHour = showFiveHour
            ? exactWindow(minutes: 300, in: limit) ?? legacyUntaggedFiveHourWindow(in: limit)
            : nil
        return .init(
            weeklyPercentLeft: Int(weekly.remainingPercent.rounded()),
            weeklyUsedFraction: weekly.clampedUsedPercent / 100,
            weeklyResetAt: weekly.resetsAt,
            fiveHourPercentLeft: fiveHour.map { Int($0.remainingPercent.rounded()) },
            fiveHourResetAt: fiveHour?.resetsAt,
            isStale: stale,
            showsUsedQuota: showUsedQuota
        )
    }

    public static func staleDate(capturedAt: Date, cadence: TimeInterval) -> Date {
        capturedAt.addingTimeInterval(max(cadence * 2, minimumStaleInterval))
    }

    private static func exactWindow(minutes: Int, in limit: CodexLimit) -> CodexQuotaWindow? {
        if limit.primary?.windowDurationMinutes == minutes { return limit.primary }
        if limit.secondary?.windowDurationMinutes == minutes { return limit.secondary }
        return nil
    }

    private static func legacyUntaggedWeeklyWindow(in limit: CodexLimit) -> CodexQuotaWindow? {
        if let secondary = limit.secondary, secondary.windowDurationMinutes == nil {
            return secondary
        }
        if let primary = limit.primary, primary.windowDurationMinutes == nil {
            return primary
        }
        return nil
    }

    private static func legacyUntaggedFiveHourWindow(in limit: CodexLimit) -> CodexQuotaWindow? {
        if let primary = limit.primary, primary.windowDurationMinutes == nil {
            return primary
        }
        if let secondary = limit.secondary, secondary.windowDurationMinutes == nil {
            return secondary
        }
        return nil
    }
}

public struct CodexLiveActivityRecoveryPlan: Equatable, Sendable {
    public let primaryID: String?
    public let duplicateIDs: [String]

    public init(primaryID: String?, duplicateIDs: [String]) {
        self.primaryID = primaryID
        self.duplicateIDs = duplicateIDs
    }
}

public enum CodexLiveActivityLifecyclePolicy {
    /// ActivityKit owns persistence. Keep the first system activity and end the rest.
    /// The iOS runtime manager uses this plan during launch, start, and every update.
    public static func recoveryPlan(existingIDs: [String]) -> CodexLiveActivityRecoveryPlan {
        CodexLiveActivityRecoveryPlan(
            primaryID: existingIDs.first,
            duplicateIDs: Array(existingIDs.dropFirst())
        )
    }
}
