import Foundation

public struct CodexLocalTokenUsage: Codable, Sendable, Equatable {
    public let inputTokens: Int
    public let cachedInputTokens: Int
    public let outputTokens: Int
    public let reasoningOutputTokens: Int
    public let totalTokens: Int

    public init(
        inputTokens: Int,
        cachedInputTokens: Int,
        outputTokens: Int,
        reasoningOutputTokens: Int,
        totalTokens: Int
    ) {
        self.inputTokens = max(0, inputTokens)
        self.cachedInputTokens = max(0, cachedInputTokens)
        self.outputTokens = max(0, outputTokens)
        self.reasoningOutputTokens = max(0, reasoningOutputTokens)
        self.totalTokens = max(0, totalTokens)
    }

    public static let zero = CodexLocalTokenUsage(
        inputTokens: 0,
        cachedInputTokens: 0,
        outputTokens: 0,
        reasoningOutputTokens: 0,
        totalTokens: 0
    )

    public var cacheHitRate: Double {
        guard inputTokens > 0 else { return 0 }
        return min(1, Double(cachedInputTokens) / Double(inputTokens))
    }

    public func adding(_ other: CodexLocalTokenUsage) -> CodexLocalTokenUsage {
        CodexLocalTokenUsage(
            inputTokens: codexSaturatingNonnegativeAdd(inputTokens, other.inputTokens),
            cachedInputTokens: codexSaturatingNonnegativeAdd(cachedInputTokens, other.cachedInputTokens),
            outputTokens: codexSaturatingNonnegativeAdd(outputTokens, other.outputTokens),
            reasoningOutputTokens: codexSaturatingNonnegativeAdd(reasoningOutputTokens, other.reasoningOutputTokens),
            totalTokens: codexSaturatingNonnegativeAdd(totalTokens, other.totalTokens)
        )
    }
}

@inline(__always)
func codexSaturatingNonnegativeAdd(_ lhs: Int, _ rhs: Int) -> Int {
    let safeLHS = max(0, lhs)
    let safeRHS = max(0, rhs)
    let (sum, overflow) = safeLHS.addingReportingOverflow(safeRHS)
    return overflow ? .max : sum
}

public struct CodexLocalRateLimitWindow: Codable, Sendable, Equatable {
    public let usedPercent: Double
    public let windowMinutes: Int?
    public let resetsAt: Date?

    public init(usedPercent: Double, windowMinutes: Int?, resetsAt: Date?) {
        self.usedPercent = usedPercent
        self.windowMinutes = windowMinutes
        self.resetsAt = resetsAt
    }
}

public struct CodexLocalRateLimits: Codable, Sendable, Equatable {
    public let primary: CodexLocalRateLimitWindow?
    public let secondary: CodexLocalRateLimitWindow?
    public let planType: String?
    public let contextWindowPercent: Double?

    public init(
        primary: CodexLocalRateLimitWindow?,
        secondary: CodexLocalRateLimitWindow?,
        planType: String?,
        contextWindowPercent: Double? = nil
    ) {
        self.primary = primary
        self.secondary = secondary
        self.planType = planType
        self.contextWindowPercent = contextWindowPercent
    }
}

public struct CodexLocalUsageEntry: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let timestamp: Date
    public let sessionID: String
    public let turnID: String?
    public let projectPath: String?
    public let model: String
    public let tokens: CodexLocalTokenUsage
    public let sourcePath: String
    public let commandCount: Int
    public let rateLimits: CodexLocalRateLimits?

    public init(
        id: String,
        timestamp: Date,
        sessionID: String,
        turnID: String?,
        projectPath: String?,
        model: String,
        tokens: CodexLocalTokenUsage,
        sourcePath: String,
        commandCount: Int,
        rateLimits: CodexLocalRateLimits?
    ) {
        self.id = id
        self.timestamp = timestamp
        self.sessionID = sessionID
        self.turnID = turnID
        self.projectPath = projectPath
        self.model = model
        self.tokens = tokens
        self.sourcePath = sourcePath
        self.commandCount = max(0, commandCount)
        self.rateLimits = rateLimits
    }
}

public struct CodexLocalUsagePeriodSummary: Codable, Sendable, Equatable {
    public let entryCount: Int
    public let totalTokens: Int
    public let inputTokens: Int
    public let cachedInputTokens: Int
    public let outputTokens: Int
    public let reasoningOutputTokens: Int

