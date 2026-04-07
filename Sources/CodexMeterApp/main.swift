#if os(macOS)
import SwiftUI
import AppKit
import CodexMeterCore
import Observation

private let sharedModel = CodexMenuBarModel()

DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
    Task { @MainActor in
        await sharedModel.start()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    override init() {
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}

struct CodexMeterMenuBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            PopupRootView(model: sharedModel)
        } label: {
            StatusBarLabel(
                snapshot: sharedModel.snapshot,
                isRefreshing: sharedModel.isRefreshing,
                hasError: sharedModel.lastError != nil
            )
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsRootView(model: sharedModel)
        }
    }
}

CodexMeterMenuBarApp.main()
#else
print("CodexMeterApp is macOS 26+ only.")
#endif
