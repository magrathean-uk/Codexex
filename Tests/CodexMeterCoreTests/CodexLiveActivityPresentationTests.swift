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

    func testStaleDateUsesAtLeastFiveMinutes() {
        let date = Date(timeIntervalSince1970: 0)
        XCTAssertEqual(CodexLiveActivityPresentation.staleDate(capturedAt: date, cadence: 30), date.addingTimeInterval(300))
        XCTAssertEqual(CodexLiveActivityPresentation.staleDate(capturedAt: date, cadence: 600), date.addingTimeInterval(1_200))
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
