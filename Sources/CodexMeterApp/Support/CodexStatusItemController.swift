#if os(macOS)
import AppKit
import Observation
import SwiftUI

@MainActor
final class CodexStatusItemController: NSObject {
    private let model: CodexMenuBarModel
    private let openSettingsAction: () -> Void
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private let menu = NSMenu()
    private var hostingController: NSHostingController<PopupRootView>?
    private var globalEventMonitor: Any?
    private var localEventMonitor: Any?
    private var settingsVisible = false

    init(model: CodexMenuBarModel, openSettings: @escaping () -> Void) {
        self.model = model
        self.openSettingsAction = openSettings
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        configureStatusItem()
        configurePopover()
        configureMenu()
        observeModel()
        updateTitle()
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(handleClick(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp, .otherMouseUp])
    }

    private func configurePopover() {
        popover.behavior = .transient
        let hostingController = NSHostingController(
            rootView: PopupRootView(
                model: model,
                onOpenSettings: { [weak self] in
                    self?.openSettings()
                }
            )
        )
        self.hostingController = hostingController
        popover.contentViewController = hostingController
        updatePopoverSize()
    }

    private func configureMenu() {
        let refresh = NSMenuItem(title: "Refresh now", action: #selector(refreshNow), keyEquivalent: "")
        let settings = NSMenuItem(title: "Settings", action: #selector(openSettingsMenu), keyEquivalent: "")
        let quit = NSMenuItem(title: "Quit Codexex", action: #selector(quitApp), keyEquivalent: "")

        refresh.target = self
        settings.target = self
        quit.target = self

        menu.addItem(refresh)
        menu.addItem(settings)
        menu.addItem(.separator())
        menu.addItem(quit)
    }

    @objc private func handleClick(_ sender: Any?) {
        guard let button = statusItem.button else { return }
        guard let event = NSApp.currentEvent else {
            togglePopover(button)
            return
        }

        switch event.type {
        case .rightMouseUp, .otherMouseUp:
            popover.performClose(nil)
            NSMenu.popUpContextMenu(menu, with: event, for: button)
        default:
            togglePopover(button)
        }
    }

    @objc private func refreshNow() {
        Task { @MainActor in
            await model.refreshNow()
        }
    }

    @objc private func openSettingsMenu() {
        openSettings()
    }

    private func openSettings() {
        openSettingsAction()
    }

    func setSettingsVisible(_ visible: Bool) {
        settingsVisible = visible
        popover.behavior = visible ? .applicationDefined : .transient

        guard let button = statusItem.button else { return }

        if visible {
            if popover.isShown == false {
                updatePopoverSize()
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            }
            stopEventMonitor()
        } else if popover.isShown {
            startEventMonitor()
        }
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    private func togglePopover(_ button: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(button)
            stopEventMonitor()
        } else {
            updatePopoverSize()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            if settingsVisible == false {
                startEventMonitor()
            }
        }
    }

    private func startEventMonitor() {
        stopEventMonitor()
        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            Task { @MainActor in
                self?.closePopoverFromMonitor()
            }
        }
        localEventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] event in
            guard let self else { return event }
            guard self.shouldClosePopover(for: event) else { return event }
            self.closePopoverFromMonitor()
            return event
        }
    }

    private func stopEventMonitor() {
        if let globalEventMonitor {
            NSEvent.removeMonitor(globalEventMonitor)
            self.globalEventMonitor = nil
        }
        if let localEventMonitor {
            NSEvent.removeMonitor(localEventMonitor)
            self.localEventMonitor = nil
        }
    }

    private func shouldClosePopover(for event: NSEvent) -> Bool {
        guard popover.isShown else { return false }

        if event.window == statusItem.button?.window {
            return false
        }

        if event.window == hostingController?.view.window {
            return false
        }

        return true
    }

    private func closePopoverFromMonitor() {
        popover.performClose(nil)
        stopEventMonitor()
    }

    private func observeModel() {
        withObservationTracking {
            trackPopupModelState()
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.updateTitle()
                self?.updatePopoverSize()
                self?.observeModel()
            }
        }
    }

    private func trackPopupModelState() {
        _ = model.snapshot
        _ = model.isRefreshing
        _ = model.lastError
        _ = model.popupSummary
        _ = model.isSigningIn
        _ = model.isSignedIn
        _ = model.hasResolvedAuthState
        _ = model.authDeviceCode
        _ = model.authStatusMessage
        _ = model.lastUpdatedAt
        _ = model.previewModeEnabled
        _ = model.showSparkEnabled
        _ = model.showHistoryEnabled
        _ = model.showHistoryChartEnabled
        _ = model.defaultHistoryMode
        _ = model.showPaceConfidence
        _ = model.hideIdleSecondaryLimits
        _ = model.showFiveHourInMenubar
        _ = model.showWeeklyInMenubar
        _ = model.usageHistory
    }

    private func updatePopoverSize() {
        guard let hostingController else { return }
        hostingController.view.layoutSubtreeIfNeeded()
        let fittingSize = hostingController.sizeThatFits(
            in: NSSize(width: GlassTokens.popupWidth, height: .greatestFiniteMagnitude)
        )
        popover.contentSize = NSSize(width: GlassTokens.popupWidth, height: ceil(fittingSize.height))
    }

    private func updateTitle() {
        let hasError = model.lastError != nil
        let button = statusItem.button
        button?.title = StatusBarLabel.makeTitle(
            snapshot: model.snapshot,
            isRefreshing: model.isRefreshing,
            hasError: hasError,
            showFiveHour: model.showFiveHourInMenubar,
            showWeekly: model.showWeeklyInMenubar
        )
        button?.image = StatusBarLabel.menuBarImage(
            isRefreshing: model.isRefreshing,
            hasError: hasError,
            severity: hasError || model.isRefreshing ? nil : model.popupSummary?.severity
        )
        button?.imagePosition = .imageLeading
    }
}
#endif
