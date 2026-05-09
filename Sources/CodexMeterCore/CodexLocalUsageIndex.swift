import Foundation

public enum CodexLocalUsageIndex {
    public static func plan(
        previous: CodexLocalUsageFileState?,
        current: CodexLocalUsageFileState
    ) -> CodexLocalUsageReadPlan {
        guard let previous else { return .fullRead }
        guard previous.inode == current.inode else { return .fullRead }
        if current.size < previous.size { return .fullRead }
        if current.size > previous.size { return .append(fromOffset: previous.size) }
        if current.modifiedAt != previous.modifiedAt { return .fullRead }
        return .skip
    }
}

public struct CodexLocalUsageIndexSnapshot: Codable, Sendable, Equatable {
    public let version: Int
    public let capturedAt: Date
    public let files: [String: CodexLocalUsageFileState]
    public let entries: [CodexLocalUsageEntry]

    public init(
        version: Int = 1,
        capturedAt: Date,
        files: [String: CodexLocalUsageFileState],
        entries: [CodexLocalUsageEntry]
    ) {
        self.version = version
        self.capturedAt = capturedAt
        self.files = files
        self.entries = entries
    }
}

public actor CodexLocalUsageIndexStore {
    private let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func load() -> CodexLocalUsageIndexSnapshot? {
        guard let data = try? Data(contentsOf: fileURL) else {
            return nil
        }
        return try? decoder.decode(CodexLocalUsageIndexSnapshot.self, from: data)
    }

    public func save(_ snapshot: CodexLocalUsageIndexSnapshot) {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try encoder.encode(snapshot)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            return
        }
    }

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()
}
