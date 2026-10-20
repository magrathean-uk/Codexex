import Foundation

/// Display-only data. Credentials, account identifiers and local paths never cross into the widget.
public struct MonitoringWidgetSnapshot: Codable, Equatable, Sendable {
    public static let schemaVersion = 1
    public static let freshnessInterval: TimeInterval = 30 * 60
    public let version: Int
    public let weeklyPercentLeft: Int?
    public let fiveHourPercentLeft: Int?
    public let weeklyResetAt: Date?
    public let fiveHourResetAt: Date?
    public let quotaUpdatedAt: Date?
    public let quotaStale: Bool
    public let apiRemainingUSD: Decimal?
    public let apiUpdatedAt: Date?
    public let apiStale: Bool
    public let isPreview: Bool

    public init(snapshot: CodexSnapshot? = nil, quotaStale: Bool = false,
                apiRemainingUSD: Decimal? = nil, apiUpdatedAt: Date? = nil,
                apiStale: Bool = false, isPreview: Bool = false) {
        version = Self.schemaVersion
        let weekly = snapshot?.codexLimit?.weeklyWindow
        let fiveHour = snapshot?.codexLimit?.fiveHourWindow
        weeklyPercentLeft = weekly.flatMap { $0.remainingPercent.isFinite ? Int($0.remainingPercent.rounded()) : nil }
        fiveHourPercentLeft = fiveHour.flatMap { $0.remainingPercent.isFinite ? Int($0.remainingPercent.rounded()) : nil }
        weeklyResetAt = weekly?.resetsAt
        fiveHourResetAt = fiveHour?.resetsAt
        quotaUpdatedAt = weeklyPercentLeft == nil && fiveHourPercentLeft == nil ? nil : snapshot?.capturedAt
        self.quotaStale = quotaStale
        self.apiRemainingUSD = apiRemainingUSD
        self.apiUpdatedAt = apiUpdatedAt
        self.apiStale = apiStale
        self.isPreview = isPreview
    }

    public static let empty = Self()

    public func quotaIsStale(at now: Date) -> Bool {
        quotaStale || isExpired(quotaUpdatedAt, at: now)
            || [weeklyResetAt, fiveHourResetAt].compactMap { $0 }.contains { $0 <= now }
    }

    public func apiIsStale(at now: Date) -> Bool { apiStale || isExpired(apiUpdatedAt, at: now) }

    private func isExpired(_ date: Date?, at now: Date) -> Bool {
        guard let date else { return true }
        return now.timeIntervalSince(date) >= Self.freshnessInterval || date > now.addingTimeInterval(60)
    }

    public var isValid: Bool {
        guard version == Self.schemaVersion,
              [weeklyPercentLeft, fiveHourPercentLeft].compactMap({ $0 }).allSatisfy({ (0...100).contains($0) }),
              [weeklyResetAt, fiveHourResetAt, quotaUpdatedAt, apiUpdatedAt].compactMap({ $0 }).allSatisfy({ $0.timeIntervalSince1970.isFinite }),
              weeklyPercentLeft == nil || quotaUpdatedAt != nil,
              fiveHourPercentLeft == nil || quotaUpdatedAt != nil else { return false }
        if let amount = apiRemainingUSD {
            return !amount.isNaN && amount >= 0 && apiUpdatedAt != nil
        }
        return true
    }
}

public struct MonitoringWidgetStore: Sendable {
    public static let appGroup = "group.com.magrathean.CodexexApp"
    public static let quotaKind = "CodexexSubscriptionQuota"
    public static let apiKind = "CodexexAPIBalance"
    private let directory: URL?
    private var file: URL? { directory?.appendingPathComponent("monitoring-widget.json") }

    public init(directory: URL? = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Self.appGroup)) {
        self.directory = directory
    }

    public func load() -> MonitoringWidgetSnapshot? {
        guard let file, let data = try? Data(contentsOf: file), data.count <= 16_384,
              let value = try? JSONDecoder().decode(MonitoringWidgetSnapshot.self, from: data), value.isValid else { return nil }
        return value
    }

    /// Returns false when the App Group is unavailable, rather than writing to a fallback location.
    @discardableResult public func save(_ value: MonitoringWidgetSnapshot) throws -> Bool {
        guard let file, value.isValid else { return false }
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(value)
        #if os(iOS)
        try data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try data.write(to: file, options: .atomic)
        #endif
        return true
    }

    @discardableResult public func clear() throws -> Bool { try save(.empty) }
}
