import Foundation

public enum CodexLocalUsageDirectoryReader {
    public static let defaultMaximumFiles = 120

    public static func entries(
        in rootURL: URL,
        maximumFiles: Int? = nil
    ) throws -> [CodexLocalUsageEntry] {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var candidates: [SessionFileCandidate] = []
        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension == "jsonl" else { continue }
            let values = try fileURL.resourceValues(forKeys: [
                .isRegularFileKey,
                .contentModificationDateKey,
                .fileSizeKey
            ])
            guard values.isRegularFile == true else { continue }
            candidates.append(
                SessionFileCandidate(
                    url: fileURL,
                    modifiedAt: values.contentModificationDate ?? .distantPast,
                    size: values.fileSize ?? 0
                )
            )
        }

        let selected = candidates
            .sorted { lhs, rhs in
                if lhs.modifiedAt != rhs.modifiedAt {
                    return lhs.modifiedAt > rhs.modifiedAt
                }
                if lhs.size != rhs.size {
                    return lhs.size > rhs.size
                }
                return lhs.url.path < rhs.url.path
            }
            .prefix(maximumFiles ?? candidates.count)

        var entries: [CodexLocalUsageEntry] = []
        for candidate in selected {
            let fileURL = candidate.url
            let data = try Data(contentsOf: fileURL)
            entries.append(
                contentsOf: try CodexLocalUsageTranscriptParser.entries(
                    from: data,
                    sourcePath: fileURL.path
                )
            )
        }
        return entries.sorted { lhs, rhs in
            if lhs.timestamp != rhs.timestamp {
                return lhs.timestamp < rhs.timestamp
            }
            return lhs.id < rhs.id
        }
    }

    public static func summary(
        in rootURL: URL,
        capturedAt: Date = Date(),
        calendar: Calendar = .autoupdatingCurrent,
        hooksInstalled: Bool = false,
        maximumFiles: Int? = nil
    ) throws -> CodexLocalUsageSummary {
        let parsed = try entries(in: rootURL, maximumFiles: maximumFiles)
        let configReport = CodexLocalConfigDoctor.report(
            hasSessionData: parsed.isEmpty == false,
            hooksInstalled: hooksInstalled,
            configPath: defaultConfigURL().path,
            sessionsPath: rootURL.path
        )
        return CodexLocalUsageAggregator.snapshot(
            entries: parsed,
            dataPath: rootURL.path,
            capturedAt: capturedAt,
            calendar: calendar,
            configReport: configReport
        )
    }

    public static func defaultSessionsURL() -> URL {
        if let codexHome = ProcessInfo.processInfo.environment["CODEX_HOME"],
           codexHome.isEmpty == false {
            return URL(fileURLWithPath: codexHome).appending(path: "sessions", directoryHint: .isDirectory)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".codex", directoryHint: .isDirectory)
            .appending(path: "sessions", directoryHint: .isDirectory)
    }

    public static func defaultConfigURL() -> URL {
        if let codexHome = ProcessInfo.processInfo.environment["CODEX_HOME"],
           codexHome.isEmpty == false {
            return URL(fileURLWithPath: codexHome).appending(path: "config.toml")
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".codex", directoryHint: .isDirectory)
            .appending(path: "config.toml")
    }
}

private struct SessionFileCandidate {
    let url: URL
    let modifiedAt: Date
    let size: Int
}
