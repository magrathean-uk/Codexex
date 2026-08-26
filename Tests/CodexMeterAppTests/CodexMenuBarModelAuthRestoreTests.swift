import XCTest
import Observation
@testable import CodexMeterApp
@testable import CodexMeterCore

@MainActor
final class CodexMenuBarModelAuthRestoreTests: XCTestCase {
    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: "codexex.previewModeEnabled")
    }

    func testRefreshFailureDoesNotResolveAuthToSignedOut() async {
        let model = testModel(service: FailingService())

        await model.refreshNow()

        XCTAssertFalse(model.hasResolvedAuthState)
        XCTAssertFalse(model.isSignedIn)
        XCTAssertEqual(model.lastError, "network down")
        XCTAssertEqual(model.authStatusMessage, "Ready.")
    }

    func testSignedOutResponseIsAccountStateInsteadOfRefreshError() async {
        let model = testModel(service: SignedOutService())

        await model.refreshNow()

        XCTAssertTrue(model.hasResolvedAuthState)
        XCTAssertFalse(model.isSignedIn)
        XCTAssertNil(model.lastError)
        XCTAssertEqual(model.statusCardTitle, "Sign in required")
        XCTAssertEqual(model.statusCardMessage, "Not signed in. Use the button below.")
        XCTAssertEqual(model.designStateBadgeKind, .signedOut)
    }

    func testPreviewModeWithSampleQuotaStartsOnSafeSummary() {
        let model = testModel(service: FailingService())

        model.enablePreviewMode()

        XCTAssertNotNil(model.snapshot)
        XCTAssertFalse(model.shouldShowStatusCard)
        XCTAssertEqual(model.popupSummary?.title, "Safe")
    }

    func testSnoozeCurrentSummaryNotifiesObservers() async {
        UserDefaults.standard.removeObject(forKey: "codexex.summarySnoozeFingerprint")
        UserDefaults.standard.removeObject(forKey: "codexex.summarySnoozeExpiresAt")
        let model = testModel(service: SnapshotService(snapshot: makeRiskSnapshot()))
        await model.refreshNow()
        XCTAssertFalse(model.isCurrentSummarySnoozed)

        let changed = expectation(description: "snooze state changed")
        withObservationTracking {
            _ = model.isCurrentSummarySnoozed
        } onChange: {
            changed.fulfill()
        }

        model.snoozeCurrentSummary()

        await fulfillment(of: [changed], timeout: 1)
        XCTAssertTrue(model.isCurrentSummarySnoozed)
    }

    func testDiagnosticsReportRedactsEmail() async {
        let model = testModel(service: SnapshotService(snapshot: makeRiskSnapshot()))
        await model.refreshNow()

        let report = model.diagnosticsReport(now: Date(timeIntervalSince1970: 1_800_000_100))

        XCTAssertFalse(report.contains("user@example.com"))
        XCTAssertTrue(report.contains("Codexex Diagnostics"))
        XCTAssertTrue(report.contains("History samples:"))
    }

    func testDiagnosticsReportIncludesAllSessionLocalUsage() async {
        let model = CodexMenuBarModel(
            service: SnapshotService(snapshot: makeRiskSnapshot()),
            localUsageProvider: StaticLocalUsageProvider(summary: makeLocalUsageSummary())
        )

        await model.refreshNow()

        let report = model.diagnosticsReport(now: Date(timeIntervalSince1970: 1_800_000_100))

        XCTAssertTrue(report.contains("Local sessions: 1"))
        XCTAssertTrue(report.contains("Local indexed tokens: 42000"))
        XCTAssertTrue(report.contains("Local coverage: All 1 files"))
        XCTAssertTrue(report.contains("Local top project: Codexex"))
        XCTAssertTrue(report.contains("Local attribution: high"))
        XCTAssertTrue(report.contains("Local context: 42%"))
    }

    func testRefreshAppliesLocalCodexUsageSummary() async {
        let model = CodexMenuBarModel(
            service: SnapshotService(snapshot: makeRiskSnapshot()),
            localUsageProvider: StaticLocalUsageProvider(summary: makeLocalUsageSummary())
        )

        await model.refreshNow()
        try? await waitUntil(timeout: 1) { model.localUsageSummary != nil }

        XCTAssertEqual(model.localUsageSummary?.today.totalTokens, 42_000)
        XCTAssertEqual(model.localUsageSummary?.latestProjectName, "Codexex")
        XCTAssertEqual(model.localUsageSummary?.wasteSignals.first?.kind, .modelOverkill)
    }

    func testRefreshFailureStillAppliesLocalCodexUsageSummary() async {
        let model = CodexMenuBarModel(
            service: FailingService(),
            localUsageProvider: StaticLocalUsageProvider(summary: makeLocalUsageSummary())
        )

        await model.refreshNow()
        try? await waitUntil(timeout: 1) { model.localUsageSummary != nil }

        XCTAssertEqual(model.lastError, "network down")
        XCTAssertEqual(model.localUsageSummary?.total.totalTokens, 42_000)
        XCTAssertEqual(model.localUsageSummary?.sessionAutopsies.first?.totalSharePercent, 100)
    }

    func testSlowLocalUsageDoesNotBlockRemoteSnapshot() async throws {
        let provider = SuspendedLocalUsageProvider()
        let model = CodexMenuBarModel(
            service: SnapshotService(snapshot: makeRiskSnapshot()),
            localUsageProvider: provider
        )

        await model.refreshNow()

        XCTAssertNotNil(model.snapshot)
        XCTAssertFalse(model.isRefreshing)
        XCTAssertNil(model.localUsageSummary)
        try await waitUntil(timeout: 1) { await provider.hasStarted }

        await provider.finish(with: .available(makeLocalUsageSummary()))
        try await waitUntil(timeout: 1) { model.localUsageSummary?.total.totalTokens == 42_000 }
    }

    func testIncompleteLocalIndexingStopsAfterBoundedBurstAndResumesOnNextRefresh() async throws {
        let coverage = CodexLocalUsageCoverage(
            indexedFileCount: 1,
            selectedFileCount: 512,
            discoveredFileCount: 512,
            bytesRead: 64 * 1_024 * 1_024
        )
        let provider = CountingIncompleteLocalUsageProvider(
            summary: makeLocalUsageSummary(coverage: coverage)
        )
        let clock = CodexMenuBarClock(
            now: { Date(timeIntervalSince1970: 1_800_000_000) },
            sleep: { _ in await Task.yield() }
        )
        let model = CodexMenuBarModel(
            service: SnapshotService(snapshot: makeRiskSnapshot()),
            localUsageProvider: provider,
            clock: clock
        )

        await model.refreshNow()
        try await waitUntil(timeout: 1) { await provider.fetchCount == 8 }
        for _ in 0..<10 { await Task.yield() }

        let firstBurstCount = await provider.fetchCount
        XCTAssertEqual(firstBurstCount, 8)
        XCTAssertEqual(model.localUsageSummary?.coverage.label, "Indexing 1 of latest 512 files")

        await model.refreshNow(manual: true)
        try await waitUntil(timeout: 1) { await provider.fetchCount == 16 }
        for _ in 0..<10 { await Task.yield() }

        let secondBurstCount = await provider.fetchCount
        XCTAssertEqual(secondBurstCount, 16)
    }

    func testStructuredTransientFailurePreservesLastGoodSnapshot() async {
        let expected = makeRiskSnapshot()
        let service = SequenceSnapshotService(responses: [
            CodexServiceSnapshotResponse(authMode: .chatGPT, snapshot: expected, errorMessage: nil),
            CodexServiceSnapshotResponse(authMode: .chatGPT, snapshot: nil, errorMessage: "server unavailable 503")
        ])
        let model = testModel(service: service)

        await model.refreshNow()
        await model.refreshNow(manual: true)

        XCTAssertEqual(model.snapshot, expected)
        XCTAssertEqual(model.lastUpdatedAt, expected.capturedAt)
        XCTAssertEqual(model.lastError, "server unavailable 503")
        XCTAssertTrue(model.isSignedIn)
    }

    func testTrueSignedOutResponseClearsLastGoodSnapshot() async {
        let expected = makeRiskSnapshot()
        let service = SequenceSnapshotService(responses: [
            CodexServiceSnapshotResponse(authMode: .chatGPT, snapshot: expected, errorMessage: nil),
            CodexServiceSnapshotResponse(authMode: nil, snapshot: nil, errorMessage: "Not signed in.")
        ])
        let model = testModel(service: service)

        await model.refreshNow()
        await model.refreshNow(manual: true)

        XCTAssertNil(model.snapshot)
        XCTAssertNil(model.lastUpdatedAt)
        XCTAssertNil(model.lastError)
        XCTAssertFalse(model.isSignedIn)
    }

    func testSignedOutQuotaRefreshDoesNotDiscardActiveDeviceCode() async throws {
        let service = PendingAuthSignedOutSnapshotService()
        let model = testModel(
            service: service,
            deviceAuthPollingConfiguration: CodexDeviceAuthPollingConfiguration(
                intervalSeconds: 10,
                timeoutSeconds: 20,
                requestTimeoutSeconds: 1
            )
        )

        model.startChatGPTSignIn()
        try await waitUntil(timeout: 1) { model.authDeviceCode == "CODE-123" }

        await model.refreshNow(manual: true)

        XCTAssertEqual(model.authDeviceCode, "CODE-123")
        XCTAssertEqual(model.authFlowID, "flow-123456789012")
        XCTAssertFalse(model.isSignedIn)
        XCTAssertNil(model.lastError)
    }

    func testSignOutBusyStateBlocksRefreshAndDuplicateSignOut() async throws {
        let service = SuspendedSignOutService(snapshot: makeRiskSnapshot())
        let model = testModel(service: service)
        await model.refreshNow()
        let fetchCountBeforeSignOut = await service.fetchCount

        model.signOut()
        model.signOut()
        try await waitUntil(timeout: 1) { await service.signOutCount == 1 }
        XCTAssertTrue(model.isSigningOut)

        await model.refreshNow(manual: true)
        let fetchCountWhileSigningOut = await service.fetchCount
        XCTAssertEqual(fetchCountWhileSigningOut, fetchCountBeforeSignOut)

        await service.finishSignOut()
        try await waitUntil(timeout: 1) { model.isSigningOut == false }
        XCTAssertFalse(model.isSignedIn)
        XCTAssertNil(model.snapshot)
    }

    func testAppResetClearsHelperAuthenticationBeforeLocalReset() async {
        let service = ResetSignOutService()
        let model = testModel(service: service)

        let failure = await model.clearHelperStateForAppReset()
        let signOutCount = await service.signOutCount

        XCTAssertNil(failure)
        XCTAssertEqual(signOutCount, 1)
    }

    func testAppResetSurfacesHelperSignOutFailure() async {
        let service = ResetSignOutService(errorMessage: "helper unavailable")
        let model = testModel(service: service)

        let failure = await model.clearHelperStateForAppReset()
        let signOutCount = await service.signOutCount

        XCTAssertEqual(signOutCount, 1)
        XCTAssertTrue(failure?.contains("helper unavailable") == true)
    }

    func testRefreshDeliversQuotaNotificationOncePerFingerprint() async throws {
        let suiteName = "CodexMenuBarModelNotifications.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settingsStore = CodexAppSettingsStore(defaults: defaults)
        settingsStore.setQuotaNotificationsEnabled(true)
        let delivery = RecordingQuotaNotificationDelivery()
        let historyURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("codexex-notification-history-\(UUID().uuidString).json")

        let model = CodexMenuBarModel(
            service: SnapshotService(snapshot: makeHighPressureSnapshot()),
            localUsageProvider: StaticLocalUsageProvider(summary: nil),
            settingsStore: settingsStore,
            historyRepository: CodexHistoryRepository(store: CodexUsageHistoryStore(fileURL: historyURL)),
            notificationDelivery: delivery
        )

        await model.refreshNow()
        await model.refreshNow()

        let delivered = await delivery.deliveredNotifications()
        XCTAssertEqual(delivered.map(\.kind), [.fiveHourPressure])
        XCTAssertEqual(
            settingsStore.quotaNotificationReceipts.deliveredFingerprints[.fiveHourPressure],
            "fiveHourPressure|1800007200"
        )
    }

    func testNotificationEnableReflectsDeniedSystemPermission() async throws {
        let suiteName = "CodexNotificationPermission.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = CodexAppSettingsStore(defaults: defaults)
        let model = CodexMenuBarModel(
            service: FailingService(),
            localUsageProvider: StaticLocalUsageProvider(summary: nil),
            settingsStore: store,
            notificationDelivery: PermissionNotificationDelivery(state: .denied)
        )

        model.setQuotaNotificationsEnabled(true)
        try await waitUntil(timeout: 1) { model.quotaNotificationAuthorizationState == .denied }

        XCTAssertFalse(model.quotaNotificationsEnabled)
        XCTAssertFalse(store.snapshot().quotaNotificationsEnabled)
        XCTAssertTrue(model.quotaNotificationStatusMessage?.contains("Blocked by macOS") == true)
    }

    func testRepeatedSignInStartCreatesOnlyOneFlow() async throws {
        let service = DeviceAuthService(snapshot: makeRiskSnapshot(), pollResults: [.pending])
        let model = testModel(
            service: service,
            deviceAuthPollingConfiguration: CodexDeviceAuthPollingConfiguration(
                intervalSeconds: 10,
                timeoutSeconds: 10,
                requestTimeoutSeconds: 1
            )
        )

        model.startChatGPTSignIn()
        model.startChatGPTSignIn()

        try await waitUntil(timeout: 1) { model.authDeviceCode != nil }
        let beginCount = await service.beginInvocationCount()
        XCTAssertEqual(beginCount, 1)
        XCTAssertFalse(model.canStartChatGPTSignIn)
    }

    func testDeviceAuthAutoPollingRefreshesSnapshotAfterApproval() async throws {
        let service = DeviceAuthService(
            snapshot: makeRiskSnapshot(),
            pollResults: [.pending, .signedIn]
        )
        let model = testModel(
            service: service,
            deviceAuthPollingConfiguration: CodexDeviceAuthPollingConfiguration(
                intervalSeconds: 0.02,
                timeoutSeconds: 1,
                requestTimeoutSeconds: 0.5
            )
        )

        model.startChatGPTSignIn()

        try await waitUntil(timeout: 1) { model.authDeviceCode == "CODE-123" }
        try await waitUntil(timeout: 1) { model.isSignedIn && model.snapshot != nil }

        let beginCount = await service.beginCount
        let fetchCount = await service.fetchCount
        let pollCount = await service.pollCount
        XCTAssertEqual(beginCount, 1)
        XCTAssertEqual(fetchCount, 1)
        XCTAssertGreaterThanOrEqual(pollCount, 2)
        XCTAssertNil(model.authDeviceCode)
    }

    func testStartingDeviceAuthOpensVerificationURL() async throws {
        let service = DeviceAuthService(
            snapshot: makeRiskSnapshot(),
            pollResults: [.pending]
        )
        var openedURLs: [URL] = []
        let model = CodexMenuBarModel(
            service: service,
            localUsageProvider: StaticLocalUsageProvider(summary: nil),
            deviceAuthPollingConfiguration: CodexDeviceAuthPollingConfiguration(
                intervalSeconds: 10,
                timeoutSeconds: 10,
                requestTimeoutSeconds: 0.5
            ),
            openURL: { url in
                openedURLs.append(url)
                return true
            }
        )

        model.startChatGPTSignIn()

        try await waitUntil(timeout: 1) { openedURLs == [URL(string: "https://chatgpt.com/activate")!] }
        XCTAssertEqual(model.authDeviceCode, "CODE-123")
    }

    func testClearingDeviceCodeStopsAutoPolling() async throws {
        let service = DeviceAuthService(
            snapshot: makeRiskSnapshot(),
            pollResults: [.pending, .pending, .pending]
        )
        let model = testModel(
            service: service,
            deviceAuthPollingConfiguration: CodexDeviceAuthPollingConfiguration(
                intervalSeconds: 0.02,
                timeoutSeconds: 1,
                requestTimeoutSeconds: 0.5
            )
        )

        model.startChatGPTSignIn()
        try await waitUntil(timeout: 1) { model.authDeviceCode == "CODE-123" }
        try await waitUntil(timeout: 1) { await service.pollCount > 0 }

        model.clearAuthCode()
        try await waitUntil(timeout: 1) { model.authDeviceCode == nil }
        let pollCountAfterClear = await service.pollCount
        try await Task.sleep(for: .seconds(0.08))
        let finalPollCount = await service.pollCount
        let cancelledFlowIDs = await service.cancelledFlowIDs

        XCTAssertEqual(finalPollCount, pollCountAfterClear)
        XCTAssertEqual(cancelledFlowIDs, ["flow-123"])
        XCTAssertNil(model.authDeviceCode)
        XCTAssertFalse(model.isSignedIn)
    }

    func testCancelDeviceCodeFailurePreservesCodeAndAllowsRetry() async throws {
        let service = DeviceAuthService(
            snapshot: makeRiskSnapshot(),
            pollResults: [.pending],
            cancelErrorMessage: "helper unavailable"
        )
        let model = testModel(
            service: service,
            deviceAuthPollingConfiguration: CodexDeviceAuthPollingConfiguration(
                intervalSeconds: 10,
                timeoutSeconds: 10,
                requestTimeoutSeconds: 1
            )
        )
        model.startChatGPTSignIn()
        try await waitUntil(timeout: 1) { model.authDeviceCode == "CODE-123" }

        model.cancelPendingChatGPTSignIn()
        try await waitUntil(timeout: 1) {
            model.isCancellingPendingSignIn == false && model.lastError != nil
        }

        XCTAssertEqual(model.authDeviceCode, "CODE-123")
        XCTAssertTrue(model.lastError?.contains("Could not cancel sign-in") == true)
        XCTAssertTrue(model.canCheckPendingChatGPTSignIn)
        let cancelCount = await service.cancelInvocationCount()
        XCTAssertEqual(cancelCount, 1)
    }

    func testRepeatedCancelDeviceCodeSendsOneHelperRequest() async throws {
        let service = DeviceAuthService(snapshot: makeRiskSnapshot(), pollResults: [.pending])
        let model = testModel(
            service: service,
            deviceAuthPollingConfiguration: CodexDeviceAuthPollingConfiguration(
                intervalSeconds: 10,
                timeoutSeconds: 10,
                requestTimeoutSeconds: 1
            )
        )
        model.startChatGPTSignIn()
        try await waitUntil(timeout: 1) { model.authDeviceCode == "CODE-123" }

        model.cancelPendingChatGPTSignIn()
        model.cancelPendingChatGPTSignIn()
        try await waitUntil(timeout: 1) { model.authDeviceCode == nil }

        let cancelCount = await service.cancelInvocationCount()
        XCTAssertEqual(cancelCount, 1)
    }

    private func testModel(
        service: any CodexServiceClient,
        deviceAuthPollingConfiguration: CodexDeviceAuthPollingConfiguration = .production
    ) -> CodexMenuBarModel {
        CodexMenuBarModel(
            service: service,
            localUsageProvider: StaticLocalUsageProvider(summary: nil),
            deviceAuthPollingConfiguration: deviceAuthPollingConfiguration,
            openURL: { _ in true }
        )
    }

    private func makeRiskSnapshot() -> CodexSnapshot {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        return CodexSnapshot(
            capturedAt: now,
            executablePath: "/Applications/Codexex.app",
            account: CodexAccount(
                authType: "chatGPT",
                email: "user@example.com",
                planType: "PRO"
            ),
            limits: [
                CodexLimit(
                    id: "codex",
                    rawLimitName: "Codex",
                    bucket: .codex,
                    primary: CodexQuotaWindow(
                        usedPercent: 64,
                        windowDurationMinutes: 300,
                        resetsAt: now.addingTimeInterval(3 * 60 * 60)
                    ),
                    secondary: CodexQuotaWindow(
                        usedPercent: 64,
                        windowDurationMinutes: 10_080,
                        resetsAt: now.addingTimeInterval(2 * 24 * 60 * 60)
                    )
                )
            ]
        )
    }

    private func makeHighPressureSnapshot() -> CodexSnapshot {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        return CodexSnapshot(
            capturedAt: now,
            executablePath: "/Applications/Codexex.app",
            account: CodexAccount(
                authType: "chatGPT",
                email: "user@example.com",
                planType: "PRO"
            ),
            limits: [
                CodexLimit(
                    id: "codex",
                    rawLimitName: "Codex",
                    bucket: .codex,
                    primary: CodexQuotaWindow(
                        usedPercent: 92,
                        windowDurationMinutes: 300,
                        resetsAt: now.addingTimeInterval(2 * 60 * 60)
                    ),
                    secondary: CodexQuotaWindow(
                        usedPercent: 44,
                        windowDurationMinutes: 10_080,
                        resetsAt: now.addingTimeInterval(2 * 24 * 60 * 60)
                    )
                )
            ]
        )
    }

    private func waitUntil(
        timeout: TimeInterval,
        condition: @escaping @MainActor () async -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if await condition() {
                return
            }
            try await Task.sleep(for: .seconds(0.01))
        }
        XCTFail("Timed out waiting for condition")
    }
}

