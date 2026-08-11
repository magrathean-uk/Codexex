import XCTest
import CodexMeterCore
@testable import Codexex

final class CodexiOSBackgroundRefreshTests: XCTestCase {
    func testEarliestBackgroundRefreshHonorsSystemFriendlyMinimum() {
        let now = Date(timeIntervalSince1970: 1_000)

        XCTAssertEqual(
            CodexiOSBackgroundRefreshPolicy.earliestBeginDate(now: now, cadence: 300),
            now.addingTimeInterval(15 * 60)
        )
    }

    func testEarliestBackgroundRefreshPreservesLongerCadence() {
        let now = Date(timeIntervalSince1970: 1_000)

        XCTAssertEqual(
            CodexiOSBackgroundRefreshPolicy.earliestBeginDate(now: now, cadence: 3_600),
            now.addingTimeInterval(3_600)
        )
    }

    func testLiveActivityStaysFreshPastEarliestBackgroundRefresh() {
        let now = Date(timeIntervalSince1970: 1_000)
        let cadence: TimeInterval = 300

        XCTAssertGreaterThan(
            CodexLiveActivityPresentation.staleDate(capturedAt: now, cadence: cadence),
            CodexiOSBackgroundRefreshPolicy.earliestBeginDate(now: now, cadence: cadence)
        )
    }
}
