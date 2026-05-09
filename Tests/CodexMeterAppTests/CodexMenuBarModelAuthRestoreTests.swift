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

    func testRefreshAppliesLocalCodexUsageSummary() async {
        let model = CodexMenuBarModel(
            service: SnapshotService(snapshot: makeRiskSnapshot()),
            localUsageProvider: StaticLocalUsageProvider(summary: makeLocalUsageSummary())
        )

        await model.refreshNow()

        XCTAssertEqual(model.localUsageSummary?.today.totalTokens, 42_000)
        XCTAssertEqual(model.localUsageSummary?.latestProjectName, "Codexex")
        XCTAssertEqual(model.localUsageSummary?.wasteSignals.first?.kind, .modelOverkill)
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
        let pollCountAfterClear = await service.pollCount
        try await Task.sleep(for: .seconds(0.08))
        let finalPollCount = await service.pollCount

        XCTAssertEqual(finalPollCount, pollCountAfterClear)
        XCTAssertNil(model.authDeviceCode)
        XCTAssertFalse(model.isSignedIn)
    }

    private func testModel(
        service: any CodexServiceClient,
        deviceAuthPollingConfiguration: CodexDeviceAuthPollingConfiguration = .production
    ) -> CodexMenuBarModel {
        CodexMenuBarModel(
            service: service,
            localUsageProvider: StaticLocalUsageProvider(summary: nil),
            deviceAuthPollingConfiguration: deviceAuthPollingConfiguration
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

private struct StaticLocalUsageProvider: CodexLocalUsageProviding {
    let summary: CodexLocalUsageSummary?

    func fetchLocalUsageSummary() async -> CodexLocalUsageSummary? {
        summary
    }
}

private func makeLocalUsageSummary() -> CodexLocalUsageSummary {
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
        contextWindowPercent: 42
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

private struct UnusedTestServiceCallError: Error {}

private actor DeviceAuthService: CodexServiceClient {
    private let snapshot: CodexSnapshot
    private var pollResults: [CodexDeviceAuthPollStatus]
    private(set) var beginCount = 0
    private(set) var pollCount = 0
    private(set) var fetchCount = 0

    init(snapshot: CodexSnapshot, pollResults: [CodexDeviceAuthPollStatus]) {
        self.snapshot = snapshot
        self.pollResults = pollResults
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

    func signOut() async throws {}
}
