import AppKit
import SwiftUI
import XCTest
@testable import CodexMeterApp
@testable import CodexMeterCore

@MainActor
final class SettingsDesignRenderTests: XCTestCase {
    func testSettingsAndWelcomeRenderAtSupportedWindowSize() throws {
        let suite = "SettingsDesignRenderTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = CodexMenuBarModel(settingsStore: CodexAppSettingsStore(defaults: defaults))
        model.apiMonitor.setPreview(true)
        for appearance in [CodexAppearanceMode.light, .dark] {
            model.setAppearanceMode(appearance)
            for section in SettingsSection.allCases {
                try capture(SettingsRootView(model: model, initialSection: section), name: "codexex-settings-\(section.rawValue)-\(appearance.rawValue)", appearance: appearance, width: 820, height: 540)
            }
            for destination in [SettingsAccountDestination.subscription, .api] {
                try capture(SettingsRootView(model: model, initialAccount: destination), name: "codexex-account-\(destination)-\(appearance.rawValue)", appearance: appearance, width: 820, height: 540)
            }
            for step in [OnboardingStep.welcome, .subscription, .api] {
                try capture(OnboardingRootView(model: model, onDismiss: {}, initialStep: step), name: "codexex-onboarding-\(step)-\(appearance.rawValue)", appearance: appearance, width: 720, height: 620)
            }
        }
    }

    private func capture<V: View>(_ view: V, name: String, appearance: CodexAppearanceMode, width: CGFloat, height: CGFloat) throws {
        let host = NSHostingView(rootView: view.frame(width: width, height: height).transaction { $0.disablesAnimations = true })
        host.frame = NSRect(x: 0, y: 0, width: width, height: height)
        let panel = ActiveDesignRenderPanel(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
        panel.appearance = NSAppearance(named: appearance == .dark ? .darkAqua : .aqua)
        panel.isReleasedWhenClosed = false
        panel.contentView = host
        let application = NSApplication.shared
        application.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        defer { panel.orderOut(nil); panel.contentView = nil }
        host.layoutSubtreeIfNeeded()
        panel.displayIfNeeded()
        let settleDeadline = Date().addingTimeInterval(0.25)
        while Date() < settleDeadline {
            let nextDeadline = min(settleDeadline, Date().addingTimeInterval(0.01))
            if let event = application.nextEvent(matching: .any, until: nextDeadline, inMode: .default, dequeue: true) {
                application.sendEvent(event)
            }
            RunLoop.main.run(until: nextDeadline)
        }
        panel.makeKey()
        host.layoutSubtreeIfNeeded()
        panel.displayIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        XCTAssertEqual(bitmap.size.width, width, accuracy: 0.5)
        XCTAssertEqual(bitmap.size.height, height, accuracy: 0.5)
        if let directory = ProcessInfo.processInfo.environment["SETTINGS_DESIGN_RENDER_OUTPUT"] {
            let destination = URL(fileURLWithPath: directory, isDirectory: true).appendingPathComponent("\(name).png")
            try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: destination, options: .atomic)
            let state = "{\"keyWindow\":\(panel.isKeyWindow),\"appActive\":\(application.isActive),\"appearance\":\"\(appearance.rawValue)\"}\n"
            try state.write(to: destination.deletingPathExtension().appendingPathExtension("json"), atomically: true, encoding: .utf8)
        }
    }
}

private final class ActiveDesignRenderPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