private actor RecordingQuotaNotificationDelivery: CodexQuotaNotificationDelivering {
    private var delivered: [CodexQuotaNotification] = []

    func deliver(_ notifications: [CodexQuotaNotification]) async -> [CodexQuotaNotificationDeliveryResult] {
        delivered.append(contentsOf: notifications)
        return notifications.map {
            CodexQuotaNotificationDeliveryResult(notification: $0, delivered: true)
        }
    }

    func deliveredNotifications() -> [CodexQuotaNotification] {
        delivered
    }
}

private struct PermissionNotificationDelivery: CodexQuotaNotificationDelivering {
    let state: CodexNotificationAuthorizationState

    func authorizationState(requestIfNeeded: Bool) async -> CodexNotificationAuthorizationState {
        state
    }

    func deliver(_ notifications: [CodexQuotaNotification]) async -> [CodexQuotaNotificationDeliveryResult] {
        notifications.map { CodexQuotaNotificationDeliveryResult(notification: $0, delivered: false) }
    }
}

private struct StaticLocalUsageProvider: CodexLocalUsageProviding {
    let summary: CodexLocalUsageSummary?

    func fetchLocalUsageSummary() async -> CodexLocalUsageFetchResult {
        summary.map(CodexLocalUsageFetchResult.available)
            ?? .unavailable("Local usage unavailable in test.")
    }
}

