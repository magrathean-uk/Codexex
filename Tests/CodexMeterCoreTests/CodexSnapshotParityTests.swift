import XCTest
@testable import CodexMeterCore

final class CodexSnapshotParityTests: XCTestCase {
    func testSnapshotReducerBuildsSnapshotFromAccountAndRateLimits() throws {
        let account = """
        {
          "account": {
            "type": "chatgpt",
            "email": "user@example.com",
            "planType": "pro"
          }
        }
        """

        let rateLimits = """
        {
          "rateLimitsByLimitId": {
            "other-limit": {
              "limitId": "other-limit",
              "limitName": "Other",
              "primary": { "usedPercent": 3, "windowDurationMins": 60, "resetsAt": 1800000000 }
            },
            "codex-5h": {
              "limitId": "codex-5h",
              "limitName": "Codex",
              "primary": { "usedPercent": 44, "windowDurationMins": 300, "resetsAt": 1800000000 },
              "secondary": { "usedPercent": 12, "windowDurationMins": 10080, "resetsAt": 1800050000 }
            }
          }
        }
        """

        let snapshot = try CodexTestSupport.snapshotFromJSON(
            executablePath: "/App/Helper",
            accountJSON: account,
            rateLimitsJSON: rateLimits,
            now: Date(timeIntervalSince1970: 1_700_000_000)
        )

        XCTAssertEqual(snapshot.account.email, "user@example.com")
        XCTAssertEqual(snapshot.limits.count, 1)
        XCTAssertEqual(snapshot.limits.map(\.id), ["codex-5h"])
        XCTAssertEqual(snapshot.limits.map(\.bucket), [.codex])

        let codexLimit = try XCTUnwrap(snapshot.limits.first)
        XCTAssertEqual(codexLimit.id, "codex-5h")
        XCTAssertEqual(codexLimit.bucket, .codex)
        XCTAssertEqual(
            codexLimit.primary,
            CodexQuotaWindow(
                usedPercent: 44,
                windowDurationMinutes: 300,
                resetsAt: Date(timeIntervalSince1970: 1_800_000_000)
            )
        )
        XCTAssertEqual(
            codexLimit.secondary,
            CodexQuotaWindow(
                usedPercent: 12,
                windowDurationMinutes: 10_080,
                resetsAt: Date(timeIntervalSince1970: 1_800_050_000)
            )
        )

    }

    func testSnapshotReducerThrowsForUnauthenticatedAccount() {
        let account = _AccountReadResult(dictionary: [:])
        let rateLimits = _RateLimitsReadResult(dictionary: [:])

        XCTAssertThrowsError(
            try _SnapshotReducer.makeSnapshot(
                executablePath: "/App/Helper",
                account: account,
                rateLimits: rateLimits
            )
        ) { error in
            XCTAssertEqual(error as? CodexProbeError, .unauthenticated)
        }
    }

    func testSnapshotReducerThrowsForNonChatGPTAccount() {
        let account = _AccountReadResult(dictionary: [
            "account": [
                "type": "other",
                "email": "user@example.com"
            ]
        ])
        let rateLimits = _RateLimitsReadResult(dictionary: [:])

        XCTAssertThrowsError(
            try _SnapshotReducer.makeSnapshot(
                executablePath: "/App/Helper",
                account: account,
                rateLimits: rateLimits
            )
        ) { error in
            XCTAssertEqual(error as? CodexProbeError, .unauthenticated)
        }
    }
}
