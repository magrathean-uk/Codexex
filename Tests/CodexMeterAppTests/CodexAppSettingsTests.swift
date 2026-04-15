import XCTest
@testable import CodexMeterApp

final class CodexAppSettingsTests: XCTestCase {
    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: "codexex.showSparkEnabled")
        UserDefaults.standard.removeObject(forKey: "codexex.showHistoryChartEnabled")
    }

    func testNewPopupSettingsDefaultOn() {
        XCTAssertTrue(CodexAppSettings.showSparkEnabled)
        XCTAssertTrue(CodexAppSettings.showHistoryChartEnabled)
    }

    func testNewPopupSettingsPersist() {
        CodexAppSettings.showSparkEnabled = false
        CodexAppSettings.showHistoryChartEnabled = false

        XCTAssertFalse(CodexAppSettings.showSparkEnabled)
        XCTAssertFalse(CodexAppSettings.showHistoryChartEnabled)
    }
}
