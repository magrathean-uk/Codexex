import ActivityKit
import CodexMeterCore
import SwiftUI
import UIKit
import WidgetKit

#if !WIDGET_DESIGN_CAPTURE
@main
#endif
struct CodexMeterWidgets: WidgetBundle {
    var body: some Widget {
        CodexSubscriptionWidget()
        CodexAPIBalanceWidget()
        CodexQuotaLiveActivity()
    }
}

struct CodexQuotaLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: CodexLiveActivityAttributes.self) { context in
            let isStale = CodexLiveActivityPresentation.resolvedStaleness(
                systemIsStale: context.isStale,
                contentStateIsStale: context.state.isStale
            )
            QuotaUsageView(state: context.state, isStale: isStale)
                .activityBackgroundTint(QuotaUsageView.backgroundColor)
                .widgetURL(URL(string: "codexex://refresh"))
        } dynamicIsland: { context in
            let isStale = CodexLiveActivityPresentation.resolvedStaleness(
                systemIsStale: context.isStale,
                contentStateIsStale: context.state.isStale
            )
            return DynamicIsland {
                DynamicIslandExpandedRegion(.bottom) {
                    QuotaUsageView(state: context.state, isStale: isStale)
                }
            } compactLeading: {
                if isStale {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .accessibilityLabel("Update needed")
                } else {
                    ActivityIcon(size: 16)
                        .accessibilityLabel("Codexex Usage")
                }
            } compactTrailing: {
                Text("\(context.state.displayedWeeklyPercent)%")
                    .monospacedDigit()
                    .foregroundStyle(QuotaUsageView.accentColor)
                    .accessibilityLabel(
                        "\(context.state.weeklyDisplayDescription). \(isStale ? "Update needed" : "Up to date")"
                    )
            } minimal: {
                if isStale {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .accessibilityLabel("Codexex Usage. Update needed")
                } else {
                    ActivityIcon(size: 16)
                        .accessibilityLabel("Codexex Usage. Up to date")
                }
            }
            .keylineTint(QuotaUsageView.accentColor)
            .widgetURL(URL(string: "codexex://refresh"))
        }
    }
}

private struct QuotaUsageView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let state: CodexLiveActivityAttributes.ContentState
    let isStale: Bool

    static let backgroundColor = Color(red: 0.12, green: 0.12, blue: 0.13)
    static let accentColor = Color(red: 0.32, green: 0.89, blue: 0.60)
    private var compactText: Bool { dynamicTypeSize.isAccessibilitySize }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header.padding(.bottom, 8)
            if compactText {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        weeklyAmount.fixedSize()
                        Spacer(minLength: 4)
                        compactWeeklyReset.fixedSize()
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        weeklyAmount
                        compactWeeklyReset
                    }
                }
                .padding(.bottom, 8)
            } else {
                weeklyAmount
                HStack(spacing: 8) {
                    Text("Weekly quota")
                    Spacer(minLength: 4)
                    if let resetAt = state.weeklyResetAt {
                        resetText(resetAt, weekly: true)
                    }
                }
                .font(.caption)
                .foregroundStyle(.white.opacity(0.72))
                .padding(.top, 1)
                .padding(.bottom, 10)
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.2))
                    Capsule().fill(Self.accentColor)
                        .frame(width: geometry.size.width * state.displayedWeeklyFraction)
                }
            }
            .frame(height: 5)
            .accessibilityHidden(true)

            if let fiveHourPercent = state.displayedFiveHourPercent {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        fiveHourAmount(fiveHourPercent).fixedSize()
                        Spacer(minLength: 4)
                        if let resetAt = state.fiveHourResetAt {
                            resetText(resetAt, weekly: false).fixedSize()
                        }
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        fiveHourAmount(fiveHourPercent)
                        if let resetAt = state.fiveHourResetAt {
                            resetText(resetAt, weekly: false)
                        }
                    }
                }
                .font(compactText ? .caption2 : .caption)
                .foregroundStyle(.white.opacity(0.78))
                .padding(.top, 9)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 18)
        .padding(.vertical, 13)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Codexex Usage")
        .accessibilityValue(accessibilitySummary)
        .accessibilityHint("Opens Codexex to refresh")
    }

    private var header: some View {
        HStack(spacing: 8) {
            ActivityIcon(size: compactText ? 16 : 24)
            Text(compactText ? "Weekly" : "CODEXEX")
                .font((compactText ? Font.caption2 : .caption).weight(.semibold))
                .tracking(compactText ? 0 : 1)
                .lineLimit(1)
            Spacer(minLength: 8)
            if isStale {
                Text(compactText ? "Stale" : "Tap to update")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.orange)
                    .lineLimit(1)
            } else if let lastUpdatedAt = state.lastUpdatedAt {
                if compactText {
                    Text("Updated").font(.caption2).foregroundStyle(.white.opacity(0.72))
                } else {
                    Text("Updated \(lastUpdatedAt, style: .time)")
                        .font(.caption2).foregroundStyle(.white.opacity(0.72))
                        .monospacedDigit().lineLimit(1)
                }
            }
        }
    }

    private var weeklyAmount: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text("\(state.displayedWeeklyPercent)%")
                .font((compactText ? Font.title2 : .title).weight(.bold))
                .foregroundStyle(Self.accentColor)
            Text(state.displaysUsedQuota ? "used" : "left")
                .font((compactText ? Font.caption2 : .subheadline).weight(.semibold))
        }
        .monospacedDigit()
    }

    @ViewBuilder private var compactWeeklyReset: some View {
        if let resetAt = state.weeklyResetAt {
            resetText(resetAt, weekly: true)
                .font(.caption2).foregroundStyle(.white.opacity(0.78))
        }
    }

    private func fiveHourAmount(_ percent: Int) -> some View {
        Text("\(compactText ? "5h " : "5-hour · ")\(percent)% \(state.displaysUsedQuota ? "used" : "left")")
            .fontWeight(.medium).monospacedDigit()
    }

    @ViewBuilder private func resetText(_ resetAt: Date, weekly: Bool) -> some View {
        if resetAt <= Date() {
            Text("Reset passed")
        } else if compactText {
            Label {
                Text(weekly
                    ? resetAt.formatted(.dateTime.weekday(.abbreviated))
                    : resetAt.formatted(date: .omitted, time: .shortened))
                    .monospacedDigit()
            } icon: {
                Image(systemName: "clock").accessibilityHidden(true)
            }
        } else {
            Text("Resets \(resetAt, style: .relative)")
        }
    }

    private var accessibilitySummary: String {
        [
                state.weeklyDisplayDescription,
                state.fiveHourDisplayDescription,
                isStale ? "Update needed" : "Up to date",
                state.lastUpdatedAt.map { "Checked \($0.formatted(date: .complete, time: .shortened))" },
                state.weeklyResetAt.map { "Weekly resets \($0.formatted(date: .complete, time: .shortened))" },
                state.fiveHourResetAt.map { "5-hour resets \($0.formatted(date: .complete, time: .shortened))" }
            ].compactMap { $0 }
            .joined(separator: ". ")
    }
}

