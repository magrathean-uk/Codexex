import Foundation
import Observation
import UIKit
import CodexMeterCore

enum CodexiOSLiveAccountState: Equatable {
    case checking
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
    private let liveActivityManager: any CodexiOSLiveActivityManaging

    var hasCompletedOnboarding: Bool
    var previewModeEnabled: Bool
    var snapshot: CodexSnapshot?
    var usageHistory: [CodexUsageHistorySample] = []
    var isRefreshing = false
    var isSigningIn = false
    var statusMessage = "Checking saved account."
    var errorMessage: String?
    var deviceCode: String?
    var verificationURL: URL?
    var flowID: String?
    var lastUpdatedAt: Date?
    private(set) var hasCheckedLiveActivityAvailability = false
    private(set) var isLiveActivityAvailable = false
    private(set) var isLiveActivityRunning = false
    private(set) var isLiveActivityTransitioning = false
    private(set) var isLiveActivityStale = false
    private(set) var liveActivityID: String?
    private(set) var liveAccountState: CodexiOSLiveAccountState

    private var liveActivityGeneration = 0
    private var liveActivityOperationCount = 0

    init(
        service: any CodexiOSServiceProtocol = CodexiOSService(),
        defaults: UserDefaults = .standard,
        historyStore: CodexUsageHistoryStore = CodexUsageHistoryStore(),
        liveActivityManager: any CodexiOSLiveActivityManaging = CodexiOSLiveActivity(),
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
        self.liveActivityManager = CodexiOSLiveActivitySerialManager(
            manager: liveActivityManager
        )
        let storedPreviewModeEnabled = defaults.bool(forKey: CodexiOSSettingsKeys.previewModeEnabled)
        hasCompletedOnboarding = defaults.bool(forKey: CodexiOSSettingsKeys.hasCompletedOnboarding)
        previewModeEnabled = storedPreviewModeEnabled
        liveAccountState = storedPreviewModeEnabled ? .signedOut : .checking
    }

    var isSignedIn: Bool {
        liveAccountState == .signedIn
    }

    var isCheckingSavedAccount: Bool {
        liveAccountState == .checking
    }

    var hasPendingSignIn: Bool {
        liveAccountState == .pendingSignIn && flowID != nil
    }

    func start() async {
        await recoverLiveActivity()
        usageHistory = await historyStore.load()
        if previewModeEnabled {
            applyPreviewSnapshot()
            await updateLiveActivity(with: snapshot)
            return
        }
        await refresh()
    }

