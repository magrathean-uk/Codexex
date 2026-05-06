import XCTest
@testable import CodexMeterApp

final class CodexRefreshBackoffTests: XCTestCase {
    func testRateLimitedFailuresBackOffAndSuccessClears() {
        var backoff = CodexRefreshBackoff(maximumDelay: 600)
        let now = Date(timeIntervalSince1970: 100)

        XCTAssertTrue(backoff.allowsAutomaticRefresh(now: now))
        backoff.recordFailure(.rateLimited, now: now)
        XCTAssertFalse(backoff.allowsAutomaticRefresh(now: now.addingTimeInterval(5)))
        XCTAssertTrue(backoff.allowsAutomaticRefresh(now: now.addingTimeInterval(30)))

        backoff.recordSuccess()
        XCTAssertTrue(backoff.allowsAutomaticRefresh(now: now.addingTimeInterval(6)))
    }

    func testOtherFailuresDoNotThrottleRefreshLoop() {
        var backoff = CodexRefreshBackoff()
        let now = Date(timeIntervalSince1970: 100)
        backoff.recordFailure(.other, now: now)
        XCTAssertTrue(backoff.allowsAutomaticRefresh(now: now))
    }
}
