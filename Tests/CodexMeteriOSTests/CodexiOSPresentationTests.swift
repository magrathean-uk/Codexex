import XCTest
import CodexMeterCore
@testable import Codexex

final class CodexiOSPresentationTests: XCTestCase {
    func testHiddenFiveHourAlwaysUsesWeeklyHeadline() throws {
        let limit = makeLimit(fiveHourUsed: 96, weeklyUsed: 28)

        let headline = try XCTUnwrap(
            CodexiOSQuotaPresentation.headline(for: limit, showFiveHour: false)
        )

        XCTAssertEqual(headline.title, "Weekly")
        XCTAssertEqual(headline.window.usedPercent, 28)
    }

    func testVisibleFiveHourCanDriveHeadline() throws {
        let limit = makeLimit(fiveHourUsed: 96, weeklyUsed: 28)

        let headline = try XCTUnwrap(
            CodexiOSQuotaPresentation.headline(for: limit, showFiveHour: true)
        )

        XCTAssertEqual(headline.title, "5H")
        XCTAssertEqual(headline.window.usedPercent, 96)
    }

    func testHeadlinePercentageIsNotRepeatedInMatchingRow() throws {
        let limit = makeLimit(fiveHourUsed: 96, weeklyUsed: 28)
        let headline = try XCTUnwrap(
            CodexiOSQuotaPresentation.headline(for: limit, showFiveHour: true)
        )
        let fiveHour = try XCTUnwrap(CodexiOSQuotaPresentation.fiveHourWindow(for: limit))
        let weekly = try XCTUnwrap(CodexiOSQuotaPresentation.weeklyWindow(for: limit))

        XCTAssertFalse(
            CodexiOSQuotaPresentation.shouldShowRowPercentage(for: fiveHour, headline: headline)
        )
        XCTAssertTrue(
            CodexiOSQuotaPresentation.shouldShowRowPercentage(for: weekly, headline: headline)
        )
    }

    func testMissingWeeklyDoesNotLeakHiddenFiveHour() {
        let limit = CodexLimit(
            id: "codex",
            rawLimitName: "Codex",
            bucket: .codex,
            primary: CodexQuotaWindow(
                usedPercent: 80,
                windowDurationMinutes: 300,
                resetsAt: nil
            ),
            secondary: nil
        )

        XCTAssertNil(CodexiOSQuotaPresentation.weeklyWindow(for: limit))
        XCTAssertNil(CodexiOSQuotaPresentation.headline(for: limit, showFiveHour: false))
        XCTAssertEqual(
            CodexiOSQuotaPresentation.headline(for: limit, showFiveHour: true)?.title,
            "5H"
        )
    }

    private func makeLimit(fiveHourUsed: Double, weeklyUsed: Double) -> CodexLimit {
        CodexLimit(
            id: "codex",
            rawLimitName: "Codex",
            bucket: .codex,
            primary: CodexQuotaWindow(
                usedPercent: fiveHourUsed,
                windowDurationMinutes: 300,
                resetsAt: nil
            ),
            secondary: CodexQuotaWindow(
                usedPercent: weeklyUsed,
                windowDurationMinutes: 10_080,
                resetsAt: nil
            )
        )
    }
}
