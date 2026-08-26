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
                .activityBackgroundTint(Color(uiColor: .systemBackground))
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
            .keylineTint(.accentColor)
        }
    }
}

private struct QuotaUsageView: View {
    let state: CodexLiveActivityAttributes.ContentState
    let isStale: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .center, spacing: 10) {
                ActivityIcon(size: 28)
                Text("Codexex Usage")
                    .font(.headline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                Spacer(minLength: 6)
                if isStale {
                    Label("Update needed", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: true, vertical: false)
                }
            }

            Text(state.weeklyDisplayDescription)
                .font(.subheadline.weight(.medium))
                .monospacedDigit()
                .fixedSize(horizontal: false, vertical: true)

            ProgressView(value: state.displayedWeeklyFraction)
                .tint(.accentColor)
                .frame(height: 8)
                .accessibilityHidden(true)

            if let fiveHour = state.fiveHourDisplayDescription {
                VStack(alignment: .leading, spacing: 2) {
                    Text(fiveHour)
                        .font(.caption.weight(.medium))
                        .monospacedDigit()
                        .fixedSize(horizontal: false, vertical: true)

                    if let resetAt = state.fiveHourResetAt {
                        Text("5-hour reset \(resetAt, style: .relative)")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            if let resetAt = state.weeklyResetAt {
                HStack(spacing: 5) {
                    Image(systemName: "clock")
                    Text("Weekly reset")
                    Text(resetAt, style: .relative)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .fontDesign(.rounded)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
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
    weeklyResetAt: nil,
    fiveHourPercentLeft: nil,
    fiveHourResetAt: nil,
    isStale: false
)
private let previewStale = CodexLiveActivityAttributes.ContentState(
    weeklyPercentLeft: 68,
    weeklyUsedFraction: 0.32,
    weeklyResetAt: nil,
    fiveHourPercentLeft: nil,
    fiveHourResetAt: nil,
    isStale: true
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
}
