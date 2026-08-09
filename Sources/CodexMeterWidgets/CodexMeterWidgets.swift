import SwiftUI
import WidgetKit
import CodexMeterCore

@main
struct CodexMeterWidgets: WidgetBundle {
    var body: some Widget { CodexQuotaLiveActivity() }
}

struct CodexQuotaLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: CodexLiveActivityAttributes.self) { context in
            QuotaLockScreen(state: context.state)
                .activityBackgroundTint(.black.opacity(0.18))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { Label("Codex", systemImage: "gauge.with.dots.needle.50percent") }
                DynamicIslandExpandedRegion(.trailing) { Text("Weekly · \(context.state.weeklyPercentLeft)% left").monospacedDigit() }
                DynamicIslandExpandedRegion(.bottom) { QuotaLockScreen(state: context.state) }
            } compactLeading: {
                Image(systemName: "gauge.with.dots.needle.50percent")
            } compactTrailing: {
                Text("\(context.state.weeklyPercentLeft)%").monospacedDigit()
            } minimal: {
                Text("\(context.state.weeklyPercentLeft)%").monospacedDigit()
            }
            .keylineTint(.accentColor)
        }
    }
}

private struct QuotaLockScreen: View {
    let state: CodexLiveActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Codex", systemImage: "gauge.with.dots.needle.50percent")
                Spacer()
                Text("Weekly · \(state.weeklyPercentLeft)% left").monospacedDigit()
            }
            ProgressView(value: state.weeklyUsedFraction)
                .tint(.accentColor)
                .accessibilityLabel("Weekly quota used")
            HStack {
                resetLabel("Weekly", state.weeklyResetAt)
                if let fiveHourPercentLeft = state.fiveHourPercentLeft {
                    Spacer()
                    Text("5H · \(fiveHourPercentLeft)% left").monospacedDigit()
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            if state.isStale { Text("Needs foreground refresh").font(.caption2).foregroundStyle(.secondary) }
        }
        .fontDesign(.rounded)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Codex weekly quota")
        .accessibilityValue("\(state.weeklyPercentLeft)% left")
    }

    @ViewBuilder private func resetLabel(_ title: String, _ date: Date?) -> some View {
        if let date { Text("\(title) resets \(date, style: .relative)").monospacedDigit() }
        else { Text("\(title) reset unavailable") }
    }
}
