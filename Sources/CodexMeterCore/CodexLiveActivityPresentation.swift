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

        public init(weeklyPercentLeft: Int, weeklyUsedFraction: Double, weeklyResetAt: Date?, fiveHourPercentLeft: Int?, fiveHourResetAt: Date?, isStale: Bool) {
            self.weeklyPercentLeft = weeklyPercentLeft
            self.weeklyUsedFraction = weeklyUsedFraction
            self.weeklyResetAt = weeklyResetAt
            self.fiveHourPercentLeft = fiveHourPercentLeft
            self.fiveHourResetAt = fiveHourResetAt
            self.isStale = isStale
        }
    }

    public let name: String
    public init(name: String = "Codex") { self.name = name }
}

#if os(iOS) && canImport(ActivityKit)
extension CodexLiveActivityAttributes: ActivityAttributes {}
#endif

public enum CodexLiveActivityPresentation {
    public static func state(snapshot: CodexSnapshot, showFiveHour: Bool, stale: Bool = false) -> CodexLiveActivityAttributes.ContentState? {
        guard let weekly = snapshot.codexLimit?.weeklyWindow else { return nil }
        let fiveHour = showFiveHour ? snapshot.codexLimit?.fiveHourWindow : nil
        return .init(
            weeklyPercentLeft: Int(weekly.remainingPercent.rounded()),
            weeklyUsedFraction: weekly.clampedUsedPercent / 100,
            weeklyResetAt: weekly.resetsAt,
            fiveHourPercentLeft: fiveHour.map { Int($0.remainingPercent.rounded()) },
            fiveHourResetAt: fiveHour?.resetsAt,
            isStale: stale
        )
    }

    public static func staleDate(capturedAt: Date, cadence: TimeInterval) -> Date {
        capturedAt.addingTimeInterval(max(cadence * 2, 300))
    }
}

public enum CodexLiveActivityLifecycleAction: Equatable, Sendable {
    case unavailable
    case start
    case update(id: String)
    case end(ids: [String])
    case none
}

public enum CodexLiveActivityLifecyclePolicy {
    public static func action(authorizationAllowed: Bool, existingIDs: [String], explicitStart: Bool, shouldEnd: Bool) -> CodexLiveActivityLifecycleAction {
        guard authorizationAllowed else { return .unavailable }
        if shouldEnd { return existingIDs.isEmpty ? .none : .end(ids: existingIDs) }
        if let id = existingIDs.first { return .update(id: id) }
        return explicitStart ? .start : .none
    }
}
