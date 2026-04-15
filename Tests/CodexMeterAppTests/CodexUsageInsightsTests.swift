import Foundation
import XCTest
@testable import CodexMeterApp
@testable import CodexMeterCore

final class CodexUsageInsightsTests: XCTestCase {
    func testInsightsAreNilWithoutCodexLimit() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let snapshot = makeSnapshot(
            now: now,
            limits: [
                CodexLimit(
                    id: "spark",
                    rawLimitName: "Codex Spark",
                    bucket: .spark,
                    primary: CodexQuotaWindow(
                        usedPercent: 22,
                        windowDurationMinutes: 300,
                        resetsAt: now.addingTimeInterval(60 * 60)
                    ),
                    secondary: nil
                )
            ]
        )

        XCTAssertNil(
            CodexUsageHistoryAnalytics.insights(
                snapshot: snapshot,
                samples: [],
                now: now
            )
        )
    }

    func testFiveHourPressureUsesFixedThresholds() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let cases: [(Double, TimeInterval, CodexUsageInsightTone)] = [
            (90, 31 * 60, .danger),
            (80, 121 * 60, .danger),
            (70, 31 * 60, .caution),
            (50, 121 * 60, .caution),
            (69, 31 * 60, .safe),
        ]

        for (usedPercent, secondsToReset, expectedTone) in cases {
            let insights = CodexUsageHistoryAnalytics.insights(
                snapshot: makeSnapshot(
                    now: now,
                    fiveHourUsed: usedPercent,
                    fiveHourReset: now.addingTimeInterval(secondsToReset),
                    weeklyUsed: 40,
                    weeklyReset: now.addingTimeInterval(3 * 24 * 60 * 60)
                ),
                samples: [],
                now: now
            )

            XCTAssertEqual(insights?.fiveHourPressure.tone, expectedTone)
            XCTAssertEqual(insights?.fiveHourPressure.message, "\(Int(usedPercent.rounded()))% used")
        }
    }

    func testFiveHourPressureUsesCautionWhenResetIsUnknown() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let insights = CodexUsageHistoryAnalytics.insights(
            snapshot: makeSnapshot(
                now: now,
                fiveHourUsed: 24,
                fiveHourReset: nil,
                weeklyUsed: 40,
                weeklyReset: now.addingTimeInterval(3 * 24 * 60 * 60),
                includeFiveHourReset: false
            ),
            samples: [],
            now: now
        )

        XCTAssertEqual(insights?.fiveHourPressure.tone, .caution)
        XCTAssertEqual(insights?.fiveHourPressure.detail, "Reset unknown")
    }

    func testWeeklyPacePassesThroughSafeForecast() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let resetAt = now.addingTimeInterval(24 * 60 * 60)
        let samples = [
            makeSample(hoursAgo: 2, fiveHour: 20, weekly: 20, weeklyReset: resetAt, now: now),
            makeSample(hoursAgo: 1, fiveHour: 21, weekly: 20, weeklyReset: resetAt, now: now),
            makeSample(hoursAgo: 0, fiveHour: 22, weekly: 20, weeklyReset: resetAt, now: now),
        ]

        let insights = CodexUsageHistoryAnalytics.insights(
            snapshot: makeSnapshot(now: now),
            samples: samples,
            now: now
        )

        XCTAssertEqual(insights?.weeklyPace.message, "On a safe pace")
        XCTAssertEqual(insights?.weeklyPace.tone, .safe)
        XCTAssertEqual(insights?.weeklyPace.projectedPercentAtReset, 20)
    }

    func testWeeklyPacePassesThroughCautionForecast() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let resetAt = now.addingTimeInterval(24 * 60 * 60)
        let samples = [
            makeSample(hoursAgo: 2, fiveHour: 20, weekly: 10, weeklyReset: resetAt, now: now),
            makeSample(hoursAgo: 1, fiveHour: 21, weekly: 20, weeklyReset: resetAt, now: now),
            makeSample(hoursAgo: 0, fiveHour: 22, weekly: 30, weeklyReset: resetAt, now: now),
        ]

        let insights = CodexUsageHistoryAnalytics.insights(
            snapshot: makeSnapshot(now: now),
            samples: samples,
            now: now
        )

        XCTAssertEqual(insights?.weeklyPace.tone, .caution)
        XCTAssertTrue(insights?.weeklyPace.message.hasPrefix("Likely over in ") == true)
        XCTAssertEqual(insights?.weeklyPace.projectedPercentAtReset, 100)
    }

    func testWeeklyPacePassesThroughDangerForecast() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let resetAt = now.addingTimeInterval(24 * 60 * 60)
        let samples = [
            makeSample(hoursAgo: 2, fiveHour: 20, weekly: 60, weeklyReset: resetAt, now: now),
            makeSample(hoursAgo: 1, fiveHour: 21, weekly: 70, weeklyReset: resetAt, now: now),
            makeSample(hoursAgo: 0, fiveHour: 22, weekly: 80, weeklyReset: resetAt, now: now),
        ]

        let insights = CodexUsageHistoryAnalytics.insights(
            snapshot: makeSnapshot(now: now),
            samples: samples,
            now: now
        )

        XCTAssertEqual(insights?.weeklyPace.tone, .danger)
        XCTAssertTrue(insights?.weeklyPace.message.hasPrefix("Likely over in ") == true)
        XCTAssertEqual(insights?.weeklyPace.projectedPercentAtReset, 100)
    }

    func testRecentPeaksUse24HourAnd7DayWindows() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let samples = [
            makeSample(hoursAgo: 30, fiveHour: 95, weekly: 40, now: now),
            makeSample(hoursAgo: 12, fiveHour: 88, weekly: 62, now: now),
            makeSample(hoursAgo: 2, fiveHour: 91, weekly: 75, now: now),
            makeSample(hoursAgo: 1, fiveHour: 50, weekly: 89, now: now),
            makeSample(hoursAgo: 8 * 24, fiveHour: 30, weekly: 99, now: now),
        ]

        let insights = CodexUsageHistoryAnalytics.insights(
            snapshot: makeSnapshot(now: now),
            samples: samples,
            now: now
        )

        XCTAssertEqual(insights?.recentPeaks.message, "5H 91% · W 89%")
    }

    func testRecentPeaksFallBackWhenHistoryIsThin() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let samples = [
            CodexUsageHistorySample(
                capturedAt: now,
                fiveHour: nil,
                weekly: CodexUsageHistoryWindow(
                    usedPercent: 42,
                    windowDurationMinutes: 10_080,
                    resetsAt: now.addingTimeInterval(24 * 60 * 60)
                )
            )
        ]

        let insights = CodexUsageHistoryAnalytics.insights(
            snapshot: makeSnapshot(now: now),
            samples: samples,
            now: now
        )

        XCTAssertEqual(insights?.recentPeaks.message, "Building history")
    }

    func testPreviewDataProducesInsights() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let insights = CodexUsageHistoryAnalytics.insights(
            snapshot: CodexPreviewData.snapshot(now: now),
            samples: CodexPreviewData.history(now: now),
            now: now
        )

        XCTAssertNotNil(insights)
        XCTAssertFalse(insights?.weeklyPace.message.isEmpty ?? true)
        XCTAssertFalse(insights?.fiveHourPressure.message.isEmpty ?? true)
        XCTAssertFalse(insights?.recentPeaks.message.isEmpty ?? true)
    }

    private func makeSnapshot(
        now: Date,
        fiveHourUsed: Double = 42,
        fiveHourReset: Date? = nil,
        weeklyUsed: Double = 28,
        weeklyReset: Date? = nil,
        limits: [CodexLimit]? = nil,
        includeFiveHourReset: Bool = true
    ) -> CodexSnapshot {
        CodexSnapshot(
            capturedAt: now,
            executablePath: "/Applications/Codexex.app",
            account: CodexAccount(
                authType: "chatGPT",
                email: "user@example.com",
                planType: "PRO"
            ),
            limits: limits ?? [
                CodexLimit(
                    id: "codex",
                    rawLimitName: "Codex",
                    bucket: .codex,
                    primary: CodexQuotaWindow(
                        usedPercent: fiveHourUsed,
                        windowDurationMinutes: 300,
                        resetsAt: includeFiveHourReset
                            ? (fiveHourReset ?? now.addingTimeInterval(2 * 60 * 60))
                            : nil
                    ),
                    secondary: CodexQuotaWindow(
                        usedPercent: weeklyUsed,
                        windowDurationMinutes: 10_080,
                        resetsAt: weeklyReset ?? now.addingTimeInterval(4 * 24 * 60 * 60)
                    )
                )
            ]
        )
    }

    private func makeSample(
        hoursAgo: Double,
        fiveHour: Double,
        weekly: Double,
        weeklyReset: Date? = nil,
        now: Date
    ) -> CodexUsageHistorySample {
        let date = now.addingTimeInterval(-(hoursAgo * 60 * 60))
        return CodexUsageHistorySample(
            capturedAt: date,
            fiveHour: CodexUsageHistoryWindow(
                usedPercent: fiveHour,
                windowDurationMinutes: 300,
                resetsAt: date.addingTimeInterval(90 * 60)
            ),
            weekly: CodexUsageHistoryWindow(
                usedPercent: weekly,
                windowDurationMinutes: 10_080,
                resetsAt: weeklyReset ?? date.addingTimeInterval(4 * 24 * 60 * 60)
            )
        )
    }
}
