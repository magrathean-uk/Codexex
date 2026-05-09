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
            inputTokens: inputTokens + other.inputTokens,
            cachedInputTokens: cachedInputTokens + other.cachedInputTokens,
            outputTokens: outputTokens + other.outputTokens,
            reasoningOutputTokens: reasoningOutputTokens + other.reasoningOutputTokens,
            totalTokens: totalTokens + other.totalTokens
        )
    }
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

    public init(
        primary: CodexLocalRateLimitWindow?,
        secondary: CodexLocalRateLimitWindow?,
        planType: String?
    ) {
        self.primary = primary
        self.secondary = secondary
        self.planType = planType
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
        contextWindowPercent: Double?
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
    }
}

public struct CodexLocalUsageFileState: Codable, Sendable, Equatable {
    public let path: String
    public let inode: UInt64
    public let size: UInt64
    public let modifiedAt: Date

    public init(path: String, inode: UInt64, size: UInt64, modifiedAt: Date) {
        self.path = path
        self.inode = inode
        self.size = size
        self.modifiedAt = modifiedAt
    }
}

public enum CodexLocalUsageReadPlan: Sendable, Equatable {
    case skip
    case fullRead
    case append(fromOffset: UInt64)
}
