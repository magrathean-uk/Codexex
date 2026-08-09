import XCTest
@testable import Codexex

final class CodexiOSMatrixSpeedTests: XCTestCase {
    func testDownwardPullSlowsRainToHalfSpeed() {
        XCTAssertEqual(
            matrixSpeedMultiplier(from: 1, verticalTranslation: 240),
            0.5,
            accuracy: 0.0001
        )
    }

    func testUpwardPullRestoresMaximumSpeed() {
        XCTAssertEqual(
            matrixSpeedMultiplier(from: 0.5, verticalTranslation: -240),
            1,
            accuracy: 0.0001
        )
    }

    func testSpeedStaysWithinConfiguredRange() {
        XCTAssertEqual(matrixSpeedMultiplier(from: 1, verticalTranslation: 2_000), 0.5)
        XCTAssertEqual(matrixSpeedMultiplier(from: 0.5, verticalTranslation: -2_000), 1)
    }
}
