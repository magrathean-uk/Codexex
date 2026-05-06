#if os(macOS)
import AppKit
import Foundation
import Observation
import SwiftUI
import CodexMeterCore

@MainActor
@Observable
final class CodexMenuBarModel {
    private final class Lifecycle {
        var refreshLoopTask: Task<Void, Never>?
        var deviceAuthPollTask: Task<Void, Never>?

        deinit {
            refreshLoopTask?.cancel()
            deviceAuthPollTask?.cancel()
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
    private(set) var showFiveHourInMenubar = CodexAppSettings.showFiveHourInMenubar
    private(set) var showWeeklyInMenubar = CodexAppSettings.showWeeklyInMenubar
    private(set) var menuBarDisplayMode = CodexAppSettings.menuBarDisplayMode
    private(set) var resetDisplayStyle = CodexAppSettings.resetDisplayStyle
    private(set) var appearanceMode = CodexAppSettings.appearanceMode
    private(set) var diagnosticsStatusMessage: String?
    private(set) var hasCompletedOnboarding = CodexAppSettings.hasCompletedOnboarding
    private(set) var previewModeEnabled = CodexAppSettings.previewModeEnabled
    private(set) var reduceMotionEnabled = false
    private var summarySnoozeFingerprint = CodexAppSettings.summarySnoozeFingerprint
    private var summarySnoozeExpiresAt = CodexAppSettings.summarySnoozeExpiresAt

    private let service: any CodexServiceClient
    private let settingsStore: CodexAppSettingsStore
    private let historyRepository: CodexHistoryRepository
    private let deviceAuthPollingConfiguration: CodexDeviceAuthPollingConfiguration
    private let refreshCoordinator = CodexRefreshCoordinator()
    private let lifecycle = Lifecycle()
    private var didStart = false
    private var refreshBackoff = CodexRefreshBackoff()

    init(
        service: any CodexServiceClient = CodexXPCClient(),
        settingsStore: CodexAppSettingsStore = CodexAppSettingsStore(),
        historyRepository: CodexHistoryRepository = CodexHistoryRepository(),
        deviceAuthPollingConfiguration: CodexDeviceAuthPollingConfiguration = .production
    ) {
        self.service = service
        self.settingsStore = settingsStore
        self.historyRepository = historyRepository
        self.deviceAuthPollingConfiguration = deviceAuthPollingConfiguration
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
    var isSignedIn: Bool { authSession.isSignedIn }
    var hasResolvedAuthState: Bool { authSession.hasResolvedState }
    var usageHistory: [CodexUsageHistorySample] { dashboard.usageHistory }
    var usageInsights: CodexUsageInsights? { dashboard.usageInsights }
    var shouldDimStatusItem: Bool { lastError != nil || isDataStale }
    var isDataStale: Bool {
        guard previewModeEnabled == false,
              isRefreshing == false,
              let lastUpdatedAt else {
            return false
        }
        let staleSeconds = max(Double(refreshIntervalSeconds * 2 + 60), 15 * 60)
        return Date().timeIntervalSince(lastUpdatedAt) > staleSeconds
    }
    var popupSummary: PopupSummaryPresentation? {
        PopupPresentation.summary(
            snapshot: snapshot,
            insights: usageInsights,
            previewModeEnabled: previewModeEnabled,
            hasRefreshIssue: dashboard.lastError != nil
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

        if previewModeEnabled {
            authSession.apply(.previewEnabled)
            dashboard.applyPreview(now: Date())
        } else {
            let history = await historyRepository.load(snapshot: nil)
            dashboard.setHistory(history)
            await refreshNow(manual: true)
        }

        lifecycle.refreshLoopTask = Task { [weak self] in
            while Task.isCancelled == false {
                guard let self else { break }

                if self.autoRefreshEnabled == false {
                    do {
                        try await Task.sleep(for: .seconds(30))
                    } catch {
                        break
                    }
                    continue
                }

                do {
                    try await Task.sleep(for: .seconds(Double(self.refreshIntervalSeconds)))
                } catch {
                    break
                }

                guard Task.isCancelled == false else { break }
                guard self.refreshBackoff.allowsAutomaticRefresh() else {
                    continue
                }
                await self.refreshNow()
            }
        }
    }

    func refreshNow(manual: Bool = false) async {
        if manual == false && refreshBackoff.allowsAutomaticRefresh() == false {
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
                refreshBackoff.recordSuccess()
            } else {
                CodexLog.refresh.log(
                    "refresh no snapshot authMode=\(String(describing: response.authMode), privacy: .public)"
                )
                animateStateChange(.easeInOut(duration: 0.18)) {
                    applySnapshotResponse(response)
                }
                if let message = response.errorMessage {
                    let failureClass = CodexRefreshBackoff.classify(errorMessage: message)
                    refreshBackoff.recordFailure(failureClass)
                } else {
                    refreshBackoff.recordSuccess()
                }
            }
        } catch {
            CodexLog.refresh.error("refresh failed message=\(error.localizedDescription, privacy: .public)")
            guard refreshCoordinator.isCurrent(generation) else { return }
            let failureClass = CodexRefreshBackoff.classify(errorMessage: error.localizedDescription)
            refreshBackoff.recordFailure(failureClass)
            animateStateChange(.easeInOut(duration: 0.18)) {
                dashboard.setError(error.localizedDescription)
            }
        }
    }

    func startChatGPTSignIn() {
        guard isSigningIn == false else { return }
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
        invalidateRefreshResults(cancelHelper: true)
        authSession.apply(.clearDeviceCode)
        dashboard.setError(nil)
    }

    func completePendingChatGPTSignIn() {
        checkPendingChatGPTSignIn()
    }

    func checkPendingChatGPTSignIn() {
        guard let authFlowID else { return }
        CodexLog.auth.log("poll pending sign-in flow=\(authFlowID, privacy: .private(mask: .hash))")
        let generation = refreshCoordinator.token()
        startDeviceAuthPolling(flowID: authFlowID, generation: generation, pollImmediately: true)
    }

    func openAuthVerificationPage() {
        guard let authVerificationURL else { return }
        completeOnboarding()
        CodexLog.auth.log("opening Safari for device auth")
        guard NSWorkspace.shared.open(authVerificationURL) else {
            authSession.apply(
                .pollingFailed("Could not open Safari. Copy the code and open the sign-in page manually.")
            )
            return
        }
        checkPendingChatGPTSignIn()
    }

    func copyAuthCode() {
        guard let code = authDeviceCode else { return }
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
    }

    func setRefreshIntervalSeconds(_ seconds: Int) {
        refreshIntervalSeconds = seconds
        settingsStore.setRefreshIntervalSeconds(seconds)
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

    func openAppStoreUpdates() {
        NSWorkspace.shared.open(CodexAppLinks.appStoreURL)
    }

    func openReleaseNotes() {
        NSWorkspace.shared.open(CodexAppLinks.releaseNotesURL)
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
    }

    func disablePreviewMode(refreshAfterDisable: Bool = true) {
        guard previewModeEnabled else { return }
        CodexLog.ui.log("disable preview mode")
        invalidateRefreshResults(cancelHelper: true)
        settingsStore.setPreviewModeEnabled(false)
        previewModeEnabled = false
        authSession.apply(.previewDisabled)
        dashboard.clearSnapshot(keepHistory: false)

        guard refreshAfterDisable else { return }
        Task { @MainActor [weak self] in
            await self?.refreshNow(manual: true)
        }
    }

    func signOut() {
        CodexLog.auth.log("signOut")
        if previewModeEnabled {
            disablePreviewMode()
            return
        }
        invalidateRefreshResults(cancelHelper: true)
        dashboard.setError(nil)
        authSession.apply(.signOutRequested)

        Task { @MainActor [weak self] in
            guard let self else { return }

            do {
                try await service.signOut()
                CodexLog.auth.log("signOut complete")
                dashboard.clearSnapshot(keepHistory: true)
                authSession.apply(.signedOut("Signed out."))
            } catch {
                CodexLog.auth.error("signOut failed message=\(error.localizedDescription, privacy: .public)")
                dashboard.setError(error.localizedDescription)
                authSession.apply(.signedIn)
            }
        }
    }

    private func applySnapshotResponse(_ response: CodexServiceSnapshotResponse) {
        let hasPendingDeviceCode = authSession.currentDeviceCode != nil
        dashboard.snapshot = nil
        dashboard.lastUpdatedAt = nil
        dashboard.setError(response.errorMessage)

        if CodexAuthFlow.shouldPreservePendingDeviceCode(
            response: response,
            hasPendingDeviceCode: hasPendingDeviceCode
        ) {
            return
        }

        switch response.authMode {
        case .chatGPT:
            authSession.apply(.signedIn)
        case nil:
            authSession.apply(.signedOut(CodexAuthFlow.signedOutMessage(for: response)))
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
            authSession.apply(.pollingPending("Still checking sign-in."))
            CodexLog.auth.log("device auth poll timed out")
            return .pending
        } catch {
            guard authFlowID == flowID, refreshCoordinator.isCurrent(generation) else { return .stale }
            authSession.apply(.pollingFailed(error.localizedDescription))
            CodexLog.auth.error(
                "poll sign-in failed message=\(error.localizedDescription, privacy: .public)"
            )
            return .stale
        }
    }

    private func animateStateChange(
        _ animation: Animation,
        updates: () -> Void
    ) {
        if reduceMotionEnabled {
            updates()
        } else {
            withAnimation(animation, updates)
        }
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
            "Signed in: \(isSignedIn)",
            "Refreshing: \(isRefreshing)",
            "Stale: \(isDataStale)",
            "Auto refresh: \(autoRefreshEnabled) / \(refreshIntervalSeconds)s",
            "Menu mode: \(menuBarDisplayMode.rawValue)",
            "Reset style: \(resetDisplayStyle.rawValue)",
            "History samples: \(usageHistory.count)",
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
