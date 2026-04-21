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
}
