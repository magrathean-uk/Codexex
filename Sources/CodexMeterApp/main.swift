#if os(macOS)
import SwiftUI
import AppKit
import Observation
private let sharedModel = CodexMenuBarModel()
private let sharedSettingsWindowController = SettingsWindowController(model: sharedModel)
private let sharedOnboardingWindowController = OnboardingWindowController(model: sharedModel)
private var sharedStatusItemController: CodexStatusItemController?

DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
    Task { @MainActor in
        await sharedModel.start()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {        NSApp.setActivationPolicy(.accessory)
        let appIcon = NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)
        appIcon.isTemplate = false
        NSApp.applicationIconImage = appIcon
        CodexLaunchAtLoginManager.syncStoredState()
        sharedStatusItemController = CodexStatusItemController(
            model: sharedModel,
            openSettings: {
                sharedSettingsWindowController.showSettingsWindow()
            }
        )
        sharedSettingsWindowController.onVisibilityChange = { visible in
            sharedStatusItemController?.setSettingsVisible(visible)
        }
        DispatchQueue.main.async {
            self.bindSettingsMenuItem()
        }

        if sharedModel.hasCompletedOnboarding == false {
            sharedOnboardingWindowController.showWelcomeWindow()
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard sharedSettingsWindowController.isVisible else {
            return .terminateNow
        }

        let alert = NSAlert()
        alert.messageText = "Quit Codexex?"
        alert.informativeText = "You can keep Codexex running in the menu bar and close only Settings."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Keep in Menu Bar")
        alert.addButton(withTitle: "Quit")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            sharedSettingsWindowController.closeSettingsWindow()
            return .terminateCancel
        }

        return .terminateNow
    }

    @objc private func openSettingsFromAppMenu() {
        sharedSettingsWindowController.showSettingsWindow()
    }

    private func bindSettingsMenuItem() {
        guard let appMenu = NSApp.mainMenu?.items.first?.submenu else { return }
        guard let settingsItem = appMenu.items.first(where: { $0.title.hasPrefix("Settings") }) else { return }
        settingsItem.target = self
        settingsItem.action = #selector(openSettingsFromAppMenu)
    }
}

struct CodexMeterMenuBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsRootView(model: sharedModel)
        }
        .defaultSize(width: GlassTokens.settingsWidth, height: GlassTokens.settingsHeight)
        .windowResizability(.automatic)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    sharedSettingsWindowController.showSettingsWindow()
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}

CodexMeterMenuBarApp.main()
#else
print("CodexMeterApp is macOS 26+ only.")
#endif
