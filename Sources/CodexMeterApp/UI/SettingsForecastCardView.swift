#if os(macOS)
import Observation
import SwiftUI

struct SettingsForecastCardView: View {
    @Bindable var model: CodexMenuBarModel

    var body: some View {
        SettingsSectionView(
            title: "Forecast",
            detail: "Controls how weekly pace is shown. Alerts stay focused on Codex only."
        ) {
            SettingsToggleRow(
                title: "Show pace confidence",
                detail: "Display labels like Early estimate, Stable, ML tuned, and Volatile.",
                isOn: Binding(
                    get: { model.showPaceConfidence },
                    set: { model.setShowPaceConfidence($0) }
                )
            )

            SettingsToggleRow(
                title: "Hide idle secondary limits",
                detail: "Collapse secondary limits when they are inactive.",
                isOn: Binding(
                    get: { model.hideIdleSecondaryLimits },
                    set: { model.setHideIdleSecondaryLimits($0) }
                )
            )

            VStack(alignment: .leading, spacing: 8) {
                Text("Default history mode")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                Picker("Default history mode", selection: Binding(
                    get: { model.defaultHistoryMode },
                    set: { model.setDefaultHistoryMode($0) }
                )) {
                    Text("Daily peaks").tag(PopupHistoryMode.dailyPeaks)
                    Text("This cycle").tag(PopupHistoryMode.thisCycle)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            Divider()

            Text("Early estimate uses prior cycles. Stable uses the current weekly pace. ML tuned starts after one month with enough data. Volatile appears when the projection swings sharply.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
#endif
