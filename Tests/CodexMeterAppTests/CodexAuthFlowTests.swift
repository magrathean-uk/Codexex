import XCTest
@testable import CodexMeterApp
@testable import CodexMeterCore

final class CodexAuthFlowTests: XCTestCase {
    func testBeginFailureTurnsRateLimitIntoShortCooldown() {
        let outcome = CodexAuthFlow.beginFailure(
            NSError(domain: "Test", code: 429, userInfo: [NSLocalizedDescriptionKey: "HTTP 429"]),
            now: Date(timeIntervalSince1970: 1_800_000_000)
        )

        XCTAssertEqual(outcome.message, "OpenAI is rate-limiting sign-in right now. Wait 10 seconds and try again.")
        XCTAssertEqual(outcome.retryNotBefore, Date(timeIntervalSince1970: 1_800_000_010))
    }

    func testSnapshotResponseKeepsPendingDeviceCodeWhenAuthModeUnknown() {
        let response = CodexServiceSnapshotResponse(authMode: nil, snapshot: nil, errorMessage: nil)

        XCTAssertTrue(CodexAuthFlow.shouldPreservePendingDeviceCode(response: response, hasPendingDeviceCode: true))
        XCTAssertFalse(CodexAuthFlow.shouldPreservePendingDeviceCode(response: response, hasPendingDeviceCode: false))
    }

    func testSignedOutMessageFallsBackToSignInCopy() {
        let response = CodexServiceSnapshotResponse(authMode: nil, snapshot: nil, errorMessage: nil)

        XCTAssertEqual(
            CodexAuthFlow.signedOutMessage(for: response),
            "Not signed in. Use the button below."
        )
    }
}
