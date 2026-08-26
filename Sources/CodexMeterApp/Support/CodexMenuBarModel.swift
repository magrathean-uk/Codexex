#if os(macOS)
import AppKit
import Foundation
import Observation
import SwiftUI
import CodexMeterCore

@MainActor
@Observable
final class CodexMenuBarModel {
    private static let maxLocalUsageScansPerRefresh = 8

    private final class Lifecycle {
        var refreshLoopTask: Task<Void, Never>?
        var deviceAuthPollTask: Task<Void, Never>?
        var localUsageTask: Task<Void, Never>?
        var staleDeadlineTask: Task<Void, Never>?

        deinit {
            refreshLoopTask?.cancel()
            deviceAuthPollTask?.cancel()
            localUsageTask?.cancel()
            staleDeadlineTask?.cancel()
        }
    }

    private(set) var dashboard = CodexDashboardState()
    private(set) var authSession = CodexAuthSession()
    private(set) var autoRefreshEnabled = CodexAppSettings.autoRefreshEnabled
    private(set) var refreshIntervalSeconds = CodexAppSettings.refreshIntervalSeconds
    private(set) var launchAtLoginEnabled = CodexAppSettings.launchAtLoginEnabled
    private(set) var launchAtLoginStatusMessage: String?
    private(set) var showHistoryEnabled = CodexAppSettings.showHistoryEnabled
    private(set) var showHistoryChartEnabled = CodexAppSettings.showHistoryChartEnabled
    private(set) var showInsightsEnabled = CodexAppSettings.showInsightsEnabled
    private(set) var showSparkEnabled = CodexAppSettings.showSparkEnabled
    private(set) var defaultHistoryMode = CodexAppSettings.defaultHistoryMode
    private(set) var showPaceConfidence = CodexAppSettings.showPaceConfidence
    private(set) var hideIdleSecondaryLimits = CodexAppSettings.hideIdleSecondaryLimits
    private(set) var quotaNotificationsEnabled = CodexAppSettings.quotaNotificationsEnabled
    private(set) var quotaNotificationAuthorizationState: CodexNotificationAuthorizationState = .unknown
    private(set) var codexSessionsPath = CodexAppSettings.codexSessionsPath
    private(set) var showFiveHourInMenubar = CodexAppSettings.showFiveHourInMenubar
    private(set) var showWeeklyInMenubar = CodexAppSettings.showWeeklyInMenubar
    private(set) var menuBarDisplayMode = CodexAppSettings.menuBarDisplayMode
    private(set) var resetDisplayStyle = CodexAppSettings.resetDisplayStyle
    private(set) var appearanceMode = CodexAppSettings.appearanceMode
    private(set) var diagnosticsStatusMessage: String?
    private(set) var hasCompletedOnboarding = CodexAppSettings.hasCompletedOnboarding
    private(set) var previewModeEnabled = CodexAppSettings.previewModeEnabled
    private(set) var reduceMotionEnabled = false
    private(set) var staleDeadlineReached = false
    private var summarySnoozeFingerprint = CodexAppSettings.summarySnoozeFingerprint
    private var summarySnoozeExpiresAt = CodexAppSettings.summarySnoozeExpiresAt

    private let service: any CodexServiceClient
    private let localUsageProvider: any CodexLocalUsageProviding
    private let settingsStore: CodexAppSettingsStore
    private let historyRepository: CodexHistoryRepository
    private let notificationDelivery: any CodexQuotaNotificationDelivering
    private let deviceAuthPollingConfiguration: CodexDeviceAuthPollingConfiguration
    private let openURL: @MainActor (URL) -> Bool
    private let clock: CodexMenuBarClock
    private let refreshCoordinator = CodexRefreshCoordinator()
    private let lifecycle = Lifecycle()
    private var didStart = false
    private var refreshBackoff = CodexRefreshBackoff()
    private var localUsageGeneration = 0
    private var notificationPermissionGeneration = 0

