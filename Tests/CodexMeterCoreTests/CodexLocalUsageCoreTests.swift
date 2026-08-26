import Darwin
import XCTest
@testable import CodexMeterCore

final class CodexLocalUsageCoreTests: XCTestCase {
    func testUnknownCoverageDoesNotClaimAnEmptyOrCompleteIndex() {
        XCTAssertFalse(CodexLocalUsageCoverage.unknown.isKnown)
        XCTAssertFalse(CodexLocalUsageCoverage.unknown.isSelectedSetIndexed)
        XCTAssertFalse(CodexLocalUsageCoverage.unknown.isComplete)
        XCTAssertEqual(CodexLocalUsageCoverage.unknown.label, "Coverage unavailable")

        let knownEmpty = CodexLocalUsageCoverage(
            indexedFileCount: 0,
            selectedFileCount: 0,
            discoveredFileCount: 0,
            bytesRead: 0
        )
        XCTAssertTrue(knownEmpty.isComplete)
        XCTAssertEqual(knownEmpty.label, "No session files")
    }

    func testCoverageDecodesOlderPayloadWithoutClaimingOmittedRows() throws {
        let decoded = try JSONDecoder().decode(
            CodexLocalUsageCoverage.self,
            from: Data("{\"isKnown\":true,\"indexedFileCount\":1,\"selectedFileCount\":2,\"discoveredFileCount\":3,\"bytesRead\":4}".utf8)
        )

        XCTAssertEqual(decoded.retainedEntryCount, 0)
        XCTAssertEqual(decoded.omittedEntryCount, 0)
        XCTAssertEqual(decoded.label, "Indexing 1 of latest 2 files")
    }

