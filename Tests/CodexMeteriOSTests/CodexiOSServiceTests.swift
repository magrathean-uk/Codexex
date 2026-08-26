import Foundation
import CodexMeterCore
import XCTest
@testable import Codexex

final class CodexiOSServiceTests: XCTestCase {
    override func tearDown() {
        CodexiOSURLProtocolStub.handler = nil
        super.tearDown()
    }

    func testSessionUsesBoundedTimeoutsAndNoPersistentWebState() {
        let configuration = CodexiOSService.makeSession().configuration

        XCTAssertEqual(configuration.timeoutIntervalForRequest, 20)
        XCTAssertEqual(configuration.timeoutIntervalForResource, 30)
        XCTAssertFalse(configuration.waitsForConnectivity)
        XCTAssertNil(configuration.urlCache)
        XCTAssertNil(configuration.httpCookieStorage)
        XCTAssertEqual(configuration.requestCachePolicy, .reloadIgnoringLocalCacheData)
    }

    func testMissingInitialRefreshTokenIsAuthExpiredAndClearedWithoutNetwork() async throws {
        let backend = InMemorySecureDataStore()
        let tokenStore = CodexiOSTokenStore(backend: backend)
        try tokenStore.save(makeTokens(refreshToken: "  "))
        let requestCount = LockedCounter()
        CodexiOSURLProtocolStub.handler = { request in
            requestCount.increment()
            return Self.response(for: request, status: 500)
        }
        let service = makeService(backend: backend)

        let outcome = try await service.fetchSnapshot()

        XCTAssertEqual(outcome, .authExpired("Sign-in expired. Sign in again."))
        XCTAssertNil(try tokenStore.load())
        XCTAssertEqual(requestCount.value, 0)
    }

    func testEarlyUsage401RefreshesAndRetriesOnce() async throws {
        let backend = InMemorySecureDataStore()
        let tokenStore = CodexiOSTokenStore(backend: backend)
        try tokenStore.save(makeTokens())
        let usageRequests = LockedCounter()
        let refreshRequests = LockedCounter()
        CodexiOSURLProtocolStub.handler = { request in
            switch request.url?.path {
            case "/backend-api/wham/usage":
                usageRequests.increment()
                if usageRequests.value == 1 {
                    return Self.response(for: request, status: 401)
                }
                return Self.response(for: request, status: 200, data: Self.usagePayload)
            case "/oauth/token":
                refreshRequests.increment()
                return Self.response(for: request, status: 200, data: Self.tokenPayload)
            default:
                return Self.response(for: request, status: 500)
            }
        }
        let service = makeService(backend: backend)

        let outcome = try await service.fetchSnapshot()

        guard case .loaded = outcome else {
            return XCTFail("Expected refreshed usage, got \(outcome)")
        }
        XCTAssertEqual(usageRequests.value, 2)
        XCTAssertEqual(refreshRequests.value, 1)
        XCTAssertEqual(try tokenStore.load()?.accessToken, "new-access")
    }

    func testUsage401ClearsCredentialsOnlyWhenRefreshTokenIsRejected() async throws {
        let backend = InMemorySecureDataStore()
        let tokenStore = CodexiOSTokenStore(backend: backend)
        try tokenStore.save(makeTokens())
        let usageRequests = LockedCounter()
        let refreshRequests = LockedCounter()
        CodexiOSURLProtocolStub.handler = { request in
            if request.url?.path == "/oauth/token" {
                refreshRequests.increment()
                return Self.response(for: request, status: 401)
            }
            usageRequests.increment()
            return Self.response(for: request, status: 401)
        }
        let service = makeService(backend: backend)

        let outcome = try await service.fetchSnapshot()

        XCTAssertEqual(outcome, .authExpired("Sign-in expired. Sign in again."))
        XCTAssertNil(try tokenStore.load())
        XCTAssertEqual(usageRequests.value, 1)
        XCTAssertEqual(refreshRequests.value, 1)
    }