private actor SuspendedLocalUsageProvider: CodexLocalUsageProviding {
    private var continuation: CheckedContinuation<CodexLocalUsageFetchResult, Never>?
    private(set) var hasStarted = false

    func fetchLocalUsageSummary() async -> CodexLocalUsageFetchResult {
        hasStarted = true
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func finish(with result: CodexLocalUsageFetchResult) {
        continuation?.resume(returning: result)
        continuation = nil
    }
}

private actor CountingIncompleteLocalUsageProvider: CodexLocalUsageProviding {
    let summary: CodexLocalUsageSummary
    private(set) var fetchCount = 0

    init(summary: CodexLocalUsageSummary) {
        self.summary = summary
    }

    func fetchLocalUsageSummary() async -> CodexLocalUsageFetchResult {
        fetchCount += 1
        return .available(summary)
    }
}

private func makeLocalUsageSummary(
    coverage: CodexLocalUsageCoverage = CodexLocalUsageCoverage(
        indexedFileCount: 1,
        selectedFileCount: 1,
        discoveredFileCount: 1,
        bytesRead: 0
    )
) -> CodexLocalUsageSummary {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let tokens = CodexLocalTokenUsage(
        inputTokens: 40_000,
        cachedInputTokens: 34_000,
        outputTokens: 2_000,
        reasoningOutputTokens: 500,
        totalTokens: 42_000
    )
    let period = CodexLocalUsagePeriodSummary(entryCount: 1, tokens: tokens)
    return CodexLocalUsageSummary(
        capturedAt: now,
        dataPath: "/Users/me/.codex/sessions",
        total: period,
        today: period,
        week: period,
        sessions: [
            CodexLocalSessionSummary(
                id: "s1",
                projectPath: "/Users/me/Codexex",
                latestModel: "gpt-5.1-codex-max",
                startedAt: now.addingTimeInterval(-300),
                lastActivityAt: now,
                entryCount: 1,
                commandCount: 4,
                tokens: tokens
            )
        ],
        projects: [
            CodexLocalProjectSummary(
                id: "/Users/me/Codexex",
                displayName: "Codexex",
                path: "/Users/me/Codexex",
                latestModel: "gpt-5.1-codex-max",
                lastActivityAt: now,
                sessionCount: 1,
                commandCount: 4,
                tokens: tokens
            )
        ],
        modelSummaries: [
            CodexLocalModelSummary(model: "gpt-5.1-codex-max", entryCount: 1, tokens: tokens)
        ],
        fiveHourBlocks: [
            CodexLocalUsageBlock(
                id: "block",
                startsAt: now.addingTimeInterval(-600),
                endsAt: now.addingTimeInterval(5 * 60 * 60),
                tokens: tokens,
                entryCount: 1
            )
        ],
        wasteSignals: [
            CodexLocalWasteSignal(
                id: "model-overkill",
                kind: .modelOverkill,
                title: "Model overkill",
                detail: "Max spent a lot for a small output."
            )
        ],
        configReport: CodexLocalConfigReport(severity: .ok, issues: []),
        latestProjectName: "Codexex",
        latestModel: "gpt-5.1-codex-max",
        contextWindowPercent: 42,
        sessionAutopsies: [
            CodexLocalSessionAutopsy(
                id: "s1",
                projectName: "Codexex",
                model: "gpt-5.1-codex-max",
                tokens: tokens,
                totalSharePercent: 100,
                commandCount: 4,
                entryCount: 1,
                lastActivityAt: now
            )
        ],
        attributionConfidence: CodexLocalAttributionConfidence(
            level: .high,
            title: "High confidence",
            detail: "All local token rows include project, model, and session data."
        ),
        coverage: coverage
    )
}

private struct FailingService: CodexServiceClient {
    func fetchSnapshotResponse() async throws -> CodexServiceSnapshotResponse {
        throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "network down"])
    }

    func beginChatGPTSignIn() async throws -> CodexDeviceAuthStart {
        throw UnusedTestServiceCallError()
    }

    func completeChatGPTSignIn(flowID: String) async throws -> CodexDeviceAuthPollResult {
        throw UnusedTestServiceCallError()
    }

    func signOut() async throws {
        throw UnusedTestServiceCallError()
    }
}

