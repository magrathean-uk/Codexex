import Foundation
import CodexMeterCore

enum CodexiOSPreviewData {
    static func snapshot(now: Date = Date(), planType: String = "PLUS") -> CodexSnapshot {
        let fiveHourReset = Calendar.current.date(byAdding: .minute, value: 118, to: now)
        let weeklyReset = Calendar.current.date(byAdding: .day, value: 3, to: now)
        let isPro = CodexAccountTier(planType: planType) == .pro

        return CodexSnapshot(
            capturedAt: now,
            executablePath: "Codexex iOS Preview",
            account: CodexAccount(authType: "preview", email: "sample@codexex.local", planType: planType),
            limits: [
                CodexLimit(
                    id: "codex",
                    rawLimitName: "Codex",
                    bucket: .codex,
                    primary: isPro
                        ? CodexQuotaWindow(usedPercent: 40, windowDurationMinutes: 10_080, resetsAt: weeklyReset)
                        : CodexQuotaWindow(usedPercent: 24, windowDurationMinutes: 300, resetsAt: fiveHourReset),
                    secondary: isPro
                        ? nil
                        : CodexQuotaWindow(usedPercent: 68, windowDurationMinutes: 10_080, resetsAt: weeklyReset),
                    credits: CodexCredits(hasCredits: true, unlimited: false, balance: "12.50")
                )
            ]
        )
    }

    static func history(now: Date = Date()) -> [CodexUsageHistorySample] {
        (0..<30).compactMap { day -> CodexUsageHistorySample? in
            guard let date = Calendar.current.date(byAdding: .day, value: -29 + day, to: now) else {
                return nil
            }

            let weekly = min(100.0, 20.0 + Double(day) * 1.8 + sin(Double(day) / 3.0) * 5.0)
            let fiveHour = max(5.0, min(96.0, 20.0 + sin(Double(day) * 0.85) * 20.0 + Double(day % 5) * 4.0))

            return CodexUsageHistorySample(
                capturedAt: date,
                fiveHour: CodexUsageHistoryWindow(
                    usedPercent: fiveHour,
                    windowDurationMinutes: 300,
                    resetsAt: Calendar.current.date(byAdding: .minute, value: 100, to: date)
                ),
                weekly: CodexUsageHistoryWindow(
                    usedPercent: weekly,
                    windowDurationMinutes: 10_080,
                    resetsAt: Calendar.current.date(byAdding: .day, value: 4, to: date)
                ),
                codexCreditsBalance: String(format: "%.2f", max(0, 22.0 - (Double(day) * 0.32)))
            )
        }
    }
}
