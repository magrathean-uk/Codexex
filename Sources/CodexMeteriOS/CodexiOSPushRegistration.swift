import Foundation
import UIKit

@MainActor
protocol CodexiOSPushRegistering {
    func enable() async
    func disable() async
    func didRegister(deviceToken: Data) async
}

struct CodexiOSPushRegistrationRecord: Codable, Equatable, Sendable {
    let installationID: String
    let installationSecret: String
}

struct CodexiOSPushRegistrationStore: Sendable {
    private let backend: any CodexiOSSecureDataStoring
    private let service = "com.magrathean.CodexexApp.iOS"
    private let account = "apns-wake-registration"

    init(backend: any CodexiOSSecureDataStoring = CodexiOSKeychainDataStore()) {
        self.backend = backend
    }

    func load() throws -> CodexiOSPushRegistrationRecord? {
        guard let data = try backend.load(service: service, account: account) else { return nil }
        return try JSONDecoder().decode(CodexiOSPushRegistrationRecord.self, from: data)
    }

    func save(_ record: CodexiOSPushRegistrationRecord) throws {
        try backend.save(
            JSONEncoder().encode(record),
            service: service,
            account: account,
            accessibility: .afterFirstUnlockThisDeviceOnly
        )
    }

    func clear() throws {
        try backend.remove(service: service, account: account)
    }
}

@MainActor
final class CodexiOSPushRegistrationManager: CodexiOSPushRegistering {
    private static let endpoint = URL(string: "https://push.magrathean.uk/v1/codexex/installations/")!
    private static let enabledKey = "ios.liveActivity.pushWakeEnabled"
    private static let requestTimeout: TimeInterval = 10

    private let store: CodexiOSPushRegistrationStore
    private let defaults: UserDefaults
    private let session: URLSession
    private let registerForRemoteNotifications: @MainActor @Sendable () -> Void
    private let registrationRetryDelay: Duration
    private var operationTail: Task<Void, Never>?
    private var retryTask: Task<Void, Never>?
    /// Kept in memory only. The keychain record deliberately contains only the
    /// opaque installation credential, never the APNs token.
    private var pendingDeviceToken: String?
    private var desiredStateVersion = 0

    init(
        store: CodexiOSPushRegistrationStore = CodexiOSPushRegistrationStore(),
        defaults: UserDefaults = .standard,
        session: URLSession = .shared,
        registrationRetryDelay: Duration = .seconds(30),
        registerForRemoteNotifications: @escaping @MainActor @Sendable () -> Void = {
            UIApplication.shared.registerForRemoteNotifications()
        }
    ) {
        self.store = store
        self.defaults = defaults
        self.session = session
        self.registrationRetryDelay = registrationRetryDelay
        self.registerForRemoteNotifications = registerForRemoteNotifications
    }

    func enable() async {
        desiredStateVersion &+= 1
        defaults.set(true, forKey: Self.enabledKey)
        registerForRemoteNotifications()
    }

    func disable() async {
        desiredStateVersion &+= 1
        defaults.set(false, forKey: Self.enabledKey)
        pendingDeviceToken = nil
        retryTask?.cancel()
        retryTask = nil
        let stateVersion = desiredStateVersion
        await enqueueOperation { [weak self] in
            guard let self,
                  self.desiredStateVersion == stateVersion,
                  self.defaults.bool(forKey: Self.enabledKey) == false,
                  let record = try? self.store.load()
            else {
                return
            }

            do {
                try await self.unregister(record)
                guard self.desiredStateVersion == stateVersion,
                      self.defaults.bool(forKey: Self.enabledKey) == false,
                      let currentRecord = try? self.store.load(),
                      currentRecord == record
                else {
                    return
                }
                try self.store.clear()
            } catch {
                // Retain the opaque record so a later stop can retry deletion.
            }
        }
    }

    func didRegister(deviceToken: Data) async {
        guard defaults.bool(forKey: Self.enabledKey) else { return }
        guard deviceToken.isEmpty == false else { return }
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        pendingDeviceToken = token
        let stateVersion = desiredStateVersion

        await registerPendingDeviceToken(token, stateVersion: stateVersion)
    }

    /// Called at foreground entry and by the bounded retry task. A token is
    /// retried only while the corresponding Live Activity remains enabled.
    func retryPendingRegistration() async {
        guard defaults.bool(forKey: Self.enabledKey), let pendingDeviceToken else { return }
        await registerPendingDeviceToken(
            pendingDeviceToken,
            stateVersion: desiredStateVersion
        )
    }

    private func registerPendingDeviceToken(_ token: String, stateVersion: Int) async {
        await enqueueOperation { [weak self] in
            guard let self,
                  self.desiredStateVersion == stateVersion,
                  self.defaults.bool(forKey: Self.enabledKey)
            else {
                return
            }

            let record: CodexiOSPushRegistrationRecord
            if let existing = try? self.store.load() {
                record = existing
            } else {
                guard let secret = try? CodexiOSSecureRandom.flowID() else { return }
                record = CodexiOSPushRegistrationRecord(
                    installationID: UUID().uuidString.lowercased(),
                    installationSecret: secret
                )
            }
            do {
                try self.store.save(record)
                try await self.register(record, deviceToken: token)
                guard self.desiredStateVersion == stateVersion,
                      self.defaults.bool(forKey: Self.enabledKey),
                      self.pendingDeviceToken == token else {
                    return
                }
                self.pendingDeviceToken = nil
                self.retryTask?.cancel()
                self.retryTask = nil
            } catch {
                guard self.desiredStateVersion == stateVersion,
                      self.defaults.bool(forKey: Self.enabledKey),
                      self.pendingDeviceToken == token else {
                    return
                }
                self.scheduleRegistrationRetry()
            }
        }
    }

    private func scheduleRegistrationRetry() {
        retryTask?.cancel()
        let delay = registrationRetryDelay
        retryTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: delay)
            } catch {
                return
            }
            await self?.retryPendingRegistration()
        }
    }

    private func enqueueOperation(_ operation: @escaping @MainActor () async -> Void) async {
        let precedingOperation = operationTail
        let nextOperation = Task { @MainActor in
            await precedingOperation?.value
            await operation()
        }
        operationTail = nextOperation
        await nextOperation.value
    }

    private func register(_ record: CodexiOSPushRegistrationRecord, deviceToken: String) async throws {
        var request = URLRequest(url: Self.endpoint.appending(path: record.installationID))
        request.httpMethod = "PUT"
        request.timeoutInterval = Self.requestTimeout
        request.setValue("Bearer \(record.installationSecret)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode([
            "deviceToken": deviceToken,
            "environment": Self.environment,
        ])
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }

    private func unregister(_ record: CodexiOSPushRegistrationRecord) async throws {
        var request = URLRequest(url: Self.endpoint.appending(path: record.installationID))
        request.httpMethod = "DELETE"
        request.timeoutInterval = Self.requestTimeout
        request.setValue("Bearer \(record.installationSecret)", forHTTPHeaderField: "Authorization")
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }

    private static var environment: String {
        #if DEBUG
        "sandbox"
        #else
        "production"
        #endif
    }
}

@MainActor
let codexiOSSharedPushRegistrationManager = CodexiOSPushRegistrationManager()
