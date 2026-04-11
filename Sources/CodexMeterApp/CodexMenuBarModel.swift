#if os(macOS)
import AppKit
import Foundation
import CodexMeterCore
import SwiftUI
import Observation

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
    private(set) var usageHistory: [CodexUsageHistorySample] = []
    private(set) var hasStoredAPIKey = CodexSecretStore.hasAPIKey()
    private(set) var reduceMotionEnabled = false

    private let service: any CodexServiceClient
    private let usageHistoryStore = CodexUsageHistoryStore()
    private let lifecycle = Lifecycle()
    private var didStart = false
    private var stateGeneration = 0

    init(service: any CodexServiceClient = CodexXPCClient()) {
        self.service = service
        launchAtLoginEnabled = CodexLaunchAtLoginManager.syncStoredState()
        hasStoredAPIKey = CodexSecretStore.hasAPIKey()
    }

    func start() async {
        guard didStart == false else { return }
        didStart = true

        usageHistory = await usageHistoryStore.load()
        await refreshNow()

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
        let generation = stateGeneration
        animateStateChange(.easeInOut(duration: 0.16)) {
            isRefreshing = true
        }
        defer { isRefreshing = false }

        do {
            var response = try await service.fetchSnapshotResponse()
            guard generation == stateGeneration else { return }

            if response.snapshot == nil, response.authMode == nil, hasStoredAPIKey {
                response = CodexServiceSnapshotResponse(
                    authMode: .apiKey,
                    snapshot: nil,
                    errorMessage: "Signed in with API key. ChatGPT quota is not available."
                )
            }

            if let result = response.snapshot {
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
                animateStateChange(.easeInOut(duration: 0.18)) {
                    applySnapshotResponse(response)
                }
            }
        } catch {
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

        invalidateRefreshResults()
        let generation = stateGeneration
        authDeviceCode = nil
        authVerificationURL = nil
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

                Task { @MainActor [weak self] in
                    guard let self else { return }

                    do {
                        try await self.service.completeChatGPTSignIn(flowID: auth.flowID)
                        guard self.stateGeneration == generation else { return }

                        self.authStatusMessage = "Finishing sign-in."
                        self.authDeviceCode = nil
                        self.authVerificationURL = nil
                        await self.refreshNow()
                    } catch {
                        guard self.stateGeneration == generation else { return }

                        self.authStatusMessage = error.localizedDescription
                        self.hasResolvedAuthState = true
                        self.lastError = error.localizedDescription
                        self.isSigningIn = false
                    }
                }
            } catch {
                guard self.stateGeneration == generation else { return }

                self.authStatusMessage = error.localizedDescription
                self.hasResolvedAuthState = true
                self.lastError = error.localizedDescription
                self.isSigningIn = false
            }
        }
    }

    func clearAuthCode() {
        invalidateRefreshResults()
        authDeviceCode = nil
        authVerificationURL = nil
        authStatusMessage = clearedAuthGuidanceMessage()
    }

    func openAuthVerificationPage() {
        guard let authVerificationURL else { return }
        NSWorkspace.shared.open(authVerificationURL)
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

    func saveAPIKey(_ key: String) {
        invalidateRefreshResults()
        do {
            try CodexSecretStore.saveAPIKey(key)
            hasStoredAPIKey = true
            lastError = nil
            authDeviceCode = nil
            authVerificationURL = nil
            authStatusMessage = "API key saved to Keychain."
            hasResolvedAuthState = true
            isSigningIn = false
            isSignedIn = true
        } catch {
            lastError = error.localizedDescription
            authStatusMessage = "Failed to save API key."
        }
    }

    func removeAPIKey() {
        invalidateRefreshResults()
        do {
            try CodexSecretStore.removeAPIKey()
            hasStoredAPIKey = false
            lastError = nil
            authStatusMessage = "API key removed from Keychain."
        } catch {
            lastError = error.localizedDescription
            authStatusMessage = "Failed to remove API key."
        }
    }

    func signOut() {
        invalidateRefreshResults()
        let generation = stateGeneration
        if snapshot == nil && hasStoredAPIKey {
            removeAPIKey()
            authDeviceCode = nil
            isSigningIn = false
            isSignedIn = false
            hasResolvedAuthState = true
            return
        }

        authStatusMessage = "Signing out…"
        authDeviceCode = nil
        authVerificationURL = nil
        isSigningIn = false
        lastError = nil

        Task { @MainActor [weak self] in
            guard let self else { return }

            do {
                try await service.signOut()
                guard self.stateGeneration == generation else { return }
                self.isSignedIn = false
                self.hasResolvedAuthState = true
                self.snapshot = nil
                self.authDeviceCode = nil
                self.authVerificationURL = nil
                self.lastError = nil
                self.authStatusMessage = "Signed out."
            } catch {
                guard self.stateGeneration == generation else { return }
                self.lastError = error.localizedDescription
                self.authStatusMessage = error.localizedDescription
            }
        }
    }

    private func applySnapshotResponse(_ response: CodexServiceSnapshotResponse) {
        snapshot = nil
        authDeviceCode = nil
        authVerificationURL = nil
        isSigningIn = false
        hasResolvedAuthState = true
        lastError = response.errorMessage

        switch response.authMode {
        case .apiKey:
            isSignedIn = true
            authStatusMessage = response.errorMessage ?? "Signed in with API key. ChatGPT quota is not available."
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
        if hasStoredAPIKey {
            return "API key saved to Keychain. Helper path is not wired yet."
        }
        if isSignedIn {
            return "Signed in with API key. ChatGPT quota is not available."
        }
        if hasResolvedAuthState {
            return lastError ?? "Not signed in. Use the button below."
        }
        return "Ready."
    }

    private func invalidateRefreshResults() {
        stateGeneration += 1
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
