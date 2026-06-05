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

                if presentedSnapshot != nil {
                    ForEach(primaryLimitPresentations, id: \.id) { presentation in
                        limitCard(for: presentation)
                    }

                    ForEach(activeSecondaryLimitPresentations, id: \.id) { presentation in
                        limitCard(for: presentation)
                    }
                }

                if showHistorySection {
                    UsageHistoryCardView(
                        samples: presentedHistory,
                        showsChart: model.showHistoryChartEnabled,
                        historyMode: model.defaultHistoryMode,
                        showPaceConfidence: model.showPaceConfidence,
                        resetDisplayStyle: model.resetDisplayStyle,
                        onHistoryModeChange: { model.setDefaultHistoryMode($0) }
                    )
                }

                if presentedSnapshot != nil {
                    ForEach(compactSecondaryLimitPresentations, id: \.id) { presentation in
                        limitCard(for: presentation)
                    }
                }
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            PopupFooterControl(title: "Settings", systemImage: "gearshape", tone: .secondary) {
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
                tone: .primary
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

    private var primaryLimitPresentations: [PopupLimitPresentation] {
        orderedLimitPresentations.filter { $0.limit.bucket != .spark }
    }

    private var secondaryLimitPresentations: [PopupLimitPresentation] {
        orderedLimitPresentations.filter { presentation in
            guard presentation.limit.bucket == .spark else { return false }
            return CodexQuotaPresentationRules.shouldShow(
                presentation.limit,
                showSpark: model.showSparkEnabled,
                hideIdleSecondaryLimits: model.hideIdleSecondaryLimits
            )
        }
    }

    private var activeSecondaryLimitPresentations: [PopupLimitPresentation] {
        secondaryLimitPresentations.filter { $0.style != .compact }
    }

    private var compactSecondaryLimitPresentations: [PopupLimitPresentation] {
        secondaryLimitPresentations.filter { $0.style == .compact }
    }

    private var showHistorySection: Bool {
        model.showHistoryEnabled && presentedHistory.isEmpty == false
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
                displayMode: model.menuBarDisplayMode
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
            hasRefreshIssue: displayMode == .live && model.lastError != nil
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
    let action: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: GlassTokens.popupMetaFontSize, weight: .semibold))
                .imageScale(.small)

            Text(title)
                .font(.system(size: GlassTokens.popupMetaFontSize, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .allowsTightening(true)
        }
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
        .onTapGesture {
            guard isEnabled else { return }
            action()
        }
        .unredacted()
        .accessibilityElement()
        .accessibilityLabel(title)
        .accessibilityAddTraits(.isButton)
    }

    private var minimumWidth: CGFloat {
        switch tone {
        case .primary:
            return 86
        case .secondary:
            return 92
        }
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
            shape.fill(
                LinearGradient(
                    colors: [
                        Color(red: 0.36, green: 0.60, blue: 1.0),
                        Color(red: 0.12, green: 0.42, blue: 0.93)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .opacity(isHovered && isEnabled ? 0.90 : 1)
        case .secondary:
            shape.fill(isHovered && isEnabled ? CodexTheme.control.opacity(0.88) : CodexTheme.control)
        }
    }
}

#endif
