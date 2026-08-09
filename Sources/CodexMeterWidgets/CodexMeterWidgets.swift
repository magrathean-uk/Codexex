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
            QuotaUsageView(state: context.state)
                .activityBackgroundTint(Color(uiColor: .systemBackground))
        } dynamicIsland: { context in
            return DynamicIsland {
                DynamicIslandExpandedRegion(.bottom) {
                    QuotaUsageView(state: context.state)
                }
            } compactLeading: {
                ActivityIcon(size: 16)
                    .accessibilityLabel("Codexex Usage")
            } compactTrailing: {
                Text("\(context.state.weeklyPercentLeft)%")
                    .monospacedDigit()
                    .accessibilityLabel("\(context.state.weeklyPercentLeft)% left of weekly usage")
            } minimal: {
                ActivityIcon(size: 16)
                    .accessibilityLabel("Codexex Usage")
            }
            .keylineTint(.accentColor)
        }
    }
}

private struct QuotaUsageView: View {
    let state: CodexLiveActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .center, spacing: 10) {
                ActivityIcon(size: 28)
                Text("Codexex Usage")
                    .font(.headline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }

            Text("\(state.weeklyPercentLeft)% left of weekly usage")
                .font(.subheadline.weight(.medium))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.78)

            ProgressView(value: state.weeklyUsedFraction)
                .tint(.accentColor)
                .frame(height: 8)
                .accessibilityHidden(true)
        }
        .fontDesign(.rounded)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Codexex Usage")
        .accessibilityValue("\(state.weeklyPercentLeft)% left of weekly usage")
    }
}

private struct ActivityIcon: View {
    let size: CGFloat

    var body: some View {
        Group {
            if let path = Bundle.main.path(forResource: "icon-1024", ofType: "png"),
               let image = UIImage(contentsOfFile: path),
               let icon = image.preparingThumbnail(of: CGSize(width: size * 3, height: size * 3)) {
                Image(uiImage: icon)
                    .widgetAccentedRenderingMode(.fullColor)
                    .scaleEffect(1.0 / 3.0)
            } else {
                Color.clear
            }
        }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
    }
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
    QuotaUsageView(state: previewNormal)
        .padding()
}
