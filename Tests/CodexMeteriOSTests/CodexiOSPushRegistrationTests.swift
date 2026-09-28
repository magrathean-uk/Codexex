import XCTest
import UIKit
@testable import Codexex

@MainActor
final class CodexiOSPushRegistrationTests: XCTestCase {
    override func tearDown() {
        CodexiOSPushURLProtocolStub.reset()
        super.tearDown()
    }

    func testVariableLengthDeviceTokenRegistersWithoutPersistingToken() async throws {
        let backend = InMemorySecureDataStore()
        let store = CodexiOSPushRegistrationStore(backend: backend)
        let defaults = makeDefaults()
        let session = makeSession()
        var didRequestRemoteRegistration = false
        var capturedRequest: URLRequest?
        var capturedBody: Data?
        CodexiOSPushURLProtocolStub.handler = { request in
            capturedRequest = request
            capturedBody = Self.bodyData(from: request)
            return Self.response(for: request, status: 201)
        }
        let manager = CodexiOSPushRegistrationManager(
            store: store,
            defaults: defaults,
            session: session,
            registerForRemoteNotifications: { didRequestRemoteRegistration = true }
        )

        await manager.enable()
        await manager.didRegister(deviceToken: Data((0..<33).map(UInt8.init)))

        XCTAssertTrue(didRequestRemoteRegistration)
        let request = try XCTUnwrap(capturedRequest)
        XCTAssertEqual(request.httpMethod, "PUT")
        XCTAssertEqual(request.url?.host, "push.magrathean.uk")
        XCTAssertTrue(request.url?.path.hasPrefix("/v1/codexex/installations/") == true)
        XCTAssertTrue(request.value(forHTTPHeaderField: "Authorization")?.hasPrefix("Bearer ") == true)
        let body = try XCTUnwrap(capturedBody)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: String])
        XCTAssertEqual(Set(object.keys), ["deviceToken", "environment"])
        XCTAssertEqual(object["deviceToken"], Data((0..<33).map(UInt8.init)).map { String(format: "%02x", $0) }.joined())
        XCTAssertEqual(object["environment"], "sandbox")

        let persisted = try XCTUnwrap(store.load())
        let persistedData = try JSONEncoder().encode(persisted)
        let persistedObject = try XCTUnwrap(JSONSerialization.jsonObject(with: persistedData) as? [String: String])
        XCTAssertEqual(Set(persistedObject.keys), ["installationID", "installationSecret"])
        let persistedText = String(decoding: persistedData, as: UTF8.self).lowercased()
        XCTAssertFalse(persistedText.contains("devicetoken"))
        XCTAssertFalse(persistedText.contains("openai"))
        XCTAssertFalse(persistedText.contains("quota"))
    }

    func testDisabledRegistrationIgnoresLateAPNsCallback() async {
        let backend = InMemorySecureDataStore()
        let store = CodexiOSPushRegistrationStore(backend: backend)
        let manager = CodexiOSPushRegistrationManager(
            store: store,
            defaults: makeDefaults(),
            session: makeSession(),
            registerForRemoteNotifications: {}
        )

        await manager.didRegister(deviceToken: Data([1, 2, 3]))

        XCTAssertNil(try? store.load())
    }

    func testDisableWaitsForInFlightRegistrationBeforeDeleting() async {
        let backend = InMemorySecureDataStore()
        let store = CodexiOSPushRegistrationStore(backend: backend)
        let putStarted = expectation(description: "PUT started")
        let earlyDelete = expectation(description: "DELETE does not start before PUT completes")
        earlyDelete.isInverted = true
        var observesEarlyDelete = true
        var requestMethods: [String] = []
        CodexiOSPushURLProtocolStub.handler = { request in
            let method = request.httpMethod ?? ""
            requestMethods.append(method)
            if method == "PUT" {
                putStarted.fulfill()
                return nil
            }
            if observesEarlyDelete {
                earlyDelete.fulfill()
            }
            return Self.response(for: request, status: 204)
        }
        let manager = CodexiOSPushRegistrationManager(
            store: store,
            defaults: makeDefaults(),
            session: makeSession(),
            registerForRemoteNotifications: {}
        )

        await manager.enable()
        let registration = Task { await manager.didRegister(deviceToken: Data([1, 2, 3])) }
        await fulfillment(of: [putStarted], timeout: 1)
        let stop = Task { await manager.disable() }
        await fulfillment(of: [earlyDelete], timeout: 0.1)
        observesEarlyDelete = false

        CodexiOSPushURLProtocolStub.completeNextPendingRequest(status: 201)
        await registration.value
        await stop.value

        XCTAssertEqual(requestMethods, ["PUT", "DELETE"])
        XCTAssertNil(try? store.load())
    }

    func testReenablingDuringDeletionPreservesRegistrationCredential() async throws {
        let backend = InMemorySecureDataStore()
        let store = CodexiOSPushRegistrationStore(backend: backend)
        let record = CodexiOSPushRegistrationRecord(
            installationID: "installation",
            installationSecret: "secret"
        )
        try store.save(record)
        let deletionStarted = expectation(description: "DELETE started")
        let earlyRegistration = expectation(description: "PUT does not start before DELETE completes")
        earlyRegistration.isInverted = true
        var observesEarlyRegistration = true
        var requestMethods: [String] = []
        CodexiOSPushURLProtocolStub.handler = { request in
            let method = request.httpMethod ?? ""
            requestMethods.append(method)
            if method == "DELETE" {
                deletionStarted.fulfill()
                return nil
            }
            if observesEarlyRegistration {
                earlyRegistration.fulfill()
            }
            return Self.response(for: request, status: 201)
        }
        let manager = CodexiOSPushRegistrationManager(
            store: store,
            defaults: makeDefaults(),
            session: makeSession(),
            registerForRemoteNotifications: {}
        )

        await manager.enable()
        let stop = Task { await manager.disable() }
        await fulfillment(of: [deletionStarted], timeout: 1)
        await manager.enable()
        let registration = Task { await manager.didRegister(deviceToken: Data([1, 2, 3])) }
        await fulfillment(of: [earlyRegistration], timeout: 0.1)
        observesEarlyRegistration = false

        CodexiOSPushURLProtocolStub.completeNextPendingRequest(status: 204)
        await stop.value
        await registration.value

        XCTAssertEqual(requestMethods, ["DELETE", "PUT"])
        XCTAssertEqual(try store.load(), record)
    }

    func testFailedDeletionRetainsCredentialForTheNextStopRetry() async throws {
        let backend = InMemorySecureDataStore()
        let store = CodexiOSPushRegistrationStore(backend: backend)
        let record = CodexiOSPushRegistrationRecord(
            installationID: "installation",
            installationSecret: "secret"
        )
        try store.save(record)
        var requestMethods: [String] = []
        CodexiOSPushURLProtocolStub.handler = { request in
            requestMethods.append(request.httpMethod ?? "")
            return Self.response(for: request, status: 500)
        }
        let manager = CodexiOSPushRegistrationManager(
            store: store,
            defaults: makeDefaults(),
            session: makeSession(),
            registerForRemoteNotifications: {}
        )

        await manager.disable()
        XCTAssertEqual(try store.load(), record)

        CodexiOSPushURLProtocolStub.handler = { request in
            requestMethods.append(request.httpMethod ?? "")
            return Self.response(for: request, status: 204)
        }
        await manager.disable()

        XCTAssertEqual(requestMethods, ["DELETE", "DELETE"])
        XCTAssertNil(try store.load())
    }

    func testTransientRegistrationFailureRetriesWithInMemoryTokenOnly() async throws {
        let backend = InMemorySecureDataStore()
        let store = CodexiOSPushRegistrationStore(backend: backend)
        var requests: [URLRequest] = []
        CodexiOSPushURLProtocolStub.handler = { request in
            requests.append(request)
            return Self.response(for: request, status: requests.count == 1 ? 500 : 201)
        }
        let manager = CodexiOSPushRegistrationManager(
            store: store,
            defaults: makeDefaults(),
            session: makeSession(),
            registrationRetryDelay: .milliseconds(1),
            registerForRemoteNotifications: {}
        )

        await manager.enable()
        await manager.didRegister(deviceToken: Data([0x01, 0x02, 0x03]))
        try await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(requests.map(\.httpMethod), ["PUT", "PUT"])
        let persisted = try XCTUnwrap(store.load())
        let persistedData = try JSONEncoder().encode(persisted)
        XCTAssertFalse(String(decoding: persistedData, as: UTF8.self).contains("010203"))
    }

    func testDisablingCancelsPendingRegistrationRetry() async throws {
        let backend = InMemorySecureDataStore()
        let store = CodexiOSPushRegistrationStore(backend: backend)
        var requestCount = 0
        CodexiOSPushURLProtocolStub.handler = { request in
            requestCount += 1
            return Self.response(for: request, status: 500)
        }
        let manager = CodexiOSPushRegistrationManager(
            store: store,
            defaults: makeDefaults(),
            session: makeSession(),
            registrationRetryDelay: .milliseconds(50),
            registerForRemoteNotifications: {}
        )

        await manager.enable()
        await manager.didRegister(deviceToken: Data([0x01, 0x02, 0x03]))
        await manager.disable()
        try await Task.sleep(for: .milliseconds(100))

        XCTAssertEqual(requestCount, 2, "Only the failed PUT and deletion may run after disable.")
    }

    func testSilentPushDeadlineCompletesExactlyOnce() async throws {
        let completed = expectation(description: "silent-push completion")
        var results: [UIBackgroundFetchResult] = []

        CodexiOSSilentPushWakeRunner.run(timeout: .milliseconds(10)) {
            do {
                try await Task.sleep(for: .seconds(1))
            } catch {
                // Simulate URLSession respecting the deadline cancellation.
            }
            return .newData
        } completion: { result in
            results.append(result)
            completed.fulfill()
        }

        await fulfillment(of: [completed], timeout: 1)
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(results, [.failed])
    }

    func testSilentPushThrottleCoalescesConcurrentAndRecentWakes() {
        let throttle = CodexiOSSilentPushWakeThrottle(minimumInterval: 60)
        let start = Date(timeIntervalSince1970: 1_000)

        XCTAssertTrue(throttle.begin(now: start))
        XCTAssertFalse(throttle.begin(now: start.addingTimeInterval(60)))

        throttle.finish()
        XCTAssertFalse(throttle.begin(now: start.addingTimeInterval(59)))
        XCTAssertTrue(throttle.begin(now: start.addingTimeInterval(60)))
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "CodexiOSPushRegistrationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CodexiOSPushURLProtocolStub.self]
        return URLSession(configuration: configuration)
    }

    private static func response(for request: URLRequest, status: Int) -> (HTTPURLResponse, Data) {
        (
            HTTPURLResponse(
                url: request.url!,
                statusCode: status,
                httpVersion: "HTTP/1.1",
                headerFields: nil
            )!,
            Data()
        )
    }

    private static func bodyData(from request: URLRequest) -> Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var result = Data()
        var buffer = [UInt8](repeating: 0, count: 1024)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            result.append(buffer, count: count)
        }
        return result
    }
}

final class CodexiOSPushURLProtocolStub: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data)?)?
    nonisolated(unsafe) private static var pendingProtocols: [CodexiOSPushURLProtocolStub] = []

    nonisolated static func completeNextPendingRequest(status: Int) {
        guard pendingProtocols.isEmpty == false else { return }
        let protocolStub = pendingProtocols.removeFirst()
        let response = HTTPURLResponse(
            url: protocolStub.request.url!,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: nil
        )!
        protocolStub.client?.urlProtocol(protocolStub, didReceive: response, cacheStoragePolicy: .notAllowed)
        protocolStub.client?.urlProtocolDidFinishLoading(protocolStub)
    }

    nonisolated static func reset() {
        handler = nil
        pendingProtocols.removeAll()
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            guard let handler = Self.handler else { throw URLError(.unsupportedURL) }
            guard let (response, data) = try handler(request) else {
                Self.pendingProtocols.append(self)
                return
            }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
