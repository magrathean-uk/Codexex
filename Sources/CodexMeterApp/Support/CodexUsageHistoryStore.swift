import Darwin
import Foundation
import CodexMeterCore
import OSLog

private let codexUsageHistoryLog = Logger(
    subsystem: "com.magrathean.CodexexApp",
    category: "history"
)

private final class CodexUsageHistoryProcessLockRegistry: @unchecked Sendable {
    static let shared = CodexUsageHistoryProcessLockRegistry()

    private let registryLock = NSLock()
    private var locks: [String: NSLock] = [:]

    func lock(for path: String) -> NSLock {
        registryLock.lock()
        defer { registryLock.unlock() }
        if let existing = locks[path] { return existing }
        let created = NSLock()
        locks[path] = created
        return created
    }
}

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
    private let fileManager: FileManager
    private let fileURL: URL
    private let secureParentDirectory: Bool
    private let retention: TimeInterval = 90 * 24 * 60 * 60
    private let futureTolerance: TimeInterval = 5 * 60
    private let fullResolutionRetention: TimeInterval = 7 * 24 * 60 * 60
    private let compactedBucketDuration: TimeInterval = 30 * 60
    private let duplicateSampleInterval: TimeInterval = 15 * 60
    private let hardSampleCap = 10_000
    private let maximumHistoryFileBytes: UInt64 = 32 * 1_024 * 1_024
    private var persistenceFailureDescription: String?

    init(
        fileManager: FileManager = .default,
        fileURL: URL? = nil,
        secureParentDirectory: Bool? = nil
    ) {
        self.fileManager = fileManager
        self.secureParentDirectory = secureParentDirectory ?? (fileURL == nil)
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
            return try withExclusiveFileLock {
                let decoded = try readSamplesLocked()
                let trimmed = trim(decoded, now: now)
                if trimmed != decoded {
                    saveLocked(trimmed)
                } else {
                    persistenceFailureDescription = nil
                }
                return trimmed
            }
        } catch {
            recordPersistenceFailure(error, operation: "lock/load")
            return []
        }
    }

    func append(snapshot: CodexSnapshot, now: Date = Date()) async -> [CodexUsageHistorySample] {
        let fiveHour = snapshot.codexLimit?.fiveHourWindow.map(CodexUsageHistoryWindow.init(from:))
        let weekly = snapshot.codexLimit?.weeklyWindow.map(CodexUsageHistoryWindow.init(from:))
        let codexCreditsBalance = snapshot.codexLimit?.credits?.balance
        let sparkCreditsBalance = snapshot.sparkLimit?.credits?.balance
        guard fiveHour != nil || weekly != nil else { return await load(now: now) }

        let newSample = CodexUsageHistorySample(
            capturedAt: snapshot.capturedAt,
            fiveHour: fiveHour,
            weekly: weekly,
            codexCreditsBalance: codexCreditsBalance,
            sparkCreditsBalance: sparkCreditsBalance
        )

        do {
            return try withExclusiveFileLock {
                var samples = trim(try readSamplesLocked(), now: now)
                guard shouldSkipAppend(existing: samples.last, incoming: newSample) == false else {
                    persistenceFailureDescription = nil
                    return samples
                }

                samples.append(newSample)
                samples = trim(samples, now: now)
                saveLocked(samples)
                return samples
            }
        } catch {
            recordPersistenceFailure(error, operation: "lock/append")
            return trim([newSample], now: now)
        }
    }

    func invalidateCacheForTests() {}

    func persistenceFailure() -> String? {
        persistenceFailureDescription
    }

    func clear() throws {
        try withExclusiveFileLock {
            guard fileManager.fileExists(atPath: fileURL.path) else { return }
            try fileManager.removeItem(at: fileURL)
        }
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
        return abs(existing.capturedAt.timeIntervalSince(incoming.capturedAt)) < duplicateSampleInterval
    }

    private func readSamplesLocked() throws -> [CodexUsageHistorySample] {
        guard fileManager.fileExists(atPath: fileURL.path) else { return [] }
        let data = try readHistoryDataSafely()
        return try JSONDecoder.codexHistoryDecoder.decode([CodexUsageHistorySample].self, from: data)
    }

    private func saveLocked(_ samples: [CodexUsageHistorySample]) {
        do {
            let data = try JSONEncoder.codexHistoryEncoder.encode(samples)
            try CodexSecureAtomicFile.write(
                data,
                to: fileURL,
                secureParentDirectory: secureParentDirectory
            )
            persistenceFailureDescription = nil
        } catch {
            recordPersistenceFailure(error, operation: "save")
        }
    }

    private func withExclusiveFileLock<T>(_ operation: () throws -> T) throws -> T {
        // POSIX record locks coordinate processes, but record locks owned by
        // the same process do not block each other. Pair them with one
        // path-scoped process lock so separate store actors also merge safely.
        let processLock = CodexUsageHistoryProcessLockRegistry.shared.lock(
            for: fileURL.standardizedFileURL.path
        )
        processLock.lock()
        defer { processLock.unlock() }

        let directoryURL = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        if secureParentDirectory {
            try fileManager.setAttributes(
                [.posixPermissions: NSNumber(value: 0o700)],
                ofItemAtPath: directoryURL.path
            )
        }
        let lockURL = directoryURL.appendingPathComponent(".\(fileURL.lastPathComponent).lock")
        let descriptor: Int32 = lockURL.withUnsafeFileSystemRepresentation { path in
            guard let path else { return Int32(-1) }
            while true {
                let result = Darwin.open(path, O_RDWR | O_CREAT | O_CLOEXEC | O_NOFOLLOW, mode_t(0o600))
                if result < 0, errno == EINTR { continue }
                return result
            }
        }
        guard descriptor >= 0 else { throw historyPOSIXError("open history lock") }
        defer { _ = Darwin.close(descriptor) }
        guard Darwin.fchmod(descriptor, mode_t(0o600)) == 0 else {
            throw historyPOSIXError("secure history lock")
        }
        var lock = Darwin.flock(
            l_start: 0,
            l_len: 0,
            l_pid: 0,
            l_type: Int16(F_WRLCK),
            l_whence: Int16(SEEK_SET)
        )
        while Darwin.fcntl(descriptor, F_SETLKW, &lock) != 0 {
            guard errno == EINTR else { throw historyPOSIXError("lock history") }
        }
        defer {
            lock.l_type = Int16(F_UNLCK)
            while Darwin.fcntl(descriptor, F_SETLK, &lock) != 0, errno == EINTR {}
        }
        return try operation()
    }

    private func readHistoryDataSafely() throws -> Data {
        let descriptor: Int32 = fileURL.withUnsafeFileSystemRepresentation { path in
            guard let path else { return Int32(-1) }
            while true {
                let result = Darwin.open(path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
                if result < 0, errno == EINTR { continue }
                return result
            }
        }
        guard descriptor >= 0 else { throw historyPOSIXError("open history") }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        var fileInfo = stat()
        guard fstat(descriptor, &fileInfo) == 0 else {
            throw historyPOSIXError("inspect history")
        }
        guard fileInfo.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
              fileInfo.st_size >= 0,
              UInt64(fileInfo.st_size) <= maximumHistoryFileBytes else {
            throw NSError(
                domain: "CodexUsageHistoryStore",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Usage history is not a valid bounded file."]
            )
        }

        var data = Data()
        data.reserveCapacity(Int(fileInfo.st_size))
        while true {
            let remaining = Int(maximumHistoryFileBytes) + 1 - data.count
            guard remaining > 0 else {
                throw NSError(
                    domain: "CodexUsageHistoryStore",
                    code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "Usage history exceeds the size limit."]
                )
            }
            guard let chunk = try handle.read(upToCount: min(64 * 1_024, remaining)),
                  chunk.isEmpty == false else {
                break
            }
            data.append(chunk)
        }
        guard UInt64(data.count) <= maximumHistoryFileBytes else {
            throw NSError(
                domain: "CodexUsageHistoryStore",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Usage history exceeds the size limit."]
            )
        }
        return data
    }

    private func historyPOSIXError(_ operation: String) -> NSError {
        let code = errno
        return NSError(
            domain: NSPOSIXErrorDomain,
            code: Int(code),
            userInfo: [NSLocalizedDescriptionKey: "Could not \(operation)."]
        )
    }

    private func recordPersistenceFailure(_ error: Error, operation: String) {
        persistenceFailureDescription = error.localizedDescription
        codexUsageHistoryLog.error(
            "usage history \(operation, privacy: .public) failed message=\(error.localizedDescription, privacy: .private)"
        )
    }

    private func trim(_ samples: [CodexUsageHistorySample], now: Date) -> [CodexUsageHistorySample] {
        let cutoff = now.addingTimeInterval(-self.retention)
        let futureCutoff = now.addingTimeInterval(self.futureTolerance)
        var retained = samples.filter { $0.capturedAt >= cutoff && $0.capturedAt <= futureCutoff }
        if zip(retained, retained.dropFirst()).contains(where: { pair in
            pair.0.capturedAt > pair.1.capturedAt
        }) {
            retained.sort { $0.capturedAt < $1.capturedAt }
        }

        let fullResolutionCutoff = now.addingTimeInterval(-fullResolutionRetention)
        var compacted: [CodexUsageHistorySample] = []
        var bucket: [CodexUsageHistorySample] = []
        var bucketIndex: Int64?

        func flushBucket() {
            guard bucket.isEmpty == false else { return }
            let fiveHourPeak = bucket
                .filter { $0.fiveHour != nil }
                .max { ($0.fiveHour?.usedPercent ?? -1) < ($1.fiveHour?.usedPercent ?? -1) }
            let weeklyPeak = bucket
                .filter { $0.weekly != nil }
                .max { ($0.weekly?.usedPercent ?? -1) < ($1.weekly?.usedPercent ?? -1) }
            var peaks = [fiveHourPeak, weeklyPeak].compactMap { $0 }
            if peaks.isEmpty {
                peaks = [bucket[bucket.count - 1]]
            }
            var uniquePeaks: [CodexUsageHistorySample] = []
            var seenIDs = Set<UUID>()
            for peak in peaks.sorted(by: { $0.capturedAt < $1.capturedAt }) {
                guard uniquePeaks.contains(peak) == false else { continue }
                if seenIDs.insert(peak.id).inserted {
                    uniquePeaks.append(peak)
                } else {
                    uniquePeaks.append(
                        CodexUsageHistorySample(
                            id: UUID(),
                            capturedAt: peak.capturedAt,
                            fiveHour: peak.fiveHour,
                            weekly: peak.weekly,
                            codexCreditsBalance: peak.codexCreditsBalance,
                            sparkCreditsBalance: peak.sparkCreditsBalance
                        )
                    )
                }
            }
            compacted.append(contentsOf: uniquePeaks)
            bucket.removeAll(keepingCapacity: true)
        }

        for sample in retained {
            guard sample.capturedAt < fullResolutionCutoff else {
                flushBucket()
                bucketIndex = nil
                compacted.append(sample)
                continue
            }
            let index = Int64(floor(sample.capturedAt.timeIntervalSince1970 / compactedBucketDuration))
            if let bucketIndex, bucketIndex != index { flushBucket() }
            bucketIndex = index
            bucket.append(sample)
        }
        flushBucket()

        guard compacted.count > hardSampleCap else { return compacted }
        return Array(compacted.suffix(hardSampleCap))
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
