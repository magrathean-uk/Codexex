import Foundation
import UIKit
import Observation

enum CodexiOSPushRegistrationState: String {
    case disabled, pending, registered

    var title: String {
        switch self {
        case .disabled: "Disabled"
        case .pending: "Pending"
        case .registered: "Registered"
        }
    }
}

struct CodexiOSPushWakeReceipt: Codable, Equatable {
    let receivedAt: TimeInterval
    let recordedAt: TimeInterval
    let outcome: String
    let snapshotCapturedAt: TimeInterval?
    let appState: String?
    let protectedDataAvailable: Bool?

    var summary: String {
        let label = switch outcome {
        case "refreshed": "Refreshed"
        case "received": "Received"
        case "coalesced": "Coalesced"
        case "no-active-activity": "Activity ended"
        case "timed-out": "Timed out"
        default: "Refresh failed"
        }
        return "\(label) · \(Date(timeIntervalSince1970: recordedAt).formatted(date: .omitted, time: .shortened))"
    }
}

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
@Observable
final class CodexiOSPushRegistrationManager: CodexiOSPushRegistering {
    private static let endpoint = URL(string: "https://push.magrathean.uk/v1/codexex/installations/")!
    private static let enabledKey = "ios.liveActivity.pushWakeEnabled"
    private static let requestTimeout: TimeInterval = 10
    private static let registeredAtKey = "ios.liveActivity.pushRegisteredAt"
    private static let registrationStateKey = "ios.liveActivity.pushRegistrationState"
    private static let wakeReceiptKey = "ios.liveActivity.lastWakeReceipt"
    private static let testWakeCooldownKey = "ios.liveActivity.testWakeCooldownUntil"

