import XCTest
@testable import CodexMeterApp

final class CodexAppSettingsTests: XCTestCase {
    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: "codexex.showFiveHourInMenubar")
        UserDefaults.standard.removeObject(forKey: "codexex.showSparkEnabled")
        UserDefaults.standard.removeObject(forKey: "codexex.showHistoryChartEnabled")
        UserDefaults.standard.removeObject(forKey: "codexex.defaultHistoryMode")
        UserDefaults.standard.removeObject(forKey: "codexex.showPaceConfidence")
        UserDefaults.standard.removeObject(forKey: "codexex.hideIdleSecondaryLimits")
        UserDefaults.standard.removeObject(forKey: "codexex.menuBarDisplayMode")
        UserDefaults.standard.removeObject(forKey: "codexex.resetDisplayStyle")
        UserDefaults.standard.removeObject(forKey: "codexex.codexSessionsPath")
        UserDefaults.standard.removeObject(forKey: "codexex.codexSessionsBookmark")
        UserDefaults.standard.removeObject(forKey: "codexex.summarySnoozeFingerprint")
        UserDefaults.standard.removeObject(forKey: "codexex.summarySnoozeExpiresAt")
        UserDefaults.standard.removeObject(forKey: "codexex.quotaNotificationsEnabled")
        UserDefaults.standard.removeObject(forKey: "codexex.quotaNotificationFingerprints")
    }

    func testPopupSettingsDefaults() {
        let store = CodexAppSettingsStore(defaults: makeDefaults())
        let snapshot = store.snapshot()

        XCTAssertTrue(snapshot.autoRefreshEnabled)
        XCTAssertTrue(snapshot.showSparkEnabled)
        XCTAssertTrue(snapshot.showHistoryChartEnabled)
        XCTAssertFalse(snapshot.showFiveHourInMenubar)
        XCTAssertEqual(snapshot.defaultHistoryMode, .dailyPeaks)
        XCTAssertTrue(snapshot.showPaceConfidence)
        XCTAssertFalse(snapshot.hideIdleSecondaryLimits)
        XCTAssertEqual(snapshot.menuBarDisplayMode, .used)
        XCTAssertEqual(snapshot.resetDisplayStyle, .relative)
        XCTAssertNil(snapshot.codexSessionsPath)
        XCTAssertNil(snapshot.codexSessionsBookmark)
        XCTAssertFalse(snapshot.quotaNotificationsEnabled)
    }

    func testNewPopupSettingsPersist() {
        let defaults = makeDefaults()
        let store = CodexAppSettingsStore(defaults: defaults)

        store.setShowSparkEnabled(false)
        store.setShowHistoryChartEnabled(false)
        store.setShowFiveHourInMenubar(true)
        store.setDefaultHistoryMode(.monthly)
        store.setShowPaceConfidence(false)
        store.setHideIdleSecondaryLimits(true)
        store.setMenuBarDisplayMode(.pace)
        store.setResetDisplayStyle(.absolute)

        let snapshot = store.snapshot()
        XCTAssertFalse(snapshot.showSparkEnabled)
        XCTAssertFalse(snapshot.showHistoryChartEnabled)
        XCTAssertTrue(snapshot.showFiveHourInMenubar)
        XCTAssertEqual(snapshot.defaultHistoryMode, .monthly)
        XCTAssertFalse(snapshot.showPaceConfidence)
        XCTAssertTrue(snapshot.hideIdleSecondaryLimits)
        XCTAssertEqual(snapshot.menuBarDisplayMode, .pace)
        XCTAssertEqual(snapshot.resetDisplayStyle, .absolute)
        XCTAssertTrue(CodexAppSettingsStore(defaults: defaults).snapshot().showFiveHourInMenubar)
    }

    func testQuotaNotificationSettingsPersistAndClear() {
        let store = CodexAppSettingsStore(defaults: makeDefaults())

        store.setQuotaNotificationsEnabled(true)
        store.setQuotaNotificationReceipts(CodexQuotaNotificationReceipts(deliveredFingerprints: [
            .fiveHourPressure: "fiveHourPressure|1800007200|92"
        ]))

        XCTAssertTrue(store.snapshot().quotaNotificationsEnabled)
        XCTAssertEqual(
            store.quotaNotificationReceipts.deliveredFingerprints[.fiveHourPressure],
            "fiveHourPressure|1800007200|92"
        )

        store.setQuotaNotificationsEnabled(false)
        store.setQuotaNotificationReceipts(.empty)

        XCTAssertFalse(store.snapshot().quotaNotificationsEnabled)
        XCTAssertTrue(store.quotaNotificationReceipts.deliveredFingerprints.isEmpty)
    }

    func testCodexSessionsPathPersistsAndClears() {
        let store = CodexAppSettingsStore(defaults: makeDefaults())

        store.setCodexSessionsPath("/Users/me/.codex/sessions")
        store.setCodexSessionsBookmark(Data([1, 2, 3]))
        XCTAssertEqual(store.snapshot().codexSessionsPath, "/Users/me/.codex/sessions")
        XCTAssertEqual(store.snapshot().codexSessionsBookmark, Data([1, 2, 3]))

        store.setCodexSessionsPath(nil)
        store.setCodexSessionsBookmark(nil)
        XCTAssertNil(store.snapshot().codexSessionsPath)
        XCTAssertNil(store.snapshot().codexSessionsBookmark)
    }

    func testCodexSessionsFolderSelectionNormalizesCodexHome() {
        let store = CodexAppSettingsStore(defaults: makeDefaults())

        store.setCodexSessionsFolder(url: URL(fileURLWithPath: "/Users/me/.codex", isDirectory: true))

        XCTAssertEqual(store.snapshot().codexSessionsPath, "/Users/me/.codex/sessions")
    }

    func testCodexSessionsFolderSelectionKeepsSessionsFolder() {
        let store = CodexAppSettingsStore(defaults: makeDefaults())

        store.setCodexSessionsFolder(url: URL(fileURLWithPath: "/Users/me/.codex/sessions", isDirectory: true))

        XCTAssertEqual(store.snapshot().codexSessionsPath, "/Users/me/.codex/sessions")
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
        defaults.set(true, forKey: "codexex.showFiveHourInMenubar")

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
        XCTAssertNil(defaults.object(forKey: "codexex.showFiveHourInMenubar"))
        XCTAssertFalse(CodexAppSettingsStore(defaults: defaults).snapshot().showFiveHourInMenubar)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "CodexAppSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
