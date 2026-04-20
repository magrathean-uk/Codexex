#if os(macOS)
import Observation
import SwiftUI

struct SettingsBehaviorCardView: View {
    @Bindable var model: CodexMenuBarModel

    var body: some View {
        GlassCard(style: .secondary) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Behavior")
                    .font(.headline)

                Toggle("Launch at login", isOn: Binding(
                    get: { model.launchAtLoginEnabled },
                    set: { model.setLaunchAtLoginEnabled($0) }
                ))

                if let launchAtLoginStatusMessage = model.launchAtLoginStatusMessage {
                    Text(launchAtLoginStatusMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Toggle("Auto-refresh", isOn: Binding(
                    get: { model.autoRefreshEnabled },
                    set: { model.setAutoRefreshEnabled($0) }
                ))

                VStack(alignment: .leading, spacing: 10) {
                    Text("Refresh every")
                        .font(.subheadline.weight(.medium))

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

                Button {
                    Task { await model.refreshNow() }
                } label: {
                    Label(model.isRefreshing ? "Refreshing" : "Refresh Now", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.isRefreshing)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
#endif
