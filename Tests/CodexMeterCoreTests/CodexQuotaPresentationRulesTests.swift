import Foundation
import XCTest
@testable import CodexMeterCore

final class CodexQuotaPresentationRulesTests: XCTestCase {
    func testOrdersPrimaryBeforeOther() {
        let ordered = CodexQuotaPresentationRules.orderedLimits([
            makeLimit(id: "research", bucket: .other),
            makeLimit(id: "codex", bucket: .codex)
        ])

        XCTAssertEqual(ordered.map(\.bucket), [.codex, .other])
    }

    func testCreditsVisibilityIsShared() {
        XCTAssertNil(CodexQuotaPresentationRules.visibleCredits(nil))
        XCTAssertNil(CodexQuotaPresentationRules.visibleCredits(.init(hasCredits: false, unlimited: false, balance: nil)))
        XCTAssertNil(CodexQuotaPresentationRules.visibleCredits(.init(hasCredits: true, unlimited: false, balance: "  ")))

        XCTAssertEqual(
            CodexQuotaPresentationRules.visibleCredits(.init(hasCredits: true, unlimited: false, balance: "12.345678901234"))?.displayText,
            "12.35"
        )
    }

    func testReportedZeroAndUnlimitedCreditsStayVisible() {
        for balance in ["0", "0.00", "-0.00"] {
            XCTAssertEqual(
                CodexQuotaPresentationRules.visibleCredits(.init(hasCredits: false, unlimited: false, balance: balance))?.displayText,
                "0.00"
            )
        }
        XCTAssertEqual(
            CodexQuotaPresentationRules.visibleCredits(.init(hasCredits: true, unlimited: true, balance: nil))?.displayText,
            "Unlimited"
        )
    }

    func testMissingCreditBalanceIsNotPresentedAsZero() {
        XCTAssertEqual(
            CodexQuotaPresentationRules.visibleCredits(.init(hasCredits: true, unlimited: false, balance: nil))?.displayText,
            "Unavailable"
        )
        XCTAssertEqual(
            CodexQuotaPresentationRules.visibleCredits(.init(hasCredits: true, unlimited: false, balance: "-12.50"))?.displayText,
            "-12.50"
        )
    }

    func testResetTextModesAreShared() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let resetAt = now.addingTimeInterval(90 * 60)

        XCTAssertEqual(
            CodexQuotaPresentationRules.resetText(style: .relative, now: now, resetAt: resetAt),
            CodexFormatting.relativeResetText(now: now, resetAt: resetAt)
        )
        XCTAssertTrue(
            CodexQuotaPresentationRules.resetText(
                style: .absolute(prefix: "resets at"),
                now: now,
                resetAt: resetAt
            )
            .hasPrefix("resets at")
        )
    }

    private func makeLimit(
        id: String,
        bucket: CodexLimitBucket,
        fiveHour: Double = 12,
        weekly: Double = 34,
        credits: CodexCredits? = nil
    ) -> CodexLimit {
        CodexLimit(
            id: id,
            rawLimitName: id,
            bucket: bucket,
            primary: CodexQuotaWindow(
                usedPercent: fiveHour,
                windowDurationMinutes: 300,
                resetsAt: nil
            ),
            secondary: CodexQuotaWindow(
                usedPercent: weekly,
                windowDurationMinutes: 10_080,
                resetsAt: nil
            ),
            credits: credits
        )
    }
}
