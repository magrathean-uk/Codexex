import Foundation
import XCTest
@testable import Codexex

final class CodexiOSUsageHistoryStoreTests: XCTestCase {
    func testDenseOlderHistoryIsCompactedWithoutLosingLocalPeak() async throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = root.appendingPathComponent("usage-history.json")
        defer { try? fileManager.removeItem(at: root) }
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let sampleCount = 8 * 24 * 12
        var samples: [CodexUsageHistorySample] = []
        samples.reserveCapacity(sampleCount)
        for index in 0..<sampleCount {
            let date = now.addingTimeInterval(-Double(sampleCount - index) * 5 * 60)
            let used = index == 5 ? 99.0 : Double(index % 70)
            samples.append(
                CodexUsageHistorySample(
                    capturedAt: date,
                    fiveHour: .init(usedPercent: used, windowDurationMinutes: 300, resetsAt: nil),
                    weekly: .init(usedPercent: used, windowDurationMinutes: 10_080, resetsAt: nil)
                )
            )
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(samples).write(to: fileURL, options: .atomic)

        let store = CodexUsageHistoryStore(fileURL: fileURL)
        let loaded = await store.load(now: now)

        XCTAssertLessThan(loaded.count, 2_200)
        XCTAssertTrue(zip(loaded, loaded.dropFirst()).allSatisfy { pair in
            pair.0.capturedAt <= pair.1.capturedAt
        })
        XCTAssertTrue(loaded.contains { $0.weekly?.usedPercent == 99 })
    }

    func testClearDeletesDiskHistoryAndCache() async throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = root.appendingPathComponent("usage-history.json")
        defer { try? fileManager.removeItem(at: root) }
        let store = CodexUsageHistoryStore(fileURL: fileURL)
        _ = await store.append(snapshot: CodexiOSPreviewData.snapshot(), now: Date())
        XCTAssertTrue(fileManager.fileExists(atPath: fileURL.path))

        try await store.clear()
        let reloaded = await store.load()

        XCTAssertFalse(fileManager.fileExists(atPath: fileURL.path))
        XCTAssertTrue(reloaded.isEmpty)
    }
}
