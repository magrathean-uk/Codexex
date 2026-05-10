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
    private var resignActiveObserver: NSObjectProtocol?
    private var settingsVisible = false
    private var lastStatusState: CodexStatusItemViewState?
    private var lastSizingState: CodexPopupSizingState?
    private var updateScheduled = false

    init(model: CodexMenuBarModel, openSettings: @escaping () -> Void) {
        self.model = model
        self.openSettingsAction = openSettings
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        configureStatusItem()
        configurePopover()
        configureMenu()
        observeAppActivation()
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
        updatePopoverSize(force: true)
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
            await model.refreshNow(manual: true)
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
                updatePopoverSize(force: true)
                showPopover(from: button)
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
            updatePopoverSize(force: true)
            showPopover(from: button)
            if settingsVisible == false {
                startEventMonitor()
            }
        }
    }

    private func showPopover(from button: NSStatusBarButton) {
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        clampPopoverToVisibleFrame(anchorFrame: CodexPopoverSizing.anchorFrameOnScreen(for: button))
        DispatchQueue.main.async { [weak self, weak button] in
            guard let self, let button else { return }
            self.clampPopoverToVisibleFrame(anchorFrame: CodexPopoverSizing.anchorFrameOnScreen(for: button))
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

    private func observeAppActivation() {
        resignActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard self?.settingsVisible == false else { return }
                self?.closePopoverFromMonitor()
            }
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
                self?.scheduleModelUpdate()
                self?.observeModel()
            }
        }
    }

    private func scheduleModelUpdate() {
        guard updateScheduled == false else { return }
        updateScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.updateScheduled = false
            self.updateTitle()
            self.updatePopoverSize()
        }
    }

    private func trackPopupModelState() {
        _ = model.snapshot
        _ = model.localUsageSummary
        _ = model.isRefreshing
        _ = model.lastError
        _ = model.popupSummary
        _ = model.isCurrentSummarySnoozed
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
        _ = model.menuBarDisplayMode
        _ = model.resetDisplayStyle
        _ = model.appearanceMode
        _ = model.diagnosticsStatusMessage
        _ = model.shouldDimStatusItem
        _ = model.usageHistory
    }

    private func updatePopoverSize(force: Bool = false) {
        guard let hostingController else { return }
        let sizingState = CodexPopupSizingState(model: model, isShown: popover.isShown)
        if force == false {
            guard popover.isShown || hostingController.view.window == nil else { return }
        }
        if force == false, sizingState == lastSizingState {
            return
        }
        lastSizingState = sizingState
        let anchorFrame = statusItem.button.flatMap(CodexPopoverSizing.anchorFrameOnScreen(for:))
        let maxHeight = CodexPopoverSizing.maxHeight(
            anchorFrame: anchorFrame,
            screen: statusItem.button?.window?.screen
        )
        hostingController.view.layoutSubtreeIfNeeded()
        let fittingSize = hostingController.sizeThatFits(
            in: NSSize(width: GlassTokens.popupWidth, height: maxHeight)
        )
        let height = CodexPopoverSizing.height(fittingHeight: fittingSize.height, maxHeight: maxHeight)
        popover.contentSize = NSSize(width: GlassTokens.popupWidth, height: height)
        if popover.isShown {
            clampPopoverToVisibleFrame(anchorFrame: anchorFrame)
        }
    }

    private func clampPopoverToVisibleFrame(anchorFrame: CGRect?) {
        guard let window = popover.contentViewController?.view.window else { return }
        let screen = CodexPopoverSizing.screenContaining(anchorFrame) ?? window.screen ?? NSScreen.main
        guard let visibleFrame = screen?.visibleFrame.insetBy(dx: 8, dy: 8) else { return }

        var frame = window.frame
        if frame.maxY > visibleFrame.maxY {
            frame.origin.y = visibleFrame.maxY - frame.height
        }
        if frame.minY < visibleFrame.minY {
            frame.origin.y = visibleFrame.minY
        }
        if frame.maxX > visibleFrame.maxX {
            frame.origin.x = visibleFrame.maxX - frame.width
        }
        if frame.minX < visibleFrame.minX {
            frame.origin.x = visibleFrame.minX
        }

        if frame != window.frame {
            window.setFrame(frame, display: true)
        }
    }

    private func updateTitle() {
        let state = CodexStatusItemViewState(model: model)
        guard state != lastStatusState else { return }
        lastStatusState = state
        let button = statusItem.button
        button?.title = state.title
        button?.image = StatusBarLabel.menuBarImage(
            isRefreshing: state.isRefreshing,
            hasError: state.hasError,
            isStale: state.isStale,
            severity: state.severity
        )
        button?.imagePosition = .imageLeading
        button?.alphaValue = state.shouldDim ? 0.55 : 1
    }
}

enum CodexPopoverSizing {
    static func maxHeight(for screen: NSScreen?) -> CGFloat {
        maxHeight(anchorFrame: nil, screen: screen)
    }

    static func maxHeight(anchorFrame: CGRect?, screen: NSScreen?) -> CGFloat {
        let targetScreen = screenContaining(anchorFrame) ?? screen ?? NSScreen.main
        guard let visibleFrame = targetScreen?.visibleFrame else {
            return GlassTokens.popupMaxHeight
        }

        let screenSafeHeight = max(0, visibleFrame.height - GlassTokens.popupScreenMargin)
        let anchoredHeight: CGFloat
        if let anchorFrame {
            let belowAnchor = max(0, anchorFrame.minY - visibleFrame.minY - GlassTokens.popupScreenMargin)
            let aboveAnchor = max(0, visibleFrame.maxY - anchorFrame.maxY - GlassTokens.popupScreenMargin)
            anchoredHeight = max(belowAnchor, aboveAnchor)
        } else {
            anchoredHeight = screenSafeHeight
        }

        let availableHeight = max(0, min(screenSafeHeight, anchoredHeight))
        return clampedPreferredHeight(forAvailableHeight: availableHeight)
    }

    static func height(fittingHeight: CGFloat, maxHeight: CGFloat) -> CGFloat {
        min(ceil(fittingHeight), maxHeight)
    }

    static func clampedPreferredHeight(forAvailableHeight availableHeight: CGFloat) -> CGFloat {
        let preferredHeight = min(GlassTokens.popupMaxHeight, max(0, availableHeight))
        let minimumUsable = min(GlassTokens.popupMinimumUsableHeight, GlassTokens.popupMaxHeight)
        guard preferredHeight < minimumUsable else {
            return preferredHeight
        }
        return preferredHeight
    }

    @MainActor
    static func anchorFrameOnScreen(for button: NSStatusBarButton) -> CGRect? {
        guard let window = button.window else { return nil }
        let rectInWindow = button.convert(button.bounds, to: nil)
        return window.convertToScreen(rectInWindow)
    }

    static func screenContaining(_ anchorFrame: CGRect?) -> NSScreen? {
        guard let anchorFrame else { return nil }
        let anchorCenter = CGPoint(x: anchorFrame.midX, y: anchorFrame.midY)
        return NSScreen.screens.first { screen in
            screen.frame.contains(anchorCenter)
        }
    }
}
#endif
