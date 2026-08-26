import Foundation
import Security
import XCTest
@testable import Codexex

final class CodexiOSCredentialStoreTests: XCTestCase {
    func testConcurrentAddDuplicateRetriesAtomicUpdateWithoutDelete() throws {
        var calls: [String] = []

        try CodexiOSKeychainSaveStateMachine.perform(
            update: { calls.append("update"); return errSecItemNotFound },
            add: { calls.append("add"); return errSecDuplicateItem },
            retryUpdate: { calls.append("retry-update"); return errSecSuccess }
        )

        XCTAssertEqual(calls, ["update", "add", "retry-update"])
    }

    func testTokenSaveFailureLeavesPreviousCredentialsIntact() throws {
        let backend = InMemorySecureDataStore()
        let store = CodexiOSTokenStore(backend: backend)
        let original = makeTokens(accessToken: "original")
        let replacement = makeTokens(accessToken: "replacement")
        try store.save(original)

        backend.failNextSave = true
        XCTAssertThrowsError(try store.save(replacement))

        XCTAssertEqual(try store.load(), original)
    }

    func testTokenDeleteFailureIsSurfacedAndDoesNotPretendToSignOut() throws {
        let backend = InMemorySecureDataStore()
        let store = CodexiOSTokenStore(backend: backend)
        let tokens = makeTokens(accessToken: "kept")
        try store.save(tokens)
        backend.failNextRemove = true

        XCTAssertThrowsError(try store.clear())
        XCTAssertEqual(try store.load(), tokens)
    }

    func testPendingAuthPersistsAcrossStoreInstancesAndExpires() throws {
        let backend = InMemorySecureDataStore()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let record = makePendingRecord(now: now)
        try CodexiOSPendingAuthStore(backend: backend).save(record)

        let restored = try CodexiOSPendingAuthStore(backend: backend).load(
            now: now.addingTimeInterval(60)
        )
        XCTAssertEqual(restored, record)

        XCTAssertThrowsError(
            try CodexiOSPendingAuthStore(backend: backend).load(now: record.expiresAt)
        ) { error in
            XCTAssertEqual(error as? CodexiOSError, .signInExpired)
        }
        XCTAssertNil(try CodexiOSPendingAuthStore(backend: backend).load(now: record.expiresAt))
    }

    func testPendingAuthRejectsExcessiveTTL() {
        let backend = InMemorySecureDataStore()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let record = CodexiOSPendingAuthRecord(
            flowID: String(repeating: "f", count: 43),
            userCode: "ABCD-1234",
            deviceAuthID: "device-auth",
            interval: 5,
            createdAt: now,
            expiresAt: now.addingTimeInterval(CodexiOSPendingAuthStore.ttl + 60),
            lastPolledAt: nil
        )

        XCTAssertThrowsError(try CodexiOSPendingAuthStore(backend: backend).save(record))
    }

    func testPendingAuthRejectsNonURLSafeFlowID() {
        let backend = InMemorySecureDataStore()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let record = CodexiOSPendingAuthRecord(
            flowID: String(repeating: "f", count: 42) + ".",
            userCode: "ABCD-1234",
            deviceAuthID: "device-auth",
            interval: 5,
            createdAt: now,
            expiresAt: now.addingTimeInterval(CodexiOSPendingAuthStore.ttl),
            lastPolledAt: nil
        )

        XCTAssertThrowsError(try CodexiOSPendingAuthStore(backend: backend).save(record))
    }

    func testResetAttemptsEveryStoreAndSurfacesFailure() {
        let suite = "CodexiOSCredentialStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.set(true, forKey: CodexiOSSettingsKeys.previewModeEnabled)
        var didClearPending = false
        var didClearHistory = false

        XCTAssertThrowsError(
            try CodexiOSAppResetter.resetLocalData(
                defaults: defaults,
                clearTokens: {
                    throw CodexiOSError.secureStoreFailure("Token delete failed.")
                },
                clearPendingAuth: { didClearPending = true },
                clearHistory: { didClearHistory = true }
            )
        )

        XCTAssertTrue(didClearPending)
        XCTAssertTrue(didClearHistory)
        XCTAssertNil(defaults.object(forKey: CodexiOSSettingsKeys.previewModeEnabled))
        defaults.removePersistentDomain(forName: suite)
    }

    func testCoordinatorSignOutAttemptsPendingDeletionWhenTokenDeletionFailsAndCanRetry() throws {
        let backend = InMemorySecureDataStore()
        let tokenStore = CodexiOSTokenStore(backend: backend)
        let pendingStore = CodexiOSPendingAuthStore(backend: backend)
        let coordinator = CodexiOSCredentialCoordinator()
        let now = Date()
        try tokenStore.save(makeTokens(accessToken: "kept"))
        try pendingStore.save(makePendingRecord(now: now))
        backend.failNextRemove = true

        XCTAssertThrowsError(
            try coordinator.signOut(tokenStore: tokenStore, pendingStore: pendingStore)
        )

        XCTAssertNotNil(try tokenStore.load())
        XCTAssertNil(try pendingStore.load(now: now))

        try coordinator.signOut(tokenStore: tokenStore, pendingStore: pendingStore)
        XCTAssertNil(try tokenStore.load())
        XCTAssertNil(try pendingStore.load(now: now))
    }

    private func makeTokens(accessToken: String) -> CodexiOSTokens {
        CodexiOSTokens(
            idToken: "header.payload.signature",
            accessToken: accessToken,
            refreshToken: "refresh-token",
            createdAt: Date(timeIntervalSince1970: 1_800_000_000),
            expiresAt: Date(timeIntervalSince1970: 1_800_003_600)
        )
    }

    private func makePendingRecord(now: Date) -> CodexiOSPendingAuthRecord {
        CodexiOSPendingAuthRecord(
            flowID: String(repeating: "f", count: 43),
            userCode: "ABCD-1234",
            deviceAuthID: "device-auth",
            interval: 5,
            createdAt: now,
            expiresAt: now.addingTimeInterval(CodexiOSPendingAuthStore.ttl),
            lastPolledAt: nil
        )
    }
}

final class InMemorySecureDataStore: CodexiOSSecureDataStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Data] = [:]
    var failNextSave = false
    var failNextSaveAccount: String?
    var failNextRemove = false

    func load(service: String, account: String) throws -> Data? {
        lock.withLock { values[key(service: service, account: account)] }
    }

    func save(
        _ data: Data,
        service: String,
        account: String,
        accessibility: CodexiOSSecureAccessibility
    ) throws {
        try lock.withLock {
            if failNextSave || failNextSaveAccount == account {
                failNextSave = false
                failNextSaveAccount = nil
                throw CodexiOSError.secureStoreFailure("Injected save failure.")
            }
            values[key(service: service, account: account)] = data
        }
    }

    func remove(service: String, account: String) throws {
        try lock.withLock {
            if failNextRemove {
                failNextRemove = false
                throw CodexiOSError.secureStoreFailure("Injected remove failure.")
            }
            values.removeValue(forKey: key(service: service, account: account))
        }
    }

    private func key(service: String, account: String) -> String {
        "\(service)|\(account)"
    }
}
