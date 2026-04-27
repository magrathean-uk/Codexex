import SwiftUI

@main
struct CodexexiOSApp: App {
    @State private var model = CodexiOSModel()

    var body: some Scene {
        WindowGroup {
            CodexiOSRootView(model: model)
        }
    }
}
