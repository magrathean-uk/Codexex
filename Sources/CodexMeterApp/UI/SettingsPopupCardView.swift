#if os(macOS)
import Observation
import SwiftUI

struct SettingsPopupCardView: View {
    @Bindable var model: CodexMenuBarModel

    var body: some View {
        SettingsSectionView(
            title: "Popup",
            detail: "Choose which sections appear and what stays in the menu bar."
        ) {
            Text("Content")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)

            SettingsToggleRow(
                title: "Show Spark",
                detail: "Keep Spark visible as raw usage only.",
                isOn: Binding(
                    get: { model.showSparkEnabled },
                    set: { model.setShowSparkEnabled($0) }
                )
            )

            SettingsToggleRow(
                title: "Show history",
                detail: "Show the usage history section in the popup.",
                isOn: Binding(
                    get: { model.showHistoryEnabled },
                    set: { model.setShowHistoryEnabled($0) }
                )
            )

            SettingsToggleRow(
                title: "Show history chart",
                detail: "Show bars and line chart inside usage history.",
                isOn: Binding(
                    get: { model.showHistoryChartEnabled },
                    set: { model.setShowHistoryChartEnabled($0) }
                ),
                isEnabled: model.showHistoryEnabled
            )

            Divider()

            Text("Quota presentation")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)

            SettingsToggleRow(
                title: "Show Codex 5-hour window",
                detail: "Show main Codex 5H in the menu bar, popup, summaries, and history. Spark stays visible.",
                isOn: Binding(
                    get: { model.showFiveHourInMenubar },
                    set: { model.setShowFiveHourInMenubar($0) }
                )
            )
            .accessibilityIdentifier("mac.settings.showFiveHour")
            .accessibilityLabel("Show Codex 5-hour window")
            .accessibilityValue(model.showFiveHourInMenubar ? "On" : "Off")

            SettingsToggleRow(
                title: "Show weekly in menu bar",
                isOn: Binding(
                    get: { model.showWeeklyInMenubar },
                    set: { model.setShowWeeklyInMenubar($0) }
                )
            )
        }
    }
}
#endif
