#if os(macOS)
import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    var isVisible: Bool {
        window?.isVisible == true
    }

    init(model: CodexMenuBarModel) {
        let hostingController = NSHostingController(rootView: SettingsRootView(model: model))
        let window = NSWindow(contentViewController: hostingController)

        window.title = "Settings"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.titleVisibility = .visible
        window.setContentSize(NSSize(width: GlassTokens.settingsWidth, height: GlassTokens.settingsHeight))
        window.contentMinSize = NSSize(width: 640, height: 500)
        window.isReleasedWhenClosed = false
        window.center()

        super.init(window: window)
        shouldCascadeWindows = false
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func showSettingsWindow() {
        guard let window else { return }
        NSApp.setActivationPolicy(.regular)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    func closeSettingsWindow() {
        window?.close()
    }
}
#endif
