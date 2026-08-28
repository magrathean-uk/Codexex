#if os(macOS)
import Foundation
import Observation
import SwiftUI
import CodexMeterCore

enum PopupRootDisplayMode {
    case live
    case settingsPreview
}

struct PopupRootView: View {
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @Bindable var model: CodexMenuBarModel
    @State private var showsLocalUsageDetails = false
    var onOpenSettings: () -> Void = {}
    var displayMode: PopupRootDisplayMode = .live
    var reduceMotionOverride: Bool?
    private let previewReferenceDate: Date

    init(
        model: CodexMenuBarModel,
        onOpenSettings: @escaping () -> Void = {},
        displayMode: PopupRootDisplayMode = .live,
        reduceMotionOverride: Bool? = nil,
        previewReferenceDate: Date = Date()
    ) {
        self.model = model
        self.onOpenSettings = onOpenSettings
        self.displayMode = displayMode
        self.reduceMotionOverride = reduceMotionOverride
        self.previewReferenceDate = previewReferenceDate
    }

    var body: some View {
        popupContent
            .frame(width: GlassTokens.popupWidth, alignment: .topLeading)
            .background(CodexTheme.window)
            .preferredColorScheme(model.appearanceMode.colorScheme)
            .onAppear {
                model.setReduceMotionEnabled(reduceMotionEnabled)
            }
            .onChange(of: accessibilityReduceMotion) { _, newValue in
                guard reduceMotionOverride == nil else { return }
                model.setReduceMotionEnabled(newValue)
            }
    }

    private var reduceMotionEnabled: Bool {
        reduceMotionOverride ?? accessibilityReduceMotion
    }

