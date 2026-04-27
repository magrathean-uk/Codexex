import XCTest
@testable import CodexMeterCore

final class CodexRateLimitPayloadMapperTests: XCTestCase {
    func testMapsWhamUsagePayloadIntoSnapshot() throws {
        let data = Data(
            """
            {
              "plan_type": "pro",
              "rate_limit": {
                "primary_window": {
                  "used_percent": 13,
                  "limit_window_seconds": 18000,
                  "reset_at": 1777339200
                },
                "secondary_window": {
                  "used_percent": 70,
                  "limit_window_seconds": 604800,
                  "reset_at": 1777508400
                }
              },
              "additional_rate_limits": [
                {
                  "limit_name": "Codex Spark",
                  "metered_feature": "codex_spark",
                  "rate_limit": {
                    "primary_window": {
                      "used_percent": 35,
                      "limit_window_seconds": 604800,
                      "reset_after_seconds": 3600
                    }
                  }
                }
              ],
              "credits": {
                "has_credits": true,
                "unlimited": false,
                "balance": "12.50"
              }
            }
            """.utf8
        )

        let capturedAt = Date(timeIntervalSince1970: 1_777_335_000)
        let snapshot = try CodexRateLimitPayloadMapper.snapshot(
            from: data,
            capturedAt: capturedAt,
            account: CodexAccount(authType: "chatGPT", email: "user@example.com", planType: nil)
        )

        XCTAssertEqual(snapshot.account.planType, "PRO")
        XCTAssertEqual(snapshot.codexLimit?.fiveHourWindow?.usedPercentText, "13%")
        XCTAssertEqual(snapshot.codexLimit?.weeklyWindow?.usedPercentText, "70%")
        XCTAssertEqual(snapshot.codexLimit?.credits?.balance, "12.50")
        XCTAssertEqual(snapshot.sparkLimit?.displayName, "Codex Spark")
        XCTAssertEqual(snapshot.sparkLimit?.fiveHourWindow?.usedPercentText, "35%")
    }
}
