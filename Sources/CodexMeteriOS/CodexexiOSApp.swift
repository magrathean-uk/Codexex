import SwiftUI
import UIKit

final class CodexiOSAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        CodexiOSBackgroundRefresh.register()
        return true
    }
}

@main
struct CodexexiOSApp: App {
    @UIApplicationDelegateAdaptor(CodexiOSAppDelegate.self) private var appDelegate
    @State private var model = CodexiOSModel()

    var body: some Scene {
        WindowGroup {
            CodexiOSShellView(model: model)
        }
    }
}
