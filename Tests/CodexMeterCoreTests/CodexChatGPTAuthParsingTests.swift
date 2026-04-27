import XCTest
@testable import CodexMeterCore

final class CodexChatGPTAuthParsingTests: XCTestCase {
    func testDeviceUserCodeAcceptsCodexPayloadShape() throws {
        let data = """
        {
          "device_auth_id": "device-auth-123",
          "user_code": "CODE-12345",
          "interval": "0"
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(CodexDeviceUserCodeResponse.self, from: data)

        XCTAssertEqual(response.deviceAuthID, "device-auth-123")
        XCTAssertEqual(response.userCode, "CODE-12345")
        XCTAssertEqual(response.interval, 0)
    }

    func testDeviceUserCodeAcceptsLegacyUsercodeAliasAndNumericInterval() throws {
        let data = """
        {
          "device_auth_id": "device-auth-456",
          "usercode": "CODE-67890",
          "interval": 5
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(CodexDeviceUserCodeResponse.self, from: data)

        XCTAssertEqual(response.deviceAuthID, "device-auth-456")
        XCTAssertEqual(response.userCode, "CODE-67890")
        XCTAssertEqual(response.interval, 5)
    }

    func testTokenExchangeAcceptsStringExpiresInAndNestedChatGPTClaims() throws {
        let data = """
        {
          "id_token": "\(Self.jwt(email: "user@example.com", accountID: "account-123", planType: "pro"))",
          "access_token": "access-token-123",
          "refresh_token": "refresh-token-123",
          "expires_in": "3600"
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(CodexTokenExchangeResponse.self, from: data)
        let claims = CodexChatGPTAuthParsing.claims(fromJWT: response.idToken)

        XCTAssertEqual(response.expiresIn, 3600)
        XCTAssertEqual(claims.email, "user@example.com")
        XCTAssertEqual(claims.accountID, "account-123")
        XCTAssertEqual(claims.planType, "pro")
    }

    private static func jwt(email: String, accountID: String, planType: String) -> String {
        let payload: [String: Any] = [
            "email": email,
            "https://api.openai.com/auth": [
                "chatgpt_account_id": accountID,
                "chatgpt_plan_type": planType
            ]
        ]
        let payloadData = try! JSONSerialization.data(withJSONObject: payload)
        return "header.\(payloadData.base64URLEncodedString()).signature"
    }
}

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
