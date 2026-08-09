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
            QuotaLockScreen(
                state: context.state,
                isStale: context.isStale || context.state.isStale
            )
            .activityBackgroundTint(Color(uiColor: .systemBackground))
        } dynamicIsland: { context in
            let isStale = context.isStale || context.state.isStale
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("Codex", systemImage: "gauge.with.dots.needle.50percent")
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    ViewThatFits(in: .horizontal) {
                        Text("Weekly · \(context.state.weeklyPercentLeft)% left")
                        Text("W · \(context.state.weeklyPercentLeft)%")
                    }
                    .monospacedDigit()
                    .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    QuotaLockScreen(state: context.state, isStale: isStale)
                }
            } compactLeading: {
                Image(
                    systemName: isStale
                        ? "exclamationmark.triangle.fill"
                        : "gauge.with.dots.needle.50percent"
                )
                .accessibilityLabel(
                    isStale
                        ? "Codex quota needs a foreground refresh"
                        : "Codex quota"
                )
            } compactTrailing: {
                Text("\(context.state.weeklyPercentLeft)%")
                    .monospacedDigit()
                    .accessibilityLabel("Weekly \(context.state.weeklyPercentLeft) percent left")
            } minimal: {
                Text(isStale ? "!" : "\(context.state.weeklyPercentLeft)%")
                    .monospacedDigit()
                    .accessibilityLabel(
                        isStale
                            ? "Codex quota needs a foreground refresh"
                            : "Weekly \(context.state.weeklyPercentLeft) percent left"
                    )
            }
            .keylineTint(.accentColor)
        }
    }
}

private struct QuotaLockScreen: View {
    let state: CodexLiveActivityAttributes.ContentState
    let isStale: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            VStack(alignment: .leading, spacing: 2) {
                Label("Codex", systemImage: "gauge.with.dots.needle.50percent")
                    .lineLimit(1)
                headlineText
            }

            ProgressView(value: state.weeklyUsedFraction)
                .tint(.accentColor)
                .accessibilityHidden(true)

            narrowDetails

            if isStale {
                Label("Needs foreground refresh", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .fontDesign(.rounded)
        .padding(.horizontal, 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Codex quota")
        .accessibilityValue(accessibilitySummary)
    }

    private var narrowDetails: some View {
        VStack(alignment: .leading, spacing: 3) {
            resetLabel("Weekly", state.weeklyResetAt)
            if let fiveHourPercentLeft = state.fiveHourPercentLeft {
                resetLabel("5H · \(fiveHourPercentLeft)% left", state.fiveHourResetAt)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .minimumScaleFactor(0.68)
    }

    private var headlineText: some View {
        Text("Weekly · \(state.weeklyPercentLeft)% left")
            .font(.headline)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.62)
    }

    @ViewBuilder
    private func resetLabel(_ title: String, _ date: Date?) -> some View {
        if let date {
            Text("\(title) resets \(date, style: .relative)")
                .monospacedDigit()
                .lineLimit(1)
        } else {
            Text("\(title) reset unavailable")
                .lineLimit(1)
        }
    }

    private var accessibilitySummary: String {
        var parts = [
            "Weekly \(state.weeklyPercentLeft) percent left",
            accessibilityReset("Weekly", state.weeklyResetAt)
        ]
        if let fiveHourPercentLeft = state.fiveHourPercentLeft {
            parts.append("5-hour \(fiveHourPercentLeft) percent left")
            parts.append(accessibilityReset("5-hour", state.fiveHourResetAt))
        }
        if isStale {
            parts.append("Needs foreground refresh")
        }
        return parts.joined(separator: ". ")
    }

    private func accessibilityReset(_ title: String, _ date: Date?) -> String {
        guard let date else { return "\(title) reset unavailable" }
        return "\(title) resets \(date.formatted(date: .abbreviated, time: .shortened))"
    }
}

private let previewAttributes = CodexLiveActivityAttributes()
private let previewReset = Date(timeIntervalSince1970: 1_800_025_200)
private let previewNormal = CodexLiveActivityAttributes.ContentState(
    weeklyPercentLeft: 68,
    weeklyUsedFraction: 0.32,
    weeklyResetAt: previewReset,
    fiveHourPercentLeft: nil,
    fiveHourResetAt: nil,
    isStale: false
)
private let previewFiveHour = CodexLiveActivityAttributes.ContentState(
    weeklyPercentLeft: 68,
    weeklyUsedFraction: 0.32,
    weeklyResetAt: previewReset,
    fiveHourPercentLeft: 42,
    fiveHourResetAt: previewReset.addingTimeInterval(-72_000),
    isStale: false
)
private let previewStale = CodexLiveActivityAttributes.ContentState(
    weeklyPercentLeft: 68,
    weeklyUsedFraction: 0.32,
    weeklyResetAt: previewReset,
    fiveHourPercentLeft: 42,
    fiveHourResetAt: previewReset.addingTimeInterval(-72_000),
    isStale: true
)

#Preview("Lock Screen states", as: .content, using: previewAttributes) {
    CodexQuotaLiveActivity()
} contentStates: {
    previewNormal
    previewFiveHour
    previewStale
}

#Preview("Dynamic Island expanded", as: .dynamicIsland(.expanded), using: previewAttributes) {
    CodexQuotaLiveActivity()
} contentStates: {
    previewNormal
    previewFiveHour
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
    QuotaLockScreen(state: previewNormal, isStale: true)
        .padding()
}
