import Foundation

public struct CodexDeviceUserCodeResponse: Decodable, Equatable {
    public let deviceAuthID: String
    public let userCode: String
    public let interval: Int

    enum CodingKeys: String, CodingKey {
        case deviceAuthID = "device_auth_id"
        case userCode = "user_code"
        case legacyUserCode = "usercode"
        case interval
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        deviceAuthID = try container.decode(String.self, forKey: .deviceAuthID)
        userCode = try container.decodeIfPresent(String.self, forKey: .userCode)
            ?? container.decode(String.self, forKey: .legacyUserCode)
        interval = try container.decodeFlexibleIntIfPresent(forKey: .interval) ?? 0
    }
}

public struct CodexDeviceApprovedResponse: Decodable, Equatable {
    public let authorizationCode: String
    public let codeVerifier: String

    enum CodingKeys: String, CodingKey {
        case authorizationCode = "authorization_code"
        case codeVerifier = "code_verifier"
    }
}

public struct CodexTokenExchangeResponse: Decodable, Equatable {
    public let idToken: String
    public let accessToken: String
    public let refreshToken: String?
    public let expiresIn: Int?

    enum CodingKeys: String, CodingKey {
        case idToken = "id_token"
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        idToken = try container.decode(String.self, forKey: .idToken)
        accessToken = try container.decode(String.self, forKey: .accessToken)
        refreshToken = try container.decodeIfPresent(String.self, forKey: .refreshToken)
        expiresIn = try container.decodeFlexibleIntIfPresent(forKey: .expiresIn)
    }
}

public struct CodexChatGPTJWTClaims: Equatable {
    public let email: String?
    public let accountID: String?
    public let planType: String?
}

public enum CodexChatGPTAuthParsing {
    public static func claims(fromJWT token: String) -> CodexChatGPTJWTClaims {
        guard let payload = jwtPayload(token) else {
            return CodexChatGPTJWTClaims(email: nil, accountID: nil, planType: nil)
        }

        let auth = payload["https://api.openai.com/auth"] as? [String: Any]
        let accountID = auth?["chatgpt_account_id"] as? String
            ?? payload["chatgpt_account_id"] as? String
            ?? payload["account_id"] as? String
        let planType = auth?["chatgpt_plan_type"] as? String
            ?? payload["chatgpt_plan_type"] as? String
            ?? payload["plan_type"] as? String

        return CodexChatGPTJWTClaims(
            email: payload["email"] as? String,
            accountID: accountID,
            planType: planType
        )
    }

    private static func jwtPayload(_ token: String) -> [String: Any]? {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var base64 = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 {
            base64.append("=")
        }
        guard let data = Data(base64Encoded: base64),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return object
    }
}

private extension KeyedDecodingContainer {
    func decodeFlexibleIntIfPresent(forKey key: Key) throws -> Int? {
        if let value = try? decodeIfPresent(Int.self, forKey: key) {
            return value
        }
        if let value = try? decodeIfPresent(String.self, forKey: key) {
            return Int(value.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return nil
    }
}
