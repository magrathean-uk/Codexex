import Foundation
import CodexMeterCore

struct CodexDashboardState {
    var snapshot: CodexSnapshot?
    var isRefreshing = false
    var lastError: String?
    var lastUpdatedAt: Date?
    var usageHistory: [CodexUsageHistorySample] = []
    var usageInsights: CodexUsageInsights?

    mutating func setHistory(_ history: [CodexUsageHistorySample], now: Date = Date()) {
        usageHistory = history
        refreshInsights(now: now)
    }

    mutating func applySnapshot(_ snapshot: CodexSnapshot, history: [CodexUsageHistorySample]) {
        self.snapshot = snapshot
        lastUpdatedAt = snapshot.capturedAt
        lastError = nil
        usageHistory = history
        refreshInsights(now: snapshot.capturedAt)
    }

    mutating func clearSnapshot(keepHistory: Bool = true, now: Date = Date()) {
        snapshot = nil
        lastUpdatedAt = nil
        lastError = nil
        if keepHistory == false {
            usageHistory = []
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
