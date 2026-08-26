import XCTest
import CodexMeterCore
@testable import CodexMeterApp

final class CodexUsageHistoryStorePersistenceTests: XCTestCase {
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

    func testLoadReloadsChangesWrittenByAnotherStoreInstance() async throws {
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }
        let firstStore = CodexUsageHistoryStore(fileURL: fileURL)
        let secondStore = CodexUsageHistoryStore(fileURL: fileURL)
        let now = Date(timeIntervalSince1970: 1_000_000)
        _ = await firstStore.append(snapshot: makeSnapshot(now: now, used: 10), now: now)
        _ = await secondStore.append(
            snapshot: makeSnapshot(now: now.addingTimeInterval(60), used: 20),
            now: now.addingTimeInterval(60)
        )

        let loaded = await firstStore.load(now: now.addingTimeInterval(60))

        XCTAssertEqual(loaded.map { $0.fiveHour?.usedPercent }, [10, 20])
    }

    func testConcurrentStoreInstancesMergeEveryAppend() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexHistoryConcurrent-\(UUID().uuidString)", isDirectory: true)
        let fileURL = root.appendingPathComponent("usage-history.json")
        defer { try? FileManager.default.removeItem(at: root) }
        let base = Date(timeIntervalSince1970: 1_000_000)
        let finalNow = base.addingTimeInterval(60)
        let work = (0..<16).map { index in
            (
                CodexUsageHistoryStore(fileURL: fileURL),
                makeSnapshot(now: base.addingTimeInterval(Double(index)), used: Double(index + 1))
            )
        }

        await withTaskGroup(of: Void.self) { group in
            for (store, snapshot) in work {
                group.addTask {
                    _ = await store.append(snapshot: snapshot, now: finalNow)
                }
            }
        }

        let loaded = await CodexUsageHistoryStore(fileURL: fileURL).load(now: finalNow)
        XCTAssertEqual(loaded.count, 16)
        XCTAssertEqual(Set(loaded.compactMap { $0.fiveHour?.usedPercent }), Set((1...16).map(Double.init)))
    }

    func testAppendDoesNotOverwriteCorruptExistingHistory() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexHistoryCorrupt-\(UUID().uuidString)", isDirectory: true)
        let fileURL = root.appendingPathComponent("usage-history.json")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let corrupt = Data("sentinel-corrupt-history".utf8)
        try corrupt.write(to: fileURL)
        let store = CodexUsageHistoryStore(fileURL: fileURL)
        let now = Date(timeIntervalSince1970: 1_000_000)

        let inMemory = await store.append(snapshot: makeSnapshot(now: now, used: 10), now: now)
        let persistenceFailure = await store.persistenceFailure()

        XCTAssertEqual(inMemory.count, 1)
        XCTAssertEqual(try Data(contentsOf: fileURL), corrupt)
        XCTAssertNotNil(persistenceFailure)
    }

    func testOversizedHistoryIsRejectedWithoutReadingOrReplacingIt() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexHistoryOversized-\(UUID().uuidString)", isDirectory: true)
        let fileURL = root.appendingPathComponent("usage-history.json")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        XCTAssertTrue(FileManager.default.createFile(atPath: fileURL.path, contents: nil))
        let handle = try FileHandle(forWritingTo: fileURL)
        try handle.truncate(atOffset: 32 * 1_024 * 1_024 + 1)
        try handle.close()
        let store = CodexUsageHistoryStore(fileURL: fileURL)

        let loaded = await store.load(now: Date(timeIntervalSince1970: 1_000_000))
        let persistenceFailure = await store.persistenceFailure()

        XCTAssertTrue(loaded.isEmpty)
        let size = try XCTUnwrap(
            FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? NSNumber
        ).uint64Value
        XCTAssertEqual(size, 32 * 1_024 * 1_024 + 1)
        XCTAssertNotNil(persistenceFailure)
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
