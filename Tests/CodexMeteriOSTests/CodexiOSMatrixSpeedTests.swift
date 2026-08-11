import XCTest
import CodexMeterCore
@testable import Codexex

final class CodexiOSMatrixSpeedTests: XCTestCase {
    func testDefaultRainSpeedMatchesGIFReference() {
        XCTAssertEqual(matrixDefaultSpeedMultiplier, 1, accuracy: 0.0001)
    }

    func testRainUsesAdaptive120FPSAndReferenceSpeed() {
        XCTAssertEqual(matrixDisplayFPS, 120, accuracy: 0.0001)
        XCTAssertEqual(matrixRenderInterval, 1.0 / 120.0, accuracy: 0.0001)
        XCTAssertEqual(matrixMotionSamplingInterval, 1.0 / 30.0, accuracy: 0.0001)
        XCTAssertEqual(matrixGIFDropInterval, 0.15, accuracy: 0.0001)
    }

    func testHorizontalPullControlsDensity() {
        XCTAssertEqual(matrixDensity(from: 0.5, horizontalTranslation: -260), 0, accuracy: 0.0001)
        XCTAssertEqual(matrixDensity(from: 0.5, horizontalTranslation: 260), 1, accuracy: 0.0001)
    }

    func testHorizontalGyroTiltIsInvertedForWaterMotion() {
        XCTAssertEqual(matrixHorizontalTilt(for: -0.5), 0.775, accuracy: 0.0001)
        XCTAssertEqual(matrixHorizontalTilt(for: 0.5), -0.775, accuracy: 0.0001)
    }

    func testWaveIsMorePronounced() {
        XCTAssertEqual(matrixWaveAmplitude, 6.5, accuracy: 0.0001)
    }

    func testMaximumDensityUsesEverySafeColumnAndNoTrackGaps() {
        XCTAssertEqual(matrixColumnCount(maximum: 22, density: 1), 22)
        XCTAssertEqual(matrixTrackGapRows(trackLength: 12, density: 1), 0)
    }

    func testLegalLinksUseCodexexPages() {
        XCTAssertEqual(CodexiOSLegalLinks.privacyPolicy.absoluteString, "https://codexex.eu/privacy/")
        XCTAssertEqual(CodexiOSLegalLinks.termsOfService.absoluteString, "https://codexex.eu/terms/")
    }

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

    func testQuotaDisplaySwitchesBetweenRemainingAndUsed() {
        let window = CodexQuotaWindow(usedPercent: 91, windowDurationMinutes: 10_080, resetsAt: nil)

        XCTAssertEqual(CodexiOSQuotaDisplay.percent(for: window, showUsedQuota: false), 9)
        XCTAssertEqual(CodexiOSQuotaDisplay.percentText(for: window, showUsedQuota: false), "9%")
        XCTAssertEqual(CodexiOSQuotaDisplay.label(showUsedQuota: false), "left")

        XCTAssertEqual(CodexiOSQuotaDisplay.percent(for: window, showUsedQuota: true), 91)
        XCTAssertEqual(CodexiOSQuotaDisplay.percentText(for: window, showUsedQuota: true), "91%")
        XCTAssertEqual(CodexiOSQuotaDisplay.label(showUsedQuota: true), "used")
    }
}
