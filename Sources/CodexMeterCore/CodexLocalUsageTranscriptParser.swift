import Foundation

public enum CodexLocalUsageTranscriptParser {
    public static func entries(from data: Data, sourcePath: String) throws -> [CodexLocalUsageEntry] {
        guard let text = String(data: data, encoding: .utf8) else {
            return []
        }

        var state = CodexLocalUsageParserState()
        var entries: [CodexLocalUsageEntry] = []
        text.enumerateLines { line, _ in
            if let entry = consume(
                lineData: Data(line.utf8),
                sourcePath: sourcePath,
                state: &state
            ) {
                entries.append(entry)
            }
        }
        return entries
    }

    static func consume(
        lineData: Data,
        sourcePath: String,
        state: inout CodexLocalUsageParserState
    ) -> CodexLocalUsageEntry? {
        state.parsedLineCount += 1
        return state.consume(
            lineData: lineData,
            sourcePath: sourcePath,
            lineNumber: state.parsedLineCount
        )
    }
}

private extension CodexLocalUsageParserState {
    mutating func consume(
        lineData: Data,
        sourcePath: String,
        lineNumber: Int
    ) -> CodexLocalUsageEntry? {
        guard let raw = try? JSONDecoder().decode(RawLine.self, from: lineData) else {
            return nil
        }

        if raw.type == "session_meta" {
            sessionID = raw.payload.id?.boundedNonEmpty(maxCharacters: 512) ?? sessionID
            projectPath = raw.payload.cwd?.boundedNonEmpty(maxCharacters: 1_024) ?? projectPath
            return nil
        }

        if raw.type == "turn_context" {
            let nextTurnID = raw.payload.turnID?.boundedNonEmpty(maxCharacters: 512) ?? turnID
            if nextTurnID != turnID {
                currentTurnCommandCount = 0
            }
            turnID = nextTurnID
            projectPath = raw.payload.cwd?.boundedNonEmpty(maxCharacters: 1_024) ?? projectPath
            model = raw.payload.model?.boundedNonEmpty(maxCharacters: 256) ?? model
            return nil
        }

        if raw.payload.type == "exec_command_end",
           let currentTurn = raw.payload.turnID?.boundedNonEmpty(maxCharacters: 512) ?? turnID {
            if currentTurn != turnID {
                turnID = currentTurn
                currentTurnCommandCount = 0
            }
            currentTurnCommandCount = codexSaturatingNonnegativeAdd(currentTurnCommandCount, 1)
            projectPath = raw.payload.cwd?.boundedNonEmpty(maxCharacters: 1_024) ?? projectPath
            return nil
        }

        guard raw.payload.type == "token_count",
              let timestamp = parseDate(raw.timestamp),
              let usage = raw.payload.info?.lastTokenUsage,
              usage.hasAnyTokens else {
            return nil
        }

        let entryTurnID = raw.payload.turnID?.boundedNonEmpty(maxCharacters: 512) ?? turnID
        let entrySessionID = raw.payload.sessionID?.boundedNonEmpty(maxCharacters: 512)
            ?? sessionID
            ?? sessionIDFromSourcePath(sourcePath)
            ?? "\(sourcePath)#\(lineNumber)"
        let entryProjectPath = raw.payload.cwd?.boundedNonEmpty(maxCharacters: 1_024) ?? projectPath
        let entryModel = raw.payload.model?.boundedNonEmpty(maxCharacters: 256) ?? model ?? "unknown"
        let commandCount = entryTurnID == turnID ? currentTurnCommandCount : 0
        let contextWindowPercent = raw.payload.info?.modelContextWindow.flatMap { window -> Double? in
            guard window > 0 else { return nil }
            return min(100, (Double(usage.tokens.totalTokens) / Double(window)) * 100)
        }

        let rawRateLimits = raw.payload.rateLimits ?? raw.rateLimits
        let rateLimits = rawRateLimits?.summary(contextWindowPercent: contextWindowPercent)
            ?? contextWindowPercent.map {
                CodexLocalRateLimits(primary: nil, secondary: nil, planType: nil, contextWindowPercent: $0)
            }

        return CodexLocalUsageEntry(
            id: "\(sourcePath)#\(lineNumber)",
            timestamp: timestamp,
            sessionID: entrySessionID,
            turnID: entryTurnID,
            projectPath: entryProjectPath,
            model: entryModel,
            tokens: usage.tokens,
            sourcePath: sourcePath,
            commandCount: commandCount,
            rateLimits: rateLimits
        )
    }

