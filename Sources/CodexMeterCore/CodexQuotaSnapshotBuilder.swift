import Foundation

public struct CodexRawQuotaWindow: Sendable, Equatable {
    public let usedPercent: Double
    public let windowDurationMinutes: Int?
    public let resetsAt: Date?

    public init(usedPercent: Double, windowDurationMinutes: Int?, resetsAt: Date?) {
        self.usedPercent = usedPercent
        self.windowDurationMinutes = windowDurationMinutes
        self.resetsAt = resetsAt
    }
}

public struct CodexRawQuotaLimit: Sendable, Equatable {
    public let id: String
    public let rawLimitName: String?
    public let primary: CodexRawQuotaWindow?
    public let secondary: CodexRawQuotaWindow?
    public let credits: CodexCredits?

    public init(
        id: String,
        rawLimitName: String?,
        primary: CodexRawQuotaWindow?,
        secondary: CodexRawQuotaWindow?,
        credits: CodexCredits?
    ) {
        self.id = id
        self.rawLimitName = rawLimitName
        self.primary = primary
        self.secondary = secondary
        self.credits = credits
    }
}

public enum CodexQuotaSnapshotBuilder {
    public static func snapshot(
        capturedAt: Date,
        executablePath: String,
        account: CodexAccount,
        rawLimits: [CodexRawQuotaLimit]
    ) -> CodexSnapshot {
        CodexSnapshot(
            capturedAt: capturedAt,
            executablePath: executablePath,
            account: account,
            limits: rawLimits.compactMap(limit(from:))
        )
    }

    public static func limit(from rawLimit: CodexRawQuotaLimit) -> CodexLimit? {
        guard rawLimit.primary != nil || rawLimit.secondary != nil || rawLimit.credits != nil else {
            return nil
        }

        return CodexLimit(
            id: rawLimit.id,
            rawLimitName: rawLimit.rawLimitName,
            bucket: CodexLimitBucket.infer(limitId: rawLimit.id, limitName: rawLimit.rawLimitName),
            primary: rawLimit.primary.map(window(from:)),
            secondary: rawLimit.secondary.map(window(from:)),
            credits: rawLimit.credits
        )
    }

    private static func window(from rawWindow: CodexRawQuotaWindow) -> CodexQuotaWindow {
        CodexQuotaWindow(
            usedPercent: rawWindow.usedPercent,
            windowDurationMinutes: rawWindow.windowDurationMinutes,
            resetsAt: rawWindow.resetsAt
        )
    }
}