    public init(entryCount: Int, tokens: CodexLocalTokenUsage) {
        self.entryCount = entryCount
        totalTokens = tokens.totalTokens
        inputTokens = tokens.inputTokens
        cachedInputTokens = tokens.cachedInputTokens
        outputTokens = tokens.outputTokens
        reasoningOutputTokens = tokens.reasoningOutputTokens
    }
}

public struct CodexLocalSessionSummary: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let projectPath: String?
    public let latestModel: String
    public let startedAt: Date
    public let lastActivityAt: Date
    public let entryCount: Int
    public let commandCount: Int
    public let tokens: CodexLocalTokenUsage

    public init(
        id: String,
        projectPath: String?,
        latestModel: String,
        startedAt: Date,
        lastActivityAt: Date,
        entryCount: Int,
        commandCount: Int,
        tokens: CodexLocalTokenUsage
    ) {
        self.id = id
        self.projectPath = projectPath
        self.latestModel = latestModel
        self.startedAt = startedAt
        self.lastActivityAt = lastActivityAt
        self.entryCount = entryCount
        self.commandCount = commandCount
        self.tokens = tokens
    }
}

public struct CodexLocalProjectSummary: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let displayName: String
    public let path: String
    public let latestModel: String
    public let lastActivityAt: Date
    public let sessionCount: Int
    public let commandCount: Int
    public let tokens: CodexLocalTokenUsage

    public init(
        id: String,
        displayName: String,
        path: String,
        latestModel: String,
        lastActivityAt: Date,
        sessionCount: Int,
        commandCount: Int,
        tokens: CodexLocalTokenUsage
    ) {
        self.id = id
        self.displayName = displayName
        self.path = path
        self.latestModel = latestModel
        self.lastActivityAt = lastActivityAt
        self.sessionCount = sessionCount
        self.commandCount = commandCount
        self.tokens = tokens
    }
}

public struct CodexLocalModelSummary: Codable, Sendable, Equatable, Identifiable {
    public var id: String { model }
    public let model: String
    public let entryCount: Int
    public let tokens: CodexLocalTokenUsage

    public init(model: String, entryCount: Int, tokens: CodexLocalTokenUsage) {
        self.model = model
        self.entryCount = entryCount
        self.tokens = tokens
    }
}

public struct CodexLocalUsageBlock: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let startsAt: Date
    public let endsAt: Date
    public let tokens: CodexLocalTokenUsage
    public let entryCount: Int

    public init(id: String, startsAt: Date, endsAt: Date, tokens: CodexLocalTokenUsage, entryCount: Int) {
        self.id = id
        self.startsAt = startsAt
        self.endsAt = endsAt
        self.tokens = tokens
        self.entryCount = entryCount
    }
}

public enum CodexLocalWasteSignalKind: String, Codable, Sendable, Equatable {
    case highCacheRead
    case toolLoop
    case modelOverkill
    case heavySession
    case suddenSpike
}

public struct CodexLocalWasteSignal: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let kind: CodexLocalWasteSignalKind
    public let title: String
    public let detail: String

    public init(id: String, kind: CodexLocalWasteSignalKind, title: String, detail: String) {
        self.id = id
        self.kind = kind
        self.title = title
        self.detail = detail
    }
}

public enum CodexLocalConfigSeverity: String, Codable, Sendable, Equatable {
    case ok
    case warning
}

public enum CodexLocalConfigIssueKind: String, Codable, Sendable, Equatable {
    case missingSessionData
    case hooksNotInstalled
    case staleSessionData
}

public struct CodexLocalConfigIssue: Codable, Sendable, Equatable, Identifiable {
    public var id: String { kind.rawValue }
    public let kind: CodexLocalConfigIssueKind
    public let title: String
    public let detail: String

    public init(kind: CodexLocalConfigIssueKind, title: String, detail: String) {
        self.kind = kind
        self.title = title
        self.detail = detail
    }
}

public struct CodexLocalConfigReport: Codable, Sendable, Equatable {
    public let severity: CodexLocalConfigSeverity
    public let issues: [CodexLocalConfigIssue]

    public init(severity: CodexLocalConfigSeverity, issues: [CodexLocalConfigIssue]) {
        self.severity = severity
        self.issues = issues
    }
}

public enum CodexLocalAttributionConfidenceLevel: String, Codable, Sendable, Equatable {
    case high
    case partial
    case unknown
}

public struct CodexLocalAttributionConfidence: Codable, Sendable, Equatable {
    public let level: CodexLocalAttributionConfidenceLevel
    public let title: String
    public let detail: String

