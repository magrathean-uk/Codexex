#if os(macOS)
import Foundation
import CodexMeterCore

protocol CodexLocalUsageProviding: Sendable {
    func fetchLocalUsageSummary() async -> CodexLocalUsageSummary?
}

struct CodexLocalUsageProvider: CodexLocalUsageProviding {
    var sessionsURL: URL?

    func fetchLocalUsageSummary() async -> CodexLocalUsageSummary? {
        let resolvedSessionsURL = sessionsURL ?? CodexAppSettings.codexSessionsURL
        return await Task.detached(priority: .utility) {
            try? CodexLocalUsageDirectoryReader.summary(
                in: resolvedSessionsURL,
                hooksInstalled: FileManager.default.fileExists(
                    atPath: FileManager.default.homeDirectoryForCurrentUser
                        .appending(path: ".codex", directoryHint: .isDirectory)
                        .appending(path: "hooks.json")
                        .path
                ),
                maximumFiles: CodexLocalUsageDirectoryReader.defaultMaximumFiles
            )
        }.value
    }
}
#endif
