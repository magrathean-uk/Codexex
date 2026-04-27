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
        UserDefaults.standard.removeObject(forKey: "codexex.menuBarDisplayMode")
        UserDefaults.standard.removeObject(forKey: "codexex.resetDisplayStyle")
        UserDefaults.standard.removeObject(forKey: "codexex.summarySnoozeFingerprint")
        UserDefaults.standard.removeObject(forKey: "codexex.summarySnoozeExpiresAt")
    }

    func testNewPopupSettingsDefaultOn() {
        XCTAssertTrue(CodexAppSettings.showSparkEnabled)
        XCTAssertTrue(CodexAppSettings.showHistoryChartEnabled)
        XCTAssertEqual(CodexAppSettings.defaultHistoryMode, .dailyPeaks)
        XCTAssertTrue(CodexAppSettings.showPaceConfidence)
        XCTAssertFalse(CodexAppSettings.hideIdleSecondaryLimits)
        XCTAssertEqual(CodexAppSettings.menuBarDisplayMode, .used)
        XCTAssertEqual(CodexAppSettings.resetDisplayStyle, .relative)
    }

    func testNewPopupSettingsPersist() {
        CodexAppSettings.showSparkEnabled = false
        CodexAppSettings.showHistoryChartEnabled = false
        CodexAppSettings.defaultHistoryMode = .thisCycle
        CodexAppSettings.showPaceConfidence = false
        CodexAppSettings.hideIdleSecondaryLimits = true
        CodexAppSettings.menuBarDisplayMode = .pace
        CodexAppSettings.resetDisplayStyle = .absolute

        XCTAssertFalse(CodexAppSettings.showSparkEnabled)
        XCTAssertFalse(CodexAppSettings.showHistoryChartEnabled)
        XCTAssertEqual(CodexAppSettings.defaultHistoryMode, .thisCycle)
        XCTAssertFalse(CodexAppSettings.showPaceConfidence)
        XCTAssertTrue(CodexAppSettings.hideIdleSecondaryLimits)
        XCTAssertEqual(CodexAppSettings.menuBarDisplayMode, .pace)
        XCTAssertEqual(CodexAppSettings.resetDisplayStyle, .absolute)
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

    func testResetLocalDataClearsSettingsAndApplicationSupport() throws {
        let suiteName = "CodexAppSettingsTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(true, forKey: "codexex.previewModeEnabled")
        defaults.set("pace", forKey: "codexex.menuBarDisplayMode")

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexexResetTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("history".utf8).write(to: directory.appendingPathComponent("usage-history.json"))

        CodexAppResetter.resetLocalData(
            defaults: defaults,
            applicationSupportURL: directory,
            bundleIdentifier: nil
        )

        XCTAssertNil(defaults.object(forKey: "codexex.previewModeEnabled"))
        XCTAssertNil(defaults.object(forKey: "codexex.menuBarDisplayMode"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
    }
}
