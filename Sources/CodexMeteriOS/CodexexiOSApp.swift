import SwiftUI

@main
struct CodexexiOSApp: App {
    @State private var model = CodexiOSModel()

    var body: some Scene {
        WindowGroup {
            if model.hasCompletedOnboarding {
                CodexiOSRootView(model: model)
            } else {
                CodexiOSOnboardingView(model: model)
            }
        }
    }
}
