import AuthenticationServices
import Foundation
import Security
import CodexMeterCore

enum CodexiOSError: LocalizedError {
    case notSignedIn
    case badResponse(String)
    case requestFailed(Int, String)

    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            return "Not signed in. Sign in with ChatGPT to read your Codex quota."
        case .badResponse(let message):
            return message
        case .requestFailed(let status, let body):
            return "OpenAI returned \(status). \(body)"
        }
    }
}

struct CodexiOSDeviceAuthStart: Equatable {
    let flowID: String
    let verificationURL: URL
    let userCode: String
}

enum CodexiOSPollResult: Equatable {
    case pending(String)
    case signedIn
}

actor CodexiOSService {
    private let session: URLSession
    private let keychain: CodexiOSTokenStore
    private let issuer = URL(string: "https://auth.openai.com")!
    private let chatGPTBaseURL = URL(string: "https://chatgpt.com/backend-api")!
    private let clientID = "app_EMoamEEZ73f0CkXaXp7hrann"

    init(
        session: URLSession = .shared,
        keychain: CodexiOSTokenStore = CodexiOSTokenStore()
    ) {
        self.session = session
        self.keychain = keychain
    }

    func fetchSnapshot() async throws -> CodexServiceSnapshotResponse {
        guard var tokens = try keychain.load() else {
            return CodexServiceSnapshotResponse(authMode: nil, snapshot: nil, errorMessage: CodexiOSError.notSignedIn.localizedDescription)
        }

        if tokens.shouldRefresh {
            tokens = try await refresh(tokens: tokens)
            try keychain.save(tokens)
        }

        let url = chatGPTBaseURL.appending(path: "wham/usage")
        var request = URLRequest(url: url)
        request.setValue("Bearer \(tokens.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("codexex-ios", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let accountID = tokens.accountID {
            request.setValue(accountID, forHTTPHeaderField: "ChatGPT-Account-Id")
        }

        do {
            let data = try await data(for: request)
            let snapshot = try CodexRateLimitPayloadMapper.snapshot(
                from: data,
                executablePath: "Codexex iOS",
                account: CodexAccount(authType: "chatGPT", email: tokens.email, planType: tokens.planType)
            )
            return CodexServiceSnapshotResponse(authMode: .chatGPT, snapshot: snapshot, errorMessage: nil)
        } catch let error as CodexiOSError {
            return CodexServiceSnapshotResponse(authMode: .chatGPT, snapshot: nil, errorMessage: error.localizedDescription)
        }
    }

    func beginSignIn() async throws -> CodexiOSDeviceAuthStart {
        let url = issuer.appending(path: "api/accounts/deviceauth/usercode")
        let payload = try JSONEncoder().encode(UserCodeRequest(clientID: clientID))
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = payload
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let data = try await data(for: request)
        let response = try JSONDecoder().decode(UserCodeResponse.self, from: data)
        let stored = StoredDeviceCode(
            verificationURL: issuer.appending(path: "codex/device"),
            userCode: response.userCode,
            deviceAuthID: response.deviceAuthID,
            interval: response.interval
        )
        return CodexiOSDeviceAuthStart(
            flowID: try stored.flowID(),
            verificationURL: stored.verificationURL,
            userCode: stored.userCode
        )
    }

    func pollSignIn(flowID: String) async throws -> CodexiOSPollResult {
        let stored = try StoredDeviceCode(flowID: flowID)
        let url = issuer.appending(path: "api/accounts/deviceauth/token")
        let payload = try JSONEncoder().encode(TokenPollRequest(deviceAuthID: stored.deviceAuthID, userCode: stored.userCode))
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = payload
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            let data = try await data(for: request, pendingStatuses: [403, 404])
            let approved = try JSONDecoder().decode(DeviceCodeApprovedResponse.self, from: data)
            let tokens = try await exchange(approved: approved)
            try keychain.save(tokens)
            return .signedIn
        } catch let error as CodexiOSError {
            if case .requestFailed(let status, _) = error, status == 403 || status == 404 {
                return .pending("Still waiting. Finish in Safari, then check again.")
            }
            throw error
        }
    }

    func signOut() throws {
        try keychain.clear()
    }

    private func exchange(approved: DeviceCodeApprovedResponse) async throws -> CodexiOSTokens {
        let url = issuer.appending(path: "oauth/token")
        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "grant_type", value: "authorization_code"),
            URLQueryItem(name: "code", value: approved.authorizationCode),
            URLQueryItem(name: "redirect_uri", value: issuer.appending(path: "deviceauth/callback").absoluteString),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "code_verifier", value: approved.codeVerifier)
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = components.percentEncodedQuery?.data(using: .utf8)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let data = try await data(for: request)
        let response = try JSONDecoder().decode(TokenExchangeResponse.self, from: data)
        return CodexiOSTokens(response: response)
    }

    private func refresh(tokens: CodexiOSTokens) async throws -> CodexiOSTokens {
        let url = issuer.appending(path: "oauth/token")
        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "grant_type", value: "refresh_token"),
            URLQueryItem(name: "refresh_token", value: tokens.refreshToken),
            URLQueryItem(name: "client_id", value: clientID)
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = components.percentEncodedQuery?.data(using: .utf8)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let data = try await data(for: request)
        let response = try JSONDecoder().decode(TokenExchangeResponse.self, from: data)
        return CodexiOSTokens(response: response, fallbackRefreshToken: tokens.refreshToken)
    }

    private func data(for request: URLRequest, pendingStatuses: Set<Int> = []) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw CodexiOSError.badResponse("OpenAI returned an invalid response.")
        }
        guard (200 ..< 300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw CodexiOSError.requestFailed(http.statusCode, String(body.prefix(180)))
        }
        return data
    }
}

