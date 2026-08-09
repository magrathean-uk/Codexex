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
        VStack(alignment: .leading, spacing: GlassTokens.contentSpacing) {
            mainContent

            if displayMode == .live {
                footer
            }
        }
        .padding(GlassTokens.pagePadding)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .transaction { transaction in
            transaction.animation = nil
            transaction.disablesAnimations = true
        }
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
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            PopupFooterControl(
                title: "Settings",
                systemImage: "gearshape",
                tone: .secondary,
                accessibilityIdentifier: "mac.popup.settings"
            ) {
                onOpenSettings()
            }

            Spacer(minLength: 12)

            if let lastUpdatedAt = presentedLastUpdatedAt {
                Text(updatedText(for: lastUpdatedAt))
                    .font(.system(size: GlassTokens.popupMetaFontSize))
                    .foregroundStyle(CodexTheme.dim)
                    .lineLimit(1)
                    .frame(minWidth: 104, alignment: .trailing)
                    .allowsHitTesting(false)
            }

            PopupFooterControl(
                title: model.isRefreshing ? "Refreshing" : "Refresh",
                systemImage: "arrow.clockwise",
                tone: .primary,
                isAnimating: model.isRefreshing,
                accessibilityIdentifier: "mac.popup.refresh"
            ) {
                guard model.isRefreshing == false else { return }
                Task { await model.refreshNow(manual: true) }
            }
            .disabled(model.isRefreshing)
        }
        .padding(.top, 2)
        .frame(maxWidth: .infinity, minHeight: GlassTokens.pillHeight, alignment: .center)
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
    @State private var isHovered = false
    let title: String
    let systemImage: String
    let tone: Tone
    var isAnimating = false
    let accessibilityIdentifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if isAnimating {
                    PopupSpinningRefreshIcon(systemImage: systemImage)
                } else {
                    Image(systemName: systemImage)
                        .font(.system(size: GlassTokens.popupMetaFontSize, weight: .semibold))
                        .imageScale(.small)
                }

                Text(title)
                    .font(.system(size: GlassTokens.popupMetaFontSize, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                    .allowsTightening(true)
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(foreground)
        .padding(.horizontal, 12)
        .frame(minWidth: minimumWidth)
        .frame(height: GlassTokens.pillHeight)
        .background {
            buttonBackground
        }
        .overlay {
            if tone == .secondary {
                RoundedRectangle(cornerRadius: GlassTokens.pillRadius, style: .continuous)
                    .strokeBorder(CodexTheme.hairlineStrong, lineWidth: 1)
            }
        }
        .opacity(isEnabled ? 1 : 0.72)
        .contentShape(RoundedRectangle(cornerRadius: GlassTokens.pillRadius, style: .continuous))
        .onHover { hovering in
            isHovered = hovering
        }
        .unredacted()
        .accessibilityLabel(title)
        .accessibilityIdentifier(accessibilityIdentifier)
        .transaction { transaction in
            transaction.disablesAnimations = false
        }
    }

    private var minimumWidth: CGFloat {
        92
    }

    private var foreground: Color {
        switch tone {
        case .primary:
            return .white
        case .secondary:
            return CodexTheme.text
        }
    }

    @ViewBuilder
    private var buttonBackground: some View {
        let shape = RoundedRectangle(cornerRadius: GlassTokens.pillRadius, style: .continuous)
        switch tone {
        case .primary:
            shape.fill(CodexTheme.accent)
            .opacity(isHovered && isEnabled ? 0.90 : 1)
        case .secondary:
            shape.fill(isHovered && isEnabled ? CodexTheme.control.opacity(0.88) : CodexTheme.control)
        }
    }
}

struct PopupSpinningRefreshIcon: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isActive = false
    let systemImage: String

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: GlassTokens.popupMetaFontSize, weight: .semibold))
            .imageScale(.small)
            .rotationEffect(.degrees(isActive && reduceMotion == false ? 360 : 0))
            .onAppear {
                guard reduceMotion == false else { return }
                isActive = true
            }
            .animation(
                reduceMotion ? nil : .linear(duration: 0.85).repeatForever(autoreverses: false),
                value: isActive
            )
            .accessibilityHidden(true)
    }
}

struct PopupLoadingBar: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isActive = false

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            let segmentWidth = max(46, width * 0.30)

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(CodexTheme.control.opacity(0.82))

                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [CodexTheme.accent, CodexTheme.accent2],
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
