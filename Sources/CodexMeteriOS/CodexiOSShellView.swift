import SwiftUI

struct CodexiOSShellView: View {
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(CodexiOSSettingsKeys.autoCheckSignInOnReturn) private var autoCheckSignInOnReturn = true
    @AppStorage(CodexiOSSettingsKeys.refreshWhenActive) private var refreshWhenActive = true
    @AppStorage(CodexiOSSettingsKeys.refreshIntervalSeconds) private var refreshIntervalSeconds = 300
    @Bindable var model: CodexiOSModel

    var body: some View {
        Group {
            if model.hasCompletedOnboarding {
                CodexiOSRootView(model: model)
            } else {
                CodexiOSOnboardingView(model: model)
            }
        }
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