private struct SignedOutService: CodexServiceClient {
    func fetchSnapshotResponse() async throws -> CodexServiceSnapshotResponse {
        CodexServiceSnapshotResponse(
            authMode: nil,
            snapshot: nil,
            errorMessage: "Not signed in. Use the button below."
        )
    }

    func beginChatGPTSignIn() async throws -> CodexDeviceAuthStart {
        throw UnusedTestServiceCallError()
    }

    func completeChatGPTSignIn(flowID: String) async throws -> CodexDeviceAuthPollResult {
        throw UnusedTestServiceCallError()
    }

    func signOut() async throws {
        throw UnusedTestServiceCallError()
    }
}

private struct SnapshotService: CodexServiceClient {
    let snapshot: CodexSnapshot

    func fetchSnapshotResponse() async throws -> CodexServiceSnapshotResponse {
        CodexServiceSnapshotResponse(authMode: .chatGPT, snapshot: snapshot, errorMessage: nil)
    }

    func beginChatGPTSignIn() async throws -> CodexDeviceAuthStart {
        throw UnusedTestServiceCallError()
    }

    func completeChatGPTSignIn(flowID: String) async throws -> CodexDeviceAuthPollResult {
        throw UnusedTestServiceCallError()
    }

    func signOut() async throws {
        throw UnusedTestServiceCallError()
    }
}

