import XCTest
@testable import CodexMeterCore

final class CodexLocalUsageCoreTests: XCTestCase {
    func testParserExtractsTokenCountEntriesWithProjectAndModelContext() throws {
        let payload = """
        {"timestamp":"2026-05-06T09:00:00.000Z","type":"session_meta","payload":{"id":"session-1","cwd":"/Users/me/App"}}
        {"timestamp":"2026-05-06T09:01:00.000Z","type":"turn_context","payload":{"turn_id":"turn-1","cwd":"/Users/me/App","model":"gpt-5.1-codex-max"}}
        {"timestamp":"2026-05-06T09:01:10.000Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":1200,"cached_input_tokens":800,"output_tokens":300,"reasoning_output_tokens":40,"total_tokens":1500},"model_context_window":1000000},"rate_limits":{"primary":{"used_percent":22.5,"window_minutes":300,"resets_at":1778079600},"secondary":{"used_percent":41.0,"window_minutes":10080,"resets_at":1778684400},"plan_type":"pro"}}}
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
    }

    func testPersistentIndexPlansAppendAndRebuildsOnShrink() {
        let old = CodexLocalUsageFileState(path: "/tmp/a.jsonl", inode: 10, size: 100, modifiedAt: Date(timeIntervalSince1970: 1))
        let appended = CodexLocalUsageFileState(path: "/tmp/a.jsonl", inode: 10, size: 140, modifiedAt: Date(timeIntervalSince1970: 2))
        let shrunk = CodexLocalUsageFileState(path: "/tmp/a.jsonl", inode: 10, size: 20, modifiedAt: Date(timeIntervalSince1970: 3))

        XCTAssertEqual(CodexLocalUsageIndex.plan(previous: old, current: appended), .append(fromOffset: 100))
        XCTAssertEqual(CodexLocalUsageIndex.plan(previous: old, current: shrunk), .fullRead)
        XCTAssertEqual(CodexLocalUsageIndex.plan(previous: old, current: old), .skip)
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

    private var fixedCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func entry(
        id: String,
        timestamp: Date,
        sessionID: String,
        project: String,
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
}