    init(
        service: any CodexServiceClient = CodexXPCClient(),
        localUsageProvider: any CodexLocalUsageProviding = CodexLocalUsageProvider(),
        settingsStore: CodexAppSettingsStore = CodexAppSettingsStore(),
        historyRepository: CodexHistoryRepository = CodexHistoryRepository(),
        notificationDelivery: any CodexQuotaNotificationDelivering = CodexUserNotificationDelivery(),
        deviceAuthPollingConfiguration: CodexDeviceAuthPollingConfiguration = .production,
        clock: CodexMenuBarClock = .live,
        openURL: @escaping @MainActor (URL) -> Bool = { NSWorkspace.shared.open($0) }
    ) {
        self.service = service
        self.localUsageProvider = localUsageProvider
        self.settingsStore = settingsStore
        self.historyRepository = historyRepository
        self.notificationDelivery = notificationDelivery
        self.deviceAuthPollingConfiguration = deviceAuthPollingConfiguration
        self.clock = clock
        self.openURL = openURL
        let settings = settingsStore.snapshot()
        autoRefreshEnabled = settings.autoRefreshEnabled
        refreshIntervalSeconds = settings.refreshIntervalSeconds
        launchAtLoginEnabled = settings.launchAtLoginEnabled
        showHistoryEnabled = settings.showHistoryEnabled
        showHistoryChartEnabled = settings.showHistoryChartEnabled
        showInsightsEnabled = settings.showInsightsEnabled
        showSparkEnabled = settings.showSparkEnabled
        defaultHistoryMode = settings.defaultHistoryMode
        showPaceConfidence = settings.showPaceConfidence
        hideIdleSecondaryLimits = settings.hideIdleSecondaryLimits
        quotaNotificationsEnabled = settings.quotaNotificationsEnabled
        codexSessionsPath = settings.codexSessionsPath
        showFiveHourInMenubar = settings.showFiveHourInMenubar
        showWeeklyInMenubar = settings.showWeeklyInMenubar
        menuBarDisplayMode = settings.menuBarDisplayMode
        resetDisplayStyle = settings.resetDisplayStyle
        appearanceMode = settings.appearanceMode
        hasCompletedOnboarding = settings.hasCompletedOnboarding
        previewModeEnabled = settings.previewModeEnabled
        summarySnoozeFingerprint = settings.summarySnoozeFingerprint
        summarySnoozeExpiresAt = settings.summarySnoozeExpiresAt
        launchAtLoginEnabled = CodexLaunchAtLoginManager.syncStoredState()
    }

    var snapshot: CodexSnapshot? { dashboard.snapshot }
    var isRefreshing: Bool { dashboard.isRefreshing }
    var lastError: String? { authSession.lastError ?? dashboard.lastError }
    var lastUpdatedAt: Date? { dashboard.lastUpdatedAt }
    var authStatusMessage: String { authSession.statusMessage }
    var authDeviceCode: String? { authSession.userCode }
    var authVerificationURL: URL? { authSession.verificationURL }
    var authFlowID: String? { authSession.flowID }
    var isSigningIn: Bool { authSession.isSigningIn }
    var isSigningOut: Bool { authSession.isSigningOut }
    var isCancellingPendingSignIn: Bool { authSession.isCancelling }
    var isAuthBusy: Bool { authSession.isBusy }
    var isSignedIn: Bool { authSession.isSignedIn }
    var hasResolvedAuthState: Bool { authSession.hasResolvedState }
    var usageHistory: [CodexUsageHistorySample] { dashboard.usageHistory }
    var usageInsights: CodexUsageInsights? { dashboard.usageInsights }
    var localUsageSummary: CodexLocalUsageSummary? { dashboard.localUsageSummary }
    var localUsageLoadState: CodexLocalUsageLoadState { dashboard.localUsageLoadState }
    var quotaNotificationStatusMessage: String? {
        switch quotaNotificationAuthorizationState {
        case .denied:
            return "Blocked by macOS. Allow notifications in System Settings."
        case .notDetermined where quotaNotificationsEnabled:
            return "Waiting for macOS notification permission."
        case .unknown where quotaNotificationsEnabled:
            return "Checking macOS notification permission."
        case .authorized, .notDetermined, .unknown:
            return nil
        }
    }
    var localIntelligenceSummary: CodexLocalIntelligenceSummary? {
        CodexLocalIntelligence.summary(
            insights: usageInsights,
            localUsage: localUsageSummary
        )
    }
    var shouldDimStatusItem: Bool { lastError != nil || isDataStale }
    var isDataStale: Bool {
        guard previewModeEnabled == false,
              isRefreshing == false,
              let lastUpdatedAt else {
            return false
        }
        let staleSeconds = max(Double(refreshIntervalSeconds * 2 + 60), 15 * 60)
        return staleDeadlineReached || clock.now().timeIntervalSince(lastUpdatedAt) > staleSeconds
    }
    var popupSummary: PopupSummaryPresentation? {
        let fallback = PopupPresentation.summary(
            snapshot: snapshot,
            insights: usageInsights,
            previewModeEnabled: previewModeEnabled,
            hasRefreshIssue: dashboard.lastError != nil,
            showFiveHour: showFiveHourInMenubar
        )
        return CodexLocalIntelligence.popupSummary(
            insights: usageInsights,
            localUsage: localUsageSummary,
            fallback: fallback
        )
    }
    var isCurrentSummarySnoozed: Bool {
        guard let popupSummary else { return false }
        return isSummarySnoozed(popupSummary)
    }

    func start() async {
        guard didStart == false else { return }
        didStart = true
        CodexLog.ui.log(
            "model start onboarding=\(self.hasCompletedOnboarding, privacy: .public) preview=\(self.previewModeEnabled, privacy: .public)"
        )
        refreshNotificationAuthorization(requestIfNeeded: false)

        if previewModeEnabled {
            authSession.apply(.previewEnabled)
            dashboard.applyPreview(now: Date())
        } else {
            let history = await historyRepository.load(snapshot: nil)
            dashboard.setHistory(history)
            await refreshNow(manual: true)
        }

        restartRefreshLoop()
    }

