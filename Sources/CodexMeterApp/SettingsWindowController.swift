#if os(macOS)
import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController {
    init(model: CodexMenuBarModel) {
        let hostingController = NSHostingController(rootView: SettingsRootView(model: model))
        let window = NSWindow(contentViewController: hostingController)

        window.title = "Settings"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.titleVisibility = .visible
        window.setContentSize(NSSize(width: 560, height: GlassTokens.settingsHeight))
        window.contentMinSize = NSSize(width: 420, height: 420)
        window.isReleasedWhenClosed = false
        window.center()

        super.init(window: window)
        shouldCascadeWindows = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func showSettingsWindow() {
        guard let window else { return }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
#endif
