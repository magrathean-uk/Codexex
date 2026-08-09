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
        XCTAssertLessThan(try JSONEncoder().encode(shown).count, 4_096)
        XCTAssertNil(CodexLiveActivityPresentation.state(snapshot: snapshot, showFiveHour: false)?.fiveHourPercentLeft)
    }

    func testStaleDateUsesAtLeastFiveMinutes() {
        let date = Date(timeIntervalSince1970: 0)
        XCTAssertEqual(CodexLiveActivityPresentation.staleDate(capturedAt: date, cadence: 30), date.addingTimeInterval(300))
        XCTAssertEqual(CodexLiveActivityPresentation.staleDate(capturedAt: date, cadence: 600), date.addingTimeInterval(1_200))
    }
}
