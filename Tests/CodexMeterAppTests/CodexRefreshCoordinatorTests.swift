import XCTest
@testable import CodexMeterApp

@MainActor
final class CodexRefreshCoordinatorTests: XCTestCase {
    func testInvalidationCancelsOldTokens() {
        let coordinator = CodexRefreshCoordinator()
        let token = coordinator.token()

        XCTAssertTrue(coordinator.isCurrent(token))

        coordinator.invalidate()

        XCTAssertFalse(coordinator.isCurrent(token))
        XCTAssertTrue(coordinator.isCurrent(coordinator.token()))
    }

    func testInvalidateCanCancelHelperWork() {
        let coordinator = CodexRefreshCoordinator()
        var cancelCount = 0

        coordinator.invalidate {
            cancelCount += 1
        }

        XCTAssertEqual(cancelCount, 1)
    }
}
