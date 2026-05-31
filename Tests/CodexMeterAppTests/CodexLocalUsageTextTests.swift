import XCTest
@testable import CodexMeterApp

final class CodexLocalUsageTextTests: XCTestCase {
    func testHeaderSummaryUsesTargetReferenceWording() {
        let text = CodexLocalUsageText.headerSummary(
            sessions: 0,
            projects: 0,
            users: 0
        )

        XCTAssertEqual(text, "0 sessions · 0 projects · 0 users")
    }
}