    private var popupContent: some View {
        Group {
            if displayMode == .live {
                ViewThatFits(in: .vertical) {
                    VStack(alignment: .leading, spacing: 0) {
                        paddedMainContent
                        paddedFooter
                    }
                    .fixedSize(horizontal: false, vertical: true)

                    VStack(alignment: .leading, spacing: 0) {
                        scrollableMainContent
                        paddedFooter
                    }
                }
            } else {
                scrollableMainContent
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .transaction { transaction in
            transaction.animation = nil
            transaction.disablesAnimations = true
        }
    }

    private var paddedMainContent: some View {
        mainContent
            .padding(.horizontal, GlassTokens.pagePadding)
            .padding(.top, GlassTokens.pagePadding)
            .padding(.bottom, GlassTokens.contentSpacing / 2)
            .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var scrollableMainContent: some View {
        ScrollView {
            paddedMainContent
        }
        .scrollIndicators(.automatic)
        .frame(maxHeight: GlassTokens.popupMaxHeight - GlassTokens.popupFooterReservedHeight)
    }

    private var paddedFooter: some View {
        footer
            .padding(.horizontal, GlassTokens.pagePadding)
            .padding(.bottom, GlassTokens.pagePadding)
            .background(CodexTheme.window)
    }

    private var mainContent: some View {
        VStack(alignment: .leading, spacing: GlassTokens.contentSpacing) {
            if shouldShowStatusCard {
                PopupStatusCardView(model: model)
            }

            if let summary = presentedSummary {
                PopupSummaryCardView(
                    summary: summary,
                    performAction: performSummaryAction(_:),
                    onSnooze: displayMode == .live ? { model.snoozeSummary(summary) } : nil
                )
            }

            if quotaLimitPresentations.isEmpty == false {
                quotaGroup
            }

            if showHistorySection {
                UsageHistoryCardView(
                    samples: presentedHistory,
                    showsChart: model.showHistoryChartEnabled,
                    historyMode: model.defaultHistoryMode,
                    showPaceConfidence: model.showPaceConfidence,
                    showFiveHour: model.showFiveHourInMenubar,
                    resetDisplayStyle: model.resetDisplayStyle,
                    onHistoryModeChange: { model.setDefaultHistoryMode($0) }
                )
            }

            if shouldShowLocalUsageSection {
                localUsageSection
            }
        }
    }

    private var shouldShowLocalUsageSection: Bool {
        if displayMode == .settingsPreview {
            return presentedLocalUsageSummary != nil
        }
        return model.localUsageSummary != nil || model.localUsageLoadState != .idle
    }

    private var localUsageSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                showsLocalUsageDetails.toggle()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: showsLocalUsageDetails ? "chevron.down" : "chevron.right")
                    Text("Local usage")
                        .font(.system(size: GlassTokens.popupBodyFontSize, weight: .semibold))
                    Spacer(minLength: 0)
                    Text(localUsageScopeText)
                        .font(.system(size: GlassTokens.popupMetaFontSize))
                        .foregroundStyle(CodexTheme.dim)
                        .lineLimit(1)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(showsLocalUsageDetails ? "Expanded" : "Collapsed")

            if showsLocalUsageDetails {
                if let message = localUsageUnavailableMessage {
                    PopupPlainSection {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(message)
                                .font(.system(size: GlassTokens.popupBodyFontSize))
                                .foregroundStyle(CodexTheme.muted)
                                .fixedSize(horizontal: false, vertical: true)
                            Button("Choose Sessions Folder") {
                                model.chooseCodexSessionsFolder()
                            }
                            .buttonStyle(CodexGhostButtonStyle())
                        }
                    }
                }
                if let summary = presentedLocalUsageSummary {
                    CodexLocalUsageCardView(summary: summary) {
                        model.chooseCodexSessionsFolder()
                    }
                } else {
                    PopupPlainSection {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(model.localUsageLoadState.statusText)
                                .font(.system(size: GlassTokens.popupBodyFontSize))
                                .foregroundStyle(CodexTheme.muted)
                                .fixedSize(horizontal: false, vertical: true)
                            Button("Choose Sessions Folder") {
                                model.chooseCodexSessionsFolder()
                            }
                            .buttonStyle(CodexGhostButtonStyle())
                        }
                    }
                }
            }
        }
    }

    private var localUsageScopeText: String {
        if localUsageUnavailableMessage != nil {
            return "Access needed"
        }
        if let summary = presentedLocalUsageSummary {
            return summary.coverage.label
        }
        return model.localUsageLoadState.statusText
    }

    private var localUsageUnavailableMessage: String? {
        guard displayMode == .live,
              case .unavailable(let message) = model.localUsageLoadState else {
            return nil
        }
        return message
    }

    private var footer: some View {
        VStack(alignment: .trailing, spacing: 6) {
            if let lastUpdatedAt = presentedLastUpdatedAt {
                Text(updatedText(for: lastUpdatedAt))
                    .font(.system(size: GlassTokens.popupMetaFontSize))
                    .foregroundStyle(CodexTheme.dim)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .allowsHitTesting(false)
            }

            HStack(spacing: 8) {
                PopupFooterControl(
                    title: "Settings",
                    systemImage: "gearshape",
                    tone: .secondary,
                    accessibilityIdentifier: "mac.popup.settings"
                ) {
                    onOpenSettings()
                }

                PopupFooterControl(
                    title: model.isRefreshing ? "Refreshing" : "Refresh",
                    systemImage: "arrow.clockwise",
                    tone: usesMonochromeRecoveryControls ? .secondary : .primary,
                    accessibilityIdentifier: "mac.popup.refresh"
                ) {
                    guard model.isRefreshing == false else { return }
                    Task { await model.refreshNow(manual: true) }
                }
                .disabled(model.isRefreshing)
            }
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private var usesMonochromeRecoveryControls: Bool {
        guard displayMode == .live, presentedSnapshot == nil else { return false }
        return model.lastError != nil || (
            model.hasResolvedAuthState && model.isSignedIn == false
        )
    }

    private func updatedText(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return "Updated \(formatter.string(from: date))"
    }

    private var orderedLimitPresentations: [PopupLimitPresentation] {
        guard let snapshot = presentedSnapshot else { return [] }
        return PopupPresentation.orderedLimits(snapshot.limits).map(PopupPresentation.presentation(for:))
    }

    private var quotaLimitPresentations: [PopupLimitPresentation] {
        orderedLimitPresentations.filter { presentation in
            guard presentation.limit.bucket == .spark else { return true }
            return CodexQuotaPresentationRules.shouldShow(
                presentation.limit,
                showSpark: model.showSparkEnabled,
                hideIdleSecondaryLimits: model.hideIdleSecondaryLimits
            )
        }
    }

    private var showHistorySection: Bool {
        model.showHistoryEnabled && presentedHistory.isEmpty == false
    }

    private var quotaGroup: some View {
        PopupPlainSection {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(quotaLimitPresentations.enumerated()), id: \.element.id) { index, presentation in
                    if index > 0 {
                        PopupQuotaDivider()
                    }
                    limitCard(for: presentation)
                }
            }
        }
    }

    @ViewBuilder
    private func limitCard(for presentation: PopupLimitPresentation) -> some View {
        switch presentation.style {
        case .compact:
            CompactLimitCardView(presentation: presentation)
        case .hero, .standard:
            LimitCardView(
                presentation: presentation,
                resetDisplayStyle: model.resetDisplayStyle,
                displayMode: model.menuBarDisplayMode,
                showFiveHour: model.showFiveHourInMenubar
            )
        }
    }

    private var shouldShowStatusCard: Bool {
        displayMode == .live && model.shouldShowStatusCard
    }

    private var presentedSnapshot: CodexSnapshot? {
        if displayMode == .settingsPreview {
            return model.snapshot ?? CodexPreviewData.snapshot(now: previewReferenceDate)
        }
        if model.previewModeEnabled {
            return model.snapshot ?? CodexPreviewData.snapshot(now: previewReferenceDate)
        }
        return model.snapshot
    }

    private var presentedHistory: [CodexUsageHistorySample] {
        if displayMode == .settingsPreview,
           model.usageHistory.isEmpty,
           model.snapshot == nil {
            return CodexPreviewData.history(now: previewReferenceDate)
        }
        if displayMode == .live,
           model.previewModeEnabled,
           model.usageHistory.isEmpty {
            return CodexPreviewData.history(now: previewReferenceDate)
        }
        return model.usageHistory
    }

    private var presentedInsights: CodexUsageInsights? {
        if displayMode == .live {
            return model.usageInsights
        }
        return CodexUsageHistoryAnalytics.insights(
            snapshot: presentedSnapshot,
            samples: presentedHistory,
            now: presentedLastUpdatedAt ?? previewReferenceDate
        )
    }

    private var presentedLocalUsageSummary: CodexLocalUsageSummary? {
        if displayMode == .settingsPreview,
           model.localUsageSummary == nil {
            return CodexPreviewData.localUsageSummary(now: previewReferenceDate)
        }
        if displayMode == .live,
           model.previewModeEnabled {
            return model.localUsageSummary ?? CodexPreviewData.localUsageSummary(now: previewReferenceDate)
        }
        return model.localUsageSummary
    }

    private var presentedSummary: PopupSummaryPresentation? {
        let fallback = PopupPresentation.summary(
            snapshot: presentedSnapshot,
            insights: presentedInsights,
            previewModeEnabled: displayMode == .live && model.previewModeEnabled,
            hasRefreshIssue: displayMode == .live && model.lastError != nil,
            showFiveHour: model.showFiveHourInMenubar
        )
        let summary = CodexLocalIntelligence.popupSummary(
            insights: presentedInsights,
            localUsage: presentedLocalUsageSummary,
            fallback: fallback
        )
        guard displayMode == .live, let summary else { return summary }
        return model.isSummarySnoozed(summary) ? nil : summary
    }

    private var presentedLastUpdatedAt: Date? {
        if displayMode == .settingsPreview {
            return model.lastUpdatedAt ?? previewReferenceDate
        }
        return model.lastUpdatedAt
    }

    private func performSummaryAction(_ action: PopupSummaryAction) {
        switch action {
        case .openSettings:
            onOpenSettings()
        case .refresh:
            Task { await model.refreshNow(manual: true) }
        case .useSampleData:
            model.enablePreviewMode()
        }
    }
}