private actor SequenceSnapshotService: CodexServiceClient {
    private var responses: [CodexServiceSnapshotResponse]

    init(responses: [CodexServiceSnapshotResponse]) {
        self.responses = responses
    }

    func fetchSnapshotResponse() async throws -> CodexServiceSnapshotResponse {
        guard responses.isEmpty == false else { throw UnusedTestServiceCallError() }
        return responses.removeFirst()
    }

    func beginChatGPTSignIn() async throws -> CodexDeviceAuthStart { throw UnusedTestServiceCallError() }
    func completeChatGPTSignIn(flowID: String) async throws -> CodexDeviceAuthPollResult { throw UnusedTestServiceCallError() }
    func signOut() async throws { throw UnusedTestServiceCallError() }
}

private struct UnusedTestServiceCallError: Error {}

private actor PendingAuthSignedOutSnapshotService: CodexServiceClient {
    func fetchSnapshotResponse() async throws -> CodexServiceSnapshotResponse {
        CodexServiceSnapshotResponse(authMode: nil, snapshot: nil, errorMessage: "Not signed in.")
    }

    func beginChatGPTSignIn() async throws -> CodexDeviceAuthStart {
        CodexDeviceAuthStart(
            flowID: "flow-123456789012",
            verificationURL: URL(string: "https://chatgpt.com/activate")!,
            userCode: "CODE-123"
        )
    }

    func completeChatGPTSignIn(flowID: String) async throws -> CodexDeviceAuthPollResult {
        CodexDeviceAuthPollResult(status: .pending)
    }

    func signOut() async throws {}
}

