#if os(macOS)
import Foundation
import CodexMeterCore

struct CodexUsageHistorySample: Codable, Identifiable, Sendable, Equatable {
    let id: UUID
    let capturedAt: Date
    let fiveHour: CodexUsageHistoryWindow?
    let weekly: CodexUsageHistoryWindow?

    init(
        id: UUID = UUID(),
        capturedAt: Date,
        fiveHour: CodexUsageHistoryWindow?,
        weekly: CodexUsageHistoryWindow?
    ) {
        self.id = id
        self.capturedAt = capturedAt
        self.fiveHour = fiveHour
        self.weekly = weekly
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
    private let retention: TimeInterval = 30 * 24 * 60 * 60

    init(fileManager: FileManager = .default) {
        let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        let directory = applicationSupport.appendingPathComponent("Codexex", isDirectory: true)
        self.fileURL = directory.appendingPathComponent("usage-history.json")
    }

    func load() async -> [CodexUsageHistorySample] {
        do {
            let data = try Data(contentsOf: self.fileURL)
            let samples = try JSONDecoder.codexHistoryDecoder.decode([CodexUsageHistorySample].self, from: data)
            return self.trim(samples)
        } catch {
            return []
        }
    }

    func append(snapshot: CodexSnapshot) async -> [CodexUsageHistorySample] {
        var samples = await self.load()
        let fiveHour = snapshot.codexLimit?.fiveHourWindow.map(CodexUsageHistoryWindow.init(from:))
        let weekly = snapshot.codexLimit?.weeklyWindow.map(CodexUsageHistoryWindow.init(from:))
        guard fiveHour != nil || weekly != nil else { return samples }

        samples.append(
            CodexUsageHistorySample(
                capturedAt: snapshot.capturedAt,
                fiveHour: fiveHour,
                weekly: weekly
            )
        )
        samples = self.trim(samples)
        self.save(samples)
        return samples
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

    private func trim(_ samples: [CodexUsageHistorySample]) -> [CodexUsageHistorySample] {
        let cutoff = Date().addingTimeInterval(-self.retention)
        return samples
            .filter { $0.capturedAt >= cutoff }
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
