#if os(macOS)
import Observation
import SwiftUI

struct SettingsBehaviorCardView: View {
    @Bindable var model: CodexMenuBarModel

    var body: some View {
        SettingsSectionView(
            title: "Behavior",
            detail: "Startup and refresh preferences."
        ) {
            SettingsToggleRow(
                title: "Launch at login",
                detail: model.launchAtLoginStatusMessage,
                isOn: Binding(
                    get: { model.launchAtLoginEnabled },
                    set: { model.setLaunchAtLoginEnabled($0) }
                )
            )

            Divider()

            SettingsToggleRow(
                title: "Auto-refresh",
                detail: "Refresh usage automatically in the background.",
                isOn: Binding(
                    get: { model.autoRefreshEnabled },
                    set: { model.setAutoRefreshEnabled($0) }
                )
            )

            VStack(alignment: .leading, spacing: 8) {
                Text("Refresh every")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                Picker("Refresh every", selection: Binding(
                    get: { model.refreshIntervalSeconds },
                    set: { model.setRefreshIntervalSeconds($0) }
                )) {
                    Text("5 min").tag(300)
                    Text("10 min").tag(600)
                    Text("60 min").tag(3600)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .disabled(model.autoRefreshEnabled == false)
            }

            Divider()

            SettingsActionRow(
                title: "Manual refresh",
                detail: "Pull the latest quota data right now."
            ) {
                Button {
                    Task { await model.refreshNow(manual: true) }
                } label: {
                    Label(model.isRefreshing ? "Refreshing" : "Refresh Now", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.isRefreshing)
            }
        }
    }
}
#endif
