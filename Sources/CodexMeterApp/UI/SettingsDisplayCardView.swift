#if os(macOS)
import Observation
import SwiftUI

struct SettingsDisplayCardView: View {
    @Bindable var model: CodexMenuBarModel

    var body: some View {
        GlassCard(style: .secondary) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Display")
                    .font(.headline)

                settingsGroup(title: "Popup") {
                    Toggle("Show Codex Spark", isOn: Binding(
                        get: { model.showSparkEnabled },
                        set: { model.setShowSparkEnabled($0) }
                    ))

                    Toggle("Show insights", isOn: Binding(
                        get: { model.showInsightsEnabled },
                        set: { model.setShowInsightsEnabled($0) }
                    ))

                    Toggle("Show history", isOn: Binding(
                        get: { model.showHistoryEnabled },
                        set: { model.setShowHistoryEnabled($0) }
                    ))

                    Toggle("Show history chart", isOn: Binding(
                        get: { model.showHistoryChartEnabled },
                        set: { model.setShowHistoryChartEnabled($0) }
                    ))
                    .disabled(model.showHistoryEnabled == false)
                }

                settingsGroup(title: "Menu bar") {
                    Toggle("Show 5H", isOn: Binding(
                        get: { model.showFiveHourInMenubar },
                        set: { model.setShowFiveHourInMenubar($0) }
                    ))

                    Toggle("Show W", isOn: Binding(
                        get: { model.showWeeklyInMenubar },
                        set: { model.setShowWeeklyInMenubar($0) }
                    ))
                }
            }
        }
    }

    private func settingsGroup<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        GlassCard(style: .inset) {
            VStack(alignment: .leading, spacing: 10) {
                Text(title)
                    .font(.subheadline.weight(.semibold))

                content()
            }
        }
    }
}
#endif