private actor SuspendedSignOutService: CodexServiceClient {
    private let snapshot: CodexSnapshot
    private var signOutContinuation: CheckedContinuation<Void, Never>?
    private(set) var fetchCount = 0
    private(set) var signOutCount = 0

    init(snapshot: CodexSnapshot) {
        self.snapshot = snapshot
    }

    func fetchSnapshotResponse() async throws -> CodexServiceSnapshotResponse {
        fetchCount += 1
        return CodexServiceSnapshotResponse(authMode: .chatGPT, snapshot: snapshot, errorMessage: nil)
    }

    func beginChatGPTSignIn() async throws -> CodexDeviceAuthStart { throw UnusedTestServiceCallError() }
    func completeChatGPTSignIn(flowID: String) async throws -> CodexDeviceAuthPollResult { throw UnusedTestServiceCallError() }

    func signOut() async throws {
        signOutCount += 1
        await withCheckedContinuation { continuation in
            signOutContinuation = continuation
        }
    }

    func finishSignOut() {
        signOutContinuation?.resume()
        signOutContinuation = nil
    }
}

private actor ResetSignOutService: CodexServiceClient {
    private let errorMessage: String?
    private(set) var signOutCount = 0

    init(errorMessage: String? = nil) {
        self.errorMessage = errorMessage
    }

    func fetchSnapshotResponse() async throws -> CodexServiceSnapshotResponse {
        throw UnusedTestServiceCallError()
    }

    func beginChatGPTSignIn() async throws -> CodexDeviceAuthStart {
        throw UnusedTestServiceCallError()
    }

    func completeChatGPTSignIn(flowID: String) async throws -> CodexDeviceAuthPollResult {
        throw UnusedTestServiceCallError()
    }

    func signOut() async throws {
        signOutCount += 1
        if let errorMessage {
            throw NSError(
                domain: "ResetSignOutService",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: errorMessage]
            )
        }
    }
}