    func refreshNow(manual: Bool = false) async {
        guard isSigningOut == false, isCancellingPendingSignIn == false else { return }
        if manual == false && refreshBackoff.allowsAutomaticRefresh(now: clock.now()) == false {
            return
        }
        guard dashboard.isRefreshing == false else { return }
        if previewModeEnabled {
            CodexLog.refresh.log("refresh preview mode")
            authSession.apply(.previewEnabled)
            dashboard.applyPreview(now: Date())
            return
        }

        let generation = refreshCoordinator.token()
        CodexLog.refresh.log("refresh start generation=\(generation, privacy: .public)")
        animateStateChange(.easeInOut(duration: 0.16)) {
            dashboard.isRefreshing = true
        }
        defer { dashboard.isRefreshing = false }

        startLocalUsageRefresh()

        do {
            let response = try await service.fetchSnapshotResponse()
            guard refreshCoordinator.isCurrent(generation) else { return }

            if let result = response.snapshot {
                CodexLog.refresh.log("refresh success snapshot")
                let updatedHistory = await historyRepository.append(snapshot: result)
                guard refreshCoordinator.isCurrent(generation) else { return }
                animateStateChange(.easeInOut(duration: 0.18)) {
                    dashboard.applySnapshot(result, historyState: updatedHistory)
                    authSession.apply(.signedIn)
                }
                scheduleStaleDeadline()
                refreshBackoff.recordSuccess()
                await deliverQuotaNotificationsIfNeeded(snapshot: result)
            } else {
                CodexLog.refresh.log(
                    "refresh no snapshot authMode=\(String(describing: response.authMode), privacy: .public)"
                )
                animateStateChange(.easeInOut(duration: 0.18)) {
                    applySnapshotResponse(response)
                }
                if let message = response.errorMessage {
                    let failureClass = CodexRefreshBackoff.classify(errorMessage: message)
                    refreshBackoff.recordFailure(failureClass, now: clock.now())
                } else {
                    refreshBackoff.recordSuccess()
                }
            }
        } catch {
            CodexLog.refresh.error("refresh failed message=\(error.localizedDescription, privacy: .public)")
            guard refreshCoordinator.isCurrent(generation) else { return }
            let failureClass = CodexRefreshBackoff.classify(errorMessage: error.localizedDescription)
            refreshBackoff.recordFailure(failureClass, now: clock.now())
            animateStateChange(.easeInOut(duration: 0.18)) {
                dashboard.setError(error.localizedDescription)
            }
        }
    }

    func startChatGPTSignIn() {
        guard canStartChatGPTSignIn else { return }
        if let cooldownMessage = authSession.cooldownMessage {
            CodexLog.auth.log("startChatGPTSignIn blocked cooldown")
            authSession.apply(.beginBlocked(message: cooldownMessage))
            dashboard.setError(nil)
            return
        }

        CodexLog.auth.log("startChatGPTSignIn")
        disablePreviewMode(refreshAfterDisable: false)
        completeOnboarding()

        invalidateRefreshResults(cancelHelper: true)
        let generation = refreshCoordinator.token()
        authSession.apply(.beginRequested)
        dashboard.setError(nil)

        Task { @MainActor [weak self] in
            guard let self else { return }

            do {
                let auth = try await service.beginChatGPTSignIn()
                guard self.refreshCoordinator.isCurrent(generation) else { return }

                let context = CodexDeviceCodeContext(
                    flowID: auth.flowID,
                    verificationURL: auth.verificationURL,
                    userCode: auth.userCode,
                    createdAt: Date()
                )
                self.dashboard.setError(nil)
                self.authSession.apply(.beginSucceeded(context))
                CodexLog.auth.log("device code ready flow=\(auth.flowID, privacy: .private(mask: .hash))")
                if self.openURL(auth.verificationURL) == false {
                    self.authSession.apply(
                        .pollingFailed("Could not open Safari. Copy the code and open the sign-in page manually.")
                    )
                    return
                }
                self.startDeviceAuthPolling(flowID: auth.flowID, generation: generation, pollImmediately: false)
            } catch {
                guard self.refreshCoordinator.isCurrent(generation) else { return }

                let outcome = CodexAuthFlow.beginFailure(error)
                self.dashboard.setError(nil)
                self.authSession.apply(
                    .beginFailed(message: outcome.message, retryNotBefore: outcome.retryNotBefore)
                )
                CodexLog.auth.error(
                    "begin sign-in failed message=\(error.localizedDescription, privacy: .public)"
                )
            }
        }
    }

    func clearAuthCode() {
        cancelPendingChatGPTSignIn()
    }

