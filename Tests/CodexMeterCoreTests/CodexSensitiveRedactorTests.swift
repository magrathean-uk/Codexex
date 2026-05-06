import XCTest
@testable import CodexMeterCore

final class CodexSensitiveRedactorTests: XCTestCase {
    func testRedactsAuthMaterialAndKeepsOperationalContext() {
        let raw = """
        user test@example.com failed Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJhY2N0IjoiMSJ9.signature1234567890 \
        access_token=tok_live_123456789 code_verifier=verifierSecret123 device_auth_id=deviceSecret \
        https://auth.openai.com/oauth/token?code=authCode&account_id=acc_1234567890 ABCD-1234
        """

        let redacted = CodexSensitiveRedactor.redacted(raw)

        XCTAssertFalse(redacted.contains("test@example.com"))
        XCTAssertFalse(redacted.contains("tok_live_123456789"))
        XCTAssertFalse(redacted.contains("verifierSecret123"))
        XCTAssertFalse(redacted.contains("deviceSecret"))
        XCTAssertFalse(redacted.contains("authCode"))
        XCTAssertFalse(redacted.contains("acc_1234567890"))
        XCTAssertFalse(redacted.contains("ABCD-1234"))
        XCTAssertTrue(redacted.contains("/oauth/token"))
        XCTAssertTrue(redacted.contains("<email>"))
        XCTAssertTrue(redacted.contains("<redacted>"))
    }
}
