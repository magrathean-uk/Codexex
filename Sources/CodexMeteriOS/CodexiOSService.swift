import Foundation
import CodexMeterCore

enum CodexiOSError: LocalizedError, Equatable {
    case notSignedIn
    case signInExpired
    case badResponse(String)
    case requestFailed(Int)
    case secureStoreFailure(String)

    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            return "Not signed in. Sign in with ChatGPT to read your Codex quota."
        case .signInExpired:
            return "Sign-in code expired. Start again."
        case .badResponse(let message), .secureStoreFailure(let message):
            return message
        case .requestFailed(let status):
            switch status {
            case 401, 403:
                return "Sign-in expired. Sign in again."
            case 408:
                return "OpenAI took too long to respond. Try again."
            case 425, 429:
                return "OpenAI is rate-limiting requests. Try again soon."
            case 500 ..< 600:
                return "OpenAI is having trouble right now. Try again soon."
            default:
                return "OpenAI returned \(status). Try again."
            }
        }
    }
}

struct CodexiOSRetryMetadata: Equatable, Sendable {
    let retryAfter: Date?
    let isTransient: Bool

    static let immediate = CodexiOSRetryMetadata(retryAfter: nil, isTransient: true)
}

enum CodexiOSSnapshotOutcome: Equatable, Sendable {
    case loaded(CodexSnapshot)
    case signedOut
    case authExpired(String)
    case unavailable(message: String, hasStoredCredentials: Bool, retry: CodexiOSRetryMetadata)
    case superseded

    static func legacy(_ response: CodexServiceSnapshotResponse) -> CodexiOSSnapshotOutcome {
        if let snapshot = response.snapshot { return .loaded(snapshot) }
        if response.authMode == .chatGPT {
            return .unavailable(
                message: response.errorMessage ?? "No quota data yet.",
                hasStoredCredentials: true,
                retry: .immediate
            )
        }
        return .signedOut
    }
}

struct CodexiOSDeviceAuthStart: Equatable, Sendable {
    let flowID: String
    let verificationURL: URL
    let userCode: String
}

enum CodexiOSPollResult: Equatable, Sendable {
    case pending(String)
    case signedIn
}

private struct CodexiOSHTTPFailure: LocalizedError {
    let status: Int
    let retryAfter: Date?

    var errorDescription: String? {
        CodexiOSError.requestFailed(status).localizedDescription
    }

    var isAuthenticationFailure: Bool { status == 401 || status == 403 }
    var isPendingDeviceAuthorization: Bool { status == 403 || status == 404 }
    var isTransient: Bool {
        status == 408 || status == 425 || status == 429 || (500 ..< 600).contains(status)
    }
}

