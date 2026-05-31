#if os(macOS)
import Foundation
import CodexMeterCore

protocol CodexLocalUsageProviding: Sendable {
    func fetchLocalUsageSummary() async -> CodexLocalUsageSummary?
}

struct CodexLocalUsageProvider: CodexLocalUsageProviding {
    var sessionsURL: URL?

    func fetchLocalUsageSummary() async -> CodexLocalUsageSummary? {
        let hasStoredBookmark = sessionsURL == nil && CodexAppSettings.codexSessionsBookmark != nil
        let bookmarkURL = sessionsURL == nil ? CodexAppSettings.codexSessionsSecurityScopedURL() : nil
        let resolvedSessionsURL = sessionsURL ?? bookmarkURL ?? CodexAppSettings.codexSessionsURL
        return await Task.detached(priority: .utility) {
            CodexLog.refresh.log(
                "local usage read start path=\(resolvedSessionsURL.path, privacy: .public) bookmarkStored=\(hasStoredBookmark, privacy: .public) bookmarkResolved=\((bookmarkURL != nil), privacy: .public)"
            )
            let hasScopedAccess = bookmarkURL?.startAccessingSecurityScopedResource() ?? false
            defer {
                if hasScopedAccess {
                    bookmarkURL?.stopAccessingSecurityScopedResource()
                }
            }
            do {
                let summary = try CodexLocalUsageDirectoryReader.summary(
                    in: resolvedSessionsURL,
                    hooksInstalled: FileManager.default.fileExists(
                        atPath: FileManager.default.homeDirectoryForCurrentUser
                            .appending(path: ".codex", directoryHint: .isDirectory)
                            .appending(path: "hooks.json")
                            .path
                    ),
                    maximumFiles: CodexLocalUsageDirectoryReader.defaultMaximumFiles
                )
                CodexLog.refresh.log(
                    "local usage read success sessions=\(summary.sessions.count, privacy: .public) projects=\(summary.projects.count, privacy: .public) entries=\(summary.total.entryCount, privacy: .public)"
                )
                return summary
            } catch {
                CodexLog.refresh.error(
                    "local usage read failed path=\(resolvedSessionsURL.path, privacy: .public) message=\(error.localizedDescription, privacy: .public)"
                )
                return nil
            }
        }.value
    }
}
#endif