    func refresh() async {
        guard isRefreshing == false else { return }
        guard previewModeEnabled == false else {
            applyPreviewSnapshot()
            await updateLiveActivity(with: snapshot)
            return
        }
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            await applySnapshotResponse(try await service.fetchSnapshot())
        } catch {
            if liveAccountState == .checking {
                liveAccountState = .signedOut
            }
            applyError(message(for: error))
            await markLiveActivityStale()
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
            let refreshIntervalSeconds = max(
                defaults.object(forKey: CodexiOSSettingsKeys.refreshIntervalSeconds) as? Int ?? 300,
                300
            )
            if let lastUpdatedAt,
               Date().timeIntervalSince(lastUpdatedAt) < Double(refreshIntervalSeconds) {
                return
            }
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
        invalidateLiveActivityOperations()
        CodexiOSBackgroundRefresh.cancel()
        liveAccountState = .signedOut
        snapshot = nil
        lastUpdatedAt = nil
        clearPendingSignIn()
        await stopLiveActivity(announce: false)
        do {
            try await service.signOut()
            errorMessage = nil
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
        invalidateLiveActivityOperations()
        previewModeEnabled = true
        defaults.set(true, forKey: CodexiOSSettingsKeys.previewModeEnabled)
        completeOnboarding()
        applyPreviewSnapshot()
        statusMessage = "Preview mode is active."
        errorMessage = nil
        clearPendingSignIn()
        liveAccountState = .signedOut
        Task { [weak self] in
            guard let self else { return }
            await self.updateLiveActivity(with: self.snapshot)
        }
    }

    func disablePreviewMode() {
        guard previewModeEnabled else { return }
        invalidateLiveActivityOperations()
        previewModeEnabled = false
        defaults.set(false, forKey: CodexiOSSettingsKeys.previewModeEnabled)
        snapshot = nil
        lastUpdatedAt = nil
        liveAccountState = .signedOut
        statusMessage = "Preview mode off."
        beginLiveActivityOperation()
        Task { [weak self] in
            guard let self else { return }
            defer { self.endLiveActivityOperation() }
            await self.stopLiveActivity(announce: false)
            guard self.previewModeEnabled == false else { return }
            await self.refresh()
        }
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

    private func applySnapshotResponse(_ response: CodexServiceSnapshotResponse) async {
        if let snapshot = response.snapshot {
            self.snapshot = snapshot
            lastUpdatedAt = snapshot.capturedAt
            errorMessage = nil
            statusMessage = "Signed in."
            clearPendingSignIn()
            liveAccountState = .signedIn
            completeOnboarding()
            usageHistory = await historyStore.append(snapshot: snapshot)
            await updateLiveActivity(with: snapshot)
            return
        }

        errorMessage = response.errorMessage
        statusMessage = response.errorMessage ?? "No quota data yet."

        if hasPendingSignIn, response.authMode == nil {
            liveAccountState = .pendingSignIn
        } else if response.authMode == .chatGPT {
            liveAccountState = .signedIn
            completeOnboarding()
            await markLiveActivityStale()
        } else {
            snapshot = nil
            lastUpdatedAt = nil
            liveAccountState = .signedOut
            invalidateLiveActivityOperations()
            await stopLiveActivity(announce: false)
        }
    }

    func startLiveActivity() async {
        guard isLiveActivityTransitioning == false else { return }
        guard (isSignedIn || previewModeEnabled), let snapshot else { applyError("Sign in and refresh quota before starting Live Activity."); return }
        let generation = liveActivityGeneration
        beginLiveActivityOperation()
        defer { endLiveActivityOperation() }
        do {
            let state = try await liveActivityManager.start(
                snapshot: snapshot,
                showFiveHour: showFiveHourInPresentation,
                showUsedQuota: showUsedQuotaInPresentation,
                cadence: liveActivityCadence
            )
            guard generation == liveActivityGeneration,
                  isSignedIn || previewModeEnabled else {
                _ = await liveActivityManager.stop()
                return
            }
            applyLiveActivityState(state)
            isLiveActivityStale = false
            errorMessage = nil
            statusMessage = state.isRunning
                ? "Live Activity started. It refreshes on-device when iOS allows it."
                : "Live Activities are unavailable on this device."
            scheduleBackgroundLiveActivityRefreshIfNeeded()
        } catch { applyError(message(for: error)) }
    }

    func stopLiveActivity(announce: Bool = true) async {
        let generation = liveActivityGeneration
        beginLiveActivityOperation()
        defer { endLiveActivityOperation() }
        let state = await liveActivityManager.stop()
        guard generation == liveActivityGeneration else { return }
        applyLiveActivityState(state)
        isLiveActivityStale = false
        if announce {
            statusMessage = "Live Activity stopped."
        }
        CodexiOSBackgroundRefresh.cancel()
    }

    func updateLiveActivityPresentation(showFiveHour: Bool) async {
        await updateLiveActivityPresentation(
            showFiveHour: showFiveHour,
            showUsedQuota: showUsedQuotaInPresentation
        )
    }

    func updateLiveActivityPresentation(showFiveHour: Bool, showUsedQuota: Bool) async {
        guard (isSignedIn || previewModeEnabled), let snapshot else { return }
        let generation = liveActivityGeneration
        beginLiveActivityOperation()
        defer { endLiveActivityOperation() }
        let state: CodexiOSLiveActivityRuntimeState
        if isLiveActivityStale {
            state = await liveActivityManager.markStale(
                snapshot: snapshot,
                showFiveHour: showFiveHour,
                showUsedQuota: showUsedQuota,
                cadence: liveActivityCadence
            )
        } else {
            state = await liveActivityManager.update(
                snapshot: snapshot,
                showFiveHour: showFiveHour,
                showUsedQuota: showUsedQuota,
                cadence: liveActivityCadence
            )
        }
        guard generation == liveActivityGeneration else { return }
        applyLiveActivityState(state)
        scheduleBackgroundLiveActivityRefreshIfNeeded()
    }

    func snoozeSummary(_ summary: PopupSummaryPresentation) {
        defaults.set(CodexSummarySnooze.fingerprint(for: summary), forKey: CodexiOSSettingsKeys.summarySnoozeFingerprint)
        defaults.set(CodexSummarySnooze.expiryDate(snapshot: snapshot), forKey: CodexiOSSettingsKeys.summarySnoozeExpiresAt)
    }

    func refreshLiveActivityInBackground() async -> Bool {
        await recoverLiveActivity()
        guard isLiveActivityRunning, previewModeEnabled == false else {
            CodexiOSBackgroundRefresh.cancel()
            return true
        }

        await refresh()
        return Task.isCancelled == false && errorMessage == nil && isLiveActivityStale == false
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

    private func markLiveActivityStale() async {
        guard let snapshot else { return }
        let generation = liveActivityGeneration
        beginLiveActivityOperation()
        defer { endLiveActivityOperation() }
        let state = await liveActivityManager.markStale(
                snapshot: snapshot,
                showFiveHour: showFiveHourInPresentation,
                showUsedQuota: showUsedQuotaInPresentation,
                cadence: liveActivityCadence
        )
        guard generation == liveActivityGeneration else { return }
        applyLiveActivityState(state)
        isLiveActivityStale = true
        scheduleBackgroundLiveActivityRefreshIfNeeded()
    }

    private func recoverLiveActivity() async {
        applyLiveActivityState(await liveActivityManager.recover())
    }

    private func updateLiveActivity(with snapshot: CodexSnapshot?) async {
        guard let snapshot else { return }
        let generation = liveActivityGeneration
        beginLiveActivityOperation()
        defer { endLiveActivityOperation() }
        let state = await liveActivityManager.update(
                snapshot: snapshot,
                showFiveHour: showFiveHourInPresentation,
                showUsedQuota: showUsedQuotaInPresentation,
                cadence: liveActivityCadence
        )
        guard generation == liveActivityGeneration else { return }
        applyLiveActivityState(state)
        isLiveActivityStale = false
        scheduleBackgroundLiveActivityRefreshIfNeeded()
    }

    private func invalidateLiveActivityOperations() {
        liveActivityGeneration &+= 1
    }

    private func beginLiveActivityOperation() {
        liveActivityOperationCount += 1
        isLiveActivityTransitioning = true
    }

    private func endLiveActivityOperation() {
        liveActivityOperationCount = max(0, liveActivityOperationCount - 1)
        isLiveActivityTransitioning = liveActivityOperationCount > 0
    }

    private func applyLiveActivityState(_ state: CodexiOSLiveActivityRuntimeState) {
        hasCheckedLiveActivityAvailability = true
        isLiveActivityAvailable = state.isAvailable
        isLiveActivityRunning = state.isRunning
        liveActivityID = state.activityID
    }

    private var liveActivityCadence: TimeInterval {
        Double(
            max(
                defaults.object(forKey: CodexiOSSettingsKeys.refreshIntervalSeconds) as? Int ?? 300,
                300
            )
        )
    }

    private var showFiveHourInPresentation: Bool {
        defaults.object(forKey: CodexiOSSettingsKeys.showFiveHourPresentation) as? Bool ?? false
    }

    private var showUsedQuotaInPresentation: Bool {
        defaults.object(forKey: CodexiOSSettingsKeys.showUsedQuota) as? Bool ?? false
    }

    private func scheduleBackgroundLiveActivityRefreshIfNeeded() {
        guard isLiveActivityRunning, previewModeEnabled == false else { return }
        CodexiOSBackgroundRefresh.schedule(cadence: liveActivityCadence)
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
