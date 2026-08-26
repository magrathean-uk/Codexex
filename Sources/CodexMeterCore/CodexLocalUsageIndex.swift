import Foundation

public enum CodexLocalUsageIndex {
    public static let currentVersion = 5

    public static func plan(
        previous: CodexLocalUsageFileState?,
        current: CodexLocalUsageFileState
    ) -> CodexLocalUsageReadPlan {
        guard let previous else { return .fullRead }
        guard previous.inode == current.inode else { return .fullRead }
        if current.size < previous.size { return .fullRead }
        if current.size > previous.size {
            guard previous.appendFingerprint != nil else { return .fullRead }
            return .append(fromOffset: previous.size)
        }
        if current.modifiedAt != previous.modifiedAt { return .fullRead }
        return .skip
    }
}

public struct CodexLocalUsageIndexSnapshot: Codable, Sendable, Equatable {
    public let version: Int
    public let capturedAt: Date
    public let rootPath: String
    public let files: [String: CodexLocalUsageFileState]
    public let parserStates: [String: CodexLocalUsageParserState]
    public let entries: [CodexLocalUsageEntry]
    public let omittedEntryCountsByFile: [String: Int]

    public init(
        version: Int = CodexLocalUsageIndex.currentVersion,
        capturedAt: Date,
        rootPath: String = "",
        files: [String: CodexLocalUsageFileState],
        parserStates: [String: CodexLocalUsageParserState] = [:],
        entries: [CodexLocalUsageEntry],
        omittedEntryCountsByFile: [String: Int] = [:]
    ) {
        self.version = version
        self.capturedAt = capturedAt
        self.rootPath = rootPath
        self.files = files
        self.parserStates = parserStates
        self.entries = entries
        self.omittedEntryCountsByFile = omittedEntryCountsByFile.reduce(into: [:]) { result, pair in
            let count = max(0, pair.value)
            if count > 0 {
                result[pair.key] = count
            }
        }
    }
}

public actor CodexLocalUsageIndexStore {
    private static let maximumIndexBytes = 64 * 1_024 * 1_024
    private let fileURL: URL
    private let secureParentDirectory: Bool
    private var cachedSnapshot: CodexLocalUsageIndexSnapshot?
    private var didAttemptLoad = false

    public init(fileURL: URL, secureParentDirectory: Bool = false) {
        self.fileURL = fileURL
        self.secureParentDirectory = secureParentDirectory
    }

    public func load() -> CodexLocalUsageIndexSnapshot? {
        if didAttemptLoad {
            return cachedSnapshot
        }
        didAttemptLoad = true
        guard let data = try? CodexSecureAtomicFile.read(
            from: fileURL,
            maximumBytes: Self.maximumIndexBytes
        ) else {
            return nil
        }
        cachedSnapshot = try? decoder.decode(CodexLocalUsageIndexSnapshot.self, from: data)
        return cachedSnapshot
    }

    public func summary(
        in rootURL: URL,
        capturedAt: Date = Date(),
        calendar: Calendar = .autoupdatingCurrent,
        hooksInstalled: Bool = false,
        maximumFiles: Int = CodexLocalUsageDirectoryReader.defaultMaximumFiles,
        maximumBytes: UInt64 = CodexLocalUsageDirectoryReader.defaultMaximumBytesPerScan,
        maximumRetainedEntries: Int = CodexLocalUsageDirectoryReader.defaultMaximumRetainedEntries
    ) throws -> CodexLocalUsageSummary {
        let stored = load()
        let previous = stored?.version == CodexLocalUsageIndex.currentVersion
            && stored?.rootPath == rootURL.path ? stored : nil
        let result = try CodexLocalUsageDirectoryReader.incrementalSummary(
            in: rootURL,
            previous: previous,
            capturedAt: capturedAt,
            calendar: calendar,
            hooksInstalled: hooksInstalled,
            maximumFiles: maximumFiles,
            maximumBytes: maximumBytes,
            maximumRetainedEntries: maximumRetainedEntries
        )
        if let previous,
           result.index.rootPath == previous.rootPath,
           result.index.files == previous.files,
           result.index.parserStates == previous.parserStates,
           result.index.entries == previous.entries,
           result.index.omittedEntryCountsByFile == previous.omittedEntryCountsByFile {
            return result.summary
        }
        try save(result.index)
        return result.summary
    }

    public func save(_ snapshot: CodexLocalUsageIndexSnapshot) throws {
        let data = try encoder.encode(snapshot)
        guard data.count <= Self.maximumIndexBytes else {
            throw NSError(
                domain: "CodexLocalUsageIndexStore",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Local usage index exceeds its safe size limit."]
            )
        }
        try CodexSecureAtomicFile.write(
            data,
            to: fileURL,
            secureParentDirectory: secureParentDirectory
        )
        cachedSnapshot = snapshot
        didAttemptLoad = true
    }

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }()

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()
}
