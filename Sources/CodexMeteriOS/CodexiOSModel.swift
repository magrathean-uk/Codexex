import Foundation
import Observation
import UIKit
import CodexMeterCore

enum CodexiOSLiveAccountState: Equatable {
    case signedOut
    case pendingSignIn
    case signedIn
}

protocol CodexiOSServiceProtocol: Sendable {
    func fetchSnapshot() async throws -> CodexServiceSnapshotResponse
    func beginSignIn() async throws -> CodexiOSDeviceAuthStart
    func pollSignIn(flowID: String) async throws -> CodexiOSPollResult
    func signOut() async throws
}

typealias CodexiOSOpenURLAction = @MainActor @Sendable (URL) async -> Void
typealias CodexiOSCopyTextAction = @MainActor @Sendable (String) -> Void

@MainActor
@Observable
final class CodexiOSModel {
    private let service: any CodexiOSServiceProtocol
    private let defaults: UserDefaults
    private let openURLAction: CodexiOSOpenURLAction
    private let copyTextAction: CodexiOSCopyTextAction
    private let historyStore: CodexUsageHistoryStore

    var hasCompletedOnboarding: Bool
    var previewModeEnabled: Bool
    var snapshot: CodexSnapshot?
    var usageHistory: [CodexUsageHistorySample] = []
    var isRefreshing = false
    var isSigningIn = false
    var statusMessage = "Sign in with ChatGPT to read Codex usage on this device."
    var errorMessage: String?
    var deviceCode: String?
    var verificationURL: URL?
    var flowID: String?
    var lastUpdatedAt: Date?
    private(set) var liveAccountState: CodexiOSLiveAccountState

    init(
        service: any CodexiOSServiceProtocol = CodexiOSService(),
        defaults: UserDefaults = .standard,
        historyStore: CodexUsageHistoryStore = CodexUsageHistoryStore(),
        openURLAction: @escaping CodexiOSOpenURLAction = { url in
            await UIApplication.shared.open(url)
        },
        copyTextAction: @escaping CodexiOSCopyTextAction = { text in
            UIPasteboard.general.string = text
        }
    ) {
        self.service = service
        self.defaults = defaults
        self.openURLAction = openURLAction
        self.copyTextAction = copyTextAction
        self.historyStore = historyStore
        hasCompletedOnboarding = defaults.bool(forKey: CodexiOSSettingsKeys.hasCompletedOnboarding)
        previewModeEnabled = defaults.bool(forKey: CodexiOSSettingsKeys.previewModeEnabled)
        liveAccountState = .signedOut
    }

    var isSignedIn: Bool {
        liveAccountState == .signedIn
    }

    var hasPendingSignIn: Bool {
        liveAccountState == .pendingSignIn && flowID != nil
    }

    func start() async {
        usageHistory = await historyStore.load()
        if previewModeEnabled {
            applyPreviewSnapshot()
            return
        }
        await refresh()
    }