    private func sessionIDFromSourcePath(_ sourcePath: String) -> String? {
        let last = URL(fileURLWithPath: sourcePath).lastPathComponent
        guard last.hasSuffix(".jsonl") else { return nil }
        return String(last.dropLast(".jsonl".count)).boundedNonEmpty(maxCharacters: 512)
    }

    private func parseDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        let fractionalISO8601 = ISO8601DateFormatter()
        fractionalISO8601.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractionalISO8601.date(from: value) {
            return date
        }
        let plainISO8601 = ISO8601DateFormatter()
        return plainISO8601.date(from: value)
    }

}

private struct RawLine: Decodable {
    let timestamp: String?
    let type: String?
    let payload: RawPayload
    let rateLimits: RawRateLimits?

    enum CodingKeys: String, CodingKey {
        case timestamp
        case type
        case payload
        case rateLimits = "rate_limits"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        timestamp = try container.decodeIfPresent(String.self, forKey: .timestamp)
        type = try container.decodeIfPresent(String.self, forKey: .type)
        payload = try container.decodeIfPresent(RawPayload.self, forKey: .payload) ?? RawPayload()
        rateLimits = try container.decodeIfPresent(RawRateLimits.self, forKey: .rateLimits)
    }
}

private struct RawPayload: Decodable {
    let id: String?
    let type: String?
    let sessionID: String?
    let turnID: String?
    let cwd: String?
    let model: String?
    let info: RawInfo?
    let rateLimits: RawRateLimits?

    init(
        id: String? = nil,
        type: String? = nil,
        sessionID: String? = nil,
        turnID: String? = nil,
        cwd: String? = nil,
        model: String? = nil,
        info: RawInfo? = nil,
        rateLimits: RawRateLimits? = nil
    ) {
        self.id = id
        self.type = type
        self.sessionID = sessionID
        self.turnID = turnID
        self.cwd = cwd
        self.model = model
        self.info = info
        self.rateLimits = rateLimits
    }

    enum CodingKeys: String, CodingKey {
        case id
        case type
        case sessionID = "session_id"
        case turnID = "turn_id"
        case cwd
        case model
        case info
        case rateLimits = "rate_limits"
    }
}

private struct RawInfo: Decodable {
    let lastTokenUsage: RawTokenUsage?
    let modelContextWindow: Int?

    enum CodingKeys: String, CodingKey {
        case lastTokenUsage = "last_token_usage"
        case modelContextWindow = "model_context_window"
    }
}

private struct RawTokenUsage: Decodable {
    let inputTokens: Int?
    let cachedInputTokens: Int?
    let outputTokens: Int?
    let reasoningOutputTokens: Int?
    let totalTokens: Int?

    var hasAnyTokens: Bool {
        tokens.totalTokens > 0
    }

    var tokens: CodexLocalTokenUsage {
        let output = outputTokens ?? 0
        let input = inputTokens ?? 0
        let total = totalTokens ?? codexSaturatingNonnegativeAdd(input, output)
        return CodexLocalTokenUsage(
            inputTokens: input,
            cachedInputTokens: cachedInputTokens ?? 0,
            outputTokens: output,
            reasoningOutputTokens: reasoningOutputTokens ?? 0,
            totalTokens: total
        )
    }

    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case cachedInputTokens = "cached_input_tokens"
        case outputTokens = "output_tokens"
        case reasoningOutputTokens = "reasoning_output_tokens"
        case totalTokens = "total_tokens"
    }
}

private struct RawRateLimits: Decodable {
    let primary: RawRateLimitWindow?
    let secondary: RawRateLimitWindow?
    let planType: String?

    func summary(contextWindowPercent: Double?) -> CodexLocalRateLimits {
        CodexLocalRateLimits(
            primary: primary?.summary,
            secondary: secondary?.summary,
            planType: planType?.boundedNonEmpty(maxCharacters: 128),
            contextWindowPercent: contextWindowPercent
        )
    }

    enum CodingKeys: String, CodingKey {
        case primary
        case secondary
        case planType = "plan_type"
    }
}

private struct RawRateLimitWindow: Decodable {
    let usedPercent: Double?
    let windowMinutes: Int?
    let resetsAt: Double?

    var summary: CodexLocalRateLimitWindow {
        CodexLocalRateLimitWindow(
            usedPercent: usedPercent ?? 0,
            windowMinutes: windowMinutes,
            resetsAt: resetsAt.map(Date.init(timeIntervalSince1970:))
        )
    }

    enum CodingKeys: String, CodingKey {
        case usedPercent = "used_percent"
        case windowMinutes = "window_minutes"
        case resetsAt = "resets_at"
    }
}

private extension String {
    func boundedNonEmpty(maxCharacters: Int) -> String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false, trimmed.count <= maxCharacters else { return nil }
        return trimmed
    }
}