    private(set) var registrationState: CodexiOSPushRegistrationState = .disabled
    private(set) var registeredAt: Date?
    private(set) var lastWake: CodexiOSPushWakeReceipt?
    private(set) var isRequestingTestWake = false
    private(set) var isTestWakeCoolingDown = false
    private var testWakeCooldownTask: Task<Void, Never>?
    private(set) var testWakeStatus: String?
    private var isLiveActivityRunning: Bool?
    private var lastRequestMethod: String?
    private var lastHTTPStatus: Int?
    private var lastRequestAt: Date?
    private var lastTestWakeHTTPStatus: Int?
    #if DEBUG
    private var debugTestPhase: String?
    func recordDebugTestPhase(_ phase: String) {
        debugTestPhase = phase
        publishDiagnostics()
    }
    #endif
    private let diagnosticsFileURL: URL?

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
        diagnosticsFileURL: URL? = URL.cachesDirectory.appending(path: "CodexexAPNsDiagnostics.json"),
        registrationRetryDelay: Duration = .seconds(30),
        registerForRemoteNotifications: @escaping @MainActor @Sendable () -> Void = {
            UIApplication.shared.registerForRemoteNotifications()
        }
    ) {
        self.store = store
        self.defaults = defaults
        self.session = session
        self.diagnosticsFileURL = diagnosticsFileURL
        self.registrationRetryDelay = registrationRetryDelay
        self.registerForRemoteNotifications = registerForRemoteNotifications
        if let diagnosticsFileURL,
           let data = try? Data(contentsOf: diagnosticsFileURL), data.count <= 4_096,
           let previous = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let method = previous["lastRequestMethod"] as? String, ["PUT", "POST", "DELETE"].contains(method) {
                lastRequestMethod = method
            }
            if let status = previous["lastHTTPStatus"] as? Int, (100...599).contains(status) { lastHTTPStatus = status }
            if let time = previous["lastRequestAt"] as? Double, time.isFinite { lastRequestAt = Date(timeIntervalSince1970: time) }
        }
        registeredAt = defaults.object(forKey: Self.registeredAtKey) as? Date
        if let data = defaults.data(forKey: Self.wakeReceiptKey) {
            lastWake = try? JSONDecoder().decode(CodexiOSPushWakeReceipt.self, from: data)
        }
        if defaults.bool(forKey: Self.enabledKey) {
            registrationState = defaults.string(forKey: Self.registrationStateKey) == CodexiOSPushRegistrationState.registered.rawValue
                && registeredAt.map { Date().timeIntervalSince($0) < 30 * 24 * 60 * 60 } == true
                ? .registered : .pending
        }
        publishDiagnostics()
        if let deadline = defaults.object(forKey: Self.testWakeCooldownKey) as? Date, deadline > Date() {
            startTestWakeCooldown(until: deadline)
        }
    }

    func enable() async {
        // Recovery may run in both the foreground and a background wake. An
        // already-enabled recovery must not invalidate an in-flight retry.
        if defaults.bool(forKey: Self.enabledKey) == false {
            desiredStateVersion &+= 1
            setRegistrationState(.pending)
        }
        defaults.set(true, forKey: Self.enabledKey)
        registerForRemoteNotifications()
    }

    func disable() async {
        desiredStateVersion &+= 1
        defaults.set(false, forKey: Self.enabledKey)
        setRegistrationState(.disabled)
        testWakeStatus = nil
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

    func didFailRemoteRegistration() {
        guard defaults.bool(forKey: Self.enabledKey) else { return }
        setRegistrationState(.pending)
    }

    func requestTestWake() async {
        guard !isRequestingTestWake, !isTestWakeCoolingDown, registrationState == .registered,
              defaults.bool(forKey: Self.enabledKey) else { return }
        isRequestingTestWake = true
        testWakeStatus = nil
        let stateVersion = desiredStateVersion
        defer { isRequestingTestWake = false }
        do {
            guard let record = try store.load() else { throw URLError(.userAuthenticationRequired) }
            var request = URLRequest(url: Self.endpoint.appending(path: record.installationID).appending(path: "wake"))
            request.httpMethod = "POST"
            request.timeoutInterval = Self.requestTimeout
            request.setValue("Bearer \(record.installationSecret)", forHTTPHeaderField: "Authorization")
            recordRequest(method: "POST", response: nil)
            let (data, response) = try await session.data(for: request)
            recordRequest(method: "POST", response: response)
            if (response as? HTTPURLResponse)?.statusCode == 429 {
                guard stateVersion == desiredStateVersion, defaults.bool(forKey: Self.enabledKey) else { return }
                startTestWakeCooldown(until: Date().addingTimeInterval(60))
                testWakeStatus = "Wait a minute before testing again."
                return
            }
            struct Acknowledgement: Decodable { let requested: Bool; let delaySeconds: Int }
            guard let http = response as? HTTPURLResponse, http.statusCode == 202,
                  let acknowledgement = try? JSONDecoder().decode(Acknowledgement.self, from: data),
                  acknowledgement.requested, (1...60).contains(acknowledgement.delaySeconds)
            else { throw URLError(.badServerResponse) }
            guard stateVersion == desiredStateVersion, defaults.bool(forKey: Self.enabledKey) else { return }
            // The server records delivery after its delay; include that delay
            // and a margin before offering another test.
            startTestWakeCooldown(until: Date().addingTimeInterval(90))
            testWakeStatus = "Requested · return to the Home Screen for \(acknowledgement.delaySeconds) seconds."
        } catch {
            guard stateVersion == desiredStateVersion, defaults.bool(forKey: Self.enabledKey) else { return }
            testWakeStatus = "Test request failed. Try again later."
        }
    }

    private func startTestWakeCooldown(until deadline: Date) {
        isTestWakeCoolingDown = true
        defaults.set(deadline, forKey: Self.testWakeCooldownKey)
        testWakeCooldownTask?.cancel()
        testWakeCooldownTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(max(0, deadline.timeIntervalSinceNow))) } catch { return }
            guard let self else { return }
            self.isTestWakeCoolingDown = false
            self.testWakeStatus = nil
            self.defaults.removeObject(forKey: Self.testWakeCooldownKey)
            self.publishDiagnostics()
        }
        publishDiagnostics()
    }

    /// Local timestamps and outcome only; no account, token, quota, or installation ID.
    func recordWake(receivedAt: Date, outcome: String, snapshotCapturedAt: Date? = nil,
                    appState: String? = nil, protectedDataAvailable: Bool? = nil) -> Data? {
        let receipt = CodexiOSPushWakeReceipt(receivedAt: receivedAt.timeIntervalSince1970,
            recordedAt: Date().timeIntervalSince1970, outcome: outcome,
            snapshotCapturedAt: snapshotCapturedAt?.timeIntervalSince1970,
            appState: appState, protectedDataAvailable: protectedDataAvailable)
        guard let data = try? JSONEncoder().encode(receipt) else { return nil }
        lastWake = receipt
        defaults.set(data, forKey: Self.wakeReceiptKey)
        publishDiagnostics()
        return data
    }

    func recordLiveActivityState(isRunning: Bool) {
        isLiveActivityRunning = isRunning
        publishDiagnostics()
    }

    func recordSystemState() { publishDiagnostics() }

    private func recordRequest(method: String, response: URLResponse?) {
        lastRequestMethod = method
        lastHTTPStatus = (response as? HTTPURLResponse)?.statusCode
        if method == "POST" { lastTestWakeHTTPStatus = lastHTTPStatus }
        lastRequestAt = Date()
        publishDiagnostics()
    }

    private func publishDiagnostics() {
        guard let diagnosticsFileURL else { return }
        var value: [String: Any] = [
            "registrationState": registrationState.rawValue,
            "recordedAt": Date().timeIntervalSince1970,
        ]
        let application = UIApplication.shared
        switch application.applicationState {
        case .active: value["currentAppState"] = "active"
        case .inactive: value["currentAppState"] = "inactive"
        case .background: value["currentAppState"] = "background"
        @unknown default: value["currentAppState"] = "unknown"
        }
        switch application.backgroundRefreshStatus {
        case .available: value["backgroundRefreshStatus"] = "available"
        case .denied: value["backgroundRefreshStatus"] = "denied"
        case .restricted: value["backgroundRefreshStatus"] = "restricted"
        @unknown default: value["backgroundRefreshStatus"] = "unknown"
        }
        value["currentProtectedDataAvailable"] = application.isProtectedDataAvailable
        value["lowPowerModeEnabled"] = ProcessInfo.processInfo.isLowPowerModeEnabled
        if let isLiveActivityRunning { value["isLiveActivityRunning"] = isLiveActivityRunning }
        if let registeredAt { value["registeredAt"] = registeredAt.timeIntervalSince1970 }
        if let lastRequestMethod { value["lastRequestMethod"] = lastRequestMethod }
        if let lastHTTPStatus { value["lastHTTPStatus"] = lastHTTPStatus }
        if let lastTestWakeHTTPStatus { value["lastTestWakeHTTPStatus"] = lastTestWakeHTTPStatus }
        if let lastRequestAt { value["lastRequestAt"] = lastRequestAt.timeIntervalSince1970 }
        #if DEBUG
        if let debugTestPhase { value["debugTestPhase"] = debugTestPhase }
        #endif
        if let lastWake {
            value["lastWakeReceivedAt"] = lastWake.receivedAt
            value["lastWakeRecordedAt"] = lastWake.recordedAt
            value["lastWakeOutcome"] = lastWake.outcome
            if let appState = lastWake.appState { value["lastWakeAppState"] = appState }
            if let protectedDataAvailable = lastWake.protectedDataAvailable { value["lastWakeProtectedDataAvailable"] = protectedDataAvailable }
        }
        guard let data = try? JSONSerialization.data(withJSONObject: value, options: .sortedKeys) else { return }
        try? data.write(to: diagnosticsFileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    private func setRegistrationState(_ state: CodexiOSPushRegistrationState) {
        registrationState = state
        defaults.set(state.rawValue, forKey: Self.registrationStateKey)
        publishDiagnostics()
    }

    /// Called at foreground entry and by the bounded retry task. A token is
    /// retried only while the corresponding Live Activity remains enabled.
    func retryPendingRegistration() async {
        guard defaults.bool(forKey: Self.enabledKey) else { return }
        guard let pendingDeviceToken else {
            // A transient UIKit/APNs failure happens before a token exists.
            // Foreground recovery must retry that stage, not just relay PUTs.
            if registrationState == .pending { registerForRemoteNotifications() }
            return
        }
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
                self.setRegistrationState(.registered)
                self.registeredAt = Date()
                self.defaults.set(self.registeredAt, forKey: Self.registeredAtKey)
                self.publishDiagnostics()
                self.retryTask?.cancel()
                self.retryTask = nil
            } catch {
                guard self.desiredStateVersion == stateVersion,
                      self.defaults.bool(forKey: Self.enabledKey),
                      self.pendingDeviceToken == token else {
                    return
                }
                self.scheduleRegistrationRetry()
                self.setRegistrationState(.pending)
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
        recordRequest(method: "PUT", response: nil)
        let (_, response) = try await session.data(for: request)
        recordRequest(method: "PUT", response: response)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }

    private func unregister(_ record: CodexiOSPushRegistrationRecord) async throws {
        var request = URLRequest(url: Self.endpoint.appending(path: record.installationID))
        request.httpMethod = "DELETE"
        request.timeoutInterval = Self.requestTimeout
        request.setValue("Bearer \(record.installationSecret)", forHTTPHeaderField: "Authorization")
        recordRequest(method: "DELETE", response: nil)
        let (_, response) = try await session.data(for: request)
        recordRequest(method: "DELETE", response: response)
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
