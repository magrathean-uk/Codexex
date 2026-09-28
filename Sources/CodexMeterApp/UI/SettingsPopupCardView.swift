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

            Text("The 5-hour window appears automatically for Plus accounts when the account provides it.")
                .font(.caption)
                .foregroundStyle(.secondary)

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
