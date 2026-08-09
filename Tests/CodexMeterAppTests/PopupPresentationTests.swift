import Foundation
import AppKit
import XCTest
@testable import CodexMeterApp
@testable import CodexMeterCore

final class PopupPresentationTests: XCTestCase {
    func testSparkAccentUsesCyanReferenceColor() throws {
        let color = try XCTUnwrap(NSColor(limitAccentColor(for: .spark)).usingColorSpace(.sRGB))

        XCTAssertLessThan(color.redComponent, 0.55)
        XCTAssertGreaterThan(color.greenComponent, 0.75)
        XCTAssertGreaterThan(color.blueComponent, 0.85)
    }

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
            for: makeLimit(id: "spark", name: "GPT-5.3-Codex-Spark", bucket: .spark, fiveHour: 0, weekly: 0)
        )

        XCTAssertEqual(presentation.style, .compact)
        XCTAssertEqual(presentation.compactDisplayName, "Spark")
    }

    func testSparkUsesFullCardWhenActive() {
        let presentation = PopupPresentation.presentation(
            for: makeLimit(id: "spark", name: "Codex Spark", bucket: .spark, fiveHour: 8, weekly: 0)
        )

        XCTAssertEqual(presentation.style, .standard)
    }

    func testSparkShowsInactiveFiveHourBesideWeekly() {
        let rows = PopupPresentation.visibleWindowRows(
            for: makeLimit(id: "spark", name: "Codex Spark", bucket: .spark, fiveHour: 0, weekly: 13),
            includeInactive: true,
            showFiveHour: true
        )

        XCTAssertEqual(rows.map(\.title), ["5H", "Weekly"])
        XCTAssertEqual(rows.map { Int($0.window.usedPercent) }, [0, 13])
    }

    func testFiveHourVisibilityFiltersRowsAndHeadline() {
        let limit = makeLimit(
            id: "codex",
            name: "Codex",
            bucket: .codex,
            fiveHour: 92,
            weekly: 45
        )

        let shownRows = PopupPresentation.visibleWindowRows(
            for: limit,
            includeInactive: true,
            showFiveHour: true
        )
        let hiddenRows = PopupPresentation.visibleWindowRows(
            for: limit,
            includeInactive: true,
            showFiveHour: false
        )

        XCTAssertEqual(shownRows.map(\.title), ["5H", "Weekly"])
        XCTAssertEqual(hiddenRows.map(\.title), ["Weekly"])
        XCTAssertEqual(
            PopupPresentation.headlineWindow(for: limit, showFiveHour: true)?.remainingPercentText,
            "8%"
        )
        XCTAssertEqual(
            PopupPresentation.headlineWindow(for: limit, showFiveHour: false)?.remainingPercentText,
            "55%"
        )
    }

    func testHiddenFiveHourDoesNotBecomeWeeklyFallback() {
        let limit = CodexLimit(
            id: "codex",
            rawLimitName: "Codex",
            bucket: .codex,
            primary: CodexQuotaWindow(
                usedPercent: 72,
                windowDurationMinutes: 300,
                resetsAt: Date(timeIntervalSince1970: 1_800_000_000)
            ),
            secondary: nil
        )

        XCTAssertTrue(
            PopupPresentation.visibleWindowRows(
                for: limit,
                includeInactive: true,
                showFiveHour: false
            ).isEmpty
        )
        XCTAssertNil(PopupPresentation.headlineWindow(for: limit, showFiveHour: false))
    }

    func testQuotaWindowDisplayUsesRemainingPercentLikeAccountPage() {
        let window = CodexQuotaWindow(
            usedPercent: 100,
            windowDurationMinutes: 300,
            resetsAt: Date(timeIntervalSince1970: 1_800_000_000)
        )

        XCTAssertEqual(PopupPresentation.quotaRemainingText(for: window), "0%")
        XCTAssertEqual(PopupPresentation.quotaRemainingProgress(for: window), 0)
    }

    func testLimitHeadlineUsesLowestRemainingWindow() throws {
        let codex = makeLimit(id: "codex", name: "Codex", bucket: .codex, fiveHour: 100, weekly: 45)
        let spark = makeLimit(id: "spark", name: "Codex Spark", bucket: .spark, fiveHour: 0, weekly: 64)

        XCTAssertEqual(PopupPresentation.headlineWindow(for: codex, showFiveHour: true)?.remainingPercentText, "0%")
        XCTAssertEqual(PopupPresentation.headlineWindow(for: spark, showFiveHour: true)?.remainingPercentText, "36%")
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
            hasRefreshIssue: false,
            showFiveHour: true
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
            hasRefreshIssue: false,
            showFiveHour: true
        )

        XCTAssertEqual(summary?.severity, .risk)
        XCTAssertEqual(summary?.supportingLabel, "5-hour pressure")
    }

    func testSummaryIgnoresFiveHourPressureWhenHidden() {
        let summary = PopupPresentation.summary(
            snapshot: makeSnapshot(),
            insights: makeFiveHourPressureInsights(),
            previewModeEnabled: false,
            hasRefreshIssue: false,
            showFiveHour: false
        )

        XCTAssertEqual(summary?.severity, .safe)
        XCTAssertEqual(summary?.message, "You are on track for this cycle.")
        XCTAssertEqual(summary?.supportingLabel, "Weekly forecast")
    }

    func testSummaryRestoresFiveHourPressureWhenEnabled() {
        let summary = PopupPresentation.summary(
            snapshot: makeSnapshot(),
            insights: makeFiveHourPressureInsights(),
            previewModeEnabled: false,
            hasRefreshIssue: false,
            showFiveHour: true
        )

        XCTAssertEqual(summary?.severity, .risk)
        XCTAssertEqual(summary?.message, "Short-term pressure is unusually high.")
        XCTAssertEqual(summary?.supportingLabel, "5-hour pressure")
    }

    func testSummaryUsesCompactForecastInsteadOfRepeatingCurrentUsage() {
        let summary = PopupPresentation.summary(
            snapshot: makeSnapshot(),
            insights: CodexUsageInsights(
                weeklyPace: CodexUsageForecast(
                    message: "Projected 89% by reset",
                    tone: .caution,
                    confidence: .volatile,
                    currentPercent: 70,
                    projectedPercentAtReset: 89,
                    paceVariancePercent: -4,
                    sampleCount: 1_281,
                    resetAt: Date(timeIntervalSince1970: 1_800_000_000),
                    detail: "4% under pace · 1281 samples",
                    likelyLowerPercent: 71,
                    likelyUpperPercent: 107
                ),
                fiveHourPressure: CodexUsageInsightRow(
                    title: "5-hour pressure",
                    message: "13% used",
                    detail: "resets in 2h",
                    tone: .safe
                ),
                recentPeaks: CodexUsageInsightRow(
                    title: "Recent peaks",
                    message: "5H 13% · W 70%",
                    detail: "Last 24h / 7d",
                    tone: .safe
                )
            ),
            previewModeEnabled: false,
            hasRefreshIssue: false,
            showFiveHour: true
        )

        XCTAssertEqual(summary?.supportingLabel, "Weekly forecast")
        XCTAssertEqual(summary?.supportingValue, "Volatile")
        XCTAssertEqual(summary?.supportingDetail, "89% by reset · likely 71-107%")
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
            hasRefreshIssue: false,
            showFiveHour: true
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

    func testHistorySeriesHideAndRestoreFiveHour() {
        let hidden = PopupPresentation.visibleHistorySeries(showFiveHour: false).map(historySeriesName)
        let shown = PopupPresentation.visibleHistorySeries(showFiveHour: true).map(historySeriesName)

        XCTAssertEqual(hidden, ["Weekly"])
        XCTAssertEqual(shown, ["5H", "Weekly"])
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

    func testHighCountHistoryGraphBarsFitCompactChartWidth() {
        let count = 96
        let size = CGSize(
            width: GlassTokens.popupWidth
                - (GlassTokens.pagePadding * 2)
                - (GlassTokens.popupSectionPadding * 2),
            height: 42
        )

        XCTAssertGreaterThan(size.width, 0)
        XCTAssertTrue(size.width.isFinite)

        for index in 0..<count {
            let rect = PopupPresentation.historyBarRect(
                usedPercent: 50,
                index: index,
                count: count,
                size: size
            )

            XCTAssertTrue(rect.minX.isFinite, "bar \(index) should have a finite origin")
            XCTAssertTrue(rect.maxX.isFinite, "bar \(index) should have a finite end")
            XCTAssertTrue(rect.width.isFinite, "bar \(index) should have a finite width")
            XCTAssertGreaterThan(rect.width, 0, "bar \(index) should remain visible")
            XCTAssertGreaterThanOrEqual(rect.minX, 0, "bar \(index) should start inside chart")
            XCTAssertLessThanOrEqual(rect.maxX, size.width, "bar \(index) should end inside chart")
        }
    }

    func testHistoryGraphAccessibilityValueSummarizesVisibleSeriesData() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let value = PopupUsageHistoryAccessibility.graphAccessibilityValue(
            fiveHourPoints: [
                makeHistoryPoint(id: "5h-old", date: now.addingTimeInterval(-7_200), usedPercent: 44),
                makeHistoryPoint(id: "5h-peak", date: now.addingTimeInterval(-3_600), usedPercent: 72),
                makeHistoryPoint(id: "5h-current", date: now, usedPercent: 61)
            ],
            weeklyPoints: [
                makeHistoryPoint(id: "w-old", date: now.addingTimeInterval(-7_200), usedPercent: 38),
                makeHistoryPoint(id: "w-current", date: now, usedPercent: 47),
                makeHistoryPoint(id: "w-peak", date: now.addingTimeInterval(-3_600), usedPercent: 83)
            ],
            axisStartLabel: "30d",
            axisEndLabel: "Today"
        )

        XCTAssertEqual(
            value,
            "30d to Today. 5-hour latest 61%, peak 72%. Weekly latest 47%, peak 83%."
        )
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

    private func makeFiveHourPressureInsights() -> CodexUsageInsights {
        CodexUsageInsights(
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
        )
    }

    private func historySeriesName(_ series: CodexUsageHistorySeries) -> String {
        switch series {
        case .fiveHour: "5H"
        case .weekly: "Weekly"
        }
    }

    private func makeHistoryPoint(id: String, date: Date, usedPercent: Double) -> CodexUsageHistoryPoint {
        CodexUsageHistoryPoint(
            id: id,
            date: date,
            usedPercent: usedPercent,
            resetsAt: nil,
            windowDurationMinutes: nil
        )
    }
}
