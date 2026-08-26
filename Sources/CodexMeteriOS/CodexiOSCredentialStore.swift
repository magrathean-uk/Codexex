import Foundation
import Security
import CodexMeterCore

enum CodexiOSSecureRandom {
    static func flowID() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else {
            throw CodexiOSError.badResponse("Could not start sign-in securely.")
        }
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

enum CodexiOSSecureAccessibility: Sendable {
    case afterFirstUnlockThisDeviceOnly
    case whenUnlockedThisDeviceOnly
}

protocol CodexiOSSecureDataStoring: Sendable {
    func load(service: String, account: String) throws -> Data?
    func save(
        _ data: Data,
        service: String,
        account: String,
        accessibility: CodexiOSSecureAccessibility
    ) throws
    func remove(service: String, account: String) throws
}

struct CodexiOSKeychainDataStore: CodexiOSSecureDataStoring, Sendable {
    func load(service: String, account: String) throws -> Data? {
        var query = baseQuery(service: service, account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else {
            throw CodexiOSError.secureStoreFailure("Could not read saved sign-in.")
        }
        return data
    }

    func save(
        _ data: Data,
        service: String,
        account: String,
        accessibility: CodexiOSSecureAccessibility
    ) throws {
        let query = baseQuery(service: service, account: account)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: accessibilityValue(accessibility)
        ]

        var addQuery = query
        attributes.forEach { addQuery[$0.key] = $0.value }
        try CodexiOSKeychainSaveStateMachine.perform(
            update: { SecItemUpdate(query as CFDictionary, attributes as CFDictionary) },
            add: { SecItemAdd(addQuery as CFDictionary, nil) },
            retryUpdate: { SecItemUpdate(query as CFDictionary, attributes as CFDictionary) }
        )
    }

    func remove(service: String, account: String) throws {
        let status = SecItemDelete(baseQuery(service: service, account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw CodexiOSError.secureStoreFailure("Could not delete saved sign-in.")
        }
    }

    private func baseQuery(service: String, account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    private func accessibilityValue(_ accessibility: CodexiOSSecureAccessibility) -> CFString {
        switch accessibility {
        case .afterFirstUnlockThisDeviceOnly:
            return kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        case .whenUnlockedThisDeviceOnly:
            return kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        }
    }
}

enum CodexiOSKeychainSaveStateMachine {
    static func perform(
        update: () -> OSStatus,
        add: () -> OSStatus,
        retryUpdate: () -> OSStatus
    ) throws {
        let updateStatus = update()
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw CodexiOSError.secureStoreFailure("Could not update saved sign-in.")
        }

        let addStatus = add()
        if addStatus == errSecSuccess { return }
        guard addStatus == errSecDuplicateItem, retryUpdate() == errSecSuccess else {
            throw CodexiOSError.secureStoreFailure("Could not save sign-in.")
        }
    }
}

struct CodexiOSTokenStore: Sendable {
    private let backend: any CodexiOSSecureDataStoring
    private let service = "com.magrathean.CodexexApp.iOS"
    private let account = "chatgpt-tokens"

    init(backend: any CodexiOSSecureDataStoring = CodexiOSKeychainDataStore()) {
        self.backend = backend
    }

    func load() throws -> CodexiOSTokens? {
        guard let data = try backend.load(service: service, account: account) else { return nil }
        do {
            return try JSONDecoder().decode(CodexiOSTokens.self, from: data)
        } catch {
            throw CodexiOSError.secureStoreFailure("Saved sign-in is damaged. Reset or sign in again.")
        }
    }

    func save(_ tokens: CodexiOSTokens) throws {
        let data = try JSONEncoder().encode(tokens)
        try backend.save(
            data,
            service: service,
            account: account,
            accessibility: .afterFirstUnlockThisDeviceOnly
        )
    }

    func clear() throws {
        try backend.remove(service: service, account: account)
    }
}

struct CodexiOSPendingAuthRecord: Codable, Equatable, Sendable {
    let flowID: String
    let userCode: String
    let deviceAuthID: String
    let interval: Int
    let createdAt: Date
    let expiresAt: Date
    var lastPolledAt: Date?
    var nextPollAt: Date? = nil
    var approved: CodexiOSApprovedAuthRecord? = nil
    var exchangedTokens: CodexiOSTokens? = nil

    var deviceAuthStart: CodexiOSDeviceAuthStart {
        CodexiOSDeviceAuthStart(
            flowID: flowID,
            verificationURL: CodexiOSService.verificationURL,
            userCode: userCode
        )
    }
}

struct CodexiOSApprovedAuthRecord: Codable, Equatable, Sendable {
    let authorizationCode: String
    let codeVerifier: String