    public init(level: CodexLocalAttributionConfidenceLevel, title: String, detail: String) {
        self.level = level
        self.title = title
        self.detail = detail
    }

    public static let unknown = CodexLocalAttributionConfidence(
        level: .unknown,
        title: "Unknown confidence",
        detail: "No local Codex session token rows were found."
    )
}

public struct CodexLocalSessionAutopsy: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let projectName: String?
    public let model: String
    public let tokens: CodexLocalTokenUsage
    public let totalSharePercent: Double
    public let commandCount: Int
    public let entryCount: Int
    public let lastActivityAt: Date

    public init(
        id: String,
        projectName: String?,
        model: String,
        tokens: CodexLocalTokenUsage,
        totalSharePercent: Double,
        commandCount: Int,
        entryCount: Int,
        lastActivityAt: Date
    ) {
        self.id = id
        self.projectName = projectName
        self.model = model
        self.tokens = tokens
        self.totalSharePercent = max(0, min(100, totalSharePercent))
        self.commandCount = max(0, commandCount)
        self.entryCount = max(0, entryCount)
        self.lastActivityAt = lastActivityAt
    }
}

public struct CodexLocalUsageSummary: Codable, Sendable, Equatable {
    public let capturedAt: Date
    public let dataPath: String
    public let total: CodexLocalUsagePeriodSummary
    public let today: CodexLocalUsagePeriodSummary
    public let week: CodexLocalUsagePeriodSummary
    public let sessions: [CodexLocalSessionSummary]
    public let projects: [CodexLocalProjectSummary]
    public let modelSummaries: [CodexLocalModelSummary]
    public let fiveHourBlocks: [CodexLocalUsageBlock]
    public let wasteSignals: [CodexLocalWasteSignal]
    public let configReport: CodexLocalConfigReport
    public let latestProjectName: String?
    public let latestModel: String?
    public let contextWindowPercent: Double?
    public let sessionAutopsies: [CodexLocalSessionAutopsy]
    public let attributionConfidence: CodexLocalAttributionConfidence
    public let coverage: CodexLocalUsageCoverage

    public init(
        capturedAt: Date,
        dataPath: String,
        total: CodexLocalUsagePeriodSummary,
        today: CodexLocalUsagePeriodSummary,
        week: CodexLocalUsagePeriodSummary,
        sessions: [CodexLocalSessionSummary],
        projects: [CodexLocalProjectSummary],
        modelSummaries: [CodexLocalModelSummary],
        fiveHourBlocks: [CodexLocalUsageBlock],
        wasteSignals: [CodexLocalWasteSignal],
        configReport: CodexLocalConfigReport,
        latestProjectName: String?,
        latestModel: String?,
        contextWindowPercent: Double?,
        sessionAutopsies: [CodexLocalSessionAutopsy] = [],
        attributionConfidence: CodexLocalAttributionConfidence = .unknown,
        coverage: CodexLocalUsageCoverage = .unknown
    ) {
        self.capturedAt = capturedAt
        self.dataPath = dataPath
        self.total = total
        self.today = today
        self.week = week
        self.sessions = sessions
        self.projects = projects
        self.modelSummaries = modelSummaries
        self.fiveHourBlocks = fiveHourBlocks
        self.wasteSignals = wasteSignals
        self.configReport = configReport
        self.latestProjectName = latestProjectName
        self.latestModel = latestModel
        self.contextWindowPercent = contextWindowPercent
        self.sessionAutopsies = sessionAutopsies
        self.attributionConfidence = attributionConfidence
        self.coverage = coverage
    }
}

public struct CodexLocalUsageCoverage: Codable, Sendable, Equatable {
    public let isKnown: Bool
    public let indexedFileCount: Int
    public let selectedFileCount: Int
    public let discoveredFileCount: Int
    public let bytesRead: UInt64
    public let retainedEntryCount: Int
    public let omittedEntryCount: Int

    public init(
        isKnown: Bool = true,
        indexedFileCount: Int,
        selectedFileCount: Int,
        discoveredFileCount: Int,
        bytesRead: UInt64,
        retainedEntryCount: Int = 0,
        omittedEntryCount: Int = 0
    ) {
        self.isKnown = isKnown
        self.indexedFileCount = max(0, indexedFileCount)
        self.selectedFileCount = max(0, selectedFileCount)
        self.discoveredFileCount = max(0, discoveredFileCount)
        self.bytesRead = bytesRead
        self.retainedEntryCount = max(0, retainedEntryCount)
        self.omittedEntryCount = max(0, omittedEntryCount)
    }

