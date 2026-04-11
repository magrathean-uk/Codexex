#if os(macOS)
import SwiftUI
import AppKit
import Observation

private let sharedModel = CodexMenuBarModel()
private let sharedSettingsWindowController = SettingsWindowController(model: sharedModel)
private var sharedStatusItemController: CodexStatusItemController?

DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
    Task { @MainActor in
        await sharedModel.start()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        CodexLaunchAtLoginManager.syncStoredState()
        sharedStatusItemController = CodexStatusItemController(
            model: sharedModel,
            openSettings: {
                sharedSettingsWindowController.showSettingsWindow()
            }
        )
    }
}

struct CodexMeterMenuBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsRootView(model: sharedModel)
        }
        .defaultSize(width: 560, height: GlassTokens.settingsHeight)
        .windowResizability(.automatic)
    }
}

CodexMeterMenuBarApp.main()
#else
print("CodexMeterApp is macOS 26+ only.")
#endif
