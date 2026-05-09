import Foundation
import CodexMeterCore

struct CodexDashboardState {
    var snapshot: CodexSnapshot?
    var isRefreshing = false
    var lastError: String?
    var lastUpdatedAt: Date?
    var usageHistory: [CodexUsageHistorySample] = []
    var usageInsights: CodexUsageInsights?
    var localUsageSummary: CodexLocalUsageSummary?

    mutating func setHistory(_ history: [CodexUsageHistorySample], now: Date = Date()) {
        usageHistory = history
        refreshInsights(now: now)
    }

    mutating func setHistory(_ state: CodexHistoryRepositoryState) {
        usageHistory = state.samples
        usageInsights = state.insights
    }

    mutating func applyLocalUsageSummary(_ summary: CodexLocalUsageSummary?) {
        localUsageSummary = summary
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

    mutating func clearSnapshot(keepHistory: Bool = true, now: Date = Date()) {
        snapshot = nil
        lastUpdatedAt = nil
        lastError = nil
        if keepHistory == false {
            usageHistory = []
        }
        localUsageSummary = nil
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
