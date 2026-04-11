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
            "codex-5h": {
              "limitId": "codex-5h",
              "limitName": "Codex",
              "primary": { "usedPercent": 44, "windowDurationMins": 300, "resetsAt": 1800000000 },
              "secondary": { "usedPercent": 12, "windowDurationMins": 10080, "resetsAt": 1800050000 }
            },
            "spark-week": {
              "limitId": "spark-week",
              "limitName": "Spark",
              "primary": { "usedPercent": 71, "windowDurationMins": 10080, "resetsAt": 1800100000 },
              "secondary": { "usedPercent": 9, "windowDurationMins": 300, "resetsAt": 1800150000 }
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
        XCTAssertEqual(snapshot.limits.count, 2)
        XCTAssertEqual(snapshot.limits.map(\.id), ["codex-5h", "spark-week"])
        XCTAssertEqual(snapshot.limits.map(\.bucket), [.codex, .spark])

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

        let sparkLimit = try XCTUnwrap(snapshot.limits.last)
        XCTAssertEqual(sparkLimit.id, "spark-week")
        XCTAssertEqual(sparkLimit.bucket, .spark)
        XCTAssertEqual(
            sparkLimit.primary,
            CodexQuotaWindow(
                usedPercent: 71,
                windowDurationMinutes: 10_080,
                resetsAt: Date(timeIntervalSince1970: 1_800_100_000)
            )
        )
        XCTAssertEqual(
            sparkLimit.secondary,
            CodexQuotaWindow(
                usedPercent: 9,
                windowDurationMinutes: 300,
                resetsAt: Date(timeIntervalSince1970: 1_800_150_000)
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
