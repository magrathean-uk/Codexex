#if os(macOS)
import AppKit
import Observation
import SwiftUI

struct SettingsRootView: View {
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @Bindable var model: CodexMenuBarModel

    var body: some View {
        GlassEffectContainer(spacing: GlassTokens.sectionSpacing) {
            ScrollView {
                ViewThatFits(in: .horizontal) {
                    wideLayout
                    stackedLayout
                }
                .padding(GlassTokens.pagePadding)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .scrollIndicators(.hidden)
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
            VStack(alignment: .leading, spacing: GlassTokens.sectionSpacing) {
                SettingsAccountCardView(model: model)
                SettingsBehaviorCardView(model: model)
            }
            .frame(maxWidth: 372, alignment: .topLeading)

            VStack(alignment: .leading, spacing: GlassTokens.sectionSpacing) {
                SettingsDisplayCardView(model: model)
                SettingsAboutCard()
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private var stackedLayout: some View {
        VStack(alignment: .leading, spacing: GlassTokens.sectionSpacing) {
            SettingsAccountCardView(model: model)
            SettingsBehaviorCardView(model: model)
            SettingsDisplayCardView(model: model)
            SettingsAboutCard()
        }
    }
}
#endif