struct CodexiOSTokens: Codable, Equatable {
    let idToken: String
    let accessToken: String
    let refreshToken: String
    let createdAt: Date
    let expiresAt: Date
    let email: String?
    let accountID: String?
    let planType: String?

    var shouldRefresh: Bool {
        Date() >= expiresAt.addingTimeInterval(-120)
    }

    fileprivate init(response: TokenExchangeResponse, fallbackRefreshToken: String? = nil, now: Date = Date()) {
        idToken = response.idToken
        accessToken = response.accessToken
        refreshToken = response.refreshToken ?? fallbackRefreshToken ?? ""
        createdAt = now
        expiresAt = now.addingTimeInterval(TimeInterval(response.expiresIn ?? 3600))
        let claims = Self.jwtClaims(response.idToken)
        email = claims?["email"] as? String
        accountID = claims?["https://api.openai.com/auth"] as? String
            ?? claims?["chatgpt_account_id"] as? String
            ?? claims?["account_id"] as? String
        planType = claims?["chatgpt_plan_type"] as? String
    }

    private static func jwtClaims(_ token: String) -> [String: Any]? {
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

struct CodexiOSTokenStore {
    private let service = "com.magrathean.CodexexApp.iOS"
    private let account = "chatgpt-tokens"

    func load() throws -> CodexiOSTokens? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess, let data = item as? Data else {
            throw CodexiOSError.badResponse("Could not read saved sign-in.")
        }
        return try JSONDecoder().decode(CodexiOSTokens.self, from: data)
    }

    func save(_ tokens: CodexiOSTokens) throws {
        let data = try JSONEncoder().encode(tokens)
        var query = baseQuery()
        SecItemDelete(query as CFDictionary)
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw CodexiOSError.badResponse("Could not save sign-in.")
        }
    }

    func clear() throws {
        SecItemDelete(baseQuery() as CFDictionary)
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}

private struct UserCodeRequest: Encodable {
    let clientID: String

    enum CodingKeys: String, CodingKey {
        case clientID = "client_id"
    }
}

private struct UserCodeResponse: Decodable {
    let deviceAuthID: String
    let userCode: String
    let interval: Int

    enum CodingKeys: String, CodingKey {
        case deviceAuthID = "device_auth_id"
        case userCode = "user_code"
        case interval
    }
}

private struct TokenPollRequest: Encodable {
    let deviceAuthID: String
    let userCode: String

    enum CodingKeys: String, CodingKey {
        case deviceAuthID = "device_auth_id"
        case userCode = "user_code"
    }
}

private struct DeviceCodeApprovedResponse: Decodable {
    let authorizationCode: String
    let codeVerifier: String

    enum CodingKeys: String, CodingKey {
        case authorizationCode = "authorization_code"
        case codeVerifier = "code_verifier"
    }
}

private struct TokenExchangeResponse: Decodable {
    let idToken: String
    let accessToken: String
    let refreshToken: String?
    let expiresIn: Int?

    enum CodingKeys: String, CodingKey {
        case idToken = "id_token"
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
    }
}

private struct StoredDeviceCode: Codable {
    let verificationURL: URL
    let userCode: String
    let deviceAuthID: String
    let interval: Int

    init(verificationURL: URL, userCode: String, deviceAuthID: String, interval: Int) {
        self.verificationURL = verificationURL
        self.userCode = userCode
        self.deviceAuthID = deviceAuthID
        self.interval = interval
    }

    init(flowID: String) throws {
        var base64 = flowID.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 {
            base64.append("=")
        }
        guard let data = Data(base64Encoded: base64) else {
            throw CodexiOSError.badResponse("Sign-in code expired. Start again.")
        }
        self = try JSONDecoder().decode(StoredDeviceCode.self, from: data)
    }

    func flowID() throws -> String {
        try JSONEncoder().encode(self).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
