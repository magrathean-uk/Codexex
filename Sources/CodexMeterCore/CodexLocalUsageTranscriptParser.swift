import Foundation

public enum CodexLocalUsageTranscriptParser {
    public static func entries(from data: Data, sourcePath: String) throws -> [CodexLocalUsageEntry] {
        guard let text = String(data: data, encoding: .utf8) else {
            return []
        }

        var state = ParseState(sourcePath: sourcePath)
        var entries: [CodexLocalUsageEntry] = []
        var lineNumber = 0
        text.enumerateLines { line, _ in
            lineNumber += 1
            if let entry = state.consume(lineData: Data(line.utf8), lineNumber: lineNumber) {
                entries.append(entry)
            }
        }
        return entries
    }
}

private struct ParseState {
    let sourcePath: String
    var sessionID: String?
    var cwd: String?
    var model: String?
    var turnID: String?
    var commandCountsByTurn: [String: Int] = [:]

    mutating func consume(lineData: Data, lineNumber: Int) -> CodexLocalUsageEntry? {
        guard let raw = try? decoder.decode(RawLine.self, from: lineData) else {
            return nil
        }

        if raw.type == "session_meta" {
            sessionID = raw.payload.id?.nilIfEmpty ?? sessionID
            cwd = raw.payload.cwd?.nilIfEmpty ?? cwd
            return nil
        }

        if raw.type == "turn_context" {
            turnID = raw.payload.turnID?.nilIfEmpty ?? turnID
            cwd = raw.payload.cwd?.nilIfEmpty ?? cwd
            model = raw.payload.model?.nilIfEmpty ?? model
            return nil
        }

        if raw.payload.type == "exec_command_end",
           let currentTurn = raw.payload.turnID?.nilIfEmpty ?? turnID {
            commandCountsByTurn[currentTurn, default: 0] += 1
            cwd = raw.payload.cwd?.nilIfEmpty ?? cwd
            return nil
        }

        guard raw.payload.type == "token_count",
              let timestamp = parseDate(raw.timestamp),
              let usage = raw.payload.info?.lastTokenUsage,
              usage.hasAnyTokens else {
            return nil
        }

        let entryTurnID = raw.payload.turnID?.nilIfEmpty ?? turnID
        let entrySessionID = raw.payload.sessionID?.nilIfEmpty
            ?? sessionID
            ?? sessionIDFromSourcePath(sourcePath)
            ?? "\(sourcePath)#\(lineNumber)"
        let entryProjectPath = raw.payload.cwd?.nilIfEmpty ?? cwd
        let entryModel = raw.payload.model?.nilIfEmpty ?? model ?? "unknown"
        let commandCount = entryTurnID.flatMap { commandCountsByTurn[$0] } ?? 0
        let contextWindowPercent = raw.payload.info?.modelContextWindow.flatMap { window -> Double? in
            guard window > 0 else { return nil }
            return min(100, (Double(usage.totalTokens ?? 0) / Double(window)) * 100)
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
            rateLimits: raw.payload.rateLimits?.summary(contextWindowPercent: contextWindowPercent)
        )
    }

    private func sessionIDFromSourcePath(_ sourcePath: String) -> String? {
        let last = URL(fileURLWithPath: sourcePath).lastPathComponent
        guard last.hasSuffix(".jsonl") else { return nil }
        return String(last.dropLast(".jsonl".count)).nilIfEmpty
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

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .useDefaultKeys
        return decoder
    }()
}

private struct RawLine: Decodable {
    let timestamp: String?
    let type: String?
    let payload: RawPayload

    enum CodingKeys: String, CodingKey {
        case timestamp
        case type
        case payload
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        timestamp = try container.decodeIfPresent(String.self, forKey: .timestamp)
        type = try container.decodeIfPresent(String.self, forKey: .type)
        payload = try container.decodeIfPresent(RawPayload.self, forKey: .payload) ?? RawPayload()
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
        let total = totalTokens ?? (input + output)
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

    func summary(contextWindowPercent _: Double?) -> CodexLocalRateLimits {
        CodexLocalRateLimits(
            primary: primary?.summary,
            secondary: secondary?.summary,
            planType: planType
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
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
