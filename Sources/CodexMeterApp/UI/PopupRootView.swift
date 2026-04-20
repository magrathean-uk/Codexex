#if os(macOS)
import Foundation
import Observation
import SwiftUI
import CodexMeterCore

struct PopupRootView: View {
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @Bindable var model: CodexMenuBarModel
    var onOpenSettings: () -> Void = {}

    var body: some View {
        GlassEffectContainer(spacing: GlassTokens.sectionSpacing) {
            VStack(alignment: .leading, spacing: GlassTokens.contentSpacing) {
                if model.shouldShowStatusCard {
                    PopupStatusCardView(model: model)
                }

                if model.snapshot != nil {
                    ForEach(primaryLimitPresentations) { presentation in
                        limitCard(for: presentation)
                    }

                    ForEach(activeSecondaryLimitPresentations) { presentation in
                        limitCard(for: presentation)
                    }
                }

                ForEach(supplementalSections, id: \.self) { section in
                    supplementalCard(for: section)
                }

                if model.snapshot != nil {
                    ForEach(compactSecondaryLimitPresentations) { presentation in
                        limitCard(for: presentation)
                    }
                }

                footer
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

            if let lastUpdatedAt = model.lastUpdatedAt {
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
        guard let snapshot = model.snapshot else { return [] }
        return PopupPresentation.orderedLimits(snapshot.limits).map(PopupPresentation.presentation(for:))
    }

    private var primaryLimitPresentations: [PopupLimitPresentation] {
        orderedLimitPresentations.filter { $0.limit.bucket != .spark }
    }

    private var secondaryLimitPresentations: [PopupLimitPresentation] {
        guard model.showSparkEnabled else { return [] }
        return orderedLimitPresentations.filter { $0.limit.bucket == .spark }
    }

    private var activeSecondaryLimitPresentations: [PopupLimitPresentation] {
        secondaryLimitPresentations.filter { $0.style != .compact }
    }

    private var compactSecondaryLimitPresentations: [PopupLimitPresentation] {
        secondaryLimitPresentations.filter { $0.style == .compact }
    }

    private var supplementalSections: [PopupSupplementalSection] {
        PopupPresentation.supplementalSections(
            showHistory: model.showHistoryEnabled && model.usageHistory.isEmpty == false,
            showInsights: model.showInsightsEnabled && model.usageInsights != nil
        )
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

    @ViewBuilder
    private func supplementalCard(for section: PopupSupplementalSection) -> some View {
        switch section {
        case .history:
            UsageHistoryCardView(
                samples: model.usageHistory,
                showsChart: model.showHistoryChartEnabled
            )
        case .insights:
            if let insights = model.usageInsights {
                InsightsCardView(insights: insights)
            }
        }
    }
}
#endif
