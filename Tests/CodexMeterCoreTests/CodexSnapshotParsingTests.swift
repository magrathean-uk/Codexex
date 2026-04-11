import XCTest
@testable import CodexMeterCore

final class CodexSnapshotParsingTests: XCTestCase {
    func testSeparateSparkBucketParsesAndSorts() throws {
        let account = """
        {
          "account": {
            "type": "chatgpt",
            "email": "user@example.com",
            "planType": "pro"
          },
          "requiresOpenaiAuth": true
        }
        """

        let rateLimits = """
        {
          "rateLimits": {
            "limitId": "codex",
            "limitName": null,
            "primary": { "usedPercent": 25, "windowDurationMins": 15, "resetsAt": 1730947200 },
            "secondary": null
          },
          "rateLimitsByLimitId": {
            "codex": {
              "limitId": "codex",
              "limitName": null,
              "primary": { "usedPercent": 25, "windowDurationMins": 15, "resetsAt": 1730947200 },
              "secondary": null
            },
            "gpt-5.3-codex-spark": {
              "limitId": "gpt-5.3-codex-spark",
              "limitName": "Codex Spark",
              "primary": { "usedPercent": 42, "windowDurationMins": 60, "resetsAt": 1730950800 },
              "secondary": null
            }
          }
        }
        """

        let snapshot = try CodexTestSupport.snapshotFromJSON(
            executablePath: "/Applications/Codex.app/Contents/Resources/codex",
            accountJSON: account,
            rateLimitsJSON: rateLimits
        )

        XCTAssertEqual(snapshot.account.email, "user@example.com")
        XCTAssertEqual(snapshot.limits.count, 2)
        XCTAssertEqual(snapshot.limits.first?.bucket, .codex)
        XCTAssertEqual(snapshot.sparkLimit?.bucket, .spark)
        XCTAssertEqual(snapshot.sparkLimit?.primary?.usedPercentText, "42%")
    }

    func testNonChatGPTAuthRejected() throws {
        let account = """
        {
          "account": {
            "type": "other"
          },
          "requiresOpenaiAuth": true
        }
        """

        let rateLimits = """
        {
          "rateLimits": {
            "limitId": "codex",
            "limitName": null,
            "primary": { "usedPercent": 25, "windowDurationMins": 15, "resetsAt": 1730947200 },
            "secondary": null
          }
        }
        """

        XCTAssertThrowsError(
            try CodexTestSupport.snapshotFromJSON(
                executablePath: "/usr/local/bin/codex",
                accountJSON: account,
                rateLimitsJSON: rateLimits
            )
        ) { error in
            XCTAssertEqual(error as? CodexProbeError, .unauthenticated)
        }
    }
}
