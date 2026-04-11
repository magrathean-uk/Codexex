#if os(macOS)
import AppKit
import SwiftUI

@MainActor
final class OnboardingWindowController: NSWindowController {
    private let model: CodexMenuBarModel

    init(model: CodexMenuBarModel) {
        self.model = model

        let hosting = NSHostingController(
            rootView: OnboardingRootView(
                model: model,
                onDismiss: {}
            )
        )

        let window = NSWindow(contentViewController: hosting)
        window.styleMask = [.titled, .closable]
        window.title = "Welcome"
        window.setContentSize(NSSize(width: 560, height: 520))
        window.center()
        window.isReleasedWhenClosed = false
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true

        super.init(window: window)

        hosting.rootView = OnboardingRootView(
            model: model,
            onDismiss: { [weak self] in
                self?.close()
            }
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func showWelcomeWindow() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
#endif