    func cancelPendingChatGPTSignIn() {
        guard let flowID = authFlowID else {
            invalidateRefreshResults(cancelHelper: true)
            authSession.apply(.clearDeviceCode)
            dashboard.setError(nil)
            return
        }
        guard isCancellingPendingSignIn == false, isSigningOut == false else { return }

        invalidateRefreshResults(cancelHelper: true)
        let generation = refreshCoordinator.token()
        authSession.apply(.cancelRequested)
        dashboard.setError(nil)

        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await withHelperTimeout(.seconds(deviceAuthPollingConfiguration.requestTimeoutSeconds)) {
                    try await self.service.cancelChatGPTSignIn(flowID: flowID)
                } onTimeout: { [service] in
                    service.cancelPendingOperations()
                }
                guard self.refreshCoordinator.isCurrent(generation), self.authFlowID == flowID else { return }
                self.authSession.apply(.clearDeviceCode)
                self.dashboard.setError(nil)
                CodexLog.auth.log("pending device auth cancelled flow=\(flowID, privacy: .private(mask: .hash))")
            } catch {
                guard self.refreshCoordinator.isCurrent(generation), self.authFlowID == flowID else { return }
                let message = CodexSensitiveRedactor.redacted(error.localizedDescription)
                self.authSession.apply(.cancelFailed("Could not cancel sign-in. \(message)"))
                CodexLog.auth.error("cancel sign-in failed message=\(message, privacy: .private)")
            }
        }
    }

    func completePendingChatGPTSignIn() {
        checkPendingChatGPTSignIn()
    }

    func checkPendingChatGPTSignIn() {
        guard let authFlowID, isCancellingPendingSignIn == false else { return }
        CodexLog.auth.log("poll pending sign-in flow=\(authFlowID, privacy: .private(mask: .hash))")
        let generation = refreshCoordinator.token()
        startDeviceAuthPolling(flowID: authFlowID, generation: generation, pollImmediately: true)
    }

    func openAuthVerificationPage() {
        guard let authVerificationURL, isCancellingPendingSignIn == false else { return }
        completeOnboarding()
        CodexLog.auth.log("opening Safari for device auth")
        guard openURL(authVerificationURL) else {
            authSession.apply(
                .pollingFailed("Could not open Safari. Copy the code and open the sign-in page manually.")
            )
            return
        }
        checkPendingChatGPTSignIn()
    }

    func copyAuthCode() {
        guard let code = authDeviceCode, isCancellingPendingSignIn == false else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(code, forType: .string)
        authSession.apply(.pollingPending("Code copied. Paste it in Safari."))
    }

    func setLaunchAtLoginEnabled(_ enabled: Bool) {
        let result = CodexLaunchAtLoginManager.setEnabled(enabled)
        launchAtLoginEnabled = result.isEnabled

        if let errorMessage = result.errorMessage, result.isEnabled != enabled {
            launchAtLoginStatusMessage = "Could not update launch at login. \(errorMessage)"
        } else {
            launchAtLoginStatusMessage = nil
        }
    }

    func setAutoRefreshEnabled(_ enabled: Bool) {
        autoRefreshEnabled = enabled
        settingsStore.setAutoRefreshEnabled(enabled)
        restartRefreshLoop()
    }

    func setRefreshIntervalSeconds(_ seconds: Int) {
        let clampedSeconds = max(seconds, 300)
        refreshIntervalSeconds = clampedSeconds
        settingsStore.setRefreshIntervalSeconds(clampedSeconds)
        restartRefreshLoop()
        scheduleStaleDeadline()
    }

    func setShowHistoryEnabled(_ enabled: Bool) {
        showHistoryEnabled = enabled
        settingsStore.setShowHistoryEnabled(enabled)
    }

    func setShowInsightsEnabled(_ enabled: Bool) {
        showInsightsEnabled = enabled
        settingsStore.setShowInsightsEnabled(enabled)
    }

    func setShowHistoryChartEnabled(_ enabled: Bool) {
        showHistoryChartEnabled = enabled
        settingsStore.setShowHistoryChartEnabled(enabled)
    }

    func setShowSparkEnabled(_ enabled: Bool) {
        showSparkEnabled = enabled
        settingsStore.setShowSparkEnabled(enabled)
    }

    func setDefaultHistoryMode(_ mode: PopupHistoryMode) {
        defaultHistoryMode = mode
        settingsStore.setDefaultHistoryMode(mode)
    }

    func setShowPaceConfidence(_ enabled: Bool) {
        showPaceConfidence = enabled
        settingsStore.setShowPaceConfidence(enabled)
    }

    func setHideIdleSecondaryLimits(_ enabled: Bool) {
        hideIdleSecondaryLimits = enabled
        settingsStore.setHideIdleSecondaryLimits(enabled)
    }

    func setQuotaNotificationsEnabled(_ enabled: Bool) {
        notificationPermissionGeneration += 1
        let generation = notificationPermissionGeneration
        guard enabled else {
            quotaNotificationsEnabled = false
            settingsStore.setQuotaNotificationsEnabled(false)
            return
        }

        quotaNotificationAuthorizationState = .notDetermined
        quotaNotificationsEnabled = false
        settingsStore.setQuotaNotificationsEnabled(false)
        Task { @MainActor [weak self, notificationDelivery] in
            let state = await notificationDelivery.authorizationState(requestIfNeeded: true)
            guard let self, self.notificationPermissionGeneration == generation else { return }
            self.quotaNotificationAuthorizationState = state
            let granted = state == .authorized
            self.quotaNotificationsEnabled = granted
            self.settingsStore.setQuotaNotificationsEnabled(granted)
        }
    }

    func setCodexSessionsPath(_ path: String?) {
        codexSessionsPath = path
        settingsStore.setCodexSessionsPath(path)
        if path == nil {
            settingsStore.setCodexSessionsBookmark(nil)
        }
    }

    func chooseCodexSessionsFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        panel.prompt = "Use Folder"
        panel.message = "Choose ~/.codex or ~/.codex/sessions."
        panel.directoryURL = codexSessionsPath.map(URL.init(fileURLWithPath:))
            ?? CodexLocalUsageDirectoryReader.defaultSessionsURL().deletingLastPathComponent()

        guard panel.runModal() == .OK,
              let url = panel.url else {
            return
        }
        let sessionsURL = CodexAppSettings.normalizedCodexSessionsURL(url)
        codexSessionsPath = sessionsURL.path
        settingsStore.setCodexSessionsFolder(url: url)
        Task { @MainActor [weak self] in
            await self?.refreshNow(manual: true)
        }
    }

    func setShowFiveHourInMenubar(_ enabled: Bool) {
        showFiveHourInMenubar = enabled
        settingsStore.setShowFiveHourInMenubar(enabled)
    }

    func setShowWeeklyInMenubar(_ enabled: Bool) {
        showWeeklyInMenubar = enabled
        settingsStore.setShowWeeklyInMenubar(enabled)
    }

    func setMenuBarDisplayMode(_ mode: CodexMenuBarDisplayMode) {
        menuBarDisplayMode = mode
        settingsStore.setMenuBarDisplayMode(mode)
    }

    func setResetDisplayStyle(_ style: CodexResetDisplayStyle) {
        resetDisplayStyle = style
        settingsStore.setResetDisplayStyle(style)
    }

    func setAppearanceMode(_ mode: CodexAppearanceMode) {
        appearanceMode = mode
        settingsStore.setAppearanceMode(mode)
    }

    func copyDiagnosticsReport() {
        let report = diagnosticsReport(now: Date())
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report, forType: .string)
        diagnosticsStatusMessage = "Copied safe diagnostics."
    }

    func setReduceMotionEnabled(_ enabled: Bool) {
        reduceMotionEnabled = enabled
    }

    func isSummarySnoozed(_ summary: PopupSummaryPresentation) -> Bool {
        CodexSummarySnooze.isSnoozed(
            summary: summary,
            storedFingerprint: summarySnoozeFingerprint,
            expiresAt: summarySnoozeExpiresAt
        )
    }

    func snoozeCurrentSummary() {
        guard let popupSummary else { return }
        snoozeSummary(popupSummary)
    }

    func snoozeSummary(_ summary: PopupSummaryPresentation) {
        let expiry = CodexSummarySnooze.expiryDate(snapshot: snapshot) ?? Date().addingTimeInterval(60 * 60)
        let fingerprint = CodexSummarySnooze.fingerprint(for: summary)
        summarySnoozeFingerprint = fingerprint
        summarySnoozeExpiresAt = expiry
        settingsStore.setSummarySnoozeFingerprint(fingerprint)
        settingsStore.setSummarySnoozeExpiresAt(expiry)
    }

    func openManageSubscription() {
        NSWorkspace.shared.open(CodexAppLinks.manageSubscriptionURL)
    }

    func completeOnboarding() {
        CodexLog.ui.log("complete onboarding")
        hasCompletedOnboarding = true
        settingsStore.setHasCompletedOnboarding(true)
    }

    func enablePreviewMode() {
        CodexLog.ui.log("enable preview mode")
        completeOnboarding()
        invalidateRefreshResults(cancelHelper: true)
        settingsStore.setPreviewModeEnabled(true)
        previewModeEnabled = true
        authSession.apply(.previewEnabled)
        dashboard.applyPreview(now: Date())
        restartRefreshLoop()
        scheduleStaleDeadline()
    }

    func disablePreviewMode(refreshAfterDisable: Bool = true) {
        guard previewModeEnabled else { return }
        CodexLog.ui.log("disable preview mode")
        invalidateRefreshResults(cancelHelper: true)
        settingsStore.setPreviewModeEnabled(false)
        previewModeEnabled = false
        authSession.apply(.previewDisabled)
        dashboard.clearSnapshot(keepHistory: false, keepLocalUsage: false)
        restartRefreshLoop()
        scheduleStaleDeadline()

        guard refreshAfterDisable else { return }
        Task { @MainActor [weak self] in
            await self?.refreshNow(manual: true)
        }
    }

    func signOut() {
        guard isSigningOut == false else { return }
        CodexLog.auth.log("signOut")
        if previewModeEnabled {
            disablePreviewMode()
            return
        }
        invalidateRefreshResults(cancelHelper: true)
        dashboard.setError(nil)
        authSession.apply(.signOutRequested)
        let generation = refreshCoordinator.token()

        Task { @MainActor [weak self] in
            guard let self else { return }

            do {
                try await service.signOut()
                guard self.refreshCoordinator.isCurrent(generation), self.isSigningOut else { return }
                CodexLog.auth.log("signOut complete")
                dashboard.clearSnapshot(keepHistory: true)
                authSession.apply(.signedOut("Signed out."))
                scheduleStaleDeadline()
            } catch {
                guard self.refreshCoordinator.isCurrent(generation), self.isSigningOut else { return }
                CodexLog.auth.error("signOut failed message=\(error.localizedDescription, privacy: .public)")
                dashboard.setError(error.localizedDescription)
                authSession.apply(.signedIn)
            }
        }
    }

    func clearHelperStateForAppReset() async -> String? {
        CodexLog.auth.log("reset helper sign-out start")
        invalidateRefreshResults(cancelHelper: true)
        do {
            try await service.signOut()
            CodexLog.auth.log("reset helper sign-out complete")
            return nil
        } catch {
            CodexLog.auth.error(
                "reset helper sign-out failed message=\(error.localizedDescription, privacy: .public)"
            )
            return "Could not clear helper sign-in: \(error.localizedDescription)"
        }
    }

    private func applySnapshotResponse(_ response: CodexServiceSnapshotResponse) {
        let hasPendingDeviceCode = authSession.currentDeviceCode != nil
        let preservesPendingDeviceCode = CodexAuthFlow.shouldPreservePendingDeviceCode(
            response: response,
            hasPendingDeviceCode: hasPendingDeviceCode
        )

        if response.authMode == nil {
            if preservesPendingDeviceCode {
                dashboard.setError(nil)
                return
            }
            dashboard.clearSnapshot(keepHistory: true)
            dashboard.setError(nil)
            authSession.apply(.signedOut(CodexAuthFlow.signedOutMessage(for: response)))
            scheduleStaleDeadline()
            return
        }

        dashboard.setError(response.errorMessage ?? "Quota is temporarily unavailable.")

        switch response.authMode {
        case .chatGPT:
            authSession.apply(.signedIn)
        case nil:
            break
        }
    }

    private func startLocalUsageRefresh() {
        localUsageGeneration += 1
        let generation = localUsageGeneration
        lifecycle.localUsageTask?.cancel()
        dashboard.beginLocalUsageLoad()
        lifecycle.localUsageTask = Task { @MainActor [weak self, localUsageProvider, clock] in
            var scanCount = 0
            while Task.isCancelled == false, scanCount < Self.maxLocalUsageScansPerRefresh {
                scanCount += 1
                let result = await localUsageProvider.fetchLocalUsageSummary()
                guard Task.isCancelled == false else { return }
                let shouldContinue: Bool
                if let self, self.localUsageGeneration == generation {
                    self.dashboard.applyLocalUsageResult(result)
                    if case .available(let summary) = result {
                        shouldContinue = summary.coverage.isSelectedSetIndexed == false
                            && summary.coverage.bytesRead > 0
                            && scanCount < Self.maxLocalUsageScansPerRefresh
                    } else {
                        shouldContinue = false
                    }
                    if shouldContinue == false {
                        self.lifecycle.localUsageTask = nil
                    }
                } else {
                    return
                }
                guard shouldContinue else { return }
                do {
                    try await clock.sleep(5)
                } catch {
                    return
                }
            }
        }
    }

    private func restartRefreshLoop() {
        lifecycle.refreshLoopTask?.cancel()
        lifecycle.refreshLoopTask = nil
        guard didStart, autoRefreshEnabled, previewModeEnabled == false else { return }

        lifecycle.refreshLoopTask = Task { @MainActor [weak self, clock] in
            while Task.isCancelled == false {
                guard let interval = self?.refreshIntervalSeconds else { return }
                do {
                    try await clock.sleep(TimeInterval(interval))
                } catch {
                    return
                }
                guard let self else { return }
                guard Task.isCancelled == false else { return }
                guard self.refreshBackoff.allowsAutomaticRefresh(now: self.clock.now()) else {
                    continue
                }
                await self.refreshNow()
            }
        }
    }

    private func scheduleStaleDeadline() {
        lifecycle.staleDeadlineTask?.cancel()
        lifecycle.staleDeadlineTask = nil
        staleDeadlineReached = false
        guard previewModeEnabled == false, let lastUpdatedAt else { return }

        let staleSeconds = max(Double(refreshIntervalSeconds * 2 + 60), 15 * 60)
        let deadline = lastUpdatedAt.addingTimeInterval(staleSeconds)
        let delay = deadline.timeIntervalSince(clock.now())
        guard delay > 0 else {
            staleDeadlineReached = true
            return
        }

        lifecycle.staleDeadlineTask = Task { @MainActor [weak self, clock] in
            do {
                try await clock.sleep(delay)
            } catch {
                return
            }
            guard let self else { return }
            guard Task.isCancelled == false,
                  self.lastUpdatedAt == lastUpdatedAt,
                  self.previewModeEnabled == false else {
                return
            }
            self.staleDeadlineReached = true
            self.lifecycle.staleDeadlineTask = nil
        }
    }

    private func deliverQuotaNotificationsIfNeeded(snapshot: CodexSnapshot) async {
        guard quotaNotificationsEnabled,
              previewModeEnabled == false else {
            return
        }

        let plan = CodexQuotaNotificationPlanner.plan(
            snapshot: snapshot,
            insights: dashboard.usageInsights,
            preferences: CodexQuotaNotificationPreferences(isEnabled: true),
            receipts: settingsStore.quotaNotificationReceipts,
            now: snapshot.capturedAt
        )
        guard plan.notifications.isEmpty == false else { return }

        let results = await notificationDelivery.deliver(plan.notifications)
        var receipts = settingsStore.quotaNotificationReceipts
        for result in results where result.delivered {
            receipts = receipts.recording(result.notification)
        }
        settingsStore.setQuotaNotificationReceipts(receipts)
    }

    private func refreshNotificationAuthorization(requestIfNeeded: Bool) {
        notificationPermissionGeneration += 1
        let generation = notificationPermissionGeneration
        Task { @MainActor [weak self, notificationDelivery] in
            let state = await notificationDelivery.authorizationState(requestIfNeeded: requestIfNeeded)
            guard let self, self.notificationPermissionGeneration == generation else { return }
            self.quotaNotificationAuthorizationState = state
            if state == .denied, self.quotaNotificationsEnabled {
                self.quotaNotificationsEnabled = false
                self.settingsStore.setQuotaNotificationsEnabled(false)
            }
        }
    }

    private func invalidateRefreshResults(cancelHelper: Bool) {
        lifecycle.deviceAuthPollTask?.cancel()
        lifecycle.deviceAuthPollTask = nil
        refreshCoordinator.invalidate {
            if cancelHelper {
                service.cancelPendingOperations()
            }
        }
    }

    private func startDeviceAuthPolling(flowID: String, generation: Int, pollImmediately: Bool) {
        lifecycle.deviceAuthPollTask?.cancel()
        lifecycle.deviceAuthPollTask = Task { @MainActor [weak self] in
            guard let self else { return }

            let expiresAt = Date().addingTimeInterval(deviceAuthPollingConfiguration.timeoutSeconds)
            var shouldPollImmediately = pollImmediately

            while Task.isCancelled == false {
                if shouldPollImmediately {
                    shouldPollImmediately = false
                } else {
                    do {
                        try await Task.sleep(for: .seconds(deviceAuthPollingConfiguration.intervalSeconds))
                    } catch {
                        break
                    }
                }

                guard Task.isCancelled == false else { break }
                guard Date() < expiresAt else {
                    guard self.authFlowID == flowID, self.refreshCoordinator.isCurrent(generation) else { return }
                    self.authSession.apply(.pollingPending("Sign-in timed out. Check status or start again."))
                    CodexLog.auth.log("device auth polling timed out")
                    return
                }

                let outcome = await self.pollPendingChatGPTSignInOnce(flowID: flowID, generation: generation)
                switch outcome {
                case .signedIn:
                    return
                case .pending:
                    continue
                case .stale:
                    return
                }
            }
        }
    }

    private enum DeviceAuthPollOutcome {
        case signedIn
        case pending
        case stale
    }

    private func pollPendingChatGPTSignInOnce(flowID: String, generation: Int) async -> DeviceAuthPollOutcome {
        guard authFlowID == flowID, refreshCoordinator.isCurrent(generation) else { return .stale }

        authSession.apply(.pollingRequested)
        dashboard.setError(nil)

        do {
            try await withHelperTimeout(.seconds(deviceAuthPollingConfiguration.requestTimeoutSeconds)) {
                let result = try await self.service.completeChatGPTSignIn(flowID: flowID)
                switch result.status {
                case .signedIn:
                    return
                case .pending:
                    throw PendingSignInStillWaiting()
                }
            } onTimeout: { [service] in
                service.cancelPendingOperations()
            }
            guard authFlowID == flowID, refreshCoordinator.isCurrent(generation) else { return .stale }

            lifecycle.deviceAuthPollTask = nil
            authSession.apply(.signedIn)
            dashboard.setError(nil)
            CodexLog.auth.log("sign-in complete; refreshing snapshot")
            await refreshNow(manual: true)
            return .signedIn
        } catch is PendingSignInStillWaiting {
            guard authFlowID == flowID, refreshCoordinator.isCurrent(generation) else { return .stale }
            authSession.apply(.pollingPending("Waiting for Safari approval."))
            CodexLog.auth.log("device auth approval still pending")
            return .pending
        } catch is HelperOperationTimedOut {
            guard authFlowID == flowID, refreshCoordinator.isCurrent(generation) else { return .stale }
            authSession.apply(.pollingPending("Sign-in check timed out. Retrying with the same code."))
            CodexLog.auth.log("device auth poll timed out")
            return .pending
        } catch {
            guard authFlowID == flowID, refreshCoordinator.isCurrent(generation) else { return .stale }
            let message = error.localizedDescription
            if CodexAuthFlow.isTerminalPollingFailure(message) {
                authSession.apply(.pollingInterrupted(message))
            } else {
                authSession.apply(.pollingFailed(message))
            }
            CodexLog.auth.error(
                "poll sign-in failed message=\(error.localizedDescription, privacy: .public)"
            )
            return CodexAuthFlow.isTerminalPollingFailure(message) ? .stale : .pending
        }
    }

    private func animateStateChange(
        _: Animation,
        updates: () -> Void
    ) {
        updates()
    }

    func diagnosticsReport(now: Date) -> String {
        let formatter = ISO8601DateFormatter()
        let limits = snapshot?.limits.map { limit in
            let windows = [
                limit.fiveHourWindow.map { "5H \($0.usedPercentText) reset=\(formatter.string(from: $0.resetsAt ?? .distantPast))" },
                limit.weeklyWindow.map { "W \($0.usedPercentText) reset=\(formatter.string(from: $0.resetsAt ?? .distantPast))" }
            ]
            .compactMap { $0 }
            .joined(separator: ", ")
            return "- \(limit.displayName): \(windows.isEmpty ? "no windows" : windows)"
        } ?? ["- no snapshot"]
        let localUsage = localUsageSummary
        let localContextText = localUsage?.contextWindowPercent.map { "\(Int($0.rounded()))%" } ?? "none"

        let forecast = usageInsights?.weeklyPace
        let readiness = forecast?.modelReadiness
        let rangeText: String
        if let lower = forecast?.likelyLowerPercent, let upper = forecast?.likelyUpperPercent {
            rangeText = "\(Int(lower.rounded()))-\(Int(upper.rounded()))%"
        } else {
            rangeText = "none"
        }

        let lines = [
            "Codexex Diagnostics",
            "Version: \(Bundle.main.codexexVersionString)",
            "Generated: \(formatter.string(from: now))",
            "Preview: \(previewModeEnabled)",
            "Signed in: \(authSession.isAuthenticated)",
            "Refreshing: \(isRefreshing)",
            "Stale: \(isDataStale)",
            "Auto refresh: \(autoRefreshEnabled) / \(refreshIntervalSeconds)s",
            "Menu mode: \(menuBarDisplayMode.rawValue)",
            "Reset style: \(resetDisplayStyle.rawValue)",
            "History samples: \(usageHistory.count)",
            "Local status: \(localUsageLoadState.statusText)",
            "Local sessions: \(localUsage.map { String($0.sessions.count) } ?? "unavailable")",
            "Local indexed tokens: \(localUsage.map { String($0.total.totalTokens) } ?? "unavailable")",
            "Local coverage: \(localUsage?.coverage.label ?? "unavailable")",
            "Local top project: \(localUsage?.projects.first?.displayName ?? "none")",
            "Local top model: \(localUsage?.modelSummaries.first?.model ?? "none")",
            "Local attribution: \(localUsage?.attributionConfidence.level.rawValue ?? "unknown")",
            "Local context: \(localContextText)",
            "Last updated: \(lastUpdatedAt.map { formatter.string(from: $0) } ?? "none")",
            "Last error: \(redactedDiagnosticText(lastError ?? "none"))",
            "Weekly forecast: \(forecast?.confidence.label ?? "none") current=\(percentText(forecast?.currentPercent)) projected=\(percentText(forecast?.projectedPercentAtReset)) range=\(rangeText)",
            "ML readiness: days \(readiness?.historyDays ?? 0)/\(readiness?.requiredHistoryDays ?? 0), samples \(readiness?.sampleCount ?? 0)/\(readiness?.requiredSamples ?? 0), cycles \(readiness?.cycleCount ?? 0)/\(readiness?.requiredCycles ?? 0)",
            "Limits:"
        ] + limits

        return lines.joined(separator: "\n")
    }

    private func percentText(_ value: Double?) -> String {
        guard let value else { return "none" }
        return "\(Int(value.rounded()))%"
    }

    private func redactedDiagnosticText(_ text: String) -> String {
        CodexSensitiveRedactor.redacted(text)
    }
}

