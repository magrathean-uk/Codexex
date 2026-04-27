import Foundation
import CodexMeterCore

enum CodexiOSPreviewData {
    static func snapshot(now: Date = Date()) -> CodexSnapshot {
        let fiveHourReset = Calendar.current.date(byAdding: .minute, value: 118, to: now)
        let weeklyReset = Calendar.current.date(byAdding: .day, value: 3, to: now)
        let sparkFiveHourReset = Calendar.current.date(byAdding: .minute, value: 240, to: now)
        let sparkWeeklyReset = Calendar.current.date(byAdding: .day, value: 2, to: now)

        return CodexSnapshot(
            capturedAt: now,
            executablePath: "Codexex iOS Preview",
            account: CodexAccount(authType: "preview", email: "sample@codexex.local", planType: "PRO"),
            limits: [
                CodexLimit(
                    id: "codex",
                    rawLimitName: "Codex",
                    bucket: .codex,
                    primary: CodexQuotaWindow(usedPercent: 24, windowDurationMinutes: 300, resetsAt: fiveHourReset),
                    secondary: CodexQuotaWindow(usedPercent: 68, windowDurationMinutes: 10_080, resetsAt: weeklyReset),
                    credits: CodexCredits(hasCredits: true, unlimited: false, balance: "12.50")
                ),
                CodexLimit(
                    id: "spark",
                    rawLimitName: "Codex Spark",
                    bucket: .spark,
                    primary: CodexQuotaWindow(usedPercent: 8, windowDurationMinutes: 300, resetsAt: sparkFiveHourReset),
                    secondary: CodexQuotaWindow(usedPercent: 38, windowDurationMinutes: 10_080, resetsAt: sparkWeeklyReset)
                )
            ]
        )
    }
}
