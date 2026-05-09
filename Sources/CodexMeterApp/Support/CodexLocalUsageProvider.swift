#if os(macOS)
import Foundation
import CodexMeterCore

protocol CodexLocalUsageProviding: Sendable {
    func fetchLocalUsageSummary() async -> CodexLocalUsageSummary?
}

struct CodexLocalUsageProvider: CodexLocalUsageProviding {
    var sessionsURL: URL?

    func fetchLocalUsageSummary() async -> CodexLocalUsageSummary? {
        let bookmarkURL = sessionsURL == nil ? CodexAppSettings.codexSessionsSecurityScopedURL() : nil
        let resolvedSessionsURL = sessionsURL ?? bookmarkURL ?? CodexAppSettings.codexSessionsURL
        return await Task.detached(priority: .utility) {
            let hasScopedAccess = bookmarkURL?.startAccessingSecurityScopedResource() ?? false
            defer {
                if hasScopedAccess {
                    bookmarkURL?.stopAccessingSecurityScopedResource()
                }
            }
            return try? CodexLocalUsageDirectoryReader.summary(
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
