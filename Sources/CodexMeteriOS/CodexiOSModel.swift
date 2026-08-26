import Foundation
import Observation
import UIKit
import CodexMeterCore

enum CodexiOSLiveAccountState: Equatable {
    case checking
    case signedOut
    case authExpired
    case unavailable
    case pendingSignIn
    case signedIn
}

protocol CodexiOSServiceProtocol: Sendable {
    func fetchSnapshot() async throws -> CodexiOSSnapshotOutcome
    func recoverPendingSignIn() async throws -> CodexiOSDeviceAuthStart?
    func beginSignIn() async throws -> CodexiOSDeviceAuthStart
    func pollSignIn(flowID: String) async throws -> CodexiOSPollResult
    func cancelSignIn() async throws
    func signOut() async throws
}

typealias CodexiOSOpenURLAction = @MainActor @Sendable (URL) async -> Bool
typealias CodexiOSCopyTextAction = @MainActor @Sendable (String) -> Void

private let codexiOSSharedUsageHistoryStore = CodexUsageHistoryStore()
private let codexiOSSharedLiveActivityManager = CodexiOSLiveActivitySerialManager(
    manager: CodexiOSLiveActivity()
)

@MainActor
@Observable
final class CodexiOSModel {
    private let service: any CodexiOSServiceProtocol
    private let defaults: UserDefaults
    private let openURLAction: CodexiOSOpenURLAction
    private let copyTextAction: CodexiOSCopyTextAction
    let historyStore: CodexUsageHistoryStore
    let liveActivityManager: any CodexiOSLiveActivityManaging
    private let backgroundRefreshScheduler: any CodexiOSBackgroundRefreshScheduling

    var hasCompletedOnboarding: Bool
    var previewModeEnabled: Bool
    var snapshot: CodexSnapshot?
    var usageHistory: [CodexUsageHistorySample] = []
    var isRefreshing = false
    var isSigningIn = false
    var isResetting = false
    var statusMessage = "Checking saved account."
    var errorMessage: String?
    var deviceCode: String?
    var verificationURL: URL?
    var flowID: String?
    var lastUpdatedAt: Date?
    var retryAvailableAt: Date?
    private(set) var hasCheckedLiveActivityAvailability = false
    private(set) var isLiveActivityAvailable = false
    private(set) var isLiveActivityRunning = false
    private(set) var isLiveActivityTransitioning = false
    private(set) var isLiveActivityStale = false
    private(set) var liveActivityID: String?
    private(set) var liveAccountState: CodexiOSLiveAccountState

    private var liveActivityGeneration = 0
    private var liveActivityOperationCount = 0
    private var accountOperationGeneration: UInt64 = 0
    private var startTask: Task<Void, Never>?
    private var retriesTransientAccountFailure = false
    private var isHandlingBackgroundRefresh = false

    init(
        service: any CodexiOSServiceProtocol = CodexiOSService(),
        defaults: UserDefaults = .standard,
        historyStore: CodexUsageHistoryStore = codexiOSSharedUsageHistoryStore,
        liveActivityManager: (any CodexiOSLiveActivityManaging)? = nil,
        liveActivityCoordinator: any CodexiOSLiveActivityManaging = codexiOSSharedLiveActivityManager,
        backgroundRefreshScheduler: any CodexiOSBackgroundRefreshScheduling = CodexiOSSystemBackgroundRefreshScheduler(),
        openURLAction: @escaping CodexiOSOpenURLAction = { url in
            await UIApplication.shared.open(url)
        },
        copyTextAction: @escaping CodexiOSCopyTextAction = { text in
            UIPasteboard.general.setItems(
                [["public.utf8-plain-text": text]],
                options: [
                    .localOnly: true,
                    .expirationDate: Date().addingTimeInterval(CodexiOSPendingAuthStore.ttl)
                ]
            )
        }
    ) {
        self.service = service
        self.defaults = defaults
        self.openURLAction = openURLAction
        self.copyTextAction = copyTextAction
        self.historyStore = historyStore
        self.liveActivityManager = if let liveActivityManager {
            CodexiOSLiveActivitySerialManager(manager: liveActivityManager)
        } else {
            liveActivityCoordinator
        }
        self.backgroundRefreshScheduler = backgroundRefreshScheduler
        let storedPreviewModeEnabled = defaults.bool(forKey: CodexiOSSettingsKeys.previewModeEnabled)
        hasCompletedOnboarding = defaults.bool(forKey: CodexiOSSettingsKeys.hasCompletedOnboarding)
        previewModeEnabled = storedPreviewModeEnabled
        liveAccountState = storedPreviewModeEnabled ? .signedOut : .checking
        if storedPreviewModeEnabled {
            applyPreviewSnapshot()
        }
    }