    func testParserExtractsTokenCountEntriesWithProjectAndModelContext() throws {
        let payload = """
        {"timestamp":"2026-05-06T09:00:00.000Z","type":"session_meta","payload":{"id":"session-1","cwd":"/Users/me/App"}}
        {"timestamp":"2026-05-06T09:01:00.000Z","type":"turn_context","payload":{"turn_id":"turn-1","cwd":"/Users/me/App","model":"gpt-5.1-codex-max"}}
        {"timestamp":"2026-05-06T09:01:10.000Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":1200,"cached_input_tokens":800,"output_tokens":300,"reasoning_output_tokens":40,"total_tokens":1500},"model_context_window":1000000}},"rate_limits":{"primary":{"used_percent":22.5,"window_minutes":300,"resets_at":1778079600},"secondary":{"used_percent":41.0,"window_minutes":10080,"resets_at":1778684400},"plan_type":"pro"}}
        """

        let entries = try CodexLocalUsageTranscriptParser.entries(
            from: Data(payload.utf8),
            sourcePath: "/Users/me/.codex/sessions/2026/05/06/rollout-1.jsonl"
        )

        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].sessionID, "session-1")
        XCTAssertEqual(entries[0].turnID, "turn-1")
        XCTAssertEqual(entries[0].projectPath, "/Users/me/App")
        XCTAssertEqual(entries[0].model, "gpt-5.1-codex-max")
        XCTAssertEqual(entries[0].tokens.totalTokens, 1_500)
        XCTAssertEqual(entries[0].tokens.cachedInputTokens, 800)
        XCTAssertEqual(entries[0].tokens.reasoningOutputTokens, 40)
        XCTAssertEqual(entries[0].rateLimits?.primary?.usedPercent, 22.5)
        XCTAssertEqual(entries[0].rateLimits?.primary?.resetsAt, Date(timeIntervalSince1970: 1_778_079_600))
        XCTAssertEqual(entries[0].rateLimits?.secondary?.windowMinutes, 10_080)
        XCTAssertEqual(entries[0].rateLimits?.contextWindowPercent ?? -1, 0.15, accuracy: 0.001)
    }

    func testExtremeTranscriptCountersSaturateInsteadOfOverflowing() throws {
        let maximum = Int.max
        let payload = Data("""
        {"timestamp":"2026-05-06T09:00:00.000Z","type":"session_meta","payload":{"id":"session-1"}}
        {"timestamp":"2026-05-06T09:01:10.000Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":\(maximum),"cached_input_tokens":\(maximum),"output_tokens":\(maximum),"reasoning_output_tokens":\(maximum)}}}}
        """.utf8)
        let parsed = try CodexLocalUsageTranscriptParser.entries(
            from: payload,
            sourcePath: "/tmp/extreme.jsonl"
        )
        let parsedEntry = try XCTUnwrap(parsed.first)
        XCTAssertEqual(parsedEntry.tokens.totalTokens, .max)

        let now = Date(timeIntervalSince1970: 1_778_095_200)
        let entries = [
            entry(id: "one", timestamp: now, sessionID: "same", project: nil, model: "test", total: .max, cached: .max, output: .max, commandCount: .max),
            entry(id: "two", timestamp: now, sessionID: "same", project: nil, model: "test", total: .max, cached: .max, output: .max, commandCount: .max)
        ]
        let summary = CodexLocalUsageAggregator.snapshot(
            entries: entries,
            dataPath: "/tmp",
            capturedAt: now,
            calendar: fixedCalendar
        )

        XCTAssertEqual(summary.total.totalTokens, .max)
        XCTAssertEqual(summary.sessions.first?.tokens.totalTokens, .max)
        XCTAssertEqual(summary.sessions.first?.commandCount, .max)

        var state = CodexLocalUsageParserState(
            turnID: "turn-max",
            currentTurnCommandCount: .max
        )
        _ = CodexLocalUsageTranscriptParser.consume(
            lineData: Data("{\"type\":\"event_msg\",\"payload\":{\"type\":\"exec_command_end\",\"turn_id\":\"turn-max\"}}".utf8),
            sourcePath: "/tmp/extreme.jsonl",
            state: &state
        )
        XCTAssertEqual(state.currentTurnCommandCount, .max)
    }

    func testContextWindowPercentUsesNormalizedTokenTotalWhenRawTotalIsMissing() throws {
        let parsed = try CodexLocalUsageTranscriptParser.entries(
            from: Data("""
            {"timestamp":"2026-05-06T09:01:10.000Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":300,"output_tokens":200},"model_context_window":1000}}}
            """.utf8),
            sourcePath: "/tmp/context-window.jsonl"
        )

        XCTAssertEqual(parsed.first?.tokens.totalTokens, 500)
        XCTAssertEqual(parsed.first?.rateLimits?.contextWindowPercent ?? -1, 50, accuracy: 0.001)
    }

    func testAggregatorBuildsProjectsModelsBlocksAndWasteSignals() throws {
        let now = Date(timeIntervalSince1970: 1_778_095_200)
        let entries = [
            entry(id: "a", timestamp: now.addingTimeInterval(-600), sessionID: "s1", project: "/Users/me/App", model: "gpt-5.1-codex-max", total: 90_000, cached: 70_000, output: 200, commandCount: 8),
            entry(id: "b", timestamp: now.addingTimeInterval(-300), sessionID: "s1", project: "/Users/me/App", model: "gpt-5.1-codex-max", total: 85_000, cached: 68_000, output: 180, commandCount: 7),
            entry(id: "c", timestamp: now.addingTimeInterval(-60), sessionID: "s2", project: "/Users/me/Tool", model: "gpt-5.4-mini", total: 2_000, cached: 100, output: 1_200, commandCount: 0)
        ]

        let summary = CodexLocalUsageAggregator.snapshot(
            entries: entries,
            dataPath: "/Users/me/.codex/sessions",
            capturedAt: now,
            calendar: fixedCalendar
        )

        XCTAssertEqual(summary.total.totalTokens, 177_000)
        XCTAssertEqual(summary.today.entryCount, 3)
        XCTAssertEqual(summary.sessions.first?.id, "s1")
        XCTAssertEqual(summary.projects.first?.displayName, "App")
        XCTAssertEqual(summary.modelSummaries.first?.model, "gpt-5.1-codex-max")
        XCTAssertEqual(summary.fiveHourBlocks.count, 1)
        XCTAssertTrue(summary.wasteSignals.contains { $0.kind == .highCacheRead })
        XCTAssertTrue(summary.wasteSignals.contains { $0.kind == .toolLoop })
        XCTAssertTrue(summary.wasteSignals.contains { $0.kind == .modelOverkill })
        XCTAssertTrue(summary.wasteSignals.contains { $0.kind == .heavySession })
        XCTAssertTrue(summary.wasteSignals.contains { $0.kind == .suddenSpike })
    }

    func testAggregatorBuildsAllSessionsAutopsyAndHighAttributionConfidence() throws {
        let now = Date(timeIntervalSince1970: 1_778_095_200)
        let entries = [
            entry(id: "a", timestamp: now.addingTimeInterval(-600), sessionID: "s1", project: "/Users/me/App", model: "gpt-5.1-codex-max", total: 90_000, cached: 70_000, output: 200, commandCount: 8),
            entry(id: "b", timestamp: now.addingTimeInterval(-300), sessionID: "s1", project: "/Users/me/App", model: "gpt-5.1-codex-max", total: 85_000, cached: 68_000, output: 180, commandCount: 7),
            entry(id: "c", timestamp: now.addingTimeInterval(-60), sessionID: "s2", project: "/Users/me/Tool", model: "gpt-5.4-mini", total: 25_000, cached: 5_000, output: 4_200, commandCount: 1)
        ]

        let summary = CodexLocalUsageAggregator.snapshot(
            entries: entries,
            dataPath: "/Users/me/.codex/sessions",
            capturedAt: now,
            calendar: fixedCalendar
        )

        XCTAssertEqual(summary.attributionConfidence.level, .high)
        XCTAssertEqual(summary.attributionConfidence.title, "High confidence")
        XCTAssertEqual(summary.sessionAutopsies.map(\.id), ["s1", "s2"])
        XCTAssertEqual(summary.sessionAutopsies.first?.projectName, "App")
        XCTAssertEqual(summary.sessionAutopsies.first?.model, "gpt-5.1-codex-max")
        XCTAssertEqual(summary.sessionAutopsies.first?.tokens.totalTokens, 175_000)
        XCTAssertEqual(summary.sessionAutopsies.first?.totalSharePercent ?? 0, 87.5, accuracy: 0.01)
    }

    func testAggregatorKeepsLatestContextWindowPressure() throws {
        let now = Date(timeIntervalSince1970: 1_778_095_200)
        let entries = try CodexLocalUsageTranscriptParser.entries(
            from: Data("""
            {"timestamp":"2026-05-06T09:00:00.000Z","type":"session_meta","payload":{"id":"session-1","cwd":"/Users/me/App"}}
            {"timestamp":"2026-05-06T09:01:00.000Z","type":"turn_context","payload":{"turn_id":"turn-1","cwd":"/Users/me/App","model":"gpt-5.1-codex-max"}}
            {"timestamp":"2026-05-06T09:01:10.000Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":90000,"cached_input_tokens":10000,"output_tokens":10000,"reasoning_output_tokens":1000,"total_tokens":100000},"model_context_window":200000}}}
            """.utf8),
            sourcePath: "/Users/me/.codex/sessions/2026/05/06/rollout-1.jsonl"
        )

        let summary = CodexLocalUsageAggregator.snapshot(
            entries: entries,
            dataPath: "/Users/me/.codex/sessions",
            capturedAt: now,
            calendar: fixedCalendar
        )

        XCTAssertEqual(summary.contextWindowPercent ?? -1, 50, accuracy: 0.001)
    }

    func testAggregatorMarksPartialAttributionWhenLocalContextIsMissing() {
        let now = Date(timeIntervalSince1970: 1_778_095_200)
        let entries = [
            entry(id: "a", timestamp: now.addingTimeInterval(-60), sessionID: "s1", project: nil, model: "unknown", total: 12_000, cached: 3_000, output: 700, commandCount: 0)
        ]

        let summary = CodexLocalUsageAggregator.snapshot(
            entries: entries,
            dataPath: "/Users/me/.codex/sessions",
            capturedAt: now,
            calendar: fixedCalendar
        )

        XCTAssertEqual(summary.attributionConfidence.level, .partial)
        XCTAssertTrue(summary.attributionConfidence.detail.contains("Some local session rows are missing project or model context."))
    }

    func testAggregatorMarksUnknownAttributionWhenNoSessionDataExists() {
        let summary = CodexLocalUsageAggregator.snapshot(
            entries: [],
            dataPath: "/Users/me/.codex/sessions",
            capturedAt: Date(timeIntervalSince1970: 1_778_095_200),
            calendar: fixedCalendar
        )

        XCTAssertEqual(summary.attributionConfidence.level, .unknown)
        XCTAssertEqual(summary.sessionAutopsies, [])
    }

    func testPersistentIndexPlansAppendAndRebuildsOnShrink() {
        let old = CodexLocalUsageFileState(
            path: "/tmp/a.jsonl",
            inode: 10,
            size: 100,
            modifiedAt: Date(timeIntervalSince1970: 1),
            appendFingerprint: "fingerprint"
        )
        let appended = CodexLocalUsageFileState(path: "/tmp/a.jsonl", inode: 10, size: 140, modifiedAt: Date(timeIntervalSince1970: 2))
        let shrunk = CodexLocalUsageFileState(path: "/tmp/a.jsonl", inode: 10, size: 20, modifiedAt: Date(timeIntervalSince1970: 3))
        let legacy = CodexLocalUsageFileState(path: "/tmp/a.jsonl", inode: 10, size: 100, modifiedAt: Date(timeIntervalSince1970: 1))

        XCTAssertEqual(CodexLocalUsageIndex.plan(previous: old, current: appended), .append(fromOffset: 100))
        XCTAssertEqual(CodexLocalUsageIndex.plan(previous: old, current: shrunk), .fullRead)
        XCTAssertEqual(CodexLocalUsageIndex.plan(previous: old, current: old), .skip)
        XCTAssertEqual(CodexLocalUsageIndex.plan(previous: legacy, current: appended), .fullRead)
    }

    func testDirectoryReaderCanLimitToNewestSessionFiles() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "CodexLocalUsageReader-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let oldFile = root.appending(path: "old.jsonl")
        let newFile = root.appending(path: "new.jsonl")
        try makePayload(session: "old-session", total: 100).write(to: oldFile)
        try makePayload(session: "new-session", total: 200).write(to: newFile)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 10)],
            ofItemAtPath: oldFile.path
        )
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 20)],
            ofItemAtPath: newFile.path
        )

        let entries = try CodexLocalUsageDirectoryReader.entries(in: root, maximumFiles: 1)

        XCTAssertEqual(entries.map(\.sessionID), ["new-session"])
        XCTAssertEqual(entries.first?.tokens.totalTokens, 200)
    }

    func testCandidateSelectionBoundsRetainedStateWhileCountingAllFiles() throws {
        let root = try makeTemporaryDirectory(prefix: "CodexLocalUsageCandidateBound")
        defer { try? FileManager.default.removeItem(at: root) }
        for index in 0..<250 {
            let file = root.appending(path: String(format: "%03d.jsonl", index))
            try Data().write(to: file)
            try FileManager.default.setAttributes(
                [.modificationDate: Date(timeIntervalSince1970: TimeInterval(index))],
                ofItemAtPath: file.path
            )
        }

        let selection = try CodexLocalUsageDirectoryReader.sessionFileSelection(
            in: root,
            maximumFiles: 7
        )

        XCTAssertEqual(selection.discoveredFileCount, 250)
        XCTAssertEqual(selection.selected.count, 7)
        XCTAssertLessThanOrEqual(selection.peakRetainedCandidateCount, 7)
        XCTAssertEqual(
            selection.selected.map { $0.url.lastPathComponent },
            ["249.jsonl", "248.jsonl", "247.jsonl", "246.jsonl", "245.jsonl", "244.jsonl", "243.jsonl"]
        )
    }

    func testIncrementalReaderContinuesAfterBudgetCutWithoutDuplicatesOrLoss() throws {
        let root = try makeTemporaryDirectory(prefix: "CodexLocalUsageBudget")
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appending(path: "session.jsonl")
        let payload = makePayload(session: "session-1", total: 321)
        try payload.write(to: file)

        var previous: CodexLocalUsageIndexSnapshot?
        var result: CodexLocalUsageDirectoryReader.IncrementalResult?
        var scanCount = 0
        var totalBytesRead: UInt64 = 0
        for _ in 0..<32 {
            let scan = try CodexLocalUsageDirectoryReader.incrementalSummary(
                in: root,
                previous: previous,
                maximumFiles: 1,
                maximumBytes: 32
            )
            scanCount += 1
            totalBytesRead += scan.summary.coverage.bytesRead
            XCTAssertLessThanOrEqual(scan.summary.coverage.bytesRead, 32)
            previous = scan.index
            result = scan
            if scan.summary.coverage.isSelectedSetIndexed { break }
        }

        let completed = try XCTUnwrap(result)
        XCTAssertGreaterThan(scanCount, 1)
        XCTAssertEqual(totalBytesRead, UInt64(payload.count))
        XCTAssertTrue(completed.summary.coverage.isSelectedSetIndexed)
        XCTAssertEqual(completed.summary.total.entryCount, 1)
        XCTAssertEqual(completed.summary.total.totalTokens, 321)

        let noChange = try CodexLocalUsageDirectoryReader.incrementalSummary(
            in: root,
            previous: completed.index,
            maximumFiles: 1,
            maximumBytes: 32
        )
        XCTAssertEqual(noChange.summary.total.entryCount, 1)
        XCTAssertEqual(noChange.summary.coverage.bytesRead, 0)
    }

    func testIncrementalReaderBoundsRetainedRowsAndReportsPartialTotals() throws {
        let root = try makeTemporaryDirectory(prefix: "CodexLocalUsageRetention")
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appending(path: "session.jsonl")
        let lines = (1...6).map { value in
            "{\"timestamp\":\"2026-05-06T09:0\(value):00.000Z\",\"type\":\"event_msg\",\"payload\":{\"type\":\"token_count\",\"session_id\":\"session-1\",\"info\":{\"last_token_usage\":{\"total_tokens\":\(value)}}}}"
        }
        try Data(lines.joined(separator: "\n").utf8).write(to: file)

        let first = try CodexLocalUsageDirectoryReader.incrementalSummary(
            in: root,
            previous: nil,
            maximumFiles: 1,
            maximumBytes: .max,
            maximumRetainedEntries: 3
        )

        XCTAssertEqual(first.index.entries.map(\.tokens.totalTokens), [4, 5, 6])
        let indexedPath = try XCTUnwrap(first.index.entries.first?.sourcePath)
        XCTAssertEqual(first.index.omittedEntryCountsByFile[indexedPath], 3)
        XCTAssertEqual(first.summary.coverage.retainedEntryCount, 3)
        XCTAssertEqual(first.summary.coverage.omittedEntryCount, 3)
        XCTAssertTrue(first.summary.coverage.isSelectedSetIndexed)
        XCTAssertFalse(first.summary.coverage.isComplete)
        XCTAssertEqual(first.summary.coverage.label, "Latest 3 rows · 1 file")

        let unchanged = try CodexLocalUsageDirectoryReader.incrementalSummary(
            in: root,
            previous: first.index,
            maximumFiles: 1,
            maximumBytes: .max,
            maximumRetainedEntries: 3
        )
        XCTAssertEqual(unchanged.index.entries, first.index.entries)
        XCTAssertEqual(unchanged.summary.coverage.omittedEntryCount, 3)

        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("\n{\"timestamp\":\"2026-05-06T09:07:00.000Z\",\"type\":\"event_msg\",\"payload\":{\"type\":\"token_count\",\"session_id\":\"session-1\",\"info\":{\"last_token_usage\":{\"total_tokens\":7}}}}".utf8))
        try handle.close()

        let appended = try CodexLocalUsageDirectoryReader.incrementalSummary(
            in: root,
            previous: unchanged.index,
            maximumFiles: 1,
            maximumBytes: .max,
            maximumRetainedEntries: 3
        )
        XCTAssertEqual(appended.index.entries.map(\.tokens.totalTokens), [5, 6, 7])
        XCTAssertEqual(appended.summary.coverage.omittedEntryCount, 4)

        try makePayload(session: "replacement", total: 9).write(to: file, options: .atomic)
        let replaced = try CodexLocalUsageDirectoryReader.incrementalSummary(
            in: root,
            previous: appended.index,
            maximumFiles: 1,
            maximumBytes: .max,
            maximumRetainedEntries: 3
        )
        XCTAssertEqual(replaced.summary.total.totalTokens, 9)
        XCTAssertEqual(replaced.summary.coverage.omittedEntryCount, 0)
    }

    func testPartialLineIndexSerializationNeverContainsRawTranscriptText() throws {
        let root = try makeTemporaryDirectory(prefix: "CodexLocalUsagePrivatePartial")
        defer { try? FileManager.default.removeItem(at: root) }
        let sentinel = "PRIVATE-PROMPT-SENTINEL-DO-NOT-PERSIST"
        let payload = Data("""
        {"timestamp":"2026-05-06T09:00:00.000Z","type":"session_meta","payload":{"id":"session-1","cwd":"/Users/me/App"}}
        {"timestamp":"2026-05-06T09:00:30.000Z","type":"response_item","payload":{"text":"\(sentinel)"}}
        {"timestamp":"2026-05-06T09:01:10.000Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":42,"cached_input_tokens":0,"output_tokens":0,"reasoning_output_tokens":0,"total_tokens":42}}}}
        """.utf8)
        try payload.write(to: root.appending(path: "session.jsonl"))

        let partial = try CodexLocalUsageDirectoryReader.incrementalSummary(
            in: root,
            previous: nil,
            maximumFiles: 1,
            maximumBytes: 160
        )
        let encoded = try JSONEncoder().encode(partial.index)
        let serialized = String(decoding: encoded, as: UTF8.self)

        XCTAssertGreaterThan(partial.index.parserStates.values.first?.pendingLineByteCount ?? 0, 0)
        XCTAssertFalse(serialized.contains(sentinel))
        XCTAssertFalse(serialized.contains("response_item"))
    }

    func testParserStateStaysBoundedAcrossManyTurns() throws {
        var state = CodexLocalUsageParserState()
        for index in 0..<2_000 {
            let turn = "turn-\(index)"
            _ = CodexLocalUsageTranscriptParser.consume(
                lineData: Data("{\"type\":\"turn_context\",\"payload\":{\"turn_id\":\"\(turn)\"}}".utf8),
                sourcePath: "/tmp/session.jsonl",
                state: &state
            )
            _ = CodexLocalUsageTranscriptParser.consume(
                lineData: Data("{\"type\":\"event_msg\",\"payload\":{\"type\":\"exec_command_end\",\"turn_id\":\"\(turn)\"}}".utf8),
                sourcePath: "/tmp/session.jsonl",
                state: &state
            )
        }

        let encoded = try JSONEncoder().encode(state)
        XCTAssertEqual(state.turnID, "turn-1999")
        XCTAssertEqual(state.currentTurnCommandCount, 1)
        XCTAssertLessThan(encoded.count, 512)
    }

    func testParserRejectsOversizedPersistedContextFields() throws {
        let oversizedID = String(repeating: "i", count: 513)
        let oversizedPath = "/" + String(repeating: "p", count: 1_024)
        let oversizedModel = String(repeating: "m", count: 257)
        let oversizedPlan = String(repeating: "x", count: 129)
        let payload = Data("""
        {"timestamp":"2026-05-06T09:00:00.000Z","type":"session_meta","payload":{"id":"\(oversizedID)","cwd":"\(oversizedPath)"}}
        {"timestamp":"2026-05-06T09:00:30.000Z","type":"turn_context","payload":{"turn_id":"\(oversizedID)","cwd":"\(oversizedPath)","model":"\(oversizedModel)"}}
        {"timestamp":"2026-05-06T09:01:10.000Z","type":"event_msg","payload":{"type":"token_count","session_id":"\(oversizedID)","turn_id":"\(oversizedID)","cwd":"\(oversizedPath)","model":"\(oversizedModel)","info":{"last_token_usage":{"total_tokens":42}},"rate_limits":{"plan_type":"\(oversizedPlan)"}}}
        """.utf8)

        let parsed = try CodexLocalUsageTranscriptParser.entries(
            from: payload,
            sourcePath: "/tmp/bounded.jsonl"
        )
        let entry = try XCTUnwrap(parsed.first)

        XCTAssertEqual(entry.sessionID, "bounded")
        XCTAssertNil(entry.turnID)
        XCTAssertNil(entry.projectPath)
        XCTAssertEqual(entry.model, "unknown")
        XCTAssertNil(entry.rateLimits?.planType)
    }

    func testIncrementalReaderReadsOnlyAppendedBytes() throws {
        let root = try makeTemporaryDirectory(prefix: "CodexLocalUsageAppend")
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appending(path: "session.jsonl")
        try makePayload(session: "session-1", total: 100).write(to: file)
        let first = try CodexLocalUsageDirectoryReader.incrementalSummary(
            in: root,
            previous: nil,
            maximumFiles: 1,
            maximumBytes: .max
        )
        let originalSize = try XCTUnwrap(first.index.files.values.first).size

        let appended = Data("\n{\"timestamp\":\"2026-05-06T09:02:10.000Z\",\"type\":\"event_msg\",\"payload\":{\"type\":\"token_count\",\"info\":{\"last_token_usage\":{\"input_tokens\":200,\"cached_input_tokens\":0,\"output_tokens\":0,\"reasoning_output_tokens\":0,\"total_tokens\":200}}}}\n".utf8)
        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd()
        try handle.write(contentsOf: appended)
        try handle.close()

        let second = try CodexLocalUsageDirectoryReader.incrementalSummary(
            in: root,
            previous: first.index,
            maximumFiles: 1,
            maximumBytes: .max
        )

        XCTAssertEqual(second.summary.total.entryCount, 2)
        XCTAssertEqual(second.summary.total.totalTokens, 300)
        XCTAssertEqual(second.summary.coverage.bytesRead, UInt64(appended.count))
        let appendedSize = try XCTUnwrap(second.index.files.values.first).size
        XCTAssertGreaterThan(appendedSize, originalSize)
    }

    func testIncrementalReaderRebuildsAfterRotation() throws {
        let root = try makeTemporaryDirectory(prefix: "CodexLocalUsageTruncate")
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appending(path: "session.jsonl")
        try makePayload(session: "old-session", total: 9_999).write(to: file)
        let first = try CodexLocalUsageDirectoryReader.incrementalSummary(
            in: root,
            previous: nil,
            maximumFiles: 1,
            maximumBytes: .max
        )

        try makePayload(session: "new", total: 7).write(to: file, options: .atomic)
        let second = try CodexLocalUsageDirectoryReader.incrementalSummary(
            in: root,
            previous: first.index,
            maximumFiles: 1,
            maximumBytes: .max
        )

        XCTAssertEqual(second.summary.sessions.map(\.id), ["new"])
        XCTAssertEqual(second.summary.total.totalTokens, 7)
    }

    func testIncrementalReaderRebuildsAfterInPlaceTruncate() throws {
        let root = try makeTemporaryDirectory(prefix: "CodexLocalUsageTruncate")
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appending(path: "session.jsonl")
        try makePayload(session: "old-session", total: 9_999).write(to: file)
        let first = try CodexLocalUsageDirectoryReader.incrementalSummary(
            in: root,
            previous: nil,
            maximumFiles: 1,
            maximumBytes: .max
        )

        let replacement = makePayload(session: "new", total: 7)
        let handle = try FileHandle(forWritingTo: file)
        try handle.truncate(atOffset: 0)
        try handle.write(contentsOf: replacement)
        try handle.close()
        let second = try CodexLocalUsageDirectoryReader.incrementalSummary(
            in: root,
            previous: first.index,
            maximumFiles: 1,
            maximumBytes: .max
        )

        XCTAssertEqual(second.summary.sessions.map(\.id), ["new"])
        XCTAssertEqual(second.summary.total.totalTokens, 7)
    }

    func testIncrementalReaderRebuildsAfterLargerInPlaceRewrite() throws {
        let root = try makeTemporaryDirectory(prefix: "CodexLocalUsageLargerRewrite")
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appending(path: "session.jsonl")
        let original = makePayload(session: "old-session", total: 9_999)
        try original.write(to: file)
        let first = try CodexLocalUsageDirectoryReader.incrementalSummary(
            in: root,
            previous: nil,
            maximumFiles: 1,
            maximumBytes: .max
        )
        let originalState = try XCTUnwrap(first.index.files.values.first)
        XCTAssertNotNil(originalState.appendFingerprint)

        var replacement = makePayload(session: "new", total: 7)
        replacement.append(Data("\n{\"type\":\"ignored\",\"payload\":{\"padding\":\"\(String(repeating: "x", count: original.count))\"}}\n".utf8))
        XCTAssertGreaterThan(replacement.count, original.count)
        let handle = try FileHandle(forWritingTo: file)
        try handle.truncate(atOffset: 0)
        try handle.write(contentsOf: replacement)
        try handle.close()

        var rewrittenInfo = stat()
        XCTAssertEqual(lstat(file.path, &rewrittenInfo), 0)
        XCTAssertEqual(UInt64(rewrittenInfo.st_ino), originalState.inode)
        let second = try CodexLocalUsageDirectoryReader.incrementalSummary(
            in: root,
            previous: first.index,
            maximumFiles: 1,
            maximumBytes: .max
        )

        XCTAssertEqual(second.summary.sessions.map(\.id), ["new"])
        XCTAssertEqual(second.summary.total.entryCount, 1)
        XCTAssertEqual(second.summary.total.totalTokens, 7)
    }

    func testDirectoryReaderRejectsJSONLSymlinkOutsideSessionsRoot() throws {
        let root = try makeTemporaryDirectory(prefix: "CodexLocalUsageSymlinkRoot")
        let outside = try makeTemporaryDirectory(prefix: "CodexLocalUsageSymlinkOutside")
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: outside)
        }
        let outsideFile = outside.appending(path: "private.jsonl")
        try makePayload(session: "outside", total: 77_777).write(to: outsideFile)
        try FileManager.default.createSymbolicLink(
            at: root.appending(path: "escape.jsonl"),
            withDestinationURL: outsideFile
        )
        XCTAssertThrowsError(
            try CodexLocalUsageDirectoryReader.openSessionFileForReading(
                root.appending(path: "escape.jsonl")
            )
        )

        let scan = try CodexLocalUsageDirectoryReader.incrementalSummary(
            in: root,
            previous: nil,
            maximumFiles: 120,
            maximumBytes: .max
        )

        XCTAssertEqual(scan.summary.coverage.discoveredFileCount, 0)
        XCTAssertEqual(scan.summary.total.entryCount, 0)
        XCTAssertTrue(scan.index.entries.isEmpty)
    }

    func testSafeSessionOpenRejectsFileSwappedAfterEnumeration() throws {
        let root = try makeTemporaryDirectory(prefix: "CodexLocalUsageSwap")
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appending(path: "session.jsonl")
        try makePayload(session: "original", total: 10).write(to: file)
        var originalInfo = stat()
        XCTAssertEqual(lstat(file.path, &originalInfo), 0)

        try makePayload(session: "replacement", total: 20).write(to: file, options: .atomic)

        XCTAssertThrowsError(
            try CodexLocalUsageDirectoryReader.openSessionFileForReading(
                file,
                expectedInode: UInt64(originalInfo.st_ino)
            )
        )
    }

    func testIndexStoreRecoversFromCorruptIndex() async throws {
        let root = try makeTemporaryDirectory(prefix: "CodexLocalUsageCorrupt")
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appending(path: "session.jsonl")
        try makePayload(session: "session-1", total: 42).write(to: file)
        let indexURL = root.appending(path: "index.json")
        try Data("not-json".utf8).write(to: indexURL)
        let store = CodexLocalUsageIndexStore(fileURL: indexURL)

        let summary = try await store.summary(
            in: root,
            maximumFiles: 1,
            maximumBytes: .max
        )

        XCTAssertEqual(summary.total.totalTokens, 42)
        let rebuiltIndex = await store.load()
        XCTAssertNotNil(rebuiltIndex)
    }

    func testIndexStoreRebuildsLegacyIndexVersion() async throws {
        let root = try makeTemporaryDirectory(prefix: "CodexLocalUsageLegacyIndex")
        defer { try? FileManager.default.removeItem(at: root) }
        let sessions = root.appending(path: "Sessions", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        let file = sessions.appending(path: "session.jsonl")
        try makePayload(session: "session-1", total: 42).write(to: file)
        let initial = try CodexLocalUsageDirectoryReader.incrementalSummary(
            in: sessions,
            previous: nil,
            maximumFiles: 1,
            maximumBytes: .max
        )
        let legacyFiles = initial.index.files.mapValues { state in
            CodexLocalUsageFileState(
                path: state.path,
                inode: state.inode,
                size: state.size,
                modifiedAt: state.modifiedAt
            )
        }
        let legacy = CodexLocalUsageIndexSnapshot(
            version: CodexLocalUsageIndex.currentVersion - 1,
            capturedAt: initial.index.capturedAt,
            rootPath: sessions.path,
            files: legacyFiles,
            parserStates: initial.index.parserStates,
            entries: []
        )
        let indexURL = root.appending(path: "index.json")
        let writer = CodexLocalUsageIndexStore(fileURL: indexURL)
        try await writer.save(legacy)
        let store = CodexLocalUsageIndexStore(fileURL: indexURL)

        let summary = try await store.summary(
            in: sessions,
            maximumFiles: 1,
            maximumBytes: .max
        )

        XCTAssertEqual(summary.total.totalTokens, 42)
        let rebuilt = await store.load()
        XCTAssertEqual(rebuilt?.version, CodexLocalUsageIndex.currentVersion)
    }

    func testIndexStoreDoesNotRewriteUnchangedIndex() async throws {
        let root = try makeTemporaryDirectory(prefix: "CodexLocalUsageNoRewrite")
        defer { try? FileManager.default.removeItem(at: root) }
        let sessions = root.appending(path: "Sessions", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        try makePayload(session: "session-1", total: 42).write(
            to: sessions.appending(path: "session.jsonl")
        )
        let indexURL = root.appending(path: "index.json")
        let store = CodexLocalUsageIndexStore(fileURL: indexURL)
        _ = try await store.summary(
            in: sessions,
            capturedAt: Date(timeIntervalSince1970: 1_800_000_000),
            maximumFiles: 1,
            maximumBytes: .max
        )
        let loadedIndex = await store.load()
        let stored = try XCTUnwrap(loadedIndex)
        XCTAssertEqual(stored.version, CodexLocalUsageIndex.currentVersion)
        let sentinelModificationDate = Date(timeIntervalSince1970: 123_456)
        try FileManager.default.setAttributes(
            [.modificationDate: sentinelModificationDate],
            ofItemAtPath: indexURL.path
        )
        let unchanged = try CodexLocalUsageDirectoryReader.incrementalSummary(
            in: sessions,
            previous: stored,
            capturedAt: Date(timeIntervalSince1970: 1_800_000_100),
            maximumFiles: 1,
            maximumBytes: .max
        ).index
        XCTAssertEqual(unchanged.rootPath, stored.rootPath)
        XCTAssertEqual(unchanged.files, stored.files)
        XCTAssertEqual(unchanged.parserStates, stored.parserStates)
        XCTAssertEqual(unchanged.entries, stored.entries)

        _ = try await store.summary(
            in: sessions,
            capturedAt: Date(timeIntervalSince1970: 1_800_000_100),
            maximumFiles: 1,
            maximumBytes: .max
        )

        let attributes = try FileManager.default.attributesOfItem(atPath: indexURL.path)
        XCTAssertEqual(attributes[.modificationDate] as? Date, sentinelModificationDate)
    }

    func testIndexStoreUsesOwnerOnlyFileAndDirectoryPermissions() async throws {
        let root = try makeTemporaryDirectory(prefix: "CodexLocalUsagePermissions")
        defer { try? FileManager.default.removeItem(at: root) }
        let sessions = root.appending(path: "Sessions", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        try makePayload(session: "session-1", total: 42).write(
            to: sessions.appending(path: "session.jsonl")
        )
        let indexDirectory = root.appending(path: "Codexex", directoryHint: .isDirectory)
        let indexURL = indexDirectory.appending(path: "index.json")
        let store = CodexLocalUsageIndexStore(
            fileURL: indexURL,
            secureParentDirectory: true
        )

        _ = try await store.summary(in: sessions, maximumFiles: 1, maximumBytes: .max)

        XCTAssertEqual(try permissions(at: indexDirectory), 0o700)
        XCTAssertEqual(try permissions(at: indexURL), 0o600)
    }

    func testIndexStoreSurfacesPersistenceFailure() async throws {
        let root = try makeTemporaryDirectory(prefix: "CodexLocalUsageSaveFailure")
        defer { try? FileManager.default.removeItem(at: root) }
        let sessions = root.appending(path: "Sessions", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        try makePayload(session: "session-1", total: 42).write(
            to: sessions.appending(path: "session.jsonl")
        )
        let blockedParent = root.appending(path: "not-a-directory")
        try Data("blocked".utf8).write(to: blockedParent)
        let store = CodexLocalUsageIndexStore(
            fileURL: blockedParent.appending(path: "index.json"),
            secureParentDirectory: true
        )

        do {
            _ = try await store.summary(in: sessions, maximumFiles: 1, maximumBytes: .max)
            XCTFail("Expected persistence failure")
        } catch {
            XCTAssertFalse(error.localizedDescription.isEmpty)
        }
    }

    func testSecureAtomicFileReplacesContentAndKeepsOwnerOnlyPermissions() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "CodexSecureAtomicFile-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let fileURL = root.appending(path: "private.json")

        try CodexSecureAtomicFile.write(
            Data("first".utf8),
            to: fileURL,
            secureParentDirectory: true
        )
        try CodexSecureAtomicFile.write(
            Data("replacement".utf8),
            to: fileURL,
            secureParentDirectory: true
        )

        XCTAssertEqual(try Data(contentsOf: fileURL), Data("replacement".utf8))
        XCTAssertEqual(try permissions(at: root), 0o700)
        XCTAssertEqual(try permissions(at: fileURL), 0o600)
    }

    func testSecureAtomicFileReadRejectsOversizedAndSymlinkedFiles() throws {
        let root = try makeTemporaryDirectory(prefix: "CodexSecureRead")
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appending(path: "private.json")
        try Data("12345".utf8).write(to: file)

        XCTAssertThrowsError(try CodexSecureAtomicFile.read(from: file, maximumBytes: 4))
        XCTAssertEqual(
            try CodexSecureAtomicFile.read(from: file, maximumBytes: 5),
            Data("12345".utf8)
        )

        let link = root.appending(path: "private-link.json")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)
        XCTAssertThrowsError(try CodexSecureAtomicFile.read(from: link, maximumBytes: 5))
    }

    func testDefaultSessionsURLUsesLoginHomeInsteadOfSandboxHome() throws {
        let passwd = try XCTUnwrap(getpwuid(getuid()))
        let loginHome = String(cString: passwd.pointee.pw_dir)

        XCTAssertEqual(
            CodexLocalUsageDirectoryReader.defaultSessionsURL().path,
            "\(loginHome)/.codex/sessions"
        )
    }

    func testConfigDoctorFlagsMissingHooksAndSessionData() {
        let report = CodexLocalConfigDoctor.report(
            hasSessionData: false,
            hooksInstalled: false,
            configPath: "/Users/me/.codex/config.toml",
            sessionsPath: "/Users/me/.codex/sessions"
        )

        XCTAssertEqual(report.issues.map(\.kind), [.missingSessionData, .hooksNotInstalled])
        XCTAssertEqual(report.severity, .warning)
    }

    func testConfigDoctorFlagsStaleSessionData() {
        let report = CodexLocalConfigDoctor.report(
            hasSessionData: true,
            hooksInstalled: true,
            configPath: "/Users/me/.codex/config.toml",
            sessionsPath: "/Users/me/.codex/sessions",
            latestSessionActivityAt: Date(timeIntervalSince1970: 1_000),
            now: Date(timeIntervalSince1970: 200_000)
        )

        XCTAssertEqual(report.issues.map(\.kind), [.staleSessionData])
        XCTAssertEqual(report.severity, .warning)
    }

    private var fixedCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func entry(
        id: String,
        timestamp: Date,
        sessionID: String,
        project: String?,
        model: String,
        total: Int,
        cached: Int,
        output: Int,
        commandCount: Int
    ) -> CodexLocalUsageEntry {
        CodexLocalUsageEntry(
            id: id,
            timestamp: timestamp,
            sessionID: sessionID,
            turnID: "turn-\(id)",
            projectPath: project,
            model: model,
            tokens: CodexLocalTokenUsage(
                inputTokens: max(0, total - output),
                cachedInputTokens: cached,
                outputTokens: output,
                reasoningOutputTokens: output / 10,
                totalTokens: total
            ),
            sourcePath: "/tmp/\(sessionID).jsonl",
            commandCount: commandCount,
            rateLimits: nil
        )
    }

    private func makePayload(session: String, total: Int) -> Data {
        Data("""
        {"timestamp":"2026-05-06T09:00:00.000Z","type":"session_meta","payload":{"id":"\(session)","cwd":"/Users/me/App"}}
        {"timestamp":"2026-05-06T09:01:10.000Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":\(total),"cached_input_tokens":0,"output_tokens":0,"reasoning_output_tokens":0,"total_tokens":\(total)}}}}
        """.utf8)
    }

    private func makeTemporaryDirectory(prefix: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "\(prefix)-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func permissions(at url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return try XCTUnwrap(attributes[.posixPermissions] as? NSNumber).intValue & 0o777
    }
}
