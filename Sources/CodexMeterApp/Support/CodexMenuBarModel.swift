#if os(macOS)
import AppKit
import Foundation
import CodexMeterCore
import SwiftUI
import Observation
import OSLog

@MainActor
@Observable
final class CodexMenuBarModel {
    private final class Lifecycle {
        var refreshLoopTask: Task<Void, Never>?

        deinit {
            refreshLoopTask?.cancel()
        }
    }

    private(set) var snapshot: CodexSnapshot?
    private(set) var isRefreshing = false
    private(set) var lastError: String?
    private(set) var lastUpdatedAt: Date?
    private(set) var authStatusMessage: String = "Ready."
    private(set) var authDeviceCode: String?
    private(set) var authVerificationURL: URL?
    private(set) var authFlowID: String?
    private(set) var isSigningIn = false
    private(set) var isSignedIn = false
    private(set) var hasResolvedAuthState = false
    private(set) var autoRefreshEnabled = CodexAppSettings.autoRefreshEnabled
    private(set) var refreshIntervalSeconds = CodexAppSettings.refreshIntervalSeconds
    private(set) var launchAtLoginEnabled = CodexAppSettings.launchAtLoginEnabled
    private(set) var launchAtLoginStatusMessage: String?
    private(set) var showHistoryEnabled = CodexAppSettings.showHistoryEnabled
    private(set) var showFiveHourInMenubar = CodexAppSettings.showFiveHourInMenubar
    private(set) var showWeeklyInMenubar = CodexAppSettings.showWeeklyInMenubar
    private(set) var hasCompletedOnboarding = CodexAppSettings.hasCompletedOnboarding
    private(set) var previewModeEnabled = CodexAppSettings.previewModeEnabled
    private(set) var usageHistory: [CodexUsageHistorySample] = []
    private(set) var reduceMotionEnabled = false

    private let service: any CodexServiceClient
    private let usageHistoryStore = CodexUsageHistoryStore()
    private let lifecycle = Lifecycle()
    private var didStart = false
    private var stateGeneration = 0
    private var authRetryNotBefore: Date?

    init(service: any CodexServiceClient = CodexXPCClient()) {
        self.service = service
        launchAtLoginEnabled = CodexLaunchAtLoginManager.syncStoredState()
    }