    var isSignedIn: Bool {
        liveAccountState == .signedIn
    }

    var isCheckingSavedAccount: Bool {
        liveAccountState == .checking
    }

    var canAutoRefresh: Bool {
        isSignedIn || (liveAccountState == .unavailable && retriesTransientAccountFailure)
    }

    var hasPendingSignIn: Bool {
        liveAccountState == .pendingSignIn && flowID != nil
    }

    func start() async {
        if let startTask {
            await startTask.value
            return
        }
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.performStart()
        }
        startTask = task
        await task.value
    }

    private func performStart() async {
        let accountGeneration = accountOperationGeneration
        let previewModeAtStart = previewModeEnabled
        await recoverLiveActivity()
        guard startupIsCurrent(
            accountGeneration: accountGeneration,
            previewModeAtStart: previewModeAtStart
        ) else { return }
        let restoredHistory = await historyStore.load()
        guard startupIsCurrent(
            accountGeneration: accountGeneration,
            previewModeAtStart: previewModeAtStart
        ) else { return }
        usageHistory = restoredHistory
        if previewModeEnabled {
            applyPreviewSnapshot()
            await updateLiveActivity(with: snapshot)
            return
        }
        do {
            let pending = try await service.recoverPendingSignIn()
            guard startupIsCurrent(
                accountGeneration: accountGeneration,
                previewModeAtStart: previewModeAtStart
            ) else { return }
            if let pending {
                applyPendingSignIn(pending, message: "Resuming ChatGPT sign-in.")
                await checkSignIn()
                return
            }
        } catch {
            guard startupIsCurrent(
                accountGeneration: accountGeneration,
                previewModeAtStart: previewModeAtStart
            ) else { return }
            if error as? CodexiOSError == .signInExpired {
                clearPendingSignIn()
                liveAccountState = .signedOut
                retriesTransientAccountFailure = false
                errorMessage = nil
                statusMessage = CodexiOSError.signInExpired.localizedDescription
            } else {
                liveAccountState = .unavailable
                retriesTransientAccountFailure = false
                applyError(message(for: error))
            }
            return
        }
        guard startupIsCurrent(
            accountGeneration: accountGeneration,
            previewModeAtStart: previewModeAtStart
        ) else { return }
        await refresh()
    }

    func refresh() async {
        guard isRefreshing == false else { return }
        guard previewModeEnabled == false else {
            applyPreviewSnapshot()
            await updateLiveActivity(with: snapshot)
            return
        }
        if let retryAvailableAt, retryAvailableAt > Date() {
            statusMessage = "Try again \(Self.relativeDescription(for: retryAvailableAt))."
            return
        }
        let generation = accountOperationGeneration
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            let outcome = try await service.fetchSnapshot()
            guard generation == accountOperationGeneration, previewModeEnabled == false else { return }
            await applySnapshotOutcome(outcome)
        } catch {
            guard generation == accountOperationGeneration, previewModeEnabled == false else { return }
            if liveAccountState == .checking {
                liveAccountState = .unavailable
                retriesTransientAccountFailure = true
            }
            applyError(message(for: error))
            await markLiveActivityStale()
        }
    }

    func beginSignIn() async {
        guard isSigningIn == false else { return }
        accountOperationGeneration &+= 1
        let generation = accountOperationGeneration
        retriesTransientAccountFailure = false
        isSigningIn = true
        errorMessage = nil
        retryAvailableAt = nil
        statusMessage = "Starting ChatGPT sign-in."
        defer { isSigningIn = false }

        do {
            let auth = try await service.beginSignIn()
            guard generation == accountOperationGeneration else { return }
            applyPendingSignIn(auth, message: "Opening Safari.")
            let didOpen = await openURLAction(auth.verificationURL)
            guard generation == accountOperationGeneration else { return }
            statusMessage = didOpen
                ? "Safari opened. Enter the device code to continue."
                : Self.manualSignInMessage
        } catch {
            guard generation == accountOperationGeneration else { return }
            clearPendingSignIn()
            liveAccountState = .signedOut
            applyError(message(for: error))
        }
    }

    func checkSignIn() async {
        guard let flowID else { return }
        guard isSigningIn == false else { return }
        let generation = accountOperationGeneration
        isSigningIn = true
        errorMessage = nil
        defer { isSigningIn = false }

        do {
            switch try await service.pollSignIn(flowID: flowID) {
            case .pending(let message):
                guard generation == accountOperationGeneration else { return }
                liveAccountState = .pendingSignIn
                retriesTransientAccountFailure = false
                statusMessage = message
            case .signedIn:
                guard generation == accountOperationGeneration else { return }
                liveAccountState = .signedIn
                retriesTransientAccountFailure = false
                statusMessage = "Signed in."
                clearPendingSignIn()
                completeOnboarding()
                await refresh()
            }
        } catch {
            guard generation == accountOperationGeneration else { return }
            if error as? CodexiOSError == .signInExpired {
                clearPendingSignIn()
                liveAccountState = .signedOut
                retriesTransientAccountFailure = false
                errorMessage = nil
                statusMessage = CodexiOSError.signInExpired.localizedDescription
            } else {
                liveAccountState = .pendingSignIn
                retriesTransientAccountFailure = false
                applyError(message(for: error))
            }
        }
    }

    func restartSignIn() async {
        await cancelSignIn()
        await beginSignIn()
    }

    func cancelSignIn() async {
        accountOperationGeneration &+= 1
        clearPendingSignIn()
        liveAccountState = .signedOut
        retriesTransientAccountFailure = false
        errorMessage = nil
        retryAvailableAt = nil
        statusMessage = "Sign-in cancelled."
        do {
            try await service.cancelSignIn()
        } catch {
            liveAccountState = .unavailable
            retriesTransientAccountFailure = false
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
        } else if refreshWhenActive, canAutoRefresh {
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
        let generation = accountOperationGeneration
        let didOpen = await openURLAction(verificationURL)
        guard generation == accountOperationGeneration,
              self.verificationURL == verificationURL else { return }
        statusMessage = didOpen
            ? "Safari opened. Enter the device code to continue."
            : Self.manualSignInMessage
    }

    func signOut() async {
        accountOperationGeneration &+= 1
        let generation = accountOperationGeneration
        invalidateLiveActivityOperations()
        backgroundRefreshScheduler.cancel()
        liveAccountState = .signedOut
        retriesTransientAccountFailure = false
        snapshot = nil
        lastUpdatedAt = nil
        clearPendingSignIn()
        await stopLiveActivity(announce: false)
        do {
            try await service.signOut()
            guard generation == accountOperationGeneration else { return }
            errorMessage = nil
            retryAvailableAt = nil
            statusMessage = "Signed out."
        } catch {
            guard generation == accountOperationGeneration else { return }
            liveAccountState = .unavailable
            retriesTransientAccountFailure = false
            applyError(message(for: error))
        }
    }

    func resetApp() async {
        guard isResetting == false else { return }
        let wasOnboarded = hasCompletedOnboarding
        isResetting = true
        defer { isResetting = false }
        accountOperationGeneration &+= 1
        invalidateLiveActivityOperations()
        backgroundRefreshScheduler.cancel()
        await stopLiveActivity(announce: false)

        var failures: [String] = []
        do { try await service.signOut() } catch { failures.append(message(for: error)) }
        do { try await historyStore.clear() } catch { failures.append(message(for: error)) }

        do {
            try CodexiOSAppResetter.resetLocalData(
                defaults: defaults,
                clearTokens: {},
                clearPendingAuth: {},
                clearHistory: {}
            )
        } catch {
            failures.append(message(for: error))
        }

        previewModeEnabled = false
        snapshot = nil
        usageHistory = []
        lastUpdatedAt = nil
        retryAvailableAt = nil
        clearPendingSignIn()

        if failures.isEmpty {
            hasCompletedOnboarding = false
            liveAccountState = .signedOut
            retriesTransientAccountFailure = false
            errorMessage = nil
            statusMessage = "Codexex was reset."
        } else {
            // Keep the current screen alive long enough to surface the failure.
            // Cleared defaults still make the next cold launch start cleanly.
            hasCompletedOnboarding = wasOnboarded
            liveAccountState = .unavailable
            retriesTransientAccountFailure = false
            applyError("Some local data could not be deleted. \(failures.joined(separator: " "))")
        }
    }

    func completeOnboarding() {
        guard hasCompletedOnboarding == false else { return }
        hasCompletedOnboarding = true
        defaults.set(true, forKey: CodexiOSSettingsKeys.hasCompletedOnboarding)
    }

    func enablePreviewMode() {
        accountOperationGeneration &+= 1
        let generation = accountOperationGeneration
        invalidateLiveActivityOperations()
        previewModeEnabled = true
        defaults.set(true, forKey: CodexiOSSettingsKeys.previewModeEnabled)
        completeOnboarding()
        applyPreviewSnapshot()
        statusMessage = "Preview mode is active."
        errorMessage = nil
        clearPendingSignIn()
        liveAccountState = .signedOut
        retriesTransientAccountFailure = false
        retryAvailableAt = nil
        Task { [weak self] in
            guard let self else { return }
            guard self.accountOperationGeneration == generation, self.previewModeEnabled else { return }
            try? await self.service.cancelSignIn()
            guard self.accountOperationGeneration == generation, self.previewModeEnabled else { return }
            await self.updateLiveActivity(with: self.snapshot)
        }
    }

    func disablePreviewMode() {
        guard previewModeEnabled else { return }
        accountOperationGeneration &+= 1
        let generation = accountOperationGeneration
        invalidateLiveActivityOperations()
        previewModeEnabled = false
        defaults.set(false, forKey: CodexiOSSettingsKeys.previewModeEnabled)
        snapshot = nil
        usageHistory = []
        lastUpdatedAt = nil
        liveAccountState = .signedOut
        retriesTransientAccountFailure = false
        retryAvailableAt = nil
        statusMessage = "Preview mode off."
        beginLiveActivityOperation()
        Task { [weak self] in
            guard let self else { return }
            defer { self.endLiveActivityOperation() }
            await self.stopLiveActivity(announce: false)
            guard self.accountOperationGeneration == generation,
                  self.previewModeEnabled == false else { return }
            let restoredHistory = await self.historyStore.load()
            guard self.accountOperationGeneration == generation,
                  self.previewModeEnabled == false else { return }
            self.usageHistory = restoredHistory
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
        retriesTransientAccountFailure = false
        retryAvailableAt = nil
    }

    private func applySnapshotOutcome(_ outcome: CodexiOSSnapshotOutcome) async {
        switch outcome {
        case .loaded(let snapshot):
            self.snapshot = snapshot
            lastUpdatedAt = snapshot.capturedAt
            errorMessage = nil
            retryAvailableAt = nil
            statusMessage = "Signed in."
            clearPendingSignIn()
            liveAccountState = .signedIn
            retriesTransientAccountFailure = false
            completeOnboarding()
            usageHistory = await historyStore.append(snapshot: snapshot)
            await updateLiveActivity(with: snapshot)
        case .signedOut:
            errorMessage = nil
            retryAvailableAt = nil
            statusMessage = "Sign in with ChatGPT to read your Codex quota."
            snapshot = nil
            lastUpdatedAt = nil
            liveAccountState = hasPendingSignIn ? .pendingSignIn : .signedOut
            retriesTransientAccountFailure = false
            if hasPendingSignIn == false {
                invalidateLiveActivityOperations()
                await stopLiveActivity(announce: false)
            }
        case .authExpired(let message):
            errorMessage = nil
            retryAvailableAt = nil
            statusMessage = message
            snapshot = nil
            lastUpdatedAt = nil
            clearPendingSignIn()
            liveAccountState = .authExpired
            retriesTransientAccountFailure = false
            invalidateLiveActivityOperations()
            await stopLiveActivity(announce: false)
        case .unavailable(let message, let hasStoredCredentials, let retry):
            errorMessage = message
            statusMessage = message
            retryAvailableAt = retry.retryAfter
            liveAccountState = hasStoredCredentials ? .unavailable : .signedOut
            retriesTransientAccountFailure = hasStoredCredentials && retry.isTransient
            if hasStoredCredentials { completeOnboarding() }
            await markLiveActivityStale()
        case .superseded:
            return
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
        backgroundRefreshScheduler.cancel()
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
            backgroundRefreshScheduler.cancel()
            return true
        }

        isHandlingBackgroundRefresh = true
        defer {
            isHandlingBackgroundRefresh = false
            if isLiveActivityRunning, previewModeEnabled == false {
                backgroundRefreshScheduler.schedule(cadence: liveActivityCadence)
            }
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
        let generation = liveActivityGeneration
        let state = await liveActivityManager.recover()
        guard generation == liveActivityGeneration else { return }
        applyLiveActivityState(state)
    }

    private func startupIsCurrent(
        accountGeneration: UInt64,
        previewModeAtStart: Bool
    ) -> Bool {
        accountGeneration == accountOperationGeneration
            && previewModeEnabled == previewModeAtStart
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
        guard isHandlingBackgroundRefresh == false,
              isLiveActivityRunning,
              previewModeEnabled == false else { return }
        backgroundRefreshScheduler.schedule(cadence: liveActivityCadence)
    }

    private func applyPendingSignIn(_ auth: CodexiOSDeviceAuthStart, message: String) {
        flowID = auth.flowID
        verificationURL = auth.verificationURL
        deviceCode = auth.userCode
        liveAccountState = .pendingSignIn
        retriesTransientAccountFailure = false
        retryAvailableAt = nil
        errorMessage = nil
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

    private static func relativeDescription(for date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private static let manualSignInMessage =
        "Could not open Safari. Copy the code, then open auth.openai.com/codex/device manually."
}