    init(_ response: CodexDeviceApprovedResponse) {
        authorizationCode = response.authorizationCode
        codeVerifier = response.codeVerifier
    }
}

struct CodexiOSPendingAuthStore: Sendable {
    static let ttl: TimeInterval = 10 * 60

    private let backend: any CodexiOSSecureDataStoring
    private let service = "com.magrathean.CodexexApp.iOS"
    private let account = "chatgpt-pending-device-auth"

    init(backend: any CodexiOSSecureDataStoring = CodexiOSKeychainDataStore()) {
        self.backend = backend
    }

    func load(now: Date = Date()) throws -> CodexiOSPendingAuthRecord? {
        guard let data = try backend.load(service: service, account: account) else { return nil }
        let record: CodexiOSPendingAuthRecord
        do {
            record = try JSONDecoder().decode(CodexiOSPendingAuthRecord.self, from: data)
        } catch {
            try? clear()
            throw CodexiOSError.signInExpired
        }
        guard Self.isValid(record, now: now) else {
            try clear()
            throw CodexiOSError.signInExpired
        }
        return record
    }

    func save(_ record: CodexiOSPendingAuthRecord) throws {
        guard Self.isValid(record, now: record.createdAt) else {
            throw CodexiOSError.badResponse("OpenAI returned an invalid sign-in code.")
        }
        try backend.save(
            JSONEncoder().encode(record),
            service: service,
            account: account,
            accessibility: .whenUnlockedThisDeviceOnly
        )
    }

    func clear() throws {
        try backend.remove(service: service, account: account)
    }

    private static func isValid(_ record: CodexiOSPendingAuthRecord, now: Date) -> Bool {
        let allowedFlowIDCharacters = CharacterSet(
            charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-"
        )
        return record.expiresAt > now
            && record.createdAt <= now.addingTimeInterval(5 * 60)
            && record.expiresAt.timeIntervalSince(record.createdAt) <= ttl + 1
            && (32 ... 96).contains(record.flowID.count)
            && record.flowID.unicodeScalars.allSatisfy(allowedFlowIDCharacters.contains)
            && record.userCode.isEmpty == false
            && record.userCode.count <= 64
            && record.deviceAuthID.isEmpty == false
            && record.deviceAuthID.count <= 512
            && (1 ... 30).contains(record.interval)
            && (record.lastPolledAt.map { $0 >= record.createdAt && $0 <= record.expiresAt } ?? true)
            && (record.nextPollAt.map { $0 >= record.createdAt && $0 <= record.expiresAt } ?? true)
            && (record.approved.map(Self.isValid) ?? true)
            && (record.exchangedTokens.map(Self.isValid) ?? true)
            && (record.exchangedTokens == nil || record.approved != nil)
    }

    private static func isValid(_ approved: CodexiOSApprovedAuthRecord) -> Bool {
        approved.authorizationCode.isEmpty == false
            && approved.authorizationCode.utf8.count <= 16 * 1_024
            && approved.codeVerifier.isEmpty == false
            && approved.codeVerifier.utf8.count <= 8 * 1_024
    }

    private static func isValid(_ tokens: CodexiOSTokens) -> Bool {
        tokens.idToken.isEmpty == false
            && tokens.idToken.utf8.count <= 64 * 1_024
            && tokens.accessToken.isEmpty == false
            && tokens.accessToken.utf8.count <= 64 * 1_024
            && tokens.hasUsableRefreshToken
            && tokens.refreshToken.utf8.count <= 64 * 1_024
            && tokens.expiresAt >= tokens.createdAt
    }
}

enum CodexiOSCredentialRefreshResult: Sendable, Equatable {
    case ready(generation: UInt64, tokens: CodexiOSTokens)
    case superseded
}

enum CodexiOSPendingAuthResumeAction: Sendable, Equatable {
    case wait(nextPollAt: Date)
    case poll(generation: UInt64, pending: CodexiOSPendingAuthRecord)
    case exchange(generation: UInt64, approved: CodexiOSApprovedAuthRecord)
    case persist(generation: UInt64, tokens: CodexiOSTokens)
}

private struct CodexiOSTokenRefreshLease: Sendable {
    let id: UUID
    let task: Task<CodexiOSTokens, Error>
}

private actor CodexiOSTokenRefreshSingleFlight {
    private var leases: [UInt64: CodexiOSTokenRefreshLease] = [:]

    func lease(
        generation: UInt64,
        operation: @escaping @Sendable () async throws -> CodexiOSTokens
    ) -> CodexiOSTokenRefreshLease {
        if let existing = leases[generation] { return existing }
        let lease = CodexiOSTokenRefreshLease(
            id: UUID(),
            task: Task { try await operation() }
        )
        leases[generation] = lease
        return lease
    }

    func remove(generation: UInt64, id: UUID) {
        guard leases[generation]?.id == id else { return }
        leases[generation] = nil
    }
}

private struct CodexiOSPendingAuthOperationKey: Hashable, Sendable {
    let generation: UInt64
    let flowID: String
}

private struct CodexiOSPendingAuthOperationLease: Sendable {
    let id: UUID
    let task: Task<CodexiOSPollResult, Error>
}

private actor CodexiOSPendingAuthSingleFlight {
    private var leases: [CodexiOSPendingAuthOperationKey: CodexiOSPendingAuthOperationLease] = [:]

    func lease(
        key: CodexiOSPendingAuthOperationKey,
        operation: @escaping @Sendable () async throws -> CodexiOSPollResult
    ) -> CodexiOSPendingAuthOperationLease {
        if let existing = leases[key] { return existing }
        let lease = CodexiOSPendingAuthOperationLease(
            id: UUID(),
            task: Task { try await operation() }
        )
        leases[key] = lease
        return lease
    }

    func remove(key: CodexiOSPendingAuthOperationKey, id: UUID) {
        guard leases[key]?.id == id else { return }
        leases[key] = nil
    }
}

/// Serializes credential epochs across every foreground/background service
/// instance in this process. Network work happens outside this lock; writes
/// only commit when the epoch captured before the request is still current.
final class CodexiOSCredentialCoordinator: @unchecked Sendable {
    static let shared = CodexiOSCredentialCoordinator()

