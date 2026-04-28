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
        let store = CodexAppSettingsStore(defaults: makeDefaults())
        let snapshot = store.snapshot()

        XCTAssertTrue(snapshot.showSparkEnabled)
        XCTAssertTrue(snapshot.showHistoryChartEnabled)
        XCTAssertEqual(snapshot.defaultHistoryMode, .dailyPeaks)
        XCTAssertTrue(snapshot.showPaceConfidence)
        XCTAssertFalse(snapshot.hideIdleSecondaryLimits)
        XCTAssertEqual(snapshot.menuBarDisplayMode, .used)
        XCTAssertEqual(snapshot.resetDisplayStyle, .relative)
    }

    func testNewPopupSettingsPersist() {
        let store = CodexAppSettingsStore(defaults: makeDefaults())

        store.setShowSparkEnabled(false)
        store.setShowHistoryChartEnabled(false)
        store.setDefaultHistoryMode(.thisCycle)
        store.setShowPaceConfidence(false)
        store.setHideIdleSecondaryLimits(true)
        store.setMenuBarDisplayMode(.pace)
        store.setResetDisplayStyle(.absolute)

        let snapshot = store.snapshot()
        XCTAssertFalse(snapshot.showSparkEnabled)
        XCTAssertFalse(snapshot.showHistoryChartEnabled)
        XCTAssertEqual(snapshot.defaultHistoryMode, .thisCycle)
        XCTAssertFalse(snapshot.showPaceConfidence)
        XCTAssertTrue(snapshot.hideIdleSecondaryLimits)
        XCTAssertEqual(snapshot.menuBarDisplayMode, .pace)
        XCTAssertEqual(snapshot.resetDisplayStyle, .absolute)
    }

    func testSummarySnoozeSettingsPersistAndClear() {
        let store = CodexAppSettingsStore(defaults: makeDefaults())
        let expiresAt = Date(timeIntervalSince1970: 1_800_000_000)

        store.setSummarySnoozeFingerprint("watch|weekly|91")
        store.setSummarySnoozeExpiresAt(expiresAt)

        XCTAssertEqual(store.summarySnoozeFingerprint, "watch|weekly|91")
        XCTAssertEqual(store.summarySnoozeExpiresAt, expiresAt)

        store.clearSummarySnooze()

        XCTAssertNil(store.summarySnoozeFingerprint)
        XCTAssertNil(store.summarySnoozeExpiresAt)
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

    private func makeDefaults() -> UserDefaults {
        let suiteName = "CodexAppSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