private struct PendingSignInStillWaiting: Error {}
private struct HelperOperationTimedOut: Error {}

struct CodexMenuBarClock: Sendable {
    let now: @Sendable () -> Date
    let sleep: @Sendable (TimeInterval) async throws -> Void

    static let live = CodexMenuBarClock(
        now: Date.init,
        sleep: { seconds in
            try await Task.sleep(for: .seconds(max(0, seconds)))
        }
    )
}

struct CodexDeviceAuthPollingConfiguration: Sendable, Equatable {
    let intervalSeconds: Double
    let timeoutSeconds: Double
    let requestTimeoutSeconds: Double

    static let production = CodexDeviceAuthPollingConfiguration(
        intervalSeconds: 3,
        timeoutSeconds: 10 * 60,
        requestTimeoutSeconds: 15
    )
}

private func withHelperTimeout<T: Sendable>(
    _ timeout: Duration,
    operation: @escaping @MainActor () async throws -> T,
    onTimeout: @escaping @MainActor () -> Void
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask {
            try await operation()
        }
        group.addTask {
            try await Task.sleep(for: timeout)
            throw HelperOperationTimedOut()
        }

        do {
            let value = try await group.next()!
            group.cancelAll()
            return value
        } catch is HelperOperationTimedOut {
            group.cancelAll()
            await onTimeout()
            throw HelperOperationTimedOut()
        } catch {
            group.cancelAll()
            throw error
        }
    }
}
#endif
