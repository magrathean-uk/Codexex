import Foundation
import CodexMeterCore

enum CodexLocalUsageLoadState: Sendable, Equatable {
    case idle
    case loading
    case available
    case unavailable(String)

    var statusText: String {
        switch self {
        case .idle: return "Not checked"
        case .loading: return "Indexing local sessions"
        case .available: return "Available"
        case .unavailable(let message): return message
        }
    }
}

struct CodexDashboardState {
    var snapshot: CodexSnapshot?
    var isRefreshing = false
    var lastError: String?
    var lastUpdatedAt: Date?
    var usageHistory: [CodexUsageHistorySample] = []
    var usageInsights: CodexUsageInsights?
    var localUsageSummary: CodexLocalUsageSummary?
    var localUsageLoadState: CodexLocalUsageLoadState = .idle

    mutating func setHistory(_ history: [CodexUsageHistorySample], now: Date = Date()) {
        usageHistory = history
        refreshInsights(now: now)
    }

    mutating func setHistory(_ state: CodexHistoryRepositoryState) {
        usageHistory = state.samples
        usageInsights = state.insights
    }

    mutating func beginLocalUsageLoad() {
        localUsageLoadState = .loading
    }

    mutating func applyLocalUsageResult(_ result: CodexLocalUsageFetchResult) {
        switch result {
        case .available(let summary):
            localUsageSummary = summary
            localUsageLoadState = .available
        case .unavailable(let message):
            localUsageLoadState = .unavailable(message)
        }
    }

    mutating func applySnapshot(_ snapshot: CodexSnapshot, history: [CodexUsageHistorySample]) {
        self.snapshot = snapshot
        lastUpdatedAt = snapshot.capturedAt
        lastError = nil
        usageHistory = history
        refreshInsights(now: snapshot.capturedAt)
    }

    mutating func applySnapshot(_ snapshot: CodexSnapshot, historyState: CodexHistoryRepositoryState) {
        self.snapshot = snapshot
        lastUpdatedAt = snapshot.capturedAt
        lastError = nil
        usageHistory = historyState.samples
        usageInsights = historyState.insights
    }

    mutating func clearSnapshot(
        keepHistory: Bool = true,
        keepLocalUsage: Bool = true,
        now: Date = Date()
    ) {
        snapshot = nil
        lastUpdatedAt = nil
        lastError = nil
        if keepHistory == false {
            usageHistory = []
        }
        if keepLocalUsage == false {
            localUsageSummary = nil
            localUsageLoadState = .idle
        }
        refreshInsights(now: now)
    }

    mutating func setError(_ message: String?, now: Date = Date()) {
        lastError = message
        refreshInsights(now: now)
    }

    mutating func applyPreview(now: Date) {
        snapshot = CodexPreviewData.snapshot(now: now)
        usageHistory = CodexPreviewData.history(now: now)
        localUsageSummary = CodexPreviewData.localUsageSummary(now: now)
        localUsageLoadState = .available
        lastUpdatedAt = now
        lastError = nil
        refreshInsights(now: now)
    }

    mutating func refreshInsights(now: Date = Date()) {
        usageInsights = CodexUsageHistoryAnalytics.insights(
            snapshot: snapshot,
            samples: usageHistory,
            now: snapshot?.capturedAt ?? lastUpdatedAt ?? now
        )
    }
}
