#if os(macOS)
import Foundation
import CodexMeterCore

struct CodexUsageHistorySample: Codable, Identifiable, Sendable, Equatable {
    let id: UUID
    let capturedAt: Date
    let fiveHour: CodexUsageHistoryWindow?
    let weekly: CodexUsageHistoryWindow?
    let codexCreditsBalance: String?
    let sparkCreditsBalance: String?

    init(
        id: UUID = UUID(),
        capturedAt: Date,
        fiveHour: CodexUsageHistoryWindow?,
        weekly: CodexUsageHistoryWindow?,
        codexCreditsBalance: String? = nil,
        sparkCreditsBalance: String? = nil
    ) {
        self.id = id
        self.capturedAt = capturedAt
        self.fiveHour = fiveHour
        self.weekly = weekly
        self.codexCreditsBalance = codexCreditsBalance
        self.sparkCreditsBalance = sparkCreditsBalance
    }
}

struct CodexUsageHistoryWindow: Codable, Sendable, Equatable {
    let usedPercent: Double
    let windowDurationMinutes: Int?
    let resetsAt: Date?

    init(usedPercent: Double, windowDurationMinutes: Int?, resetsAt: Date?) {
        self.usedPercent = usedPercent
        self.windowDurationMinutes = windowDurationMinutes
        self.resetsAt = resetsAt
    }

    init(from window: CodexQuotaWindow) {
        self.usedPercent = window.usedPercent
        self.windowDurationMinutes = window.windowDurationMinutes
        self.resetsAt = window.resetsAt
    }
}

actor CodexUsageHistoryStore {
    private let fileURL: URL
    private let retention: TimeInterval = 180 * 24 * 60 * 60
    private let futureTolerance: TimeInterval = 5 * 60

    init(fileManager: FileManager = .default, fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
            return
        }

        let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        let directory = applicationSupport.appendingPathComponent("Codexex", isDirectory: true)
        self.fileURL = directory.appendingPathComponent("usage-history.json")
    }

    func load(now: Date = Date()) async -> [CodexUsageHistorySample] {
        do {
            let data = try Data(contentsOf: self.fileURL)
            let samples = try JSONDecoder.codexHistoryDecoder.decode([CodexUsageHistorySample].self, from: data)
            return self.trim(samples, now: now)
        } catch {
            return []
        }
    }

    func append(snapshot: CodexSnapshot, now: Date = Date()) async -> [CodexUsageHistorySample] {
        var samples = await self.load(now: now)
        let fiveHour = snapshot.codexLimit?.fiveHourWindow.map(CodexUsageHistoryWindow.init(from:))
        let weekly = snapshot.codexLimit?.weeklyWindow.map(CodexUsageHistoryWindow.init(from:))
        let codexCreditsBalance = snapshot.codexLimit?.credits?.balance
        let sparkCreditsBalance = snapshot.sparkLimit?.credits?.balance
        guard fiveHour != nil || weekly != nil else { return samples }

        let newSample = CodexUsageHistorySample(
            capturedAt: snapshot.capturedAt,
            fiveHour: fiveHour,
            weekly: weekly,
            codexCreditsBalance: codexCreditsBalance,
            sparkCreditsBalance: sparkCreditsBalance
        )

        if shouldSkipAppend(existing: samples.last, incoming: newSample) {
            return samples
        }

        samples.append(newSample)
        samples = self.trim(samples, now: now)
        self.save(samples)
        return samples
    }

    private func shouldSkipAppend(
        existing: CodexUsageHistorySample?,
        incoming: CodexUsageHistorySample
    ) -> Bool {
        guard let existing else { return false }
        guard existing.fiveHour == incoming.fiveHour,
              existing.weekly == incoming.weekly,
              existing.codexCreditsBalance == incoming.codexCreditsBalance,
              existing.sparkCreditsBalance == incoming.sparkCreditsBalance else {
            return false
        }
        return abs(existing.capturedAt.timeIntervalSince(incoming.capturedAt)) < 60
    }

    private func save(_ samples: [CodexUsageHistorySample]) {
        do {
            try FileManager.default.createDirectory(
                at: self.fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder.codexHistoryEncoder.encode(samples)
            try data.write(to: self.fileURL, options: [.atomic])
        } catch {
            return
        }
    }

    private func trim(_ samples: [CodexUsageHistorySample], now: Date) -> [CodexUsageHistorySample] {
        let cutoff = now.addingTimeInterval(-self.retention)
        let futureCutoff = now.addingTimeInterval(self.futureTolerance)
        return samples
            .filter { $0.capturedAt >= cutoff && $0.capturedAt <= futureCutoff }
            .sorted { $0.capturedAt < $1.capturedAt }
    }
}

private extension JSONDecoder {
    static var codexHistoryDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

private extension JSONEncoder {
    static var codexHistoryEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}
#endif
