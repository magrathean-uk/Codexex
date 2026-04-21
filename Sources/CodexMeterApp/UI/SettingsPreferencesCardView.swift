#if os(macOS)
import Observation
import SwiftUI

struct SettingsPreferencesCardView: View {
    @Bindable var model: CodexMenuBarModel

    var body: some View {
        GlassCard(style: .secondary) {
            VStack(alignment: .leading, spacing: 18) {
                Text("Preferences")
                    .font(.headline)

                SettingsBehaviorCardView(model: model)
                Divider()
                SettingsPopupCardView(model: model)
                Divider()
                SettingsForecastCardView(model: model)
            }
        }
    }
}
#endif