#if DEBUG
extension CodexWidgetDesignFixtures {
    static var activityBackground: Color { QuotaUsageView.backgroundColor }

    /// The exact lock-screen and expanded-island content; no ActivityKit request is made.
    static func activity(
        state: CodexLiveActivityAttributes.ContentState,
        isStale: Bool
    ) -> some View {
        QuotaUsageView(state: state, isStale: isStale)
    }
}
#endif

private struct ActivityIcon: View {
    let size: CGFloat

    var body: some View {
        Group {
            if let icon = ActivityIconAsset.preparedImage {
                Image(uiImage: icon)
                    .widgetAccentedRenderingMode(.fullColor)
                    .scaleEffect(size / ActivityIconAsset.pointSize)
            } else {
                Image(systemName: "terminal.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.primary)
                    .padding(size * 0.18)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
    }
}

@MainActor
private enum ActivityIconAsset {
    static let pointSize: CGFloat = 84
    static let preparedImage: UIImage? = {
        guard let path = Bundle.main.path(forResource: "icon-1024", ofType: "png"),
              let source = UIImage(contentsOfFile: path) else { return nil }
        return source.preparingThumbnail(of: CGSize(width: pointSize, height: pointSize)) ?? source
    }()
}

private let previewAttributes = CodexLiveActivityAttributes()
private let previewNormal = CodexLiveActivityAttributes.ContentState(
    weeklyPercentLeft: 68,
    weeklyUsedFraction: 0.32,
    weeklyResetAt: .now.addingTimeInterval(6 * 24 * 60 * 60),
    fiveHourPercentLeft: 100,
    fiveHourResetAt: .now.addingTimeInterval(4 * 60 * 60),
    isStale: false,
    lastUpdatedAt: .now
)
private let previewStale = CodexLiveActivityAttributes.ContentState(
    weeklyPercentLeft: 68,
    weeklyUsedFraction: 0.32,
    weeklyResetAt: .now.addingTimeInterval(6 * 24 * 60 * 60),
    fiveHourPercentLeft: 100,
    fiveHourResetAt: .now.addingTimeInterval(4 * 60 * 60),
    isStale: true,
    lastUpdatedAt: .now
)

#Preview("Lock Screen states", as: .content, using: previewAttributes) {
    CodexQuotaLiveActivity()
} contentStates: {
    previewNormal
    previewStale
}

#Preview("Dynamic Island expanded", as: .dynamicIsland(.expanded), using: previewAttributes) {
    CodexQuotaLiveActivity()
} contentStates: {
    previewNormal
    previewStale
}

#Preview("Dynamic Island compact", as: .dynamicIsland(.compact), using: previewAttributes) {
    CodexQuotaLiveActivity()
} contentStates: {
    previewNormal
    previewStale
}

#Preview("Dynamic Island minimal", as: .dynamicIsland(.minimal), using: previewAttributes) {
    CodexQuotaLiveActivity()
} contentStates: {
    previewNormal
    previewStale
}

#Preview("System stale layout") {
    QuotaUsageView(state: previewNormal, isStale: true)
        .padding()
        .background(QuotaUsageView.backgroundColor, in: RoundedRectangle(cornerRadius: 20))
}
