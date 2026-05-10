#if os(macOS)
import Foundation
import CodexMeterCore

struct CodexStatusItemViewState: Equatable {
    let title: String
    let isRefreshing: Bool
    let hasError: Bool
    let isStale: Bool
    let severity: CodexQuotaSeverity?
    let shouldDim: Bool

    @MainActor
    init(model: CodexMenuBarModel) {
        hasError = model.lastError != nil
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
    let showSpark: Bool
    let hasVisibleSummary: Bool
    let appearance: CodexAppearanceMode

    @MainActor
    init(model: CodexMenuBarModel, isShown: Bool) {
        self.isShown = isShown
        hasStatusCard = model.shouldShowStatusCard
        hasLocalUsageCard = model.localUsageSummary != nil
        limitCount = model.snapshot?.limits.count ?? 0
        historyCount = model.usageHistory.count
        showHistory = model.showHistoryEnabled
        showHistoryChart = model.showHistoryChartEnabled
        showSpark = model.showSparkEnabled
        hasVisibleSummary = model.popupSummary != nil && model.isCurrentSummarySnoozed == false
        appearance = model.appearanceMode
    }
}
#endif