    private let lock = NSLock()
    private let tokenRefreshSingleFlight = CodexiOSTokenRefreshSingleFlight()
    private let pendingAuthSingleFlight = CodexiOSPendingAuthSingleFlight()
    private var generation: UInt64 = 0

    func loadTokens(from store: CodexiOSTokenStore) throws -> (generation: UInt64, tokens: CodexiOSTokens?) {
        try lock.withLock { (generation, try store.load()) }
    }

    func recoverPending(
        tokenStore: CodexiOSTokenStore,
        pendingStore: CodexiOSPendingAuthStore
    ) throws -> CodexiOSPendingAuthRecord? {
        try lock.withLock {
            if try tokenStore.load() != nil {
                try pendingStore.clear()
                return nil
            }
            return try pendingStore.load()
        }
    }

    func beginPendingFlow(pendingStore: CodexiOSPendingAuthStore) throws -> UInt64 {
        try lock.withLock {
            generation &+= 1
            try pendingStore.clear()
            return generation
        }
    }

    func refreshTokens(
        _ originalTokens: CodexiOSTokens,
        expectedGeneration: UInt64,
        store: CodexiOSTokenStore,
        operation: @escaping @Sendable (CodexiOSTokens) async throws -> CodexiOSTokens
    ) async throws -> CodexiOSCredentialRefreshResult {
        let mayRefresh = try lock.withLock {
            guard generation == expectedGeneration else { return false }
            return try store.load() == originalTokens
        }
        guard mayRefresh else { return .superseded }

        let lease = await tokenRefreshSingleFlight.lease(generation: expectedGeneration) {
            try await operation(originalTokens)
        }

        do {
            let refreshedTokens = try await lease.task.value
            let result = try lock.withLock { () throws -> CodexiOSCredentialRefreshResult in
                if generation != expectedGeneration {
                    guard let current = try store.load(), current == refreshedTokens else {
                        return .superseded
                    }
                    return .ready(generation: generation, tokens: current)
                }
                guard try store.load() == originalTokens else { return .superseded }
                try store.save(refreshedTokens)
                generation &+= 1
                return .ready(generation: generation, tokens: refreshedTokens)
            }
            await tokenRefreshSingleFlight.remove(generation: expectedGeneration, id: lease.id)
            return result
        } catch {
            await tokenRefreshSingleFlight.remove(generation: expectedGeneration, id: lease.id)
            throw error
        }
    }

    func savePending(
        _ pending: CodexiOSPendingAuthRecord,
        expectedGeneration: UInt64,
        to store: CodexiOSPendingAuthStore
    ) throws -> Bool {
        try lock.withLock {
            guard generation == expectedGeneration else { return false }
            try store.save(pending)
            return true
        }
    }

    func performPendingSignIn(
        flowID: String,
        operation: @escaping @Sendable () async throws -> CodexiOSPollResult
    ) async throws -> CodexiOSPollResult {
        let key = lock.withLock {
            CodexiOSPendingAuthOperationKey(generation: generation, flowID: flowID)
        }
        let lease = await pendingAuthSingleFlight.lease(key: key, operation: operation)
        do {
            let result = try await lease.task.value
            await pendingAuthSingleFlight.remove(key: key, id: lease.id)
            return result
        } catch {
            await pendingAuthSingleFlight.remove(key: key, id: lease.id)
            throw error
        }
    }

