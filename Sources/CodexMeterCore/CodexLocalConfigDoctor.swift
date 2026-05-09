import Foundation

public enum CodexLocalConfigDoctor {
    public static func report(
        hasSessionData: Bool,
        hooksInstalled: Bool,
        configPath: String,
        sessionsPath: String
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