    func testUsage403PreservesCredentialsWithoutRefreshing() async throws {
        let backend = InMemorySecureDataStore()
        let tokenStore = CodexiOSTokenStore(backend: backend)
        let tokens = makeTokens()
        try tokenStore.save(tokens)
        let usageRequests = LockedCounter()
        let refreshRequests = LockedCounter()
        CodexiOSURLProtocolStub.handler = { request in
            if request.url?.path == "/oauth/token" {
                refreshRequests.increment()
            } else {
                usageRequests.increment()
            }
            return Self.response(for: request, status: 403)
        }
        let service = makeService(backend: backend)

        let outcome = try await service.fetchSnapshot()

        guard case .unavailable(let message, let hasStoredCredentials, let retry) = outcome else {
            return XCTFail("Expected non-destructive unavailable outcome, got \(outcome)")
        }
        XCTAssertEqual(message, "OpenAI denied access to quota data. Try again later.")
        XCTAssertTrue(hasStoredCredentials)
        XCTAssertFalse(retry.isTransient)
        XCTAssertNil(retry.retryAfter)
        XCTAssertEqual(try tokenStore.load(), tokens)
        XCTAssertEqual(usageRequests.value, 1)
        XCTAssertEqual(refreshRequests.value, 0)
    }

    func testMalformedRefreshResponseDoesNotReplaceStoredCredentials() async throws {
        let backend = InMemorySecureDataStore()
        let tokenStore = CodexiOSTokenStore(backend: backend)
        let tokens = makeTokens(expiresAt: Date().addingTimeInterval(-60))
        try tokenStore.save(tokens)
        let usageRequests = LockedCounter()
        let refreshRequests = LockedCounter()
        CodexiOSURLProtocolStub.handler = { request in
            if request.url?.path == "/oauth/token" {
                refreshRequests.increment()
                return Self.response(
                    for: request,
                    status: 200,
                    data: Data(
                        #"{"id_token":"header.payload.signature","access_token":" ","refresh_token":"new-refresh","expires_in":3600}"#.utf8
                    )
                )
            }
            usageRequests.increment()
            return Self.response(for: request, status: 500)
        }
        let service = makeService(backend: backend)

        let outcome = try await service.fetchSnapshot()

        guard case .unavailable(let message, let hasStoredCredentials, _) = outcome else {
            return XCTFail("Expected unavailable outcome, got \(outcome)")
        }
        XCTAssertEqual(message, "OpenAI returned an invalid access token. Try again.")
        XCTAssertTrue(hasStoredCredentials)
        XCTAssertEqual(try tokenStore.load(), tokens)
        XCTAssertEqual(refreshRequests.value, 1)
        XCTAssertEqual(usageRequests.value, 0)
    }

    func testInvalidRefreshLifetimeDoesNotReplaceStoredCredentials() async throws {
        let backend = InMemorySecureDataStore()
        let tokenStore = CodexiOSTokenStore(backend: backend)
        let tokens = makeTokens(expiresAt: Date().addingTimeInterval(-60))
        try tokenStore.save(tokens)
        CodexiOSURLProtocolStub.handler = { request in
            Self.response(
                for: request,
                status: 200,
                data: Data(
                    #"{"id_token":"header.payload.signature","access_token":"new-access","refresh_token":"new-refresh","expires_in":-1}"#.utf8
                )
            )
        }
        let service = makeService(backend: backend)

        let outcome = try await service.fetchSnapshot()

        guard case .unavailable(let message, let hasStoredCredentials, _) = outcome else {
            return XCTFail("Expected unavailable outcome, got \(outcome)")
        }
        XCTAssertEqual(message, "OpenAI returned an invalid session lifetime. Try again.")
        XCTAssertTrue(hasStoredCredentials)
        XCTAssertEqual(try tokenStore.load(), tokens)
    }

    func testRateLimitReturnsRetryMetadataWithoutDiscardingCredentials() async throws {
        let backend = InMemorySecureDataStore()
        let tokenStore = CodexiOSTokenStore(backend: backend)
        let tokens = makeTokens()
        try tokenStore.save(tokens)
        CodexiOSURLProtocolStub.handler = { request in
            Self.response(for: request, status: 429, headers: ["Retry-After": "120"])
        }
        let service = makeService(backend: backend)
        let before = Date()

        let outcome = try await service.fetchSnapshot()

        guard case .unavailable(let message, let hasStoredCredentials, let retry) = outcome else {
            return XCTFail("Expected unavailable outcome, got \(outcome)")
        }
        XCTAssertEqual(message, "OpenAI is rate-limiting requests. Try again soon.")
        XCTAssertTrue(hasStoredCredentials)
        XCTAssertTrue(retry.isTransient)
        let retryAfter = try XCTUnwrap(retry.retryAfter)
        XCTAssertGreaterThanOrEqual(retryAfter, before.addingTimeInterval(119))
        XCTAssertLessThanOrEqual(retryAfter, Date().addingTimeInterval(121))
        XCTAssertEqual(try tokenStore.load(), tokens)
    }

