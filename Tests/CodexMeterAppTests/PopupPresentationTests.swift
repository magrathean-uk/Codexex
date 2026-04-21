import Foundation
import XCTest
@testable import CodexMeterApp
@testable import CodexMeterCore

final class PopupPresentationTests: XCTestCase {
    func testPopupOrdersSparkAfterPrimaryLimits() {
        let ordered = PopupPresentation.orderedLimits([
            makeLimit(id: "spark", name: "Codex Spark", bucket: .spark, fiveHour: 12, weekly: 18),
            makeLimit(id: "other", name: "Research", bucket: .other, fiveHour: 42, weekly: 55),
            makeLimit(id: "codex", name: "Codex", bucket: .codex, fiveHour: 34, weekly: 69)
        ])

        XCTAssertEqual(ordered.map(\.bucket), [.codex, .other, .spark])
    }

    func testSparkUsesCompactCardWhenIdle() {
        let presentation = PopupPresentation.presentation(
            for: makeLimit(id: "spark", name: "Codex Spark", bucket: .spark, fiveHour: 0, weekly: 0)
        )

        XCTAssertEqual(presentation.style, .compact)
    }

    func testSparkUsesFullCardWhenActive() {
        let presentation = PopupPresentation.presentation(
            for: makeLimit(id: "spark", name: "Codex Spark", bucket: .spark, fiveHour: 8, weekly: 0)
        )

        XCTAssertEqual(presentation.style, .standard)
    }

    func testZeroAndUnlimitedCreditsStayHidden() {
        let zeroCredits = PopupPresentation.presentation(
            for: makeLimit(
                id: "codex",
                name: "Codex",
                bucket: .codex,
                fiveHour: 10,
                weekly: 20,
                credits: CodexCredits(hasCredits: true, unlimited: false, balance: "0")
            )
        )
        let unlimitedCredits = PopupPresentation.presentation(
            for: makeLimit(
                id: "codex",
                name: "Codex",
                bucket: .codex,
                fiveHour: 10,
                weekly: 20,
                credits: CodexCredits(hasCredits: true, unlimited: true, balance: nil)
            )
        )

        XCTAssertNil(zeroCredits.visibleCredits)
        XCTAssertNil(unlimitedCredits.visibleCredits)
    }

    func testMeaningfulCreditsStayVisible() {
        let presentation = PopupPresentation.presentation(
            for: makeLimit(
                id: "codex",
                name: "Codex",
                bucket: .codex,
                fiveHour: 10,
                weekly: 20,
                credits: CodexCredits(hasCredits: true, unlimited: false, balance: "12.50")
            )
        )

        XCTAssertEqual(presentation.visibleCredits?.displayText, "12.50")
    }

    func testSummaryUsesTooEarlySeverityForLearningForecast() {
        let summary = PopupPresentation.summary(
            snapshot: makeSnapshot(),
            insights: CodexUsageInsights(
                weeklyPace: CodexUsageForecast(
                    message: "Learning this cycle",
                    tone: .caution,
                    confidence: .learning,
                    currentPercent: 10,
                    projectedPercentAtReset: nil,
                    paceVariancePercent: nil,
                    sampleCount: 2,
                    resetAt: Date(timeIntervalSince1970: 1_800_000_000),
                    detail: "Need 1 more samples"
                ),
                fiveHourPressure: CodexUsageInsightRow(
                    title: "5-hour pressure",
                    message: "18% used",
                    detail: "resets in 4h",
                    tone: .safe
                ),
                recentPeaks: CodexUsageInsightRow(
                    title: "Recent peaks",
                    message: "5H 18% · W 22%",
                    detail: "Last 24h / 7d",
                    tone: .safe
                )
            ),
            previewModeEnabled: false,
            hasRefreshIssue: false
        )

        XCTAssertEqual(summary?.severity, .tooEarly)
        XCTAssertEqual(summary?.title, "Too early")
    }