    public var isComplete: Bool {
        isKnown
            && isSelectedSetIndexed
            && selectedFileCount >= discoveredFileCount
            && omittedEntryCount == 0
    }

    public var isSelectedSetIndexed: Bool {
        isKnown && indexedFileCount >= selectedFileCount
    }

    public var label: String {
        guard isKnown else { return "Coverage unavailable" }
        guard discoveredFileCount > 0 else { return "No session files" }
        if omittedEntryCount > 0 {
            let retained = "Latest \(retainedEntryCount) rows"
            if isSelectedSetIndexed == false {
                return "Indexing \(indexedFileCount) of latest \(selectedFileCount) files · \(retained.lowercased())"
            }
            let allFiles = discoveredFileCount == 1 ? "1 file" : "\(discoveredFileCount) files"
            let fileScope = selectedFileCount >= discoveredFileCount
                ? allFiles
                : "\(selectedFileCount) of \(discoveredFileCount) files"
            return "\(retained) · \(fileScope)"
        }
        return isComplete
            ? "All \(discoveredFileCount) files"
            : isSelectedSetIndexed
                ? "Latest \(selectedFileCount) of \(discoveredFileCount) files"
                : "Indexing \(indexedFileCount) of latest \(selectedFileCount) files"
    }

    private enum CodingKeys: String, CodingKey {
        case isKnown
        case indexedFileCount
        case selectedFileCount
        case discoveredFileCount
        case bytesRead
        case retainedEntryCount
        case omittedEntryCount
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            isKnown: try values.decodeIfPresent(Bool.self, forKey: .isKnown) ?? true,
            indexedFileCount: try values.decode(Int.self, forKey: .indexedFileCount),
            selectedFileCount: try values.decode(Int.self, forKey: .selectedFileCount),
            discoveredFileCount: try values.decode(Int.self, forKey: .discoveredFileCount),
            bytesRead: try values.decode(UInt64.self, forKey: .bytesRead),
            retainedEntryCount: try values.decodeIfPresent(Int.self, forKey: .retainedEntryCount) ?? 0,
            omittedEntryCount: try values.decodeIfPresent(Int.self, forKey: .omittedEntryCount) ?? 0
        )
    }

    public static let unknown = CodexLocalUsageCoverage(
        isKnown: false,
        indexedFileCount: 0,
        selectedFileCount: 0,
        discoveredFileCount: 0,
        bytesRead: 0
    )
}

public struct CodexLocalUsageParserState: Codable, Sendable, Equatable {
    public var sessionID: String?
    public var projectPath: String?
    public var model: String?
    public var turnID: String?
    public var currentTurnCommandCount: Int
    public var parsedLineCount: Int
    public var isDiscardingOversizedLine: Bool
    public var pendingLineByteCount: Int
    public var hasParsedUnterminatedLine: Bool

    public init(
        sessionID: String? = nil,
        projectPath: String? = nil,
        model: String? = nil,
        turnID: String? = nil,
        currentTurnCommandCount: Int = 0,
        parsedLineCount: Int = 0,
        isDiscardingOversizedLine: Bool = false,
        pendingLineByteCount: Int = 0,
        hasParsedUnterminatedLine: Bool = false
    ) {
        self.sessionID = sessionID
        self.projectPath = projectPath
        self.model = model
        self.turnID = turnID
        self.currentTurnCommandCount = max(0, currentTurnCommandCount)
        self.parsedLineCount = max(0, parsedLineCount)
        self.isDiscardingOversizedLine = isDiscardingOversizedLine
        self.pendingLineByteCount = max(0, pendingLineByteCount)
        self.hasParsedUnterminatedLine = hasParsedUnterminatedLine
    }
}

public struct CodexLocalUsageFileState: Codable, Sendable, Equatable {
    public let path: String
    public let inode: UInt64
    public let size: UInt64
    public let modifiedAt: Date
    public let appendFingerprint: String?

    public init(
        path: String,
        inode: UInt64,
        size: UInt64,
        modifiedAt: Date,
        appendFingerprint: String? = nil
    ) {
        self.path = path
        self.inode = inode
        self.size = size
        self.modifiedAt = modifiedAt
        self.appendFingerprint = appendFingerprint
    }
}

public enum CodexLocalUsageReadPlan: Sendable, Equatable {
    case skip
    case fullRead
    case append(fromOffset: UInt64)
}
