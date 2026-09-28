import XCTest
@testable import CodexMeterCore

final class CodexSnapshotParsingTests: XCTestCase {
    func testCodexBucketParsesAndSorts() throws {
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
        XCTAssertEqual(snapshot.limits.count, 1)
        XCTAssertEqual(snapshot.limits.first?.bucket, .codex)
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
