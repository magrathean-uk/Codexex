#if os(macOS)
import Foundation
import CodexMeterCore

enum CodexPreviewData {
    static func snapshot(now: Date = Date()) -> CodexSnapshot {
        let fiveHourReset = Calendar.current.date(byAdding: .minute, value: 262, to: now)
        let weeklyReset = Calendar.current.date(byAdding: .minute, value: 9_480, to: now)
        let sparkFiveHourReset = Calendar.current.date(byAdding: .minute, value: 299, to: now)
        let sparkWeeklyReset = Calendar.current.date(byAdding: .minute, value: 2_220, to: now)

        return CodexSnapshot(
            capturedAt: now,
            executablePath: "/Applications/Codexex.app/Contents/Helpers/codexex-helper",
            account: CodexAccount(
                authType: "preview",
                email: "reviewer@sample.invalid",
                planType: "PRO"
            ),
            limits: [
                CodexLimit(
                    id: "codex",
                    rawLimitName: "Codex",
                    bucket: .codex,
                    primary: CodexQuotaWindow(usedPercent: 8, windowDurationMinutes: 300, resetsAt: fiveHourReset),
                    secondary: CodexQuotaWindow(usedPercent: 5, windowDurationMinutes: 10_080, resetsAt: weeklyReset)
                ),
                CodexLimit(
                    id: "spark",
                    rawLimitName: "GPT-5.3-Codex-Spark",
                    bucket: .spark,
                    primary: CodexQuotaWindow(usedPercent: 0, windowDurationMinutes: 300, resetsAt: sparkFiveHourReset),
                    secondary: CodexQuotaWindow(usedPercent: 49, windowDurationMinutes: 10_080, resetsAt: sparkWeeklyReset)
                )
            ]
        )
    }

    static func history(now: Date = Date()) -> [CodexUsageHistorySample] {
        let days: [Int] = Array<Int>(unsafeUninitializedCapacity: 30) { buffer, count in
            for index in 0..<30 { buffer[index] = index }
            count = 30
        }

        return days.compactMap { day -> CodexUsageHistorySample? in
            guard let date = Calendar.current.date(byAdding: .day, value: -29 + day, to: now) else {
                return nil
            }

            let weeklyReference: [Double] = [
                56, 64, 68, 10, 26, 44, 61, 14, 62, 69,
                8, 18, 22, 24, 52, 21, 30, 34, 18, 35,
                72, 76, 4, 11, 22, 27, 36, 58, 70, 5
            ]
            let fiveHourReference: [Double] = [
                18, 10, 9, 14, 72, 76, 8, 16, 18, 12,
                14, 15, 7, 18, 16, 18, 21, 16, 18, 22,
                60, 59, 5, 14, 38, 7, 9, 33, 29, 8
            ]
            let weekly = weeklyReference[day]
            let fiveHour = fiveHourReference[day]

            return CodexUsageHistorySample(
                capturedAt: date,
                fiveHour: CodexUsageHistoryWindow(
                    usedPercent: fiveHour,
                    windowDurationMinutes: 300,
                    resetsAt: Calendar.current.date(byAdding: .minute, value: 90, to: date)
                ),
                weekly: CodexUsageHistoryWindow(
                    usedPercent: weekly,
                    windowDurationMinutes: 10_080,
                    resetsAt: Calendar.current.date(byAdding: .day, value: 5, to: date)
                ),
                codexCreditsBalance: String(format: "%.2f", max(0, 24.0 - (Double(day) * 0.35))),
                sparkCreditsBalance: nil
            )
        }
    }

    static func localUsageSummary(now: Date = Date()) -> CodexLocalUsageSummary {
        let sessionsPath = CodexLocalUsageDirectoryReader.defaultSessionsURL().path
        let period = CodexLocalUsagePeriodSummary(entryCount: 0, tokens: .zero)
        return CodexLocalUsageSummary(
            capturedAt: now,
            dataPath: sessionsPath,
            total: period,
            today: period,
            week: period,
            sessions: [],
            projects: [],
            modelSummaries: [],
            fiveHourBlocks: [],
            wasteSignals: [],
            configReport: CodexLocalConfigReport(severity: .warning, issues: [
                CodexLocalConfigIssue(
                    kind: .missingSessionData,
                    title: "No local sessions",
                    detail: "No Codex JSONL session data found at \(sessionsPath)."
                )
            ]),
            latestProjectName: nil,
            latestModel: nil,
            contextWindowPercent: nil
        )
    }
}
#endif