private struct PopupQuotaDivider: View {
    var body: some View {
        Rectangle()
            .fill(CodexTheme.hairline)
            .frame(height: 1)
            .padding(.vertical, 8)
    }
}

private struct PopupFooterControl: View {
    enum Tone {
        case primary
        case secondary
    }

    @Environment(\.isEnabled) private var isEnabled
    let title: String
    let systemImage: String
    let tone: Tone
    let accessibilityIdentifier: String
    let action: () -> Void

    var body: some View {
        PopupAppKitButton(
            title: title,
            systemImage: systemImage,
            tone: tone == .primary ? .primary : .secondary,
            minimumWidth: 92,
            accessibilityIdentifier: accessibilityIdentifier,
            isEnabled: isEnabled,
            action: action
        )
        .frame(maxWidth: .infinity, minHeight: GlassTokens.pillHeight)
    }
}

struct PopupLoadingBar: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isActive = false
    var monochrome = false

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            let segmentWidth = max(46, width * 0.30)

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(
                        monochrome
                            ? Color.primary.opacity(0.12)
                            : CodexTheme.control.opacity(0.82)
                    )

                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: monochrome
                                ? [Color.primary.opacity(0.82), Color.secondary]
                                : [CodexTheme.accent, CodexTheme.accent2],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: segmentWidth)
                    .offset(x: reduceMotion ? 0 : (isActive ? width - segmentWidth : 0))
                    .opacity(reduceMotion ? 0.78 : 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
        }
        .frame(height: 6)
        .onAppear {
            guard reduceMotion == false else { return }
            isActive = true
        }
        .animation(
            reduceMotion ? nil : .easeInOut(duration: 1.05).repeatForever(autoreverses: true),
            value: isActive
        )
        .transaction { transaction in
            transaction.disablesAnimations = false
        }
    }
}

#endif
