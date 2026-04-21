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

        deinit {
            refreshLoopTask?.cancel()
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
    private(set) var hasCompletedOnboarding = CodexAppSettings.hasCompletedOnboarding
    private(set) var previewModeEnabled = CodexAppSettings.previewModeEnabled
    private(set) var reduceMotionEnabled = false

    private let service: any CodexServiceClient
    private let usageHistoryStore = CodexUsageHistoryStore()
    private let lifecycle = Lifecycle()
    private var didStart = false
    private var stateGeneration = 0

    init(service: any CodexServiceClient = CodexXPCClient()) {
        self.service = service
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
    var popupSummary: PopupSummaryPresentation? {
        PopupPresentation.summary(
            snapshot: snapshot,
            insights: usageInsights,
            previewModeEnabled: previewModeEnabled,
            hasRefreshIssue: dashboard.lastError != nil
        )
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
            let history = await usageHistoryStore.load()
            dashboard.setHistory(history)
            await refreshNow()
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
                await self.refreshNow()
            }
        }
    }

    func refreshNow() async {
        guard dashboard.isRefreshing == false else { return }
        if previewModeEnabled {
            CodexLog.refresh.log("refresh preview mode")
            authSession.apply(.previewEnabled)
            dashboard.applyPreview(now: Date())
            return
        }

        let generation = stateGeneration
        CodexLog.refresh.log("refresh start generation=\(generation, privacy: .public)")
        animateStateChange(.easeInOut(duration: 0.16)) {
            dashboard.isRefreshing = true
        }
        defer { dashboard.isRefreshing = false }

        do {
            let response = try await service.fetchSnapshotResponse()
            guard generation == stateGeneration else { return }

            if let result = response.snapshot {
                CodexLog.refresh.log("refresh success snapshot")
                let updatedHistory = await usageHistoryStore.append(snapshot: result)
                guard generation == stateGeneration else { return }
                animateStateChange(.easeInOut(duration: 0.18)) {
                    dashboard.applySnapshot(result, history: updatedHistory)
                    authSession.apply(.signedIn)
                }
            } else {
                CodexLog.refresh.log(
                    "refresh no snapshot authMode=\(String(describing: response.authMode), privacy: .public)"
                )
                animateStateChange(.easeInOut(duration: 0.18)) {
                    applySnapshotResponse(response)
                }
            }
        } catch {
            CodexLog.refresh.error("refresh failed message=\(error.localizedDescription, privacy: .public)")
            guard generation == stateGeneration else { return }
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
        let generation = stateGeneration
        authSession.apply(.beginRequested)
        dashboard.setError(nil)

        Task { @MainActor [weak self] in
            guard let self else { return }

            do {
                let auth = try await service.beginChatGPTSignIn()
                guard self.stateGeneration == generation else { return }

                let context = CodexDeviceCodeContext(
                    flowID: auth.flowID,
                    verificationURL: auth.verificationURL,
                    userCode: auth.userCode,
                    createdAt: Date()
                )
                self.dashboard.setError(nil)
                self.authSession.apply(.beginSucceeded(context))
                CodexLog.auth.log("device code ready flow=\(auth.flowID, privacy: .private(mask: .hash))")
            } catch {
                guard self.stateGeneration == generation else { return }

                let retryNotBefore: Date?
                let message: String
                if error.localizedDescription.contains("429") {
                    retryNotBefore = Date().addingTimeInterval(10)
                    message = "OpenAI is rate-limiting sign-in right now. Wait 10 seconds and try again."
                } else {
                    retryNotBefore = nil
                    message = error.localizedDescription
                }
                self.dashboard.setError(nil)
                self.authSession.apply(
                    .beginFailed(message: message, retryNotBefore: retryNotBefore)
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
        let generation = stateGeneration
        authSession.apply(.pollingRequested)
        dashboard.setError(nil)

        Task { @MainActor [weak self] in
            guard let self else { return }

            do {
                try await withHelperTimeout(.seconds(15)) {
                    let result = try await self.service.completeChatGPTSignIn(flowID: authFlowID)
                    switch result.status {
                    case .signedIn:
                        return
                    case .pending:
                        throw PendingSignInStillWaiting()
                    }
                } onTimeout: { [service] in
                    service.cancelPendingOperations()
                }
                guard self.stateGeneration == generation else { return }

                self.authSession.apply(.signedIn)
                self.dashboard.setError(nil)
                CodexLog.auth.log("sign-in complete; refreshing snapshot")
                await self.refreshNow()
            } catch is PendingSignInStillWaiting {
                guard self.stateGeneration == generation else { return }
                self.authSession.apply(.pollingPending("Sign-in approval still pending."))
                CodexLog.auth.log("device auth approval still pending")
            } catch {
                guard self.stateGeneration == generation else { return }
                self.authSession.apply(.pollingFailed(error.localizedDescription))
                CodexLog.auth.error(
                    "poll sign-in failed message=\(error.localizedDescription, privacy: .public)"
                )
            }
        }
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
        CodexAppSettings.autoRefreshEnabled = enabled
    }

    func setRefreshIntervalSeconds(_ seconds: Int) {
        refreshIntervalSeconds = seconds
        CodexAppSettings.refreshIntervalSeconds = seconds
    }

    func setShowHistoryEnabled(_ enabled: Bool) {
        showHistoryEnabled = enabled
        CodexAppSettings.showHistoryEnabled = enabled
    }

    func setShowInsightsEnabled(_ enabled: Bool) {
        showInsightsEnabled = enabled
        CodexAppSettings.showInsightsEnabled = enabled
    }

    func setShowHistoryChartEnabled(_ enabled: Bool) {
        showHistoryChartEnabled = enabled
        CodexAppSettings.showHistoryChartEnabled = enabled
    }

    func setShowSparkEnabled(_ enabled: Bool) {
        showSparkEnabled = enabled
        CodexAppSettings.showSparkEnabled = enabled
    }

    func setDefaultHistoryMode(_ mode: PopupHistoryMode) {
        defaultHistoryMode = mode
        CodexAppSettings.defaultHistoryMode = mode
    }

    func setShowPaceConfidence(_ enabled: Bool) {
        showPaceConfidence = enabled
        CodexAppSettings.showPaceConfidence = enabled
    }

    func setHideIdleSecondaryLimits(_ enabled: Bool) {
        hideIdleSecondaryLimits = enabled
        CodexAppSettings.hideIdleSecondaryLimits = enabled
    }

    func setShowFiveHourInMenubar(_ enabled: Bool) {
        showFiveHourInMenubar = enabled
        CodexAppSettings.showFiveHourInMenubar = enabled
    }

    func setShowWeeklyInMenubar(_ enabled: Bool) {
        showWeeklyInMenubar = enabled
        CodexAppSettings.showWeeklyInMenubar = enabled
    }

    func setReduceMotionEnabled(_ enabled: Bool) {
        reduceMotionEnabled = enabled
    }

    func completeOnboarding() {
        CodexLog.ui.log("complete onboarding")
        hasCompletedOnboarding = true
        CodexAppSettings.hasCompletedOnboarding = true
    }

    func enablePreviewMode() {
        CodexLog.ui.log("enable preview mode")
        completeOnboarding()
        invalidateRefreshResults(cancelHelper: true)
        CodexAppSettings.previewModeEnabled = true
        previewModeEnabled = true
        authSession.apply(.previewEnabled)
        dashboard.applyPreview(now: Date())
    }

    func disablePreviewMode(refreshAfterDisable: Bool = true) {
        guard previewModeEnabled else { return }
        CodexLog.ui.log("disable preview mode")
        invalidateRefreshResults(cancelHelper: true)
        CodexAppSettings.previewModeEnabled = false
        previewModeEnabled = false
        authSession.apply(.previewDisabled)
        dashboard.clearSnapshot(keepHistory: false)

        guard refreshAfterDisable else { return }
        Task { @MainActor [weak self] in
            await self?.refreshNow()
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

        if hasPendingDeviceCode, response.authMode == nil {
            return
        }

        switch response.authMode {
        case .chatGPT:
            authSession.apply(.signedIn)
        case nil:
            authSession.apply(.signedOut(response.errorMessage ?? "Not signed in. Use the button below."))
        }
    }

    private func invalidateRefreshResults(cancelHelper: Bool) {
        stateGeneration += 1
        if cancelHelper {
            service.cancelPendingOperations()
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
}

private struct PendingSignInStillWaiting: Error {}

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
            throw PendingSignInStillWaiting()
        }

        do {
            let value = try await group.next()!
            group.cancelAll()
            return value
        } catch is PendingSignInStillWaiting {
            group.cancelAll()
            await onTimeout()
            throw PendingSignInStillWaiting()
        } catch {
            group.cancelAll()
            throw error
        }
    }
}
#endif
