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
        ZStack(alignment: .top) {
            Triangle()
                .fill(CodexTheme.window)
                .frame(width: 18, height: 12)
                .offset(y: -7)

            ViewThatFits(in: .vertical) {
                popupContent

                ScrollView(.vertical) {
                    popupContent
                }
                .scrollIndicators(.hidden)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .background(CodexTheme.window, in: RoundedRectangle(cornerRadius: GlassTokens.popupRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: GlassTokens.popupRadius, style: .continuous)
                .strokeBorder(CodexTheme.hairline, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.42), radius: 34, y: 22)
        .preferredColorScheme(.dark)
        .frame(width: GlassTokens.popupWidth)
        .onAppear {
            model.setReduceMotionEnabled(accessibilityReduceMotion)
        }
        .onChange(of: accessibilityReduceMotion) { _, newValue in
            model.setReduceMotionEnabled(newValue)
        }
    }

    private var popupContent: some View {
        content
            .padding(GlassTokens.pagePadding)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var content: some View {
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
                        resetDisplayStyle: model.resetDisplayStyle,
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
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button {
                onOpenSettings()
            } label: {
                Label("Settings", systemImage: "gearshape.fill")
            }
            .buttonStyle(CodexGhostButtonStyle())
            .keyboardShortcut(",", modifiers: .command)

            Spacer()

            if let lastUpdatedAt = presentedLastUpdatedAt {
                Text(updatedText(for: lastUpdatedAt))
                    .font(.system(size: 11.5).monospacedDigit())
                    .foregroundStyle(CodexTheme.dim)
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
            LimitCardView(presentation: presentation, resetDisplayStyle: model.resetDisplayStyle)
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
        let summary = PopupPresentation.summary(
            snapshot: presentedSnapshot,
            insights: presentedInsights,
            previewModeEnabled: displayMode == .live && model.previewModeEnabled,
            hasRefreshIssue: displayMode == .live && model.lastError != nil
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
            Task { await model.refreshNow() }
        case .useSampleData:
            model.enablePreviewMode()
        }
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
#endif
