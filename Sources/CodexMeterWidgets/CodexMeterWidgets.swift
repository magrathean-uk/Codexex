import ActivityKit
import CodexMeterCore
import SwiftUI
import UIKit
import WidgetKit

@main
struct CodexMeterWidgets: WidgetBundle {
    var body: some Widget { CodexQuotaLiveActivity() }
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
    let state: CodexLiveActivityAttributes.ContentState
    let isStale: Bool

    static let backgroundColor = Color(red: 0.12, green: 0.12, blue: 0.13)
    static let accentColor = Color(red: 0.32, green: 0.89, blue: 0.60)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                ActivityIcon(size: 24)
                Text("CODEXEX")
                    .font(.caption.weight(.semibold))
                    .tracking(1)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if isStale {
                    Label("Tap to update", systemImage: "arrow.clockwise")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                } else if let lastUpdatedAt = state.lastUpdatedAt {
                    Text("Updated \(lastUpdatedAt, style: .time)")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.65))
                        .monospacedDigit()
                        .lineLimit(1)
                }
            }
            .padding(.bottom, 8)

            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text("\(state.displayedWeeklyPercent)%")
                    .font(.system(.title, design: .rounded, weight: .bold))
                    .foregroundStyle(Self.accentColor)
                Text(state.displaysUsedQuota ? "used" : "left")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Spacer(minLength: 0)
            }
            .monospacedDigit()

            HStack(spacing: 8) {
                Text("Weekly quota")
                Spacer(minLength: 4)
                if let resetAt = state.weeklyResetAt {
                    Text("Resets \(resetAt, style: .relative)")
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .font(.caption)
            .foregroundStyle(.white.opacity(0.65))
            .padding(.top, 1)
            .padding(.bottom, 10)

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.white.opacity(0.2))
                    Capsule()
                        .fill(Self.accentColor)
                        .frame(width: geometry.size.width * state.displayedWeeklyFraction)
                }
            }
            .frame(height: 5)
            .accessibilityHidden(true)

            if let fiveHourPercent = state.displayedFiveHourPercent {
                HStack(spacing: 8) {
                    Text("5-hour · \(fiveHourPercent)% \(state.displaysUsedQuota ? "used" : "left")")
                        .font(.caption.weight(.medium))
                        .monospacedDigit()
                    Spacer(minLength: 4)
                    if let resetAt = state.fiveHourResetAt {
                        Text("Resets \(resetAt, style: .relative)")
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
                .font(.caption)
                .foregroundStyle(.white.opacity(0.72))
                .padding(.top, 9)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 18)
        .padding(.vertical, 13)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Codexex Usage")
        .accessibilityValue(state.accessibilityDescription(isStale: isStale))
    }
}

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
