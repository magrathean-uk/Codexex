import Foundation

public enum CodexLocalConfigDoctor {
    public static func report(
        hasSessionData: Bool,
        hooksInstalled: Bool,
        configPath: String,
        sessionsPath: String,
        latestSessionActivityAt: Date? = nil,
        now: Date = Date(),
        staleAfter: TimeInterval = 24 * 60 * 60
    ) -> CodexLocalConfigReport {
        var issues: [CodexLocalConfigIssue] = []

        if hasSessionData == false {
            issues.append(
                CodexLocalConfigIssue(
                    kind: .missingSessionData,
                    title: "No local sessions",
                    detail: "No Codex JSONL session data found at \(sessionsPath)."
                )
            )
        }

        if hasSessionData,
           let latestSessionActivityAt,
           now.timeIntervalSince(latestSessionActivityAt) > staleAfter {
            issues.append(
                CodexLocalConfigIssue(
                    kind: .staleSessionData,
                    title: "Stale local sessions",
                    detail: "No Codex token row has been seen in the last 24 hours."
                )
            )
        }

        if hooksInstalled == false {
            issues.append(
                CodexLocalConfigIssue(
                    kind: .hooksNotInstalled,
                    title: "Hooks not installed",
                    detail: "Install local Codexex hooks in \(configPath) for live tool and approval events."
                )
            )
        }

        return CodexLocalConfigReport(
            severity: issues.isEmpty ? .ok : .warning,
            issues: issues
        )
    }
}
