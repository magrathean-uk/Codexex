import Foundation
import XCTest
@testable import CodexMeterApp
@testable import CodexMeterCore

@MainActor
final class StatusBarLabelTests: XCTestCase {
    func testMenuBarUsedModeShowsUsedPercentages() {
        let title = StatusBarLabel.makeTitle(
            snapshot: makeSnapshot(),
            isRefreshing: false,
            hasError: false,
            displayMode: .used,
            showFiveHour: true,
            showWeekly: true,
            insights: nil
        )

        XCTAssertEqual(title, "5H 13% W 70%")
    }

    func testMenuBarRemainingModeShowsRemainingPercentages() {
        let title = StatusBarLabel.makeTitle(
            snapshot: makeSnapshot(),
            isRefreshing: false,
            hasError: false,
            displayMode: .remaining,
            showFiveHour: true,
            showWeekly: true,
            insights: nil
        )

        XCTAssertEqual(title, "5H 87% W 30%")
    }

    func testWeeklyOnlyMenuBarUsesTheOpenAILogoSlot() {
        let title = StatusBarLabel.makeTitle(
            snapshot: makeSnapshot(),
            isRefreshing: false,
            hasError: false,
            displayMode: .remaining,
            showFiveHour: false,
            showWeekly: true,
            insights: nil
        )

        XCTAssertEqual(title, "30%")
        XCTAssertTrue(StatusBarLabel.usesOpenAILogo(showFiveHour: false, showWeekly: true))
    }

    func testMenuBarPaceModeShowsWeeklyProjection() {
        let title = StatusBarLabel.makeTitle(
            snapshot: makeSnapshot(),
            isRefreshing: false,
            hasError: false,
            displayMode: .pace,
            showFiveHour: true,
            showWeekly: true,
            insights: CodexUsageInsights(
                weeklyPace: CodexUsageForecast(
                    message: "Projected 89% by reset",
                    tone: .caution,
                    confidence: .volatile,
                    currentPercent: 70,
                    projectedPercentAtReset: 89,
                    paceVariancePercent: -4
                ),
                fiveHourPressure: CodexUsageInsightRow(
                    title: "5-hour pressure",
                    message: "13% used",
                    detail: nil,
                    tone: .safe
                ),
                recentPeaks: CodexUsageInsightRow(
                    title: "Recent peaks",
                    message: "5H 13% · W 70%",
                    detail: nil,
                    tone: .safe
                )
            )
        )

        XCTAssertEqual(title, "W 70%->89%")
    }

    func testWeeklyOnlyPaceMenuBarUsesTheOpenAILogoSlot() {
        let title = StatusBarLabel.makeTitle(
            snapshot: makeSnapshot(),
            isRefreshing: false,
            hasError: false,
            displayMode: .pace,
            showFiveHour: false,
            showWeekly: true,
            insights: CodexUsageInsights(
                weeklyPace: CodexUsageForecast(
                    message: "Projected 89% by reset",
                    tone: .caution,
                    confidence: .volatile,
                    currentPercent: 70,
                    projectedPercentAtReset: 89,
                    paceVariancePercent: -4
                ),
                fiveHourPressure: CodexUsageInsightRow(
                    title: "5-hour pressure",
                    message: "13% used",
                    detail: nil,
                    tone: .safe
                ),
                recentPeaks: CodexUsageInsightRow(
                    title: "Recent peaks",
                    message: "5H 13% · W 70%",
                    detail: nil,
                    tone: .safe
                )
            )
        )

        XCTAssertEqual(title, "70%->89%")
    }

    func testNormalMenuBarImageUsesSeverityDot() {
        let image = StatusBarLabel.menuBarImage(
            isRefreshing: false,
            hasError: false,
            isStale: false,
            severity: .safe
        )

        XCTAssertEqual(image?.size.width, 8)
        XCTAssertEqual(image?.size.height, 8)
        XCTAssertEqual(image?.isTemplate, false)
    }

    func testNormalMenuBarImageIsNilWithoutSeverity() {
        let image = StatusBarLabel.menuBarImage(
            isRefreshing: false,
            hasError: false,
            isStale: false,
            severity: nil
        )

        XCTAssertNil(image)
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
            limits: [
                CodexLimit(
                    id: "codex",
                    rawLimitName: "Codex",
                    bucket: .codex,
                    primary: CodexQuotaWindow(
                        usedPercent: 13,
                        windowDurationMinutes: 300,
                        resetsAt: now.addingTimeInterval(2 * 60 * 60)
                    ),
                    secondary: CodexQuotaWindow(
                        usedPercent: 70,
                        windowDurationMinutes: 10_080,
                        resetsAt: now.addingTimeInterval(2 * 24 * 60 * 60)
                    )
                )
            ]
        )
    }
}
