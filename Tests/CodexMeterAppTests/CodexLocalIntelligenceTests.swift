import XCTest
@testable import CodexMeterApp
@testable import CodexMeterCore

final class CodexLocalIntelligenceTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testSummaryShowsLikelyRangeForSafeForecast() {
        let summary = CodexLocalIntelligence.summary(
            insights: makeInsights(tone: .safe, lower: 42, upper: 58),
            localUsage: nil
        )

        XCTAssertEqual(summary?.severity, .safe)
        XCTAssertEqual(summary?.title, "Safe")
        XCTAssertEqual(summary?.message, "Likely 42-58% by reset.")
        XCTAssertEqual(summary?.supportingValue, "42-58%")
    }

    func testBurnSignalRaisesSafeForecastToWatch() {
        let summary = CodexLocalIntelligence.summary(
            insights: makeInsights(tone: .safe, lower: 42, upper: 58),
            localUsage: makeLocalUsage(signal: .heavySession)
        )

        XCTAssertEqual(summary?.severity, .watch)
        XCTAssertEqual(summary?.title, "Watch")
        XCTAssertEqual(summary?.message, "Likely 42-58% by reset. Heavy session detected.")
        XCTAssertEqual(summary?.supportingDetail, "Codexex used 160K tokens.")
    }

    func testDangerForecastKeepsDangerTitle() {
        let summary = CodexLocalIntelligence.summary(
            insights: makeInsights(tone: .danger, lower: 92, upper: 108),
            localUsage: makeLocalUsage(signal: .toolLoop)
        )

        XCTAssertEqual(summary?.severity, .risk)
        XCTAssertEqual(summary?.title, "Danger")
        XCTAssertEqual(summary?.message, "Likely 92-108% by reset. Tool loop detected.")
    }

    private func makeInsights(
        tone: CodexUsageForecast.Tone,
        lower: Double,
        upper: Double
    ) -> CodexUsageInsights {
        CodexUsageInsights(
            weeklyPace: CodexUsageForecast(
                message: "Projected \(Int(upper.rounded()))% by reset",
                tone: tone,
                confidence: .stable,
                currentPercent: 40,
                projectedPercentAtReset: upper,
                paceVariancePercent: nil,
                sampleCount: 6,
                resetAt: now.addingTimeInterval(2 * 24 * 60 * 60),
                detail: "6 samples",
                likelyLowerPercent: lower,
                likelyUpperPercent: upper
            ),
            fiveHourPressure: CodexUsageInsightRow(
                title: "5-hour pressure",
                message: "24% used",
                detail: "resets in 2h",
                tone: .safe
            ),
            recentPeaks: CodexUsageInsightRow(
                title: "Recent peaks",
                message: "5H 24% · W 40%",
                detail: "Last 24h / 7d",
                tone: .safe
            )
        )
    }

    private func makeLocalUsage(signal: CodexLocalWasteSignalKind) -> CodexLocalUsageSummary {
        let tokens = CodexLocalTokenUsage(
            inputTokens: 150_000,
            cachedInputTokens: 90_000,
            outputTokens: 8_000,
            reasoningOutputTokens: 2_000,
            totalTokens: 160_000
        )
        let period = CodexLocalUsagePeriodSummary(entryCount: 1, tokens: tokens)
        let wasteSignal = CodexLocalWasteSignal(
            id: signal.rawValue,
            kind: signal,
            title: signal == .toolLoop ? "Tool loop" : "Heavy session",
            detail: signal == .toolLoop ? "12 shell/tool completions in one session." : "Codexex used 160K tokens."
        )
        return CodexLocalUsageSummary(
            capturedAt: now,
            dataPath: "/Users/me/.codex/sessions",
            total: period,
            today: period,
            week: period,
            sessions: [],
            projects: [],
            modelSummaries: [],
            fiveHourBlocks: [],
            wasteSignals: [wasteSignal],
            configReport: CodexLocalConfigReport(severity: .ok, issues: []),
            latestProjectName: "Codexex",
            latestModel: "gpt-5.1-codex-max",
            contextWindowPercent: nil
        )
    }
}