    func claimPendingSignIn(
        flowID: String,
        store: CodexiOSPendingAuthStore,
        now: Date = Date()
    ) throws -> CodexiOSPendingAuthResumeAction {
        try lock.withLock {
            guard var pending = try store.load(now: now), pending.flowID == flowID else {
                throw CodexiOSError.signInExpired
            }
            let currentGeneration = generation
            if let exchangedTokens = pending.exchangedTokens {
                return .persist(generation: currentGeneration, tokens: exchangedTokens)
            }
            if let nextPollAt = pending.nextPollAt, nextPollAt > now {
                return .wait(nextPollAt: nextPollAt)
            }

            pending.lastPolledAt = now
            pending.nextPollAt = min(
                pending.expiresAt,
                now.addingTimeInterval(TimeInterval(pending.interval))
            )
            try store.save(pending)
            if let approved = pending.approved {
                return .exchange(generation: currentGeneration, approved: approved)
            }
            return .poll(generation: currentGeneration, pending: pending)
        }
    }

    func markApproved(
        _ approved: CodexiOSApprovedAuthRecord,
        flowID: String,
        expectedGeneration: UInt64,
        store: CodexiOSPendingAuthStore
    ) throws -> Bool {
        try lock.withLock {
            guard generation == expectedGeneration,
                  var pending = try store.load(),
                  pending.flowID == flowID else { return false }
            pending.approved = approved
            pending.exchangedTokens = nil
            try store.save(pending)
            return true
        }
    }

    func markExchanged(
        _ tokens: CodexiOSTokens,
        flowID: String,
        expectedGeneration: UInt64,
        store: CodexiOSPendingAuthStore
    ) throws -> Bool {
        try lock.withLock {
            guard generation == expectedGeneration,
                  var pending = try store.load(),
                  pending.flowID == flowID,
                  pending.approved != nil else { return false }
            pending.exchangedTokens = tokens
            try store.save(pending)
            return true
        }
    }

    func deferPendingSignIn(
        flowID: String,
        expectedGeneration: UInt64,
        retryAfter: Date?,
        store: CodexiOSPendingAuthStore,
        now: Date = Date()
    ) throws -> Bool {
        try lock.withLock {
            guard generation == expectedGeneration,
                  var pending = try store.load(now: now),
                  pending.flowID == flowID else { return false }
            let intervalDate = now.addingTimeInterval(TimeInterval(pending.interval))
            pending.nextPollAt = min(
                pending.expiresAt,
                max(pending.nextPollAt ?? intervalDate, retryAfter ?? intervalDate)
            )
            try store.save(pending)
            return true
        }
    }

    func finishSignIn(
        tokens: CodexiOSTokens,
        expectedGeneration: UInt64,
        tokenStore: CodexiOSTokenStore,
        pendingStore: CodexiOSPendingAuthStore
    ) throws -> Bool {
        try lock.withLock {
            guard generation == expectedGeneration else { return false }
            try tokenStore.save(tokens)
            generation &+= 1
            try pendingStore.clear()
            return true
        }
    }

    func clearPending(
        expectedGeneration: UInt64,
        store: CodexiOSPendingAuthStore
    ) throws -> Bool {
        try lock.withLock {
            guard generation == expectedGeneration else { return false }
            try store.clear()
            return true
        }
    }

    func cancelSignIn(pendingStore: CodexiOSPendingAuthStore) throws {
        try lock.withLock {
            generation &+= 1
            try pendingStore.clear()
        }
    }

    func signOut(
        tokenStore: CodexiOSTokenStore,
        pendingStore: CodexiOSPendingAuthStore
    ) throws {
        try lock.withLock {
            generation &+= 1
            var firstError: Error?
            do { try tokenStore.clear() } catch { firstError = error }
            do { try pendingStore.clear() } catch { if firstError == nil { firstError = error } }
            if let firstError { throw firstError }
        }
    }

    func clearExpiredCredentials(
        expectedGeneration: UInt64,
        tokenStore: CodexiOSTokenStore,
        pendingStore: CodexiOSPendingAuthStore
    ) throws -> Bool {
        try lock.withLock {
            guard generation == expectedGeneration else { return false }
            generation &+= 1
            var firstError: Error?
            do { try tokenStore.clear() } catch { firstError = error }
            do { try pendingStore.clear() } catch { if firstError == nil { firstError = error } }
            if let firstError { throw firstError }
            return true
        }
    }

    func isCurrent(_ expectedGeneration: UInt64) -> Bool {
        lock.withLock { generation == expectedGeneration }
    }
}
