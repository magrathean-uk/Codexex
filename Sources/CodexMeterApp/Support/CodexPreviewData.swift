#if os(macOS)
import Foundation
import CodexMeterCore

enum CodexPreviewData {
    static func snapshot(now: Date = Date()) -> CodexSnapshot {
        let fiveHourReset = Calendar.current.date(byAdding: .minute, value: 96, to: now)
        let weeklyReset = Calendar.current.date(byAdding: .day, value: 4, to: now)
        let sparkFiveHourReset = Calendar.current.date(byAdding: .minute, value: 202, to: now)
        let sparkWeeklyReset = Calendar.current.date(byAdding: .day, value: 2, to: now)

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
                    primary: CodexQuotaWindow(usedPercent: 34, windowDurationMinutes: 300, resetsAt: fiveHourReset),
                    secondary: CodexQuotaWindow(usedPercent: 58, windowDurationMinutes: 10_080, resetsAt: weeklyReset),
                    credits: CodexCredits(hasCredits: true, unlimited: false, balance: "12.50")
                ),
                CodexLimit(
                    id: "spark",
                    rawLimitName: "Codex Spark",
                    bucket: .spark,
                    primary: CodexQuotaWindow(usedPercent: 12, windowDurationMinutes: 300, resetsAt: sparkFiveHourReset),
                    secondary: CodexQuotaWindow(usedPercent: 41, windowDurationMinutes: 10_080, resetsAt: sparkWeeklyReset)
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

            let weekly = min(100.0, 18.0 + Double(day) * 1.7 + sin(Double(day) / 3.0) * 4.0)
            let fiveHour = max(6.0, min(92.0, 22.0 + sin(Double(day) * 0.9) * 18.0 + Double(day % 5) * 3.5))

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
        let tokens = CodexLocalTokenUsage(
            inputTokens: 38_000,
            cachedInputTokens: 24_000,
            outputTokens: 3_400,
            reasoningOutputTokens: 620,
            totalTokens: 41_400
        )
        let period = CodexLocalUsagePeriodSummary(entryCount: 9, tokens: tokens)
        return CodexLocalUsageSummary(
            capturedAt: now,
            dataPath: "~/.codex/sessions",
            total: period,
            today: period,
            week: CodexLocalUsagePeriodSummary(
                entryCount: 48,
                tokens: CodexLocalTokenUsage(
                    inputTokens: 210_000,
                    cachedInputTokens: 151_000,
                    outputTokens: 18_000,
                    reasoningOutputTokens: 4_400,
                    totalTokens: 228_000
                )
            ),
            sessions: [
                CodexLocalSessionSummary(
                    id: "preview",
                    projectPath: "/Users/you/dev/source/Codexex",
                    latestModel: "gpt-5.1-codex-max",
                    startedAt: now.addingTimeInterval(-42 * 60),
                    lastActivityAt: now,
                    entryCount: 9,
                    commandCount: 16,
                    tokens: tokens
                )
            ],
            projects: [
                CodexLocalProjectSummary(
                    id: "/Users/you/dev/source/Codexex",
                    displayName: "Codexex",
                    path: "/Users/you/dev/source/Codexex",
                    latestModel: "gpt-5.1-codex-max",
                    lastActivityAt: now,
                    sessionCount: 1,
                    commandCount: 16,
                    tokens: tokens
                )
            ],
            modelSummaries: [
                CodexLocalModelSummary(model: "gpt-5.1-codex-max", entryCount: 9, tokens: tokens)
            ],
            fiveHourBlocks: [
                CodexLocalUsageBlock(
                    id: "preview-block",
                    startsAt: now.addingTimeInterval(-2 * 60 * 60),
                    endsAt: now.addingTimeInterval(3 * 60 * 60),
                    tokens: tokens,
                    entryCount: 9
                )
            ],
            wasteSignals: [
                CodexLocalWasteSignal(
                    id: "preview-tool-loop",
                    kind: .toolLoop,
                    title: "Tool loop",
                    detail: "16 shell/tool completions in one session."
                )
            ],
            configReport: CodexLocalConfigReport(severity: .warning, issues: [
                CodexLocalConfigIssue(
                    kind: .hooksNotInstalled,
                    title: "Hooks not installed",
                    detail: "Install local Codexex hooks for live tool and approval events."
                )
            ]),
            latestProjectName: "Codexex",
            latestModel: "gpt-5.1-codex-max",
            contextWindowPercent: 4.1
        )
    }
}
#endif
