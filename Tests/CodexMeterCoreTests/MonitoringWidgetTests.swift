import Foundation
import Testing
@testable import CodexMeterCore

@Suite struct MonitoringWidgetTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func cachedValuesExcludeIdentityAndCredentials() throws {
        let quota = CodexSnapshot(capturedAt: now, executablePath: "/private/example/session",
            account: .init(authType: "chatGPT", email: "private@example.invalid", planType: "pro"),
            limits: [.init(id: "codex", rawLimitName: nil, bucket: .codex,
                          primary: .init(usedPercent: 12, windowDurationMinutes: 300, resetsAt: now.addingTimeInterval(60)),
                          secondary: .init(usedPercent: 32, windowDurationMinutes: 10080, resetsAt: now.addingTimeInterval(3600)), credits: nil)])
        let value = MonitoringWidgetSnapshot(snapshot: quota, apiRemainingUSD: Decimal(string: "2.37"), apiUpdatedAt: now)
        let data = try JSONEncoder().encode(value)
        let text = try #require(String(data: data, encoding: .utf8))
        #expect(!text.contains("private@example"))
        #expect(!text.contains("/private/example"))
        #expect(!text.contains("account"))
        #expect(value.weeklyPercentLeft == 68)
        #expect(value.fiveHourPercentLeft == 88)
        #expect(try JSONDecoder().decode(MonitoringWidgetSnapshot.self, from: data) == value)
        #expect(!value.quotaIsStale(at: now))
        #expect(value.quotaIsStale(at: now.addingTimeInterval(60)))
    }

    @Test func missingBalanceNeverBecomesZeroAndEmptyWalletIsValid() {
        #expect(MonitoringWidgetSnapshot.empty.apiRemainingUSD == nil)
        let zero = MonitoringWidgetSnapshot(apiRemainingUSD: 0, apiUpdatedAt: now)
        #expect(zero.isValid)
        #expect(zero.apiRemainingUSD == 0)
        #expect(!zero.apiIsStale(at: now.addingTimeInterval(1799)))
        #expect(zero.apiIsStale(at: now.addingTimeInterval(1800)))
        #expect(MonitoringWidgetSnapshot(apiRemainingUSD: -1, apiUpdatedAt: now).isValid == false)
        #expect(MonitoringWidgetSnapshot(apiRemainingUSD: .nan, apiUpdatedAt: now).isValid == false)
        #expect(MonitoringWidgetSnapshot(apiRemainingUSD: 5).isValid == false)
    }

    @Test func atomicStoreClearsOldValuesAndRejectsUnknownSchema() throws {
        let directory = URL.temporaryDirectory.appendingPathComponent("widget-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = MonitoringWidgetStore(directory: directory)
        #expect(store.load() == nil)
        #expect(try store.save(.init(apiRemainingUSD: 5, apiUpdatedAt: now)))
        #expect(store.load()?.apiRemainingUSD == 5)
        #expect(try store.clear())
        #expect(store.load() == .empty)
        let file = directory.appendingPathComponent("monitoring-widget.json")
        var object = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        object["version"] = 999
        try JSONSerialization.data(withJSONObject: object).write(to: file)
        #expect(store.load() == nil)
        try Data("not json".utf8).write(to: file)
        #expect(store.load() == nil)
        #expect(try MonitoringWidgetStore(directory: nil).save(.empty) == false)
    }
}