    func refresh() async {
        guard isRefreshing == false else { return }
        guard previewModeEnabled == false else {
            applyPreviewSnapshot()
            return
        }
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            applySnapshotResponse(try await service.fetchSnapshot())
        } catch {
            applyError(message(for: error))
        }
    }

    func beginSignIn() async {
        guard isSigningIn == false else { return }
        isSigningIn = true
        errorMessage = nil
        statusMessage = "Starting ChatGPT sign-in."
        defer { isSigningIn = false }

        do {
            let auth = try await service.beginSignIn()
            deviceCode = auth.userCode
            verificationURL = auth.verificationURL
            flowID = auth.flowID
            liveAccountState = .pendingSignIn
            copyTextAction(auth.userCode)
            statusMessage = "Device code copied. Paste it in Safari."
        } catch {
            clearPendingSignIn()
            liveAccountState = .signedOut
            applyError(message(for: error))
        }
    }

    func checkSignIn() async {
        guard let flowID else { return }
        guard isSigningIn == false else { return }
        isSigningIn = true
        errorMessage = nil
        defer { isSigningIn = false }

        do {
            switch try await service.pollSignIn(flowID: flowID) {
            case .pending(let message):
                liveAccountState = .pendingSignIn
                statusMessage = message
            case .signedIn:
                liveAccountState = .signedIn
                statusMessage = "Signed in."
                clearPendingSignIn()
                completeOnboarding()
                await refresh()
            }
        } catch {
            liveAccountState = .pendingSignIn
            applyError(message(for: error))
        }
    }

    func checkSignInAfterReturn() async {
        guard hasPendingSignIn else { return }
        statusMessage = "Checking sign-in."
        await checkSignIn()
    }

    func handleSceneDidBecomeActive(
        autoCheckSignInOnReturn: Bool,
        refreshWhenActive: Bool
    ) async {
        guard previewModeEnabled == false else { return }
        if autoCheckSignInOnReturn, hasPendingSignIn {
            await checkSignInAfterReturn()
        } else if refreshWhenActive, isSignedIn {
            await refresh()
        }
    }

    func copyCode() {
        guard let deviceCode else { return }
        copyTextAction(deviceCode)
        statusMessage = "Code copied. Paste it in Safari."
    }

    func openSignInPage() async {
        guard let verificationURL else { return }
        await openURLAction(verificationURL)
    }

    func signOut() async {
        do {
            try await service.signOut()
            snapshot = nil
            lastUpdatedAt = nil
            errorMessage = nil
            clearPendingSignIn()
            liveAccountState = .signedOut
            statusMessage = "Signed out."
        } catch {
            applyError(message(for: error))
        }
    }

    func completeOnboarding() {
        guard hasCompletedOnboarding == false else { return }
        hasCompletedOnboarding = true
        defaults.set(true, forKey: CodexiOSSettingsKeys.hasCompletedOnboarding)
    }

    func enablePreviewMode() {
        previewModeEnabled = true
        defaults.set(true, forKey: CodexiOSSettingsKeys.previewModeEnabled)
        completeOnboarding()
        applyPreviewSnapshot()
        statusMessage = "Preview mode is active."
        errorMessage = nil
        clearPendingSignIn()
        liveAccountState = .signedOut
    }

    func disablePreviewMode() {
        guard previewModeEnabled else { return }
        previewModeEnabled = false
        defaults.set(false, forKey: CodexiOSSettingsKeys.previewModeEnabled)
        snapshot = nil
        lastUpdatedAt = nil
        liveAccountState = .signedOut
        statusMessage = "Preview mode off."
        Task { await refresh() }
    }

    private func applyPreviewSnapshot() {
        let preview = CodexiOSPreviewData.snapshot()
        snapshot = preview
        lastUpdatedAt = preview.capturedAt
        usageHistory = CodexiOSPreviewData.history(now: preview.capturedAt)
        errorMessage = nil
        statusMessage = "Preview mode is active."
        liveAccountState = .signedOut
    }

    private func applySnapshotResponse(_ response: CodexServiceSnapshotResponse) {
        if let snapshot = response.snapshot {
            self.snapshot = snapshot
            lastUpdatedAt = snapshot.capturedAt
            errorMessage = nil
            statusMessage = "Signed in."
            clearPendingSignIn()
            liveAccountState = .signedIn
            completeOnboarding()
            Task {
                self.usageHistory = await self.historyStore.append(snapshot: snapshot)
            }
            return
        }

        snapshot = nil
        lastUpdatedAt = nil
        errorMessage = response.errorMessage
        statusMessage = response.errorMessage ?? "No quota data yet."

        if hasPendingSignIn, response.authMode == nil {
            liveAccountState = .pendingSignIn
        } else {
            liveAccountState = response.authMode == .chatGPT ? .signedIn : .signedOut
        }
    }

    func snoozeSummary(_ summary: PopupSummaryPresentation) {
        defaults.set(CodexSummarySnooze.fingerprint(for: summary), forKey: CodexiOSSettingsKeys.summarySnoozeFingerprint)
        defaults.set(CodexSummarySnooze.expiryDate(snapshot: snapshot), forKey: CodexiOSSettingsKeys.summarySnoozeExpiresAt)
    }

    func isSummarySnoozed(_ summary: PopupSummaryPresentation) -> Bool {
        CodexSummarySnooze.isSnoozed(
            summary: summary,
            storedFingerprint: defaults.string(forKey: CodexiOSSettingsKeys.summarySnoozeFingerprint),
            expiresAt: defaults.object(forKey: CodexiOSSettingsKeys.summarySnoozeExpiresAt) as? Date
        )
    }

    private func applyError(_ message: String) {
        errorMessage = message
        statusMessage = message
    }

    private func clearPendingSignIn() {
        deviceCode = nil
        verificationURL = nil
        flowID = nil
    }

    private func message(for error: Error) -> String {
        if let localized = error as? LocalizedError, let description = localized.errorDescription {
            return description
        }
        return error.localizedDescription
    }
}