    func testTwoServiceInstancesCannotResaveTokenAfterSignOut() async throws {
        let backend = InMemorySecureDataStore()
        let tokenStore = CodexiOSTokenStore(backend: backend)
        try tokenStore.save(makeTokens(expiresAt: Date().addingTimeInterval(-60)))
        let coordinator = CodexiOSCredentialCoordinator()
        let requestStarted = expectation(description: "refresh request started")
        let responseGate = DispatchSemaphore(value: 0)
        CodexiOSURLProtocolStub.handler = { request in
            requestStarted.fulfill()
            _ = responseGate.wait(timeout: .now() + 5)
            let json = Data(
                #"{"id_token":"header.payload.signature","access_token":"new-access","refresh_token":"new-refresh","expires_in":3600}"#.utf8
            )
            return Self.response(for: request, status: 200, data: json)
        }
        let first = makeService(backend: backend, coordinator: coordinator)
        let second = makeService(backend: backend, coordinator: coordinator)

        let refresh = Task { try await first.fetchSnapshot() }
        await fulfillment(of: [requestStarted], timeout: 2)
        try await second.signOut()
        responseGate.signal()
        let outcome = try await refresh.value

        XCTAssertEqual(outcome, .superseded)
        XCTAssertNil(try tokenStore.load())
    }

    func testConcurrentServiceInstancesSingleFlightRotatingTokenRefresh() async throws {
        let backend = InMemorySecureDataStore()
        let tokenStore = CodexiOSTokenStore(backend: backend)
        try tokenStore.save(makeTokens(expiresAt: Date().addingTimeInterval(-60)))
        let coordinator = CodexiOSCredentialCoordinator()
        let refreshStarted = expectation(description: "refresh request started")
        refreshStarted.assertForOverFulfill = true
        let responseGate = DispatchSemaphore(value: 0)
        let refreshRequests = LockedCounter()
        CodexiOSURLProtocolStub.handler = { request in
            if request.url?.path == "/oauth/token" {
                refreshRequests.increment()
                refreshStarted.fulfill()
                _ = responseGate.wait(timeout: .now() + 5)
                let json = Data(
                    #"{"id_token":"header.payload.signature","access_token":"fresh-access","refresh_token":"fresh-refresh","expires_in":3600}"#.utf8
                )
                return Self.response(for: request, status: 200, data: json)
            }
            return Self.response(for: request, status: 200, data: Self.usagePayload)
        }
        let firstService = makeService(backend: backend, coordinator: coordinator)
        let secondService = makeService(backend: backend, coordinator: coordinator)

        let first = Task { try await firstService.fetchSnapshot() }
        let second = Task { try await secondService.fetchSnapshot() }
        await fulfillment(of: [refreshStarted], timeout: 2)
        responseGate.signal()
        let firstOutcome = try await first.value
        let secondOutcome = try await second.value

        guard case .loaded = firstOutcome else {
            return XCTFail("Expected first refresh to load, got \(firstOutcome)")
        }
        guard case .loaded = secondOutcome else {
            return XCTFail("Expected second refresh to load, got \(secondOutcome)")
        }
        XCTAssertEqual(refreshRequests.value, 1)
        XCTAssertEqual(try tokenStore.load()?.refreshToken, "fresh-refresh")
    }

    func testApprovedCodeSurvivesTransientExchangeAndServiceRecreationWithoutRepolling() async throws {
        let backend = InMemorySecureDataStore()
        let pendingStore = CodexiOSPendingAuthStore(backend: backend)
        let record = makePendingRecord()
        try pendingStore.save(record)
        let pollRequests = LockedCounter()
        let exchangeRequests = LockedCounter()
        CodexiOSURLProtocolStub.handler = { request in
            switch request.url?.path {
            case "/api/accounts/deviceauth/token":
                pollRequests.increment()
                return Self.response(for: request, status: 200, data: Self.approvedPayload)
            case "/oauth/token":
                exchangeRequests.increment()
                if exchangeRequests.value == 1 {
                    return Self.response(for: request, status: 500)
                }
                return Self.response(for: request, status: 200, data: Self.tokenPayload)
            default:
                return Self.response(for: request, status: 500)
            }
        }
        let firstService = makeService(
            backend: backend,
            coordinator: CodexiOSCredentialCoordinator()
        )

        do {
            _ = try await firstService.pollSignIn(flowID: record.flowID)
            XCTFail("Expected transient token exchange failure")
        } catch {
            // Approval must remain resumable.
        }
        var persisted = try XCTUnwrap(try pendingStore.load())
        XCTAssertNotNil(persisted.approved)
        XCTAssertNil(persisted.exchangedTokens)
        persisted.nextPollAt = nil
        try pendingStore.save(persisted)

        let recreatedService = makeService(
            backend: backend,
            coordinator: CodexiOSCredentialCoordinator()
        )
        let result = try await recreatedService.pollSignIn(flowID: record.flowID)

        XCTAssertEqual(result, .signedIn)
        XCTAssertEqual(pollRequests.value, 1)
        XCTAssertEqual(exchangeRequests.value, 2)
        XCTAssertNotNil(try CodexiOSTokenStore(backend: backend).load())
        XCTAssertNil(try pendingStore.load())
    }