actor CodexiOSService: CodexiOSServiceProtocol {
    static let verificationURL = URL(string: "https://auth.openai.com/codex/device")!
    static let requestTimeout: TimeInterval = 20
    static let resourceTimeout: TimeInterval = 30

    private let session: URLSession
    private let keychain: CodexiOSTokenStore
    private let pendingStore: CodexiOSPendingAuthStore
    private let credentialCoordinator: CodexiOSCredentialCoordinator
    private let issuer = URL(string: "https://auth.openai.com")!
    private let chatGPTBaseURL = URL(string: "https://chatgpt.com/backend-api")!
    private let clientID = "app_EMoamEEZ73f0CkXaXp7hrann"

    init(
        session: URLSession = CodexiOSService.makeSession(),
        keychain: CodexiOSTokenStore = CodexiOSTokenStore(),
        pendingStore: CodexiOSPendingAuthStore = CodexiOSPendingAuthStore(),
        credentialCoordinator: CodexiOSCredentialCoordinator = .shared
    ) {
        self.session = session
        self.keychain = keychain
        self.pendingStore = pendingStore
        self.credentialCoordinator = credentialCoordinator
    }

    nonisolated static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = requestTimeout
        configuration.timeoutIntervalForResource = resourceTimeout
        configuration.waitsForConnectivity = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        return URLSession(configuration: configuration)
    }

    func fetchSnapshot() async throws -> CodexiOSSnapshotOutcome {
        var generation: UInt64
        let storedTokens: CodexiOSTokens
        do {
            let loaded = try credentialCoordinator.loadTokens(from: keychain)
            generation = loaded.generation
            guard let tokens = loaded.tokens else { return .signedOut }
            storedTokens = tokens
        } catch {
            return unavailable(error, hasStoredCredentials: true)
        }

        guard storedTokens.hasUsableRefreshToken else {
            return clearExpiredCredentialsIfCurrent(generation: generation)
        }

        var tokens = storedTokens
        var didRefreshTokens = false
        if tokens.shouldRefresh {
            do {
                let refreshResult = try await credentialCoordinator.refreshTokens(
                    tokens,
                    expectedGeneration: generation,
                    store: keychain,
                    operation: { [self] tokens in
                        try await refresh(tokens: tokens)
                    }
                )
                switch refreshResult {
                case .ready(let refreshedGeneration, let refreshedTokens):
                    generation = refreshedGeneration
                    tokens = refreshedTokens
                    didRefreshTokens = true
                case .superseded:
                    return .superseded
                }
                try Task.checkCancellation()
            } catch let failure as CodexiOSHTTPFailure where failure.isAuthenticationFailure {
                return clearExpiredCredentialsIfCurrent(generation: generation)
            } catch is CancellationError {
                return .superseded
            } catch {
                guard credentialCoordinator.isCurrent(generation) else { return .superseded }
                return unavailable(error, hasStoredCredentials: true)
            }
        }

        return await fetchUsageSnapshot(
            tokens: tokens,
            generation: generation,
            mayRefreshAfterUnauthorized: didRefreshTokens == false
        )
    }

    private func fetchUsageSnapshot(
        tokens: CodexiOSTokens,
        generation: UInt64,
        mayRefreshAfterUnauthorized: Bool
    ) async -> CodexiOSSnapshotOutcome {
        let url = chatGPTBaseURL.appending(path: "wham/usage")
        var request = URLRequest(url: url, timeoutInterval: Self.requestTimeout)
        request.setValue("Bearer \(tokens.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("codexex-ios", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let accountID = tokens.accountID {
            request.setValue(accountID, forHTTPHeaderField: "ChatGPT-Account-Id")
        }

        do {
            let data = try await data(for: request)
            guard credentialCoordinator.isCurrent(generation) else { return .superseded }
            let snapshot = try CodexRateLimitPayloadMapper.snapshot(
                from: data,
                executablePath: "Codexex iOS",
                account: CodexAccount(authType: "chatGPT", email: tokens.email, planType: tokens.planType)
            )
            _ = try? credentialCoordinator.clearPending(
                expectedGeneration: generation,
                store: pendingStore
            )
            return .loaded(snapshot)
        } catch let failure as CodexiOSHTTPFailure where failure.status == 401 {
            guard credentialCoordinator.isCurrent(generation) else { return .superseded }
            guard mayRefreshAfterUnauthorized else {
                return usageAuthorizationUnavailable(status: failure.status)
            }
            return await refreshAfterUsageRejection(
                tokens: tokens,
                generation: generation
            )
        } catch let failure as CodexiOSHTTPFailure where failure.status == 403 {
            guard credentialCoordinator.isCurrent(generation) else { return .superseded }
            return usageAuthorizationUnavailable(status: failure.status)
        } catch is CancellationError {
            return .superseded
        } catch {
            guard credentialCoordinator.isCurrent(generation) else { return .superseded }
            return unavailable(error, hasStoredCredentials: true)
        }
    }

    private func refreshAfterUsageRejection(
        tokens: CodexiOSTokens,
        generation: UInt64
    ) async -> CodexiOSSnapshotOutcome {
        do {
            let refreshResult = try await credentialCoordinator.refreshTokens(
                tokens,
                expectedGeneration: generation,
                store: keychain,
                operation: { [self] tokens in
                    try await refresh(tokens: tokens)
                }
            )
            switch refreshResult {
            case .ready(let refreshedGeneration, let refreshedTokens):
                try Task.checkCancellation()
                return await fetchUsageSnapshot(
                    tokens: refreshedTokens,
                    generation: refreshedGeneration,
                    mayRefreshAfterUnauthorized: false
                )
            case .superseded:
                return .superseded
            }
        } catch let failure as CodexiOSHTTPFailure where failure.isAuthenticationFailure {
            return clearExpiredCredentialsIfCurrent(generation: generation)
        } catch is CancellationError {
            return .superseded
        } catch {
            guard credentialCoordinator.isCurrent(generation) else { return .superseded }
            return unavailable(error, hasStoredCredentials: true)
        }
    }

    func recoverPendingSignIn() async throws -> CodexiOSDeviceAuthStart? {
        try credentialCoordinator.recoverPending(
            tokenStore: keychain,
            pendingStore: pendingStore
        )?.deviceAuthStart
    }

    func beginSignIn() async throws -> CodexiOSDeviceAuthStart {
        let generation = try credentialCoordinator.beginPendingFlow(pendingStore: pendingStore)

        let url = issuer.appending(path: "api/accounts/deviceauth/usercode")
        let payload = try JSONEncoder().encode(UserCodeRequest(clientID: clientID))
        var request = URLRequest(url: url, timeoutInterval: Self.requestTimeout)
        request.httpMethod = "POST"
        request.httpBody = payload
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let data = try await data(for: request)
        guard credentialCoordinator.isCurrent(generation) else { throw CancellationError() }
        let response = try JSONDecoder().decode(CodexDeviceUserCodeResponse.self, from: data)
        let now = Date()
        let record = CodexiOSPendingAuthRecord(
            flowID: try CodexiOSSecureRandom.flowID(),
            userCode: response.userCode,
            deviceAuthID: response.deviceAuthID,
            interval: min(max(response.interval, 1), 30),
            createdAt: now,
            expiresAt: now.addingTimeInterval(CodexiOSPendingAuthStore.ttl),
            lastPolledAt: nil
        )
        guard try credentialCoordinator.savePending(
            record,
            expectedGeneration: generation,
            to: pendingStore
        ) else { throw CancellationError() }
        return record.deviceAuthStart
    }

    func pollSignIn(flowID: String) async throws -> CodexiOSPollResult {
        try await credentialCoordinator.performPendingSignIn(flowID: flowID) { [self] in
            try await performPollSignIn(flowID: flowID)
        }
    }

    private func performPollSignIn(flowID: String) async throws -> CodexiOSPollResult {
        switch try credentialCoordinator.claimPendingSignIn(
            flowID: flowID,
            store: pendingStore
        ) {
        case .wait(let nextPollAt):
            return .pending(Self.pendingMessage(nextPollAt: nextPollAt, now: Date()))
        case .poll(let generation, let pending):
            return try await pollForApproval(
                flowID: flowID,
                generation: generation,
                pending: pending
            )
        case .exchange(let generation, let approved):
            return try await exchangeAndFinish(
                flowID: flowID,
                generation: generation,
                approved: approved
            )
        case .persist(let generation, let tokens):
            return try persistExchangedTokens(
                tokens,
                generation: generation
            )
        }
    }

    private func pollForApproval(
        flowID: String,
        generation: UInt64,
        pending: CodexiOSPendingAuthRecord
    ) async throws -> CodexiOSPollResult {

        let url = issuer.appending(path: "api/accounts/deviceauth/token")
        let payload = try JSONEncoder().encode(
            TokenPollRequest(deviceAuthID: pending.deviceAuthID, userCode: pending.userCode)
        )
        var request = URLRequest(url: url, timeoutInterval: Self.requestTimeout)
        request.httpMethod = "POST"
        request.httpBody = payload
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let approved: CodexDeviceApprovedResponse
        do {
            approved = try JSONDecoder().decode(
                CodexDeviceApprovedResponse.self,
                from: try await data(for: request)
            )
        } catch let failure as CodexiOSHTTPFailure where failure.isPendingDeviceAuthorization {
            guard (try? credentialCoordinator.deferPendingSignIn(
                flowID: flowID,
                expectedGeneration: generation,
                retryAfter: failure.retryAfter,
                store: pendingStore
            )) == true else { throw CancellationError() }
            return .pending("Still waiting. Finish in Safari, then check again.")
        } catch let failure as CodexiOSHTTPFailure where failure.isTransient {
            guard (try? credentialCoordinator.deferPendingSignIn(
                flowID: flowID,
                expectedGeneration: generation,
                retryAfter: failure.retryAfter,
                store: pendingStore
            )) == true else { throw CancellationError() }
            throw failure
        } catch is URLError {
            throw CodexiOSError.badResponse("Could not check sign-in. Check your connection and try again.")
        } catch {
            _ = try? credentialCoordinator.clearPending(
                expectedGeneration: generation,
                store: pendingStore
            )
            throw error
        }

        let approvedRecord = CodexiOSApprovedAuthRecord(approved)
        guard try credentialCoordinator.markApproved(
            approvedRecord,
            flowID: flowID,
            expectedGeneration: generation,
            store: pendingStore
        ) else { throw CancellationError() }
        return try await exchangeAndFinish(
            flowID: flowID,
            generation: generation,
            approved: approvedRecord
        )
    }

    func cancelSignIn() async throws {
        try credentialCoordinator.cancelSignIn(pendingStore: pendingStore)
    }

    func signOut() async throws {
        try credentialCoordinator.signOut(
            tokenStore: keychain,
            pendingStore: pendingStore
        )
    }

    private func exchangeAndFinish(
        flowID: String,
        generation: UInt64,
        approved: CodexiOSApprovedAuthRecord
    ) async throws -> CodexiOSPollResult {
        let tokens: CodexiOSTokens
        do {
            tokens = try await exchange(approved: approved)
        } catch let failure as CodexiOSHTTPFailure where failure.isTransient {
            guard (try? credentialCoordinator.deferPendingSignIn(
                flowID: flowID,
                expectedGeneration: generation,
                retryAfter: failure.retryAfter,
                store: pendingStore
            )) == true else { throw CancellationError() }
            throw failure
        } catch is URLError {
            throw CodexiOSError.badResponse("Could not finish sign-in. Check your connection and try again.")
        } catch {
            _ = try? credentialCoordinator.clearPending(
                expectedGeneration: generation,
                store: pendingStore
            )
            throw error
        }

        guard try credentialCoordinator.markExchanged(
            tokens,
            flowID: flowID,
            expectedGeneration: generation,
            store: pendingStore
        ) else { throw CancellationError() }
        return try persistExchangedTokens(tokens, generation: generation)
    }

    private func persistExchangedTokens(
        _ tokens: CodexiOSTokens,
        generation: UInt64
    ) throws -> CodexiOSPollResult {
        guard try credentialCoordinator.finishSignIn(
            tokens: tokens,
            expectedGeneration: generation,
            tokenStore: keychain,
            pendingStore: pendingStore
        ) else { throw CancellationError() }
        return .signedIn
    }

    private func exchange(approved: CodexiOSApprovedAuthRecord) async throws -> CodexiOSTokens {
        let url = issuer.appending(path: "oauth/token")
        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "grant_type", value: "authorization_code"),
            URLQueryItem(name: "code", value: approved.authorizationCode),
            URLQueryItem(name: "redirect_uri", value: issuer.appending(path: "deviceauth/callback").absoluteString),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "code_verifier", value: approved.codeVerifier)
        ]

        var request = URLRequest(url: url, timeoutInterval: Self.requestTimeout)
        request.httpMethod = "POST"
        request.httpBody = components.percentEncodedQuery?.data(using: .utf8)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let response = try JSONDecoder().decode(
            CodexTokenExchangeResponse.self,
            from: try await data(for: request)
        )
        return try CodexiOSTokens(response: response)
    }

    private func refresh(tokens: CodexiOSTokens) async throws -> CodexiOSTokens {
        guard tokens.hasUsableRefreshToken else { throw CodexiOSError.notSignedIn }
        let url = issuer.appending(path: "oauth/token")
        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "grant_type", value: "refresh_token"),
            URLQueryItem(name: "refresh_token", value: tokens.refreshToken),
            URLQueryItem(name: "client_id", value: clientID)
        ]

        var request = URLRequest(url: url, timeoutInterval: Self.requestTimeout)
        request.httpMethod = "POST"
        request.httpBody = components.percentEncodedQuery?.data(using: .utf8)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let response = try JSONDecoder().decode(
            CodexTokenExchangeResponse.self,
            from: try await data(for: request)
        )
        return try CodexiOSTokens(response: response, fallbackRefreshToken: tokens.refreshToken)
    }

    private func data(for request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse else {
            throw CodexiOSError.badResponse("OpenAI returned an invalid response.")
        }
        guard (200 ..< 300).contains(http.statusCode) else {
            throw CodexiOSHTTPFailure(
                status: http.statusCode,
                retryAfter: Self.retryAfter(from: http)
            )
        }
        return data
    }

    private func clearExpiredCredentialsIfCurrent(generation: UInt64) -> CodexiOSSnapshotOutcome {
        do {
            guard try credentialCoordinator.clearExpiredCredentials(
                expectedGeneration: generation,
                tokenStore: keychain,
                pendingStore: pendingStore
            ) else { return .superseded }
            return .authExpired("Sign-in expired. Sign in again.")
        } catch {
            return unavailable(error, hasStoredCredentials: true)
        }
    }

    private func unavailable(_ error: Error, hasStoredCredentials: Bool) -> CodexiOSSnapshotOutcome {
        let retryAfter = (error as? CodexiOSHTTPFailure)?.retryAfter
        let transient = (error as? CodexiOSHTTPFailure)?.isTransient ?? true
        return .unavailable(
            message: Self.message(for: error),
            hasStoredCredentials: hasStoredCredentials,
            retry: CodexiOSRetryMetadata(retryAfter: retryAfter, isTransient: transient)
        )
    }

    private func usageAuthorizationUnavailable(status: Int) -> CodexiOSSnapshotOutcome {
        let message = status == 403
            ? "OpenAI denied access to quota data. Try again later."
            : "OpenAI did not accept the refreshed session. Try again later."
        return .unavailable(
            message: message,
            hasStoredCredentials: true,
            retry: CodexiOSRetryMetadata(retryAfter: nil, isTransient: false)
        )
    }

    private nonisolated static func retryAfter(from response: HTTPURLResponse) -> Date? {
        guard let raw = response.value(forHTTPHeaderField: "Retry-After")?.trimmingCharacters(in: .whitespacesAndNewlines),
              raw.isEmpty == false else { return nil }
        if let seconds = TimeInterval(raw) { return Date().addingTimeInterval(max(0, seconds)) }
        return HTTPDateFormatter.date(from: raw)
    }

    private nonisolated static func message(for error: Error) -> String {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost:
                return "No internet connection. Try again when you are online."
            case .timedOut:
                return "OpenAI took too long to respond. Try again."
            default:
                return "Could not reach OpenAI. Try again."
            }
        }
        if let localized = error as? LocalizedError, let description = localized.errorDescription {
            return description
        }
        return error.localizedDescription
    }

    private nonisolated static func pendingMessage(nextPollAt: Date?, now: Date) -> String {
        guard let nextPollAt, nextPollAt > now else {
            return "Still waiting. Finish in Safari, then check again."
        }
        let seconds = max(1, Int(ceil(nextPollAt.timeIntervalSince(now))))
        return "Still waiting. Check again in \(seconds) seconds."
    }
}