    func testSummaryEscalatesToFiveHourPressureWhenWeeklyLooksSafe() {
        let summary = PopupPresentation.summary(
            snapshot: makeSnapshot(),
            insights: CodexUsageInsights(
                weeklyPace: CodexUsageForecast(
                    message: "Projected 62% by reset",
                    tone: .safe,
                    confidence: .stable,
                    currentPercent: 41,
                    projectedPercentAtReset: 62,
                    paceVariancePercent: -4,
                    sampleCount: 6,
                    resetAt: Date(timeIntervalSince1970: 1_800_000_000),
                    detail: "4% under pace · 6 samples"
                ),
                fiveHourPressure: CodexUsageInsightRow(
                    title: "5-hour pressure",
                    message: "88% used",
                    detail: "resets in 2h",
                    tone: .danger
                ),
                recentPeaks: CodexUsageInsightRow(
                    title: "Recent peaks",
                    message: "5H 88% · W 63%",
                    detail: "Last 24h / 7d",
                    tone: .danger
                )
            ),
            previewModeEnabled: false,
            hasRefreshIssue: false
        )

        XCTAssertEqual(summary?.severity, .risk)
        XCTAssertEqual(summary?.supportingLabel, "5-hour pressure")
    }

    func testSummaryIgnoresSparkLimitsForAlerting() {
        let sparkLimit = makeLimit(id: "spark", name: "Codex Spark", bucket: .spark, fiveHour: 0, weekly: 100)
        let snapshot = CodexSnapshot(
            capturedAt: Date(timeIntervalSince1970: 1_800_000_000),
            executablePath: "/Applications/Codexex.app",
            account: CodexAccount(
                authType: "chatGPT",
                email: "user@example.com",
                planType: "PRO"
            ),
            limits: [
                makeLimit(id: "codex", name: "Codex", bucket: .codex, fiveHour: 12, weekly: 41),
                sparkLimit
            ]
        )

        let summary = PopupPresentation.summary(
            snapshot: snapshot,
            insights: CodexUsageInsights(
                weeklyPace: CodexUsageForecast(
                    message: "Projected 62% by reset",
                    tone: .safe,
                    confidence: .stable,
                    currentPercent: 41,
                    projectedPercentAtReset: 62,
                    paceVariancePercent: -4,
                    sampleCount: 6,
                    resetAt: Date(timeIntervalSince1970: 1_800_000_000),
                    detail: "4% under pace · 6 samples"
                ),
                fiveHourPressure: CodexUsageInsightRow(
                    title: "5-hour pressure",
                    message: "12% used",
                    detail: "resets in 4h",
                    tone: .safe
                ),
                recentPeaks: CodexUsageInsightRow(
                    title: "Recent peaks",
                    message: "5H 18% · W 62%",
                    detail: "Last 24h / 7d",
                    tone: .safe
                )
            ),
            previewModeEnabled: false,
            hasRefreshIssue: false
        )

        XCTAssertEqual(summary?.severity, .safe)
        XCTAssertEqual(summary?.message, "You are on track for this cycle.")
    }

    func testHistoryLegendUsesCurrentPercentNotForecastWarning() {
        let forecast = CodexUsageForecast(
            message: "Likely over in 6h",
            tone: .danger,
            confidence: .volatile,
            currentPercent: 91,
            projectedPercentAtReset: 100,
            paceVariancePercent: 82
        )

        XCTAssertEqual(PopupPresentation.historyLegendValue(for: forecast), "91%")
    }

    func testHistoryGraphBarsAreBottomAligned() {
        let rect = PopupPresentation.historyBarRect(
            usedPercent: 25,
            index: 0,
            count: 10,
            size: CGSize(width: 100, height: 40)
        )

        XCTAssertEqual(rect.minY, 30)
        XCTAssertEqual(rect.maxY, 40)
        XCTAssertEqual(rect.height, 10)
    }

    private func makeLimit(
        id: String,
        name: String,
        bucket: CodexLimitBucket,
        fiveHour: Double,
        weekly: Double,
        credits: CodexCredits? = nil
    ) -> CodexLimit {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        return CodexLimit(
            id: id,
            rawLimitName: name,
            bucket: bucket,
            primary: CodexQuotaWindow(
                usedPercent: fiveHour,
                windowDurationMinutes: 300,
                resetsAt: now.addingTimeInterval(4 * 60 * 60)
            ),
            secondary: CodexQuotaWindow(
                usedPercent: weekly,
                windowDurationMinutes: 10_080,
                resetsAt: now.addingTimeInterval(24 * 60 * 60)
            ),
            credits: credits
        )
    }

    private func makeSnapshot() -> CodexSnapshot {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        return CodexSnapshot(
            capturedAt: now,
            executablePath: "/Applications/Codexex.app",
            account: CodexAccount(
                authType: "chatGPT",
                email: "user@example.com",
                planType: "PRO"
            ),
            limits: [makeLimit(id: "codex", name: "Codex", bucket: .codex, fiveHour: 12, weekly: 41)]
        )
    }
}