    func start() async {
        guard didStart == false else { return }
        didStart = true
        CodexLog.ui.log("model start onboarding=\(self.hasCompletedOnboarding, privacy: .public) preview=\(self.previewModeEnabled, privacy: .public)")

        if previewModeEnabled {
            applyPreviewData(now: Date())
        } else {
            usageHistory = await usageHistoryStore.load()
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
        guard isRefreshing == false else { return }
        if previewModeEnabled {
            CodexLog.refresh.log("refresh preview mode")
            applyPreviewData(now: Date())
            return
        }
        let generation = stateGeneration
        CodexLog.refresh.log("refresh start generation=\(generation, privacy: .public)")
        animateStateChange(.easeInOut(duration: 0.16)) {
            isRefreshing = true
        }
        defer { isRefreshing = false }

        do {
            var response = try await service.fetchSnapshotResponse()
            guard generation == stateGeneration else { return }

            if let result = response.snapshot {
                CodexLog.refresh.log("refresh success snapshot")
                animateStateChange(.easeInOut(duration: 0.18)) {
                    snapshot = result
                    lastUpdatedAt = result.capturedAt
                    lastError = nil
                    authDeviceCode = nil
                    authStatusMessage = "Signed in with ChatGPT."
                    isSignedIn = true
                    isSigningIn = false
                    hasResolvedAuthState = true
                }

                let updatedHistory = await usageHistoryStore.append(snapshot: result)
                guard generation == stateGeneration else { return }
                animateStateChange(.easeInOut(duration: 0.18)) {
                    usageHistory = updatedHistory
                }
            } else {
                CodexLog.refresh.log("refresh no snapshot authMode=\(String(describing: response.authMode), privacy: .public)")
                animateStateChange(.easeInOut(duration: 0.18)) {
                    applySnapshotResponse(response)
                }
            }
        } catch {
            CodexLog.refresh.error("refresh failed message=\(error.localizedDescription, privacy: .public)")
            guard generation == stateGeneration else { return }
            animateStateChange(.easeInOut(duration: 0.18)) {
                lastError = error.localizedDescription
                isSigningIn = false
                hasResolvedAuthState = true
                authStatusMessage = error.localizedDescription
            }
        }
    }

    func startChatGPTSignIn() {
        guard isSigningIn == false else { return }
        if let authRetryNotBefore, authRetryNotBefore > Date() {
            let seconds = max(Int(authRetryNotBefore.timeIntervalSinceNow.rounded(.up)), 1)
            let message = "Please wait \(seconds)s before trying sign-in again."
            CodexLog.auth.log("startChatGPTSignIn blocked cooldown seconds=\(seconds, privacy: .public)")
            lastError = message
            authStatusMessage = message
            hasResolvedAuthState = true
            return
        }
        CodexLog.auth.log("startChatGPTSignIn")
        disablePreviewMode()
        completeOnboarding()

        invalidateRefreshResults()
        let generation = stateGeneration
        authDeviceCode = nil
        authVerificationURL = nil
        authFlowID = nil
        lastError = nil
        authStatusMessage = "Starting ChatGPT sign-in."
        isSigningIn = true

        Task { @MainActor [weak self] in
            guard let self else { return }

            do {
                let auth = try await service.beginChatGPTSignIn()
                guard self.stateGeneration == generation else { return }

                self.authStatusMessage = "Enter the code in your browser."
                self.hasResolvedAuthState = true
                self.lastError = nil
                self.authDeviceCode = auth.userCode
                self.authVerificationURL = auth.verificationURL
                self.authFlowID = auth.flowID
                self.isSigningIn = false
                CodexLog.auth.log("device code ready flow=\(auth.flowID, privacy: .private(mask: .hash))")
            } catch {
                guard self.stateGeneration == generation else { return }

                let message: String
                if error.localizedDescription.contains("429") {
                    self.authRetryNotBefore = Date().addingTimeInterval(10)
                    message = "OpenAI is rate-limiting sign-in right now. Wait 10 seconds and try again."
                } else {
                    message = error.localizedDescription
                }
                self.authStatusMessage = message
                self.hasResolvedAuthState = true
                self.lastError = message
                self.isSigningIn = false
                CodexLog.auth.error("begin sign-in failed message=\(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func clearAuthCode() {
        invalidateRefreshResults()
        authDeviceCode = nil
        authVerificationURL = nil
        authFlowID = nil
        authStatusMessage = clearedAuthGuidanceMessage()
    }

    func completePendingChatGPTSignIn() {
        guard let authFlowID else { return }
        CodexLog.auth.log("poll pending sign-in flow=\(authFlowID, privacy: .private(mask: .hash))")
        let generation = stateGeneration
        isSigningIn = true
        authStatusMessage = "Finishing sign-in."
        lastError = nil

        Task { @MainActor [weak self] in
            guard let self else { return }

            do {
                try await self.service.completeChatGPTSignIn(flowID: authFlowID)
                guard self.stateGeneration == generation else { return }

                self.authDeviceCode = nil
                self.authVerificationURL = nil
                self.authFlowID = nil
                self.authRetryNotBefore = nil
                CodexLog.auth.log("sign-in complete; refreshing snapshot")
                await self.refreshNow()
            } catch {
                guard self.stateGeneration == generation else { return }
                self.authStatusMessage = error.localizedDescription
                self.hasResolvedAuthState = true
                self.lastError = error.localizedDescription
                self.isSigningIn = false
                CodexLog.auth.error("poll sign-in failed message=\(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func openAuthVerificationPage() {
        guard let authVerificationURL else { return }
        completeOnboarding()
        CodexLog.auth.log("opening Safari for device auth")
        NSWorkspace.shared.open(authVerificationURL)
        completePendingChatGPTSignIn()
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
        CodexAppSettings.previewModeEnabled = true
        previewModeEnabled = true
        applyPreviewData(now: Date())
    }

    func disablePreviewMode() {
        guard previewModeEnabled else { return }
        CodexLog.ui.log("disable preview mode")
        CodexAppSettings.previewModeEnabled = false
        previewModeEnabled = false
        snapshot = nil
        usageHistory = []
        lastUpdatedAt = nil
        authStatusMessage = "Preview mode off."
        hasResolvedAuthState = false
        isSignedIn = false
        lastError = nil
    }

    func signOut() {
        CodexLog.auth.log("signOut")
        if previewModeEnabled {
            disablePreviewMode()
            return
        }
        invalidateRefreshResults()

        authStatusMessage = "Signing out…"
        authDeviceCode = nil
        authVerificationURL = nil
        authFlowID = nil
        authRetryNotBefore = nil
        isSigningIn = false
        lastError = nil

        Task { @MainActor [weak self] in
            guard let self else { return }

            do {
                try await service.signOut()
                CodexLog.auth.log("signOut complete")
                self.isSignedIn = false
                self.hasResolvedAuthState = true
                self.snapshot = nil
                self.authDeviceCode = nil
                self.authVerificationURL = nil
                self.authFlowID = nil
                self.lastError = nil
                self.authStatusMessage = "Signed out."
            } catch {
                CodexLog.auth.error("signOut failed message=\(error.localizedDescription, privacy: .public)")
                self.lastError = error.localizedDescription
                self.authStatusMessage = error.localizedDescription
            }
        }
    }

    private func applySnapshotResponse(_ response: CodexServiceSnapshotResponse) {
        snapshot = nil
        authDeviceCode = nil
        authVerificationURL = nil
        authFlowID = nil
        isSigningIn = false
        hasResolvedAuthState = true
        lastError = response.errorMessage

        switch response.authMode {
        case .chatGPT:
            isSignedIn = true
            authStatusMessage = response.errorMessage ?? "Signed in with ChatGPT."
        case nil:
            snapshot = nil
            isSignedIn = false
            authStatusMessage = response.errorMessage ?? "Not signed in. Use the button below."
        }
    }

    private func clearedAuthGuidanceMessage() -> String {
        if snapshot != nil {
            return "Signed in with ChatGPT."
        }
        if hasResolvedAuthState {
            return lastError ?? "Not signed in. Use the button below."
        }
        return "Ready."
    }

    private func invalidateRefreshResults() {
        stateGeneration += 1
    }

    private func applyPreviewData(now: Date) {
        let previewSnapshot = CodexPreviewData.snapshot(now: now)
        snapshot = previewSnapshot
        usageHistory = CodexPreviewData.history(now: now)
        lastUpdatedAt = now
        authDeviceCode = nil
        authVerificationURL = nil
        authFlowID = nil
        isSigningIn = false
        isSignedIn = true
        hasResolvedAuthState = true
        lastError = nil
        authStatusMessage = "Preview mode."
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
#endif
