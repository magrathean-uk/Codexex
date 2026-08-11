import XCTest
@testable import CodexMeterCore

final class CodexLiveActivityPresentationTests: XCTestCase {
    func testMapsWeeklyAndOptionalFiveHourAndStaysSmall() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let snapshot = CodexSnapshot(capturedAt: now, executablePath: "local", account: .init(authType: "chatgpt", email: nil, planType: nil), limits: [
            .init(id: "codex", rawLimitName: nil, bucket: .codex,
                  primary: .init(usedPercent: 68, windowDurationMinutes: 300, resetsAt: now),
                  secondary: .init(usedPercent: 32, windowDurationMinutes: 10_080, resetsAt: now))
        ])
        let shown = try XCTUnwrap(CodexLiveActivityPresentation.state(snapshot: snapshot, showFiveHour: true))
        XCTAssertEqual(shown.weeklyPercentLeft, 68)
        XCTAssertEqual(shown.fiveHourPercentLeft, 32)
        let payloadSize = try JSONEncoder().encode(CodexLiveActivityAttributes()).count
            + JSONEncoder().encode(shown).count
        XCTAssertLessThan(payloadSize, 4_096)

        let hidden = try XCTUnwrap(
            CodexLiveActivityPresentation.state(snapshot: snapshot, showFiveHour: false)
        )
        XCTAssertNil(hidden.fiveHourPercentLeft)
        XCTAssertNil(hidden.fiveHourResetAt)
    }

    func testTaggedFiveHourNeverSubstitutesForMissingWeeklyWindow() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let snapshot = CodexSnapshot(
            capturedAt: now,
            executablePath: "local",
            account: .init(authType: "chatgpt", email: nil, planType: nil),
            limits: [
                .init(
                    id: "codex",
                    rawLimitName: nil,
                    bucket: .codex,
                    primary: .init(
                        usedPercent: 68,
                        windowDurationMinutes: 300,
                        resetsAt: now
                    ),
                    secondary: nil
                )
            ]
        )

        XCTAssertNil(
            CodexLiveActivityPresentation.state(snapshot: snapshot, showFiveHour: false)
        )
        XCTAssertNil(
            CodexLiveActivityPresentation.state(snapshot: snapshot, showFiveHour: true)
        )
    }

    func testCarriesUsedQuotaDisplayMode() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let snapshot = CodexSnapshot(
            capturedAt: now,
            executablePath: "local",
            account: .init(authType: "chatgpt", email: nil, planType: nil),
            limits: [
                .init(
                    id: "codex",
                    rawLimitName: nil,
                    bucket: .codex,
                    primary: .init(usedPercent: 32, windowDurationMinutes: 10_080, resetsAt: nil),
                    secondary: nil
                )
            ]
        )

        let remaining = try XCTUnwrap(
            CodexLiveActivityPresentation.state(
                snapshot: snapshot,
                showFiveHour: false,
                showUsedQuota: false
            )
        )
        let used = try XCTUnwrap(
            CodexLiveActivityPresentation.state(
                snapshot: snapshot,
                showFiveHour: false,
                showUsedQuota: true
            )
        )

        XCTAssertFalse(remaining.displaysUsedQuota)
        XCTAssertTrue(used.displaysUsedQuota)
        XCTAssertEqual(remaining.weeklyPercentLeft, 68)
        XCTAssertEqual(used.weeklyPercentLeft, 68)
        XCTAssertEqual(remaining.displayedWeeklyPercent, 68)
        XCTAssertEqual(remaining.displayedWeeklyFraction, 0.68, accuracy: 0.0001)
        XCTAssertEqual(remaining.weeklyDisplayDescription, "68% left of weekly quota")
        XCTAssertEqual(used.displayedWeeklyPercent, 32)
        XCTAssertEqual(used.displayedWeeklyFraction, 0.32, accuracy: 0.0001)
        XCTAssertEqual(used.weeklyDisplayDescription, "32% used of weekly quota")
    }

    func testLegacyUntaggedWindowsPreservePrimaryFiveHourAndSecondaryWeeklyRoles() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let snapshot = CodexSnapshot(
            capturedAt: now,
            executablePath: "local",
            account: .init(authType: "chatgpt", email: nil, planType: nil),
            limits: [
                .init(
                    id: "codex",
                    rawLimitName: nil,
                    bucket: .codex,
                    primary: .init(usedPercent: 25, windowDurationMinutes: nil, resetsAt: now),
                    secondary: .init(usedPercent: 40, windowDurationMinutes: nil, resetsAt: now)
                )
            ]
        )

        let state = try XCTUnwrap(
            CodexLiveActivityPresentation.state(snapshot: snapshot, showFiveHour: true)
        )
        XCTAssertEqual(state.weeklyPercentLeft, 60)
        XCTAssertEqual(state.fiveHourPercentLeft, 75)
    }

    func testStaleDateAllowsBackgroundRefreshBeforeBecomingStale() {
        let date = Date(timeIntervalSince1970: 0)
        XCTAssertEqual(
            CodexLiveActivityPresentation.staleDate(capturedAt: date, cadence: 30),
            date.addingTimeInterval(30 * 60)
        )
        XCTAssertEqual(
            CodexLiveActivityPresentation.staleDate(capturedAt: date, cadence: 600),
            date.addingTimeInterval(30 * 60)
        )
        XCTAssertEqual(
            CodexLiveActivityPresentation.staleDate(capturedAt: date, cadence: 3_600),
            date.addingTimeInterval(2 * 3_600)
        )
    }

    func testRecoveryPlanKeepsFirstAndEndsEveryDuplicate() {
        XCTAssertEqual(
            CodexLiveActivityLifecyclePolicy.recoveryPlan(existingIDs: []),
            CodexLiveActivityRecoveryPlan(primaryID: nil, duplicateIDs: [])
        )
        XCTAssertEqual(
            CodexLiveActivityLifecyclePolicy.recoveryPlan(existingIDs: ["same"]),
            CodexLiveActivityRecoveryPlan(primaryID: "same", duplicateIDs: [])
        )
        XCTAssertEqual(
            CodexLiveActivityLifecyclePolicy.recoveryPlan(
                existingIDs: ["same", "duplicate-1", "duplicate-2"]
            ),
            CodexLiveActivityRecoveryPlan(
                primaryID: "same",
                duplicateIDs: ["duplicate-1", "duplicate-2"]
            )
        )
    }
}
