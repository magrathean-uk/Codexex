import Foundation
import XCTest
@testable import CodexMeterApp
@testable import CodexMeterCore

final class CodexQuotaNotificationPlannerTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testPlansFiveHourPressureWhenHighUseAndResetNotSoon() {
        let snapshot = makeSnapshot(fiveHourUsed: 92, fiveHourResetOffset: 2 * 60 * 60)

        let plan = CodexQuotaNotificationPlanner.plan(
            snapshot: snapshot,
            insights: nil,
            preferences: .enabled,
            receipts: .empty,
            now: now
        )

        XCTAssertEqual(plan.notifications.map(\.kind), [.fiveHourPressure])
        XCTAssertEqual(plan.notifications.first?.title, "Codex 5H near limit")
        XCTAssertEqual(plan.notifications.first?.fingerprint, "fiveHourPressure|1800007200|92")
    }

    func testPlansResetSoonWhenHeavyWindowIsAboutToReset() {
        let snapshot = makeSnapshot(fiveHourUsed: 76, fiveHourResetOffset: 12 * 60)

        let plan = CodexQuotaNotificationPlanner.plan(
            snapshot: snapshot,
            insights: nil,
            preferences: .enabled,
            receipts: .empty,
            now: now
        )

        XCTAssertEqual(plan.notifications.map(\.kind), [.fiveHourResetSoon])
        XCTAssertEqual(plan.notifications.first?.title, "Codex 5H resets soon")
    }

    func testPlansWeeklyForecastRiskWhenProjectionWillHitLimit() {
        let snapshot = makeSnapshot(fiveHourUsed: 24, fiveHourResetOffset: 2 * 60 * 60, weeklyUsed: 81)
        let insights = makeInsights(projectedWeeklyPercent: 116)

        let plan = CodexQuotaNotificationPlanner.plan(
            snapshot: snapshot,
            insights: insights,
            preferences: .enabled,
            receipts: .empty,
            now: now
        )

        XCTAssertEqual(plan.notifications.map(\.kind), [.weeklyForecastRisk])
        XCTAssertEqual(plan.notifications.first?.fingerprint, "weeklyForecastRisk|1800345600|116")
        XCTAssertEqual(plan.notifications.first?.body, "Projected 116% by reset · Stable.")
    }

    func testSuppressesAlreadyDeliveredFingerprint() {
        let snapshot = makeSnapshot(fiveHourUsed: 24, fiveHourResetOffset: 2 * 60 * 60, weeklyUsed: 81)
        let insights = makeInsights(projectedWeeklyPercent: 116)
        let firstPlan = CodexQuotaNotificationPlanner.plan(
            snapshot: snapshot,
            insights: insights,
            preferences: .enabled,
            receipts: .empty,
            now: now
        )
        let notification = try! XCTUnwrap(firstPlan.notifications.first)
        let receipts = CodexQuotaNotificationReceipts(deliveredFingerprints: [
            notification.kind: notification.fingerprint
        ])

        let secondPlan = CodexQuotaNotificationPlanner.plan(
            snapshot: snapshot,
            insights: insights,
            preferences: .enabled,
            receipts: receipts,
            now: now
        )

        XCTAssertTrue(secondPlan.notifications.isEmpty)
    }

    func testDoesNotPlanWhenDisabledOrMissingSnapshot() {
        let snapshot = makeSnapshot(fiveHourUsed: 98, fiveHourResetOffset: 3 * 60 * 60)

        XCTAssertTrue(CodexQuotaNotificationPlanner.plan(
            snapshot: snapshot,
            insights: nil,
            preferences: .disabled,
            receipts: .empty,
            now: now
        ).notifications.isEmpty)
        XCTAssertTrue(CodexQuotaNotificationPlanner.plan(
            snapshot: nil,
            insights: nil,
            preferences: .enabled,
            receipts: .empty,
            now: now
        ).notifications.isEmpty)
    }

    private func makeSnapshot(
        fiveHourUsed: Double,
        fiveHourResetOffset: TimeInterval,
        weeklyUsed: Double = 44
    ) -> CodexSnapshot {
        CodexSnapshot(
            capturedAt: now,
            executablePath: "/Applications/Codexex.app/Contents/Helpers/codexex-helper",
            account: CodexAccount(authType: "chatGPT", email: nil, planType: "PRO"),
            limits: [
                CodexLimit(
                    id: "codex",
                    rawLimitName: "Codex",
                    bucket: .codex,
                    primary: CodexQuotaWindow(
                        usedPercent: fiveHourUsed,
                        windowDurationMinutes: 300,
                        resetsAt: now.addingTimeInterval(fiveHourResetOffset)
                    ),
                    secondary: CodexQuotaWindow(
                        usedPercent: weeklyUsed,
                        windowDurationMinutes: 10_080,
                        resetsAt: now.addingTimeInterval(4 * 24 * 60 * 60)
                    )
                )
            ]
        )
    }

    private func makeInsights(projectedWeeklyPercent: Double) -> CodexUsageInsights {
        CodexUsageInsights(
            weeklyPace: CodexUsageForecast(
                message: "Projected \(Int(projectedWeeklyPercent.rounded()))% by reset",
                tone: .danger,
                confidence: .stable,
                currentPercent: 81,
                projectedPercentAtReset: projectedWeeklyPercent,
                paceVariancePercent: 16,
                sampleCount: 6,
                resetAt: now.addingTimeInterval(4 * 24 * 60 * 60),
                detail: "16% over pace"
            ),
            fiveHourPressure: CodexUsageInsightRow(
                title: "5-hour pressure",
                message: "24% used",
                detail: "resets in 2h",
                tone: .safe
            ),
            recentPeaks: CodexUsageInsightRow(
                title: "Recent peaks",
                message: "5H 24% · W 81%",
                detail: "Last 24h / 7d",
                tone: .danger
            )
        )
    }
}