    func testExchangedTokensSurviveTokenStoreFailureAndResumeWithoutNetwork() async throws {
        let backend = InMemorySecureDataStore()
        let pendingStore = CodexiOSPendingAuthStore(backend: backend)
        let record = makePendingRecord()
        try pendingStore.save(record)
        let pollRequests = LockedCounter()
        let exchangeRequests = LockedCounter()
        CodexiOSURLProtocolStub.handler = { request in
            switch request.url?.path {
            case "/api/accounts/deviceauth/token":
                pollRequests.increment()
                return Self.response(for: request, status: 200, data: Self.approvedPayload)
            case "/oauth/token":
                exchangeRequests.increment()
                return Self.response(for: request, status: 200, data: Self.tokenPayload)
            default:
                return Self.response(for: request, status: 500)
            }
        }
        backend.failNextSaveAccount = "chatgpt-tokens"
        let firstService = makeService(
            backend: backend,
            coordinator: CodexiOSCredentialCoordinator()
        )

        do {
            _ = try await firstService.pollSignIn(flowID: record.flowID)
            XCTFail("Expected token store failure")
        } catch {
            // Exchanged tokens must remain in the staged record.
        }
        let persisted = try XCTUnwrap(try pendingStore.load())
        XCTAssertNotNil(persisted.exchangedTokens)
        XCTAssertNil(try CodexiOSTokenStore(backend: backend).load())

        let recreatedService = makeService(
            backend: backend,
            coordinator: CodexiOSCredentialCoordinator()
        )
        let result = try await recreatedService.pollSignIn(flowID: record.flowID)

        XCTAssertEqual(result, .signedIn)
        XCTAssertEqual(pollRequests.value, 1)
        XCTAssertEqual(exchangeRequests.value, 1)
        XCTAssertNotNil(try CodexiOSTokenStore(backend: backend).load())
        XCTAssertNil(try pendingStore.load())
    }

    func testConcurrentApprovedExchangeIsSingleFlightPastPollInterval() async throws {
        let backend = InMemorySecureDataStore()
        let pendingStore = CodexiOSPendingAuthStore(backend: backend)
        let createdAt = Date().addingTimeInterval(-10)
        var record = makePendingRecord(now: createdAt)
        let approved = try JSONDecoder().decode(
            CodexDeviceApprovedResponse.self,
            from: Self.approvedPayload
        )
        record.approved = CodexiOSApprovedAuthRecord(approved)
        record.nextPollAt = Date().addingTimeInterval(-1)
        try pendingStore.save(record)
        let flowID = record.flowID

        let exchangeStarted = expectation(description: "first exchange started")
        exchangeStarted.assertForOverFulfill = true
        let responseGate = DispatchSemaphore(value: 0)
        let exchangeRequests = LockedCounter()
        CodexiOSURLProtocolStub.handler = { request in
            guard request.url?.path == "/oauth/token" else {
                return Self.response(for: request, status: 500)
            }
            exchangeRequests.increment()
            if exchangeRequests.value == 1 {
                exchangeStarted.fulfill()
                _ = responseGate.wait(timeout: .now() + 5)
                return Self.response(for: request, status: 200, data: Self.tokenPayload)
            }
            return Self.response(for: request, status: 400)
        }
        let coordinator = CodexiOSCredentialCoordinator()
        let firstService = makeService(backend: backend, coordinator: coordinator)
        let secondService = makeService(backend: backend, coordinator: coordinator)

        let first = Task { @Sendable in try await firstService.pollSignIn(flowID: flowID) }
        await fulfillment(of: [exchangeStarted], timeout: 2)
        try await Task.sleep(for: .seconds(1.1))
        let second = Task { @Sendable in try await secondService.pollSignIn(flowID: flowID) }
        try await Task.sleep(for: .milliseconds(100))
        responseGate.signal()

        let firstResult = try await first.value
        let secondResult = try await second.value
        XCTAssertEqual(firstResult, .signedIn)
        XCTAssertEqual(secondResult, .signedIn)
        XCTAssertEqual(exchangeRequests.value, 1)
        XCTAssertNotNil(try CodexiOSTokenStore(backend: backend).load())
        XCTAssertNil(try pendingStore.load())
    }

