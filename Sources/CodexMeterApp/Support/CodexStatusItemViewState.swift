#if os(macOS)
import Foundation
import CodexMeterCore

struct CodexStatusItemViewState: Equatable {
    let title: String
    let isRefreshing: Bool
    let hasError: Bool
    let isStale: Bool
    let severity: CodexQuotaSeverity?
    let showsOpenAILogo: Bool
    let shouldDim: Bool

    var accessibilityValue: String {
        let status: String
        if isRefreshing { status = "Refreshing" }
        else if hasError { status = "Issue" }
        else if isStale { status = "Stale" }
        else if let severity { status = severity.title }
        else { status = "Live" }
        return "\(title), \(status)"
    }

    @MainActor
    init(model: CodexMenuBarModel) {
        if !model.previewModeEnabled, !model.isSignedIn, model.apiMonitor.hasKey {
            let balance = model.apiMonitor.unofficialBalanceEnabled ? model.apiMonitor.balance : nil
            title = balance.map { $0.remainingUSD.formatted(.currency(code: "USD").locale(Locale(identifier: "en_US"))) }
                ?? (model.apiMonitor.keyKind == .billingSession ? "Reconnect API" : "API")
            isRefreshing = model.apiMonitor.isRefreshing
            hasError = model.apiMonitor.error != nil || (model.apiMonitor.unofficialBalanceEnabled && model.apiMonitor.balanceError != nil)
            isStale = balance.map { Date().timeIntervalSince($0.fetchedAt) > 600 } ?? false
            severity = nil
            showsOpenAILogo = true
            shouldDim = !model.apiMonitor.isValidated
            return
        }
        hasError = model.lastError != nil
        showsOpenAILogo = StatusBarLabel.usesOpenAILogo(
            showFiveHour: model.showFiveHourInMenubar,
            showWeekly: model.showWeeklyInMenubar
        )
        title = StatusBarLabel.makeTitle(
            snapshot: model.snapshot,
            isRefreshing: model.isRefreshing,
            hasError: hasError,
            displayMode: model.menuBarDisplayMode,
            showFiveHour: model.showFiveHourInMenubar,
            showWeekly: model.showWeeklyInMenubar,
            insights: model.usageInsights
        )
        isRefreshing = model.isRefreshing
        isStale = model.isDataStale
        severity = hasError || model.isRefreshing ? nil : model.popupSummary?.severity
        shouldDim = model.shouldDimStatusItem
    }
}

struct CodexPopupSizingState: Equatable {
    let isShown: Bool
    let hasStatusCard: Bool
    let hasLocalUsageCard: Bool
    let limitCount: Int
    let historyCount: Int
    let showHistory: Bool
    let showHistoryChart: Bool
    let hasVisibleSummary: Bool
    let hasAPICard: Bool
    let hasAPIBalance: Bool
    let isAPIOnly: Bool
    let appearance: CodexAppearanceMode

    @MainActor
    init(model: CodexMenuBarModel, isShown: Bool) {
        self.isShown = isShown
        hasAPICard = !model.previewModeEnabled && model.apiMonitor.hasKey
        hasAPIBalance = model.apiMonitor.balance != nil
        isAPIOnly = !model.previewModeEnabled && model.snapshot == nil && model.apiMonitor.hasKey
        hasStatusCard = model.shouldShowStatusCard
        hasLocalUsageCard = model.localUsageSummary != nil
        limitCount = model.snapshot?.limits.count ?? 0
        historyCount = model.usageHistory.count
        showHistory = model.showHistoryEnabled
        showHistoryChart = model.showHistoryChartEnabled
        hasVisibleSummary = model.popupSummary != nil && model.isCurrentSummarySnoozed == false
        appearance = model.appearanceMode
    }
}
#endif
