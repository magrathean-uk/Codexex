import XCTest
import CodexMeterCore
@testable import CodexMeterApp

final class CodexUsageHistoryStoreCachedTests: XCTestCase {
    func testAppendSkipsDuplicateWithoutGrowingHistory() async throws {
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        let store = CodexUsageHistoryStore(fileURL: fileURL)
        let now = Date(timeIntervalSince1970: 1_000_000)
        let snapshot = makeSnapshot(now: now, used: 10)

        let first = await store.append(snapshot: snapshot, now: now)
        let second = await store.append(snapshot: snapshot, now: now.addingTimeInterval(30))

        XCTAssertEqual(first.count, 1)
        XCTAssertEqual(second.count, 1)
    }

    func testLoadUsesCacheAfterFirstDecode() async throws {
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        let store = CodexUsageHistoryStore(fileURL: fileURL)
        let now = Date(timeIntervalSince1970: 1_000_000)
        _ = await store.append(snapshot: makeSnapshot(now: now, used: 10), now: now)

        let first = await store.load(now: now)
        try Data("not json".utf8).write(to: fileURL, options: [.atomic])
        let second = await store.load(now: now)

        XCTAssertEqual(first, second)
    }

    private func makeSnapshot(now: Date, used: Double) -> CodexSnapshot {
        CodexSnapshot(
            capturedAt: now,
            executablePath: "test",
            account: CodexAccount(authType: "chatGPT", email: nil, planType: nil),
            limits: [
                CodexLimit(
                    id: "codex",
                    rawLimitName: nil,
                    bucket: .codex,
                    primary: CodexQuotaWindow(
                        usedPercent: used,
                        windowDurationMinutes: 300,
                        resetsAt: now.addingTimeInterval(3600)
                    ),
                    secondary: CodexQuotaWindow(
                        usedPercent: used,
                        windowDurationMinutes: 10_080,
                        resetsAt: now.addingTimeInterval(604800)
                    )
                )
            ]
        )
    }
}
