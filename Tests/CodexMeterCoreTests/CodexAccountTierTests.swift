import XCTest
@testable import CodexMeterCore

final class CodexAccountTierTests: XCTestCase {
    func testPlusIsDisplayed() {
        let account = CodexAccount(authType: "chatGPT", email: "plus@example.com", planType: " plus ")

        XCTAssertEqual(account.tier, .plus)
        XCTAssertEqual(account.displayPlan, "PLUS")
    }

    func testProIsDisplayed() {
        let account = CodexAccount(authType: "chatGPT", email: "pro@example.com", planType: "Pro")

        XCTAssertEqual(account.tier, .pro)
        XCTAssertEqual(account.displayPlan, "PRO")
    }

    func testBusinessVariantsAreDisplayed() {
        for planType in ["Business", "Team", "self_serve_business_usage_based", "Enterprise"] {
            let account = CodexAccount(authType: "chatGPT", email: nil, planType: planType)

            XCTAssertEqual(account.tier, .business, planType)
        }
    }

    func testSnapshotShowsReportedFiveHourWindowRegardlessOfPlan() {
        let limit = CodexLimit(
            id: "codex",
            rawLimitName: nil,
            bucket: .codex,
            primary: CodexQuotaWindow(usedPercent: 20, windowDurationMinutes: 300, resetsAt: nil),
            secondary: nil
        )

        for planType in ["PLUS", "PRO", "Business", "unknown"] {
            let snapshot = CodexSnapshot(
                capturedAt: .distantPast,
                executablePath: "test",
                account: CodexAccount(authType: "chatGPT", email: nil, planType: planType),
                limits: [limit]
            )
            XCTAssertTrue(snapshot.showsFiveHourLimit, planType)
        }
    }

    func testSnapshotDoesNotInventFiveHourWindowWhenOnlyWeeklyIsReported() {
        let weekly = CodexLimit(
            id: "codex",
            rawLimitName: nil,
            bucket: .codex,
            primary: CodexQuotaWindow(usedPercent: 20, windowDurationMinutes: 10_080, resetsAt: nil),
            secondary: nil
        )

        for planType in ["PLUS", "PRO", "Business", "unknown"] {
            let snapshot = CodexSnapshot(
                capturedAt: .distantPast,
                executablePath: "test",
                account: CodexAccount(authType: "chatGPT", email: nil, planType: planType),
                limits: [weekly]
            )
            XCTAssertFalse(snapshot.showsFiveHourLimit, planType)
        }
    }

    func testTaggedSingleWindowIsNotMislabelledAsAnotherDuration() {
        let fiveHourOnly = CodexLimit(
            id: "codex",
            rawLimitName: nil,
            bucket: .codex,
            primary: CodexQuotaWindow(usedPercent: 20, windowDurationMinutes: 300, resetsAt: nil),
            secondary: nil
        )
        let weeklyOnly = CodexLimit(
            id: "codex",
            rawLimitName: nil,
            bucket: .codex,
            primary: CodexQuotaWindow(usedPercent: 40, windowDurationMinutes: 10_080, resetsAt: nil),
            secondary: nil
        )

        XCTAssertNotNil(fiveHourOnly.fiveHourWindow)
        XCTAssertNil(fiveHourOnly.weeklyWindow)
        XCTAssertNil(weeklyOnly.fiveHourWindow)
        XCTAssertNotNil(weeklyOnly.weeklyWindow)
    }
}
