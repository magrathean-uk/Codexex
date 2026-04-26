#if os(macOS)
import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private let model: CodexMenuBarModel
    var onVisibilityChange: ((Bool) -> Void)?

    var isVisible: Bool {
        window?.isVisible == true
    }

    init(model: CodexMenuBarModel) {
        self.model = model
        super.init(window: nil)
        shouldCascadeWindows = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    private func makeWindowIfNeeded() -> NSWindow {
        if let window {
            return window
        }

        let hostingController = NSHostingController(rootView: SettingsRootView(model: model))
        let window = NSWindow(contentViewController: hostingController)

        window.title = "Settings"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.setContentSize(NSSize(width: GlassTokens.settingsWidth, height: GlassTokens.settingsHeight))
        window.contentMinSize = NSSize(width: 760, height: 540)
        window.isReleasedWhenClosed = false
        window.center()
        window.delegate = self

        self.window = window
        return window
    }

    func showSettingsWindow() {
        let window = makeWindowIfNeeded()
        NSApp.setActivationPolicy(.regular)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        onVisibilityChange?(true)
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        onVisibilityChange?(false)
    }

    func closeSettingsWindow() {
        window?.close()
    }
}
#endif
