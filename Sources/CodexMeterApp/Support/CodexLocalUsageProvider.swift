#if os(macOS)
import Foundation
import CodexMeterCore

protocol CodexLocalUsageProviding: Sendable {
    func fetchLocalUsageSummary() async -> CodexLocalUsageFetchResult
}

enum CodexLocalUsageFetchResult: Sendable, Equatable {
    case available(CodexLocalUsageSummary)
    case unavailable(String)

    var summary: CodexLocalUsageSummary? {
        guard case .available(let summary) = self else { return nil }
        return summary
    }
}

struct CodexLocalUsageProvider: CodexLocalUsageProviding {
    let sessionsURL: URL?
    private let indexStore: CodexLocalUsageIndexStore

    init(sessionsURL: URL? = nil, indexURL: URL? = nil) {
        self.sessionsURL = sessionsURL
        let applicationSupportURL = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appending(path: "Library/Application Support", directoryHint: .isDirectory)
        let resolvedIndexURL = indexURL ?? applicationSupportURL
            .appending(path: "Codexex", directoryHint: .isDirectory)
            .appending(path: "local-usage-index-v2.json")
        indexStore = CodexLocalUsageIndexStore(
            fileURL: resolvedIndexURL,
            secureParentDirectory: indexURL == nil
        )
    }

    func fetchLocalUsageSummary() async -> CodexLocalUsageFetchResult {
        let hasStoredBookmark = sessionsURL == nil && CodexAppSettings.codexSessionsBookmark != nil
        let bookmarkURL = sessionsURL == nil ? CodexAppSettings.codexSessionsSecurityScopedURL() : nil
        if hasStoredBookmark, bookmarkURL == nil {
            return .unavailable("Sessions access expired. Choose the Codex sessions folder again.")
        }
        let resolvedSessionsURL = sessionsURL ?? bookmarkURL ?? CodexAppSettings.codexSessionsURL
        CodexLog.refresh.log(
            "local usage read start path=\(resolvedSessionsURL.path, privacy: .private(mask: .hash)) bookmarkStored=\(hasStoredBookmark, privacy: .public) bookmarkResolved=\((bookmarkURL != nil), privacy: .public)"
        )
        let hasScopedAccess = bookmarkURL?.startAccessingSecurityScopedResource() ?? false
        if bookmarkURL != nil, hasScopedAccess == false {
            return .unavailable("Codex sessions access was denied. Choose the folder again.")
        }
        defer {
            if hasScopedAccess {
                bookmarkURL?.stopAccessingSecurityScopedResource()
            }
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: resolvedSessionsURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return .unavailable("Codex sessions folder is unavailable. Choose the folder to enable local usage.")
        }
        do {
            let summary = try await indexStore.summary(
                in: resolvedSessionsURL,
                hooksInstalled: FileManager.default.fileExists(
                    atPath: FileManager.default.homeDirectoryForCurrentUser
                        .appending(path: ".codex", directoryHint: .isDirectory)
                        .appending(path: "hooks.json")
                        .path
                )
            )
            CodexLog.refresh.log(
                "local usage read success sessions=\(summary.sessions.count, privacy: .public) projects=\(summary.projects.count, privacy: .public) entries=\(summary.total.entryCount, privacy: .public) files=\(summary.coverage.indexedFileCount, privacy: .public)/\(summary.coverage.discoveredFileCount, privacy: .public) bytes=\(summary.coverage.bytesRead, privacy: .public)"
            )
            return .available(summary)
        } catch is CancellationError {
            return .unavailable("Local usage scan cancelled.")
        } catch {
            CodexLog.refresh.error(
                "local usage read failed path=\(resolvedSessionsURL.path, privacy: .private(mask: .hash)) message=\(error.localizedDescription, privacy: .private)"
            )
            return .unavailable("Local usage is unavailable. Check Sessions folder access.")
        }
    }
}
#endif