struct CodexiOSTokens: Codable, Equatable, Sendable {
    let idToken: String
    let accessToken: String
    let refreshToken: String
    let createdAt: Date
    let expiresAt: Date
    let email: String?
    let accountID: String?
    let planType: String?

    var shouldRefresh: Bool { Date() >= expiresAt.addingTimeInterval(-120) }
    var hasUsableRefreshToken: Bool { refreshToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false }

    init(
        idToken: String,
        accessToken: String,
        refreshToken: String,
        createdAt: Date,
        expiresAt: Date,
        email: String? = nil,
        accountID: String? = nil,
        planType: String? = nil
    ) {
        self.idToken = idToken
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.createdAt = createdAt
        self.expiresAt = expiresAt
        self.email = email
        self.accountID = accountID
        self.planType = planType
    }

    fileprivate init(
        response: CodexTokenExchangeResponse,
        fallbackRefreshToken: String? = nil,
        now: Date = Date()
    ) throws {
        let resolvedRefreshToken = response.refreshToken ?? fallbackRefreshToken
        guard response.idToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
              response.idToken.utf8.count <= 64 * 1_024 else {
            throw CodexiOSError.badResponse("OpenAI returned an invalid identity token. Try again.")
        }
        guard response.accessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
              response.accessToken.utf8.count <= 64 * 1_024 else {
            throw CodexiOSError.badResponse("OpenAI returned an invalid access token. Try again.")
        }
        guard let resolvedRefreshToken,
              resolvedRefreshToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
              resolvedRefreshToken.utf8.count <= 64 * 1_024 else {
            throw CodexiOSError.badResponse("OpenAI did not return a refresh token. Start sign-in again.")
        }
        let expiresIn = response.expiresIn ?? 3_600
        guard (1 ... 365 * 24 * 60 * 60).contains(expiresIn) else {
            throw CodexiOSError.badResponse("OpenAI returned an invalid session lifetime. Try again.")
        }
        idToken = response.idToken
        accessToken = response.accessToken
        refreshToken = resolvedRefreshToken
        createdAt = now
        expiresAt = now.addingTimeInterval(TimeInterval(expiresIn))
        let claims = CodexChatGPTAuthParsing.claims(fromJWT: response.idToken)
        email = claims.email
        accountID = claims.accountID
        planType = claims.planType
    }
}

private enum HTTPDateFormatter {
    static func date(from value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss z"
        return formatter.date(from: value)
    }
}

private struct UserCodeRequest: Encodable {
    let clientID: String

    enum CodingKeys: String, CodingKey {
        case clientID = "client_id"
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
