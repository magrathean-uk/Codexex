import Foundation

public struct CodexSnapshot: Sendable, Equatable, Codable {
    public let capturedAt: Date
    public let executablePath: String
    public let account: CodexAccount
    public let limits: [CodexLimit]

    public init(
        capturedAt: Date,
        executablePath: String,
        account: CodexAccount,
        limits: [CodexLimit]
    ) {
        self.capturedAt = capturedAt
        self.executablePath = executablePath
        self.account = account
        self.limits = limits.sorted {
            if $0.sortOrder != $1.sortOrder {
                return $0.sortOrder < $1.sortOrder
            }
            return $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    public var codexLimit: CodexLimit? {
        limits.first(where: { $0.bucket == .codex }) ?? limits.first
    }

    public var sparkLimit: CodexLimit? {
        limits.first(where: { $0.bucket == .spark })
    }
}

public struct CodexAccount: Sendable, Equatable, Codable {
    public let authType: String
    public let email: String?
    public let planType: String?

    public init(authType: String, email: String?, planType: String?) {
        self.authType = authType
        self.email = email
        self.planType = planType
    }

    public var displaySubtitle: String {
        let parts = [email, planType?.uppercased()].compactMap { value -> String? in
            guard let value, value.isEmpty == false else { return nil }
            return value
        }

        if parts.isEmpty {
            return authType
        }

        return parts.joined(separator: " · ")
    }
}

public struct CodexCredits: Sendable, Equatable, Codable {
    public let hasCredits: Bool
    public let unlimited: Bool
    public let balance: String?

    public init(hasCredits: Bool, unlimited: Bool, balance: String?) {
        self.hasCredits = hasCredits
        self.unlimited = unlimited
        self.balance = balance
    }

    public var displayText: String {
        if unlimited {
            return "Unlimited"
        }
        if let balance, balance.isEmpty == false {
            return balance
        }
        if hasCredits {
            return "Unavailable"
        }
        return "None"
    }

    public var isNegativeBalance: Bool {
        balance?.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("-") == true
    }
}

public enum CodexLimitBucket: String, Sendable, Codable, CaseIterable {
    case codex
    case spark
    case other

    public static func infer(limitId: String, limitName: String?) -> CodexLimitBucket {
        let haystack = "\(limitId) \(limitName ?? "")".lowercased()
        if haystack.contains("spark") {
            return .spark
        }
        if haystack.contains("codex") {
            return .codex
        }
        return .other
    }

    public var sortOrder: Int {
        switch self {
        case .codex: 0
        case .spark: 1
        case .other: 2
        }
    }
}

public struct CodexLimit: Sendable, Equatable, Codable, Identifiable {
    public let id: String
    public let rawLimitName: String?
    public let bucket: CodexLimitBucket
    public let primary: CodexQuotaWindow?
    public let secondary: CodexQuotaWindow?
    public let credits: CodexCredits?

    public init(
        id: String,
        rawLimitName: String?,
        bucket: CodexLimitBucket,
        primary: CodexQuotaWindow?,
        secondary: CodexQuotaWindow?,
        credits: CodexCredits? = nil
    ) {
        self.id = id
        self.rawLimitName = rawLimitName
        self.bucket = bucket
        self.primary = primary
        self.secondary = secondary
        self.credits = credits
    }

    public var displayName: String {
        switch bucket {
        case .codex:
            return "Codex"
        case .spark:
            return "Codex Spark"
        case .other:
            if let rawLimitName, rawLimitName.isEmpty == false {
                return rawLimitName
            }
            return id
        }
    }

    public var sortOrder: Int {
        bucket.sortOrder
    }

    public var fiveHourWindow: CodexQuotaWindow? {
        resolvedWindow(preferredMinutes: 300, fallback: primary ?? secondary)
    }

    public var weeklyWindow: CodexQuotaWindow? {
        resolvedWindow(preferredMinutes: 10_080, fallback: secondary ?? primary)
    }

    private func resolvedWindow(preferredMinutes: Int, fallback: CodexQuotaWindow?) -> CodexQuotaWindow? {
        if primary?.windowDurationMinutes == preferredMinutes {
            return primary
        }
        if secondary?.windowDurationMinutes == preferredMinutes {
            return secondary
        }
        return fallback
    }
}

public struct CodexQuotaWindow: Sendable, Equatable, Codable {
    public let usedPercent: Double
    public let windowDurationMinutes: Int?
    public let resetsAt: Date?

    public init(
        usedPercent: Double,
        windowDurationMinutes: Int?,
        resetsAt: Date?
    ) {
        self.usedPercent = usedPercent
        self.windowDurationMinutes = windowDurationMinutes
        self.resetsAt = resetsAt
    }

    public var clampedUsedPercent: Double {
        usedPercent.clamped(to: 0 ... 100)
    }

    public var remainingPercent: Double {
        (100 - clampedUsedPercent).clamped(to: 0 ... 100)
    }

    public var usedPercentText: String {
        "\(Int(clampedUsedPercent.rounded()))%"
    }

    public var remainingPercentText: String {
        "\(Int(remainingPercent.rounded()))%"
    }

    public var windowText: String {
        CodexFormatting.windowDuration(minutes: windowDurationMinutes)
    }
}

extension Double {
    fileprivate func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
