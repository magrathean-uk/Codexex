import Foundation
import XCTest
@testable import CodexMeterApp
@testable import CodexMeterCore

final class CodexSummarySnoozeTests: XCTestCase {
    func testSnoozeMatchesSameAlertBeforeExpiryEvenWhenNumbersChange() {
        let summary = makeSummary(projected: "91% by reset")
        let laterSummary = makeSummary(projected: "96% by reset")
        let fingerprint = CodexSummarySnooze.fingerprint(for: summary)
        let expiresAt = Date(timeIntervalSince1970: 1_800_000_000)
        let now = expiresAt.addingTimeInterval(-60)

        XCTAssertTrue(CodexSummarySnooze.isSnoozed(
            summary: summary,
            storedFingerprint: fingerprint,
            expiresAt: expiresAt,
            now: now
        ))
        XCTAssertTrue(CodexSummarySnooze.isSnoozed(
            summary: laterSummary,
            storedFingerprint: fingerprint,
            expiresAt: expiresAt,
            now: now
        ))
    }

    func testSnoozeExpiresAtReset() {
        let summary = makeSummary(projected: "91% by reset")
        let fingerprint = CodexSummarySnooze.fingerprint(for: summary)
        let expiresAt = Date(timeIntervalSince1970: 1_800_000_000)

        XCTAssertFalse(CodexSummarySnooze.isSnoozed(
            summary: summary,
            storedFingerprint: fingerprint,
            expiresAt: expiresAt,
            now: expiresAt
        ))
    }

    func testExpiryUsesTwentyFourHours() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let fiveHourReset = now.addingTimeInterval(90 * 60)
        let weeklyReset = now.addingTimeInterval(3 * 24 * 60 * 60)
        let snapshot = CodexSnapshot(
            capturedAt: now,
            executablePath: "/Applications/Codexex.app",
            account: CodexAccount(authType: "chatGPT", email: "user@example.com", planType: "PRO"),
            limits: [
                CodexLimit(
                    id: "codex",
                    rawLimitName: "Codex",
                    bucket: .codex,
                    primary: CodexQuotaWindow(usedPercent: 48, windowDurationMinutes: 300, resetsAt: fiveHourReset),
                    secondary: CodexQuotaWindow(usedPercent: 91, windowDurationMinutes: 10_080, resetsAt: weeklyReset)
                )
            ]
        )

        XCTAssertEqual(CodexSummarySnooze.expiryDate(snapshot: snapshot, now: now), now.addingTimeInterval(24 * 60 * 60))
    }

    private func makeSummary(projected: String) -> PopupSummaryPresentation {
        PopupSummaryPresentation(
            severity: .watch,
            title: "Watch",
            message: "Usage is rising faster than planned.",
            supportingLabel: "Current weekly",
            supportingValue: "48% used",
            supportingDetail: projected,
            action: nil
        )
    }
}