    func testDevicePollPersistsServerRetryAfterAcrossServiceInstances() async throws {
        let backend = InMemorySecureDataStore()
        let pendingStore = CodexiOSPendingAuthStore(backend: backend)
        let now = Date()
        let record = CodexiOSPendingAuthRecord(
            flowID: String(repeating: "f", count: 43),
            userCode: "ABCD-1234",
            deviceAuthID: "device-auth",
            interval: 1,
            createdAt: now,
            expiresAt: now.addingTimeInterval(CodexiOSPendingAuthStore.ttl),
            lastPolledAt: nil
        )
        try pendingStore.save(record)
        let requestCount = LockedCounter()
        CodexiOSURLProtocolStub.handler = { request in
            requestCount.increment()
            return Self.response(for: request, status: 429, headers: ["Retry-After": "120"])
        }
        let coordinator = CodexiOSCredentialCoordinator()
        let first = makeService(backend: backend, coordinator: coordinator)

        do {
            _ = try await first.pollSignIn(flowID: record.flowID)
            XCTFail("Expected rate-limit failure")
        } catch {
            // The pending record must survive a transient response.
        }
        let persisted = try XCTUnwrap(try pendingStore.load())
        XCTAssertGreaterThan(persisted.nextPollAt ?? .distantPast, Date().addingTimeInterval(115))

        let second = makeService(backend: backend, coordinator: coordinator)
        let result = try await second.pollSignIn(flowID: record.flowID)
        guard case .pending(let message) = result else {
            return XCTFail("Expected locally throttled pending result")
        }
        XCTAssertTrue(message.contains("Check again in"))
        XCTAssertEqual(requestCount.value, 1)
    }

    private func makeService(
        backend: InMemorySecureDataStore,
        coordinator: CodexiOSCredentialCoordinator = CodexiOSCredentialCoordinator()
    ) -> CodexiOSService {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CodexiOSURLProtocolStub.self]
        configuration.timeoutIntervalForRequest = CodexiOSService.requestTimeout
        configuration.timeoutIntervalForResource = CodexiOSService.resourceTimeout
        return CodexiOSService(
            session: URLSession(configuration: configuration),
            keychain: CodexiOSTokenStore(backend: backend),
            pendingStore: CodexiOSPendingAuthStore(backend: backend),
            credentialCoordinator: coordinator
        )
    }

    private func makeTokens(
        refreshToken: String = "refresh-token",
        expiresAt: Date = Date().addingTimeInterval(3_600)
    ) -> CodexiOSTokens {
        CodexiOSTokens(
            idToken: "header.payload.signature",
            accessToken: "access-token",
            refreshToken: refreshToken,
            createdAt: Date(),
            expiresAt: expiresAt
        )
    }

    private func makePendingRecord(now: Date = Date()) -> CodexiOSPendingAuthRecord {
        CodexiOSPendingAuthRecord(
            flowID: String(repeating: "f", count: 43),
            userCode: "ABCD-1234",
            deviceAuthID: "device-auth",
            interval: 1,
            createdAt: now,
            expiresAt: now.addingTimeInterval(CodexiOSPendingAuthStore.ttl),
            lastPolledAt: nil
        )
    }

    private static let approvedPayload = Data(
        #"{"authorization_code":"approved-code","code_verifier":"approved-verifier"}"#.utf8
    )

    private static let tokenPayload = Data(
        #"{"id_token":"header.payload.signature","access_token":"new-access","refresh_token":"new-refresh","expires_in":3600}"#.utf8
    )

    private static let usagePayload = Data(
        #"{"plan_type":"pro","rate_limit":{"primary_window":{"used_percent":13,"limit_window_seconds":18000},"secondary_window":{"used_percent":70,"limit_window_seconds":604800}}}"#.utf8
    )

    private static func response(
        for request: URLRequest,
        status: Int,
        headers: [String: String] = [:],
        data: Data = Data()
    ) -> (HTTPURLResponse, Data) {
        (
            HTTPURLResponse(
                url: request.url!,
                statusCode: status,
                httpVersion: "HTTP/1.1",
                headerFields: headers
            )!,
            data
        )
    }
}

final class CodexiOSURLProtocolStub: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            guard let handler = Self.handler else {
                throw URLError(.unsupportedURL)
            }
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    func increment() {
        lock.withLock { count += 1 }
    }

    var value: Int {
        lock.withLock { count }
    }
}
