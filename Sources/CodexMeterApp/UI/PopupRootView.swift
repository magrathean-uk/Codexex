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
    private let previewReferenceDate: Date

    init(
        model: CodexMenuBarModel,
        onOpenSettings: @escaping () -> Void = {},
        displayMode: PopupRootDisplayMode = .live,
        previewReferenceDate: Date = Date()
    ) {
        self.model = model
        self.onOpenSettings = onOpenSettings
        self.displayMode = displayMode
        self.previewReferenceDate = previewReferenceDate
    }

    var body: some View {
        GlassEffectContainer(spacing: GlassTokens.sectionSpacing) {
            VStack(alignment: .leading, spacing: GlassTokens.contentSpacing) {
                if shouldShowStatusCard {
                    PopupStatusCardView(model: model)
                }

                if let summary = presentedSummary {
                    PopupSummaryCardView(
                        summary: summary,
                        performAction: performSummaryAction(_:)
                    )
                }

                if presentedSnapshot != nil {
                    ForEach(primaryLimitPresentations) { presentation in
                        limitCard(for: presentation)
                    }

                    ForEach(activeSecondaryLimitPresentations) { presentation in
                        limitCard(for: presentation)
                    }
                }

                if showHistorySection {
                    UsageHistoryCardView(
                        samples: presentedHistory,
                        showsChart: model.showHistoryChartEnabled,
                        historyMode: model.defaultHistoryMode,
                        showPaceConfidence: model.showPaceConfidence,
                        onHistoryModeChange: { model.setDefaultHistoryMode($0) }
                    )
                }

                if presentedSnapshot != nil {
                    ForEach(compactSecondaryLimitPresentations) { presentation in
                        limitCard(for: presentation)
                    }
                }

                if displayMode == .live {
                    footer
                }
            }
            .padding(GlassTokens.pagePadding)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: GlassTokens.popupWidth)
        .onAppear {
            model.setReduceMotionEnabled(accessibilityReduceMotion)
        }
        .onChange(of: accessibilityReduceMotion) { _, newValue in
            model.setReduceMotionEnabled(newValue)
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button {
                onOpenSettings()
            } label: {
                Label("Settings", systemImage: "gearshape.fill")
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(.white.opacity(0.18), in: Capsule())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .font(.footnote.weight(.medium))
            .keyboardShortcut(",", modifiers: .command)

            Spacer()

            if let lastUpdatedAt = presentedLastUpdatedAt {
                Text(updatedText(for: lastUpdatedAt))
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .contentTransition(accessibilityReduceMotion ? .identity : .numericText())
            }
        }
        .padding(.top, 2)
        .contentTransition(accessibilityReduceMotion ? .identity : .opacity)
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
        guard model.showSparkEnabled else { return [] }
        let presentations = orderedLimitPresentations.filter { $0.limit.bucket == .spark }
        if model.hideIdleSecondaryLimits {
            return presentations.filter { PopupPresentation.isIdle($0.limit) == false }
        }
        return presentations
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
            LimitCardView(presentation: presentation)
        }
    }

    private var shouldShowStatusCard: Bool {
        displayMode == .live && model.shouldShowStatusCard
    }

    private var presentedSnapshot: CodexSnapshot? {
        if displayMode == .settingsPreview {
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
        return model.usageHistory
    }

    private var presentedInsights: CodexUsageInsights? {
        CodexUsageHistoryAnalytics.insights(
            snapshot: presentedSnapshot,
            samples: presentedHistory,
            now: presentedLastUpdatedAt ?? previewReferenceDate
        )
    }

    private var presentedSummary: PopupSummaryPresentation? {
        PopupPresentation.summary(
            snapshot: presentedSnapshot,
            insights: presentedInsights,
            previewModeEnabled: displayMode == .live && model.previewModeEnabled,
            hasRefreshIssue: displayMode == .live && model.lastError != nil
        )
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
            Task { await model.refreshNow() }
        case .useSampleData:
            model.enablePreviewMode()
        }
    }
}
#endif
