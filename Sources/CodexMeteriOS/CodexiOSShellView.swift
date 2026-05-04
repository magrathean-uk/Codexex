import SwiftUI

struct CodexiOSShellView: View {
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(CodexiOSSettingsKeys.autoCheckSignInOnReturn) private var autoCheckSignInOnReturn = true
    @AppStorage(CodexiOSSettingsKeys.refreshWhenActive) private var refreshWhenActive = true
    @AppStorage(CodexiOSSettingsKeys.refreshIntervalSeconds) private var refreshIntervalSeconds = 300
    @AppStorage(CodexiOSSettingsKeys.appearanceMode) private var appearanceMode = CodexiOSAppearanceMode.system.rawValue
    @AppStorage(CodexiOSSettingsKeys.hasCompletedOnboarding) private var storedHasCompletedOnboarding = false
    @Bindable var model: CodexiOSModel

    var body: some View {
        Group {
            if hasCompletedOnboarding {
                CodexiOSRootView(model: model)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .trailing)).combined(with: .scale(scale: 0.98)),
                        removal: .opacity.combined(with: .move(edge: .leading)).combined(with: .scale(scale: 1.02))
                    ))
            } else {
                CodexiOSOnboardingView(model: model)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .leading)).combined(with: .scale(scale: 0.98)),
                        removal: .opacity.combined(with: .move(edge: .leading)).combined(with: .scale(scale: 0.98))
                    ))
            }
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.86), value: hasCompletedOnboarding)
        .task {
            await model.start()
        }
        .task(id: refreshTaskID) {
            await runAutoRefreshLoop()
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            Task {
                await model.handleSceneDidBecomeActive(
                    autoCheckSignInOnReturn: autoCheckSignInOnReturn,
                    refreshWhenActive: refreshWhenActive
                )
            }
        }
        .preferredColorScheme(CodexiOSAppearanceMode(rawValue: appearanceMode)?.colorScheme)
    }

    private var hasCompletedOnboarding: Bool {
        model.hasCompletedOnboarding || storedHasCompletedOnboarding
    }

    private var refreshTaskID: String {
        "\(refreshWhenActive)-\(max(refreshIntervalSeconds, 300))"
    }

    private func runAutoRefreshLoop() async {
        guard refreshWhenActive else { return }
        while Task.isCancelled == false {
            try? await Task.sleep(for: .seconds(Double(max(refreshIntervalSeconds, 300))))
            guard Task.isCancelled == false else { return }
            if scenePhase == .active, model.isSignedIn {
                await model.refresh()
            }
        }
    }
}
