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

    func testWeeklyPaceUsesElapsedFractionProjectionForSafeForecast() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let resetAt = now.addingTimeInterval(24 * 60 * 60)
        let samples = [
            makeSample(hoursAgo: 2, fiveHour: 20, weekly: 20, weeklyReset: resetAt, now: now),
            makeSample(hoursAgo: 1, fiveHour: 21, weekly: 20, weeklyReset: resetAt, now: now),
            makeSample(hoursAgo: 0, fiveHour: 22, weekly: 20, weeklyReset: resetAt, now: now),
        ]

        let forecast = CodexUsageHistoryAnalytics.forecast(from: samples, series: .weekly)

        XCTAssertEqual(forecast.tone, .safe)
        XCTAssertEqual(forecast.message, "Projected 23% by reset")
        XCTAssertEqual(forecast.currentPercent, 20)
        XCTAssertEqual(forecast.projectedPercentAtReset ?? -1, 23.333333333333336, accuracy: 0.001)
        XCTAssertEqual(forecast.detail, "66% under pace · 3 samples")
    }

    func testWeeklyPaceUsesElapsedFractionProjectionForCautionForecast() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let resetAt = now.addingTimeInterval(5 * 24 * 60 * 60)
        let samples = [
            makeSample(hoursAgo: 2, fiveHour: 20, weekly: 15, weeklyReset: resetAt, now: now),
            makeSample(hoursAgo: 1, fiveHour: 21, weekly: 20, weeklyReset: resetAt, now: now),
            makeSample(hoursAgo: 0, fiveHour: 22, weekly: 25, weeklyReset: resetAt, now: now),
        ]

        let forecast = CodexUsageHistoryAnalytics.forecast(from: samples, series: .weekly)

        XCTAssertEqual(forecast.tone, .caution)
        XCTAssertEqual(forecast.message, "Projected 88% by reset")
        XCTAssertEqual(forecast.projectedPercentAtReset ?? -1, 87.5, accuracy: 0.001)
        XCTAssertEqual(forecast.detail, "4% under pace · 3 samples")
    }

    func testWeeklyPaceUsesElapsedFractionProjectionForDangerForecast() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let resetAt = now.addingTimeInterval(5 * 24 * 60 * 60)
        let samples = [
            makeSample(hoursAgo: 2, fiveHour: 20, weekly: 30, weeklyReset: resetAt, now: now),
            makeSample(hoursAgo: 1, fiveHour: 21, weekly: 35, weeklyReset: resetAt, now: now),
            makeSample(hoursAgo: 0, fiveHour: 22, weekly: 40, weeklyReset: resetAt, now: now),
        ]

        let forecast = CodexUsageHistoryAnalytics.forecast(from: samples, series: .weekly)

        XCTAssertEqual(forecast.tone, .danger)
        XCTAssertEqual(forecast.message, "Projected 140% by reset")
        XCTAssertEqual(forecast.projectedPercentAtReset ?? -1, 140, accuracy: 0.001)
        XCTAssertEqual(forecast.detail, "11% over pace · 3 samples")
    }

    func testWeeklyPaceWaitsUntilCycleHasEnoughCoverage() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let resetAt = now.addingTimeInterval((7 * 24 * 60 * 60) - (60 * 60))
        let samples = [
            makeSample(hoursAgo: 2, fiveHour: 20, weekly: 8, weeklyReset: resetAt, now: now),
            makeSample(hoursAgo: 1, fiveHour: 21, weekly: 9, weeklyReset: resetAt, now: now),
            makeSample(hoursAgo: 0, fiveHour: 22, weekly: 10, weeklyReset: resetAt, now: now),
        ]

        let forecast = CodexUsageHistoryAnalytics.forecast(from: samples, series: .weekly)

        XCTAssertEqual(forecast.message, "Learning this cycle")
        XCTAssertEqual(forecast.tone, .caution)
        XCTAssertEqual(forecast.currentPercent, 10)
        XCTAssertNil(forecast.projectedPercentAtReset)
    }

    func testPointsCollapseMultipleSamplesFromSameDayIntoDailyPeak() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: now)
        let previousDay = calendar.date(byAdding: .day, value: -1, to: day)!

        let sameDayMorning = makeSample(
            at: day.addingTimeInterval(9 * 60 * 60),
            fiveHour: 18,
            weekly: 42,
            weeklyReset: now.addingTimeInterval(4 * 24 * 60 * 60)
        )
        let sameDayEvening = makeSample(
            at: day.addingTimeInterval(17 * 60 * 60),
            fiveHour: 61,
            weekly: 55,
            weeklyReset: now.addingTimeInterval(4 * 24 * 60 * 60)
        )
        let priorDay = makeSample(
            at: previousDay.addingTimeInterval(10 * 60 * 60),
            fiveHour: 20,
            weekly: 35,
            weeklyReset: now.addingTimeInterval(5 * 24 * 60 * 60)
        )

        let points = CodexUsageHistoryAnalytics.points(
            from: [priorDay, sameDayMorning, sameDayEvening],
            series: .fiveHour,
            limit: 30
        )

        XCTAssertEqual(points.count, 2)
        XCTAssertEqual(points.last?.usedPercent, 61)
        XCTAssertEqual(points.last?.windowDurationMinutes, 300)
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
        XCTAssertEqual(insights?.recentPeaks.detail, "Last 24h / 7d")
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

    func testUsageHistoryStoreSkipsDuplicateSamplesAndUsesInjectedFileURL() async throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = root.appendingPathComponent("usage-history.json")
        defer { try? fileManager.removeItem(at: root) }

        let store = CodexUsageHistoryStore(fileURL: fileURL)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let snapshot = makeSnapshot(now: now)

        let first = await store.append(snapshot: snapshot, now: now)
        let second = await store.append(snapshot: snapshot, now: now.addingTimeInterval(30))
        let loaded = await store.load(now: now.addingTimeInterval(30))

        XCTAssertEqual(first.count, 1)
        XCTAssertEqual(second.count, 1)
        XCTAssertEqual(loaded.count, 1)
        XCTAssertTrue(fileManager.fileExists(atPath: fileURL.path))
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
        makeSample(
            at: now.addingTimeInterval(-(hoursAgo * 60 * 60)),
            fiveHour: fiveHour,
            weekly: weekly,
            weeklyReset: weeklyReset
        )
    }

    private func makeSample(
        at date: Date,
        fiveHour: Double,
        weekly: Double,
        weeklyReset: Date? = nil
    ) -> CodexUsageHistorySample {
        CodexUsageHistorySample(
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
