#if os(macOS)
import AppKit
import Observation
import SwiftUI

struct SettingsRootView: View {
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @Bindable var model: CodexMenuBarModel

    var body: some View {
        GeometryReader { proxy in
            GlassEffectContainer(spacing: GlassTokens.sectionSpacing) {
                ScrollView {
                    if proxy.size.width >= 820 {
                        wideLayout
                    } else {
                        stackedLayout
                    }
                }
                .padding(GlassTokens.pagePadding)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .scrollIndicators(.hidden)
            }
        }
        .onAppear {
            model.setReduceMotionEnabled(accessibilityReduceMotion)
        }
        .onChange(of: accessibilityReduceMotion) { _, newValue in
            model.setReduceMotionEnabled(newValue)
        }
    }

    private var wideLayout: some View {
        HStack(alignment: .top, spacing: GlassTokens.sectionSpacing) {
            sidebarColumn
                .frame(width: 280, alignment: .topLeading)

            controlsColumn
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private var stackedLayout: some View {
        VStack(alignment: .leading, spacing: GlassTokens.sectionSpacing) {
            SettingsAccountCardView(model: model)
            SettingsBehaviorCardView(model: model)
            SettingsPopupCardView(model: model)
            SettingsForecastCardView(model: model)
            SettingsAboutCard()
        }
    }

    private var sidebarColumn: some View {
        VStack(alignment: .leading, spacing: GlassTokens.sectionSpacing) {
            SettingsAccountCardView(model: model)
            SettingsBehaviorCardView(model: model)
            SettingsAboutCard()
        }
    }

    private var controlsColumn: some View {
        VStack(alignment: .leading, spacing: GlassTokens.sectionSpacing) {
            SettingsPopupCardView(model: model)
            SettingsForecastCardView(model: model)
        }
    }
}
#endif
