import XCTest
@testable import CodexMeterApp

final class CodexAppSettingsTests: XCTestCase {
    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: "codexex.showSparkEnabled")
        UserDefaults.standard.removeObject(forKey: "codexex.showHistoryChartEnabled")
        UserDefaults.standard.removeObject(forKey: "codexex.defaultHistoryMode")
        UserDefaults.standard.removeObject(forKey: "codexex.showPaceConfidence")
        UserDefaults.standard.removeObject(forKey: "codexex.hideIdleSecondaryLimits")
        UserDefaults.standard.removeObject(forKey: "codexex.summarySnoozeFingerprint")
        UserDefaults.standard.removeObject(forKey: "codexex.summarySnoozeExpiresAt")
    }

    func testNewPopupSettingsDefaultOn() {
        XCTAssertTrue(CodexAppSettings.showSparkEnabled)
        XCTAssertTrue(CodexAppSettings.showHistoryChartEnabled)
        XCTAssertEqual(CodexAppSettings.defaultHistoryMode, .dailyPeaks)
        XCTAssertTrue(CodexAppSettings.showPaceConfidence)
        XCTAssertFalse(CodexAppSettings.hideIdleSecondaryLimits)
    }

    func testNewPopupSettingsPersist() {
        CodexAppSettings.showSparkEnabled = false
        CodexAppSettings.showHistoryChartEnabled = false
        CodexAppSettings.defaultHistoryMode = .thisCycle
        CodexAppSettings.showPaceConfidence = false
        CodexAppSettings.hideIdleSecondaryLimits = true

        XCTAssertFalse(CodexAppSettings.showSparkEnabled)
        XCTAssertFalse(CodexAppSettings.showHistoryChartEnabled)
        XCTAssertEqual(CodexAppSettings.defaultHistoryMode, .thisCycle)
        XCTAssertFalse(CodexAppSettings.showPaceConfidence)
        XCTAssertTrue(CodexAppSettings.hideIdleSecondaryLimits)
    }

    func testSummarySnoozeSettingsPersistAndClear() {
        let expiresAt = Date(timeIntervalSince1970: 1_800_000_000)

        CodexAppSettings.summarySnoozeFingerprint = "watch|weekly|91"
        CodexAppSettings.summarySnoozeExpiresAt = expiresAt

        XCTAssertEqual(CodexAppSettings.summarySnoozeFingerprint, "watch|weekly|91")
        XCTAssertEqual(CodexAppSettings.summarySnoozeExpiresAt, expiresAt)

        CodexAppSettings.clearSummarySnooze()

        XCTAssertNil(CodexAppSettings.summarySnoozeFingerprint)
        XCTAssertNil(CodexAppSettings.summarySnoozeExpiresAt)
    }
}
