import Foundation

struct CodexRefreshBackoff: Sendable, Equatable {
    enum FailureClass: Sendable, Equatable {
        case rateLimited
        case serverUnavailable
        case other
    }

    private(set) var failureCount = 0
    private(set) var nextAutomaticRefreshAt: Date?
    let maximumDelay: TimeInterval

    init(maximumDelay: TimeInterval = 10 * 60) {
        self.maximumDelay = maximumDelay
    }

    func allowsAutomaticRefresh(now: Date = Date()) -> Bool {
        guard let nextAutomaticRefreshAt else { return true }
        return now >= nextAutomaticRefreshAt
    }

    mutating func recordSuccess() {
        failureCount = 0
        nextAutomaticRefreshAt = nil
    }

    mutating func recordFailure(_ failureClass: FailureClass, now: Date = Date()) {
        guard failureClass != .other else { return }
        failureCount = min(failureCount + 1, 8)
        let base: TimeInterval = failureClass == .rateLimited ? 20 : 45
        let exponential = min(maximumDelay, base * pow(2, Double(failureCount - 1)))
        let deterministicJitter = TimeInterval((failureCount * 7) % 11)
        nextAutomaticRefreshAt = now.addingTimeInterval(min(maximumDelay, exponential + deterministicJitter))
    }

    static func classify(errorMessage: String) -> FailureClass {
        let text = errorMessage.lowercased()
        if text.contains("429") || text.contains("rate-limit") || text.contains("rate limiting") || text.contains("rate-limiting") {
            return .rateLimited
        }
        if text.contains("500") || text.contains("502") || text.contains("503") || text.contains("504") || text.contains("server") || text.contains("unavailable") {
            return .serverUnavailable
        }
        return .other
    }
}