private actor DeviceAuthService: CodexServiceClient {
    private let snapshot: CodexSnapshot
    private var pollResults: [CodexDeviceAuthPollStatus]
    private let cancelErrorMessage: String?
    private(set) var beginCount = 0
    private(set) var pollCount = 0
    private(set) var fetchCount = 0
    private(set) var cancelledFlowIDs: [String] = []

    init(
        snapshot: CodexSnapshot,
        pollResults: [CodexDeviceAuthPollStatus],
        cancelErrorMessage: String? = nil
    ) {
        self.snapshot = snapshot
        self.pollResults = pollResults
        self.cancelErrorMessage = cancelErrorMessage
    }

    func fetchSnapshotResponse() async throws -> CodexServiceSnapshotResponse {
        fetchCount += 1
        return CodexServiceSnapshotResponse(authMode: .chatGPT, snapshot: snapshot, errorMessage: nil)
    }

    func beginChatGPTSignIn() async throws -> CodexDeviceAuthStart {
        beginCount += 1
        return CodexDeviceAuthStart(
            flowID: "flow-123",
            verificationURL: URL(string: "https://chatgpt.com/activate")!,
            userCode: "CODE-123"
        )
    }

    func completeChatGPTSignIn(flowID: String) async throws -> CodexDeviceAuthPollResult {
        pollCount += 1
        let status = pollResults.isEmpty ? CodexDeviceAuthPollStatus.pending : pollResults.removeFirst()
        return CodexDeviceAuthPollResult(status: status)
    }

    func cancelChatGPTSignIn(flowID: String) async throws {
        cancelledFlowIDs.append(flowID)
        if let cancelErrorMessage {
            throw NSError(
                domain: "DeviceAuthService",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: cancelErrorMessage]
            )
        }
    }

    func signOut() async throws {}

    func beginInvocationCount() -> Int {
        beginCount
    }

    func cancelInvocationCount() -> Int {
        cancelledFlowIDs.count
    }
}
