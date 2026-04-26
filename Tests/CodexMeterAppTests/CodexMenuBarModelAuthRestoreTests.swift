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
        let model = CodexMenuBarModel(service: FailingService())

        await model.refreshNow()

        XCTAssertFalse(model.hasResolvedAuthState)
        XCTAssertFalse(model.isSignedIn)
        XCTAssertEqual(model.lastError, "network down")
        XCTAssertEqual(model.authStatusMessage, "Ready.")
    }

    func testSnoozeCurrentSummaryNotifiesObservers() async {
        UserDefaults.standard.removeObject(forKey: "codexex.summarySnoozeFingerprint")
        UserDefaults.standard.removeObject(forKey: "codexex.summarySnoozeExpiresAt")
        let model = CodexMenuBarModel(service: SnapshotService(snapshot: makeRiskSnapshot()))
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
        let model = CodexMenuBarModel(service: SnapshotService(snapshot: makeRiskSnapshot()))
        await model.refreshNow()

        let report = model.diagnosticsReport(now: Date(timeIntervalSince1970: 1_800_000_100))

        XCTAssertFalse(report.contains("user@example.com"))
        XCTAssertTrue(report.contains("Codexex Diagnostics"))
        XCTAssertTrue(report.contains("History samples:"))
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
}

private struct FailingService: CodexServiceClient {
    func fetchSnapshotResponse() async throws -> CodexServiceSnapshotResponse {
        throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "network down"])
    }

    func beginChatGPTSignIn() async throws -> CodexDeviceAuthStart {
        fatalError("unused")
    }

    func completeChatGPTSignIn(flowID: String) async throws -> CodexDeviceAuthPollResult {
        fatalError("unused")
    }

    func signOut() async throws {
        fatalError("unused")
    }
}

private struct SnapshotService: CodexServiceClient {
    let snapshot: CodexSnapshot

    func fetchSnapshotResponse() async throws -> CodexServiceSnapshotResponse {
        CodexServiceSnapshotResponse(authMode: .chatGPT, snapshot: snapshot, errorMessage: nil)
    }

    func beginChatGPTSignIn() async throws -> CodexDeviceAuthStart {
        fatalError("unused")
    }

    func completeChatGPTSignIn(flowID: String) async throws -> CodexDeviceAuthPollResult {
        fatalError("unused")
    }

    func signOut() async throws {
        fatalError("unused")
    }
}
