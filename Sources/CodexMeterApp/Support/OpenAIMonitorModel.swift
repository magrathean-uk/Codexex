import Foundation
import Observation
import CodexMeterCore

@MainActor @Observable
final class OpenAIMonitorModel {
    private(set) var hasKey = false
    private(set) var isValidated = false
    private(set) var deletionPending = false
    private(set) var isRefreshing = false
    private(set) var keyKind: OpenAIAPIKeyKind = .regular
    private(set) var organizationID: String?
    private(set) var report: OpenAIAPIReport?
    private(set) var balance: OpenAICreditBalance?
    private(set) var balanceError: String?
    private(set) var error: String?
    private(set) var validatedAt: Date?
    private(set) var unofficialBalanceEnabled = false
    private let client: OpenAIAPIClient
    private let loadCredential: () throws -> OpenAIAPICredential?
    private let persistCredential: (OpenAIAPICredential) throws -> Void
    private let deleteCredential: () throws -> Void
    private let loadConsent: () -> Bool
    private let persistConsent: (Bool) throws -> Void
    private var generation = 0
    private var lastAttempt: Date?
    private var preview = false
    private var refreshTask: Task<Void, Never>?
    private var consentRevokedInSession = false

    init(client: OpenAIAPIClient = OpenAIAPIClient(), store: OpenAIAPICredentialStore = OpenAIAPICredentialStore(), preview: Bool = false,
         load: (() throws -> OpenAIAPICredential?)? = nil,
         persist: ((OpenAIAPICredential) throws -> Void)? = nil,
         delete: (() throws -> Void)? = nil,
         loadConsent: (() -> Bool)? = nil,
         persistConsent: ((Bool) throws -> Void)? = nil) {
        self.client = client
        self.loadCredential = load ?? { try store.load() }
        self.persistCredential = persist ?? { try store.save($0) }
        self.deleteCredential = delete ?? { try store.delete() }
        self.loadConsent = loadConsent ?? { UserDefaults.standard.bool(forKey: "codexex.unofficialOpenAIBalanceConsent.v2") }
        self.persistConsent = persistConsent ?? { UserDefaults.standard.set($0, forKey: "codexex.unofficialOpenAIBalanceConsent.v2") }
        self.preview = preview
        guard !preview else { return }
        unofficialBalanceEnabled = self.loadConsent()
        do {
            if let credential = try loadCredential() {
                hasKey = true; keyKind = credential.kind; organizationID = credential.organizationID
                if credential.kind == .billingSession && !unofficialBalanceEnabled { self.error = Self.balanceDisabledMessage }
            }
        } catch { self.error = error.localizedDescription }
    }
    func setPreview(_ enabled: Bool) {
        guard enabled != preview else { return }
        preview = enabled
        generation += 1
        refreshTask?.cancel()
        isRefreshing = false
        isValidated = false
        report = nil
        balance = nil
        balanceError = nil
        error = nil
        if !enabled && !deletionPending {
            unofficialBalanceEnabled = !consentRevokedInSession && loadConsent()
            do {
                let credential = try loadCredential()
                hasKey = credential != nil; keyKind = credential?.kind ?? .regular; organizationID = credential?.organizationID
                if credential?.kind == .billingSession && !unofficialBalanceEnabled { self.error = Self.balanceDisabledMessage }
            }
            catch { self.error = error.localizedDescription }
        }
    }
    func saveKey(_ key: String, kind: OpenAIAPIKeyKind, organizationID: String? = nil) {
        guard !preview else { return }
        guard kind != .billingSession || unofficialBalanceEnabled else { error = Self.balanceDisabledMessage; return }
        let credential = OpenAIAPICredential(key: key.trimmingCharacters(in: .whitespacesAndNewlines), kind: kind, organizationID: organizationID)
        do {
            try OpenAIAPIClient.validateCredential(credential.key, kind: credential.kind)
            try OpenAIAPIClient.validateOrganizationID(credential.organizationID)
        }
        catch { self.error = error.localizedDescription; return }
        generation += 1
        refreshTask?.cancel()
        isRefreshing = true
        error = nil
        let currentGeneration = generation
        let now = Date()
        let allowUnofficial = unofficialBalanceEnabled
        refreshTask = Task { [weak self, client] in
            do {
                let result = try await Self.fetch(client: client, credential: credential, now: now, allowUnofficial: allowUnofficial)
                guard let self, self.generation == currentGeneration, !self.preview, !Task.isCancelled else { return }
                // Persist only after the selected capability has succeeded, and only while still authorized.
                try self.persistCredential(credential)
                self.deletionPending = false
                self.hasKey = true; self.keyKind = kind; self.organizationID = credential.organizationID; self.isValidated = true; self.report = result.report
                self.balance = result.balance; self.balanceError = result.balanceError
                self.validatedAt = now; self.lastAttempt = now; self.isRefreshing = false
            } catch {
                guard let self, self.generation == currentGeneration, !self.preview, !Task.isCancelled else { return }
                self.error = (error as? OpenAIAPIError)?.localizedDescription
                    ?? (error as? OpenAIAPICredentialStore.CredentialError)?.localizedDescription
                    ?? "The read-only API check failed. Try again later."
                self.isRefreshing = false
            }
        }
    }
    func waitForPendingRequest() async { await refreshTask?.value }

    /// The native confirmation dialog is the only UI entry point for enabling this.
    /// Withdrawal cancels every pending result before clearing unofficial data.
    func setUnofficialBalanceEnabled(_ enabled: Bool) {
        guard !preview, enabled != unofficialBalanceEnabled else { return }
        // Revocation takes effect in memory even if writing its preference fails.
        if !enabled { unofficialBalanceEnabled = false; consentRevokedInSession = true }
        generation += 1
        refreshTask?.cancel()
        isRefreshing = false
        balance = nil
        balanceError = enabled ? nil : Self.balanceDisabledMessage
        lastAttempt = nil
        if keyKind == .billingSession { isValidated = false; validatedAt = nil }
        do {
            try persistConsent(enabled)
            unofficialBalanceEnabled = enabled
            if enabled { consentRevokedInSession = false }
            error = nil
        } catch {
            self.error = "The unofficial balance preference could not be saved. Balance access is disabled for this session."
            unofficialBalanceEnabled = false
        }
    }

    func disconnect() {
        guard !preview else { return }
        generation += 1
        refreshTask?.cancel()
        isRefreshing = false
        hasKey = false; isValidated = false; organizationID = nil; report = nil; balance = nil; balanceError = nil; error = nil; validatedAt = nil; lastAttempt = nil
        do { try deleteCredential(); deletionPending = false }
        catch {
            deletionPending = true
            self.error = "Monitoring stopped, but Keychain could not remove the API key. Unlock the device and retry removal."
        }
    }
    func refresh() {
        // A background launch can precede device unlock. Retry only the existing
        // saved credential; a pending disconnect must never resume access.
        if !preview, !deletionPending, !hasKey, error != nil {
            do {
                if let credential = try loadCredential() {
                    hasKey = true; keyKind = credential.kind; organizationID = credential.organizationID
                }
            } catch { return }
        }
        guard !preview, hasKey, !isRefreshing else { return }
        let now = Date()
        guard lastAttempt.map({ now.timeIntervalSince($0) >= 60 }) ?? true else { return }
        let credential: OpenAIAPICredential
        do {
            guard let stored = try loadCredential() else { hasKey = false; return }
            guard stored.kind != .billingSession || unofficialBalanceEnabled else {
                self.error = Self.balanceDisabledMessage
                self.isValidated = false
                return
            }
            credential = stored
        } catch { self.error = error.localizedDescription; return }
        lastAttempt = now
        isRefreshing = true
        error = nil
        let currentGeneration = generation
        let allowUnofficial = unofficialBalanceEnabled
        refreshTask = Task { [weak self, client] in
            do {
                let result = try await Self.fetch(client: client, credential: credential, now: now, allowUnofficial: allowUnofficial)
                guard let self, self.generation == currentGeneration, !Task.isCancelled else { return }
                self.report = result.report; self.balance = result.balance; self.balanceError = result.balanceError
                self.isValidated = true; self.validatedAt = now; self.isRefreshing = false
            } catch {
                guard let self, self.generation == currentGeneration, !Task.isCancelled else { return }
                self.error = (error as? OpenAIAPIError)?.localizedDescription ?? "The read-only API check failed. Try again later."
                self.isValidated = false; self.balance = nil; self.balanceError = nil; self.isRefreshing = false
            }
        }
    }
    private static let balanceDisabledMessage = "Unofficial balance access is disabled. Review the account-risk warning to enable it, or open API billing."
    private struct FetchResult: Sendable {
        let report: OpenAIAPIReport?
        let balance: OpenAICreditBalance?
        let balanceError: String?
    }
    private nonisolated static func fetch(client: OpenAIAPIClient, credential: OpenAIAPICredential, now: Date, allowUnofficial: Bool) async throws -> FetchResult {
        try Task.checkCancellation()
        try OpenAIAPIClient.validateCredential(credential.key, kind: credential.kind)
        if credential.kind == .billingSession {
            let balance = try await client.balance(key: credential.key, organizationID: credential.organizationID, now: now, allowUnofficial: allowUnofficial)
            return FetchResult(report: nil, balance: balance, balanceError: nil)
        }
        let report: OpenAIAPIReport?
        if credential.kind == .admin { report = try await client.report(key: credential.key, now: now) }
        else { try await client.validate(key: credential.key); report = nil }
        try Task.checkCancellation()
        guard allowUnofficial else { return FetchResult(report: report, balance: nil, balanceError: "Automatic dollars remaining are not available through documented public APIs. Unofficial balance access is disabled.") }
        do {
            let balance = try await client.balance(key: credential.key, organizationID: credential.organizationID, now: now, allowUnofficial: true)
            return FetchResult(report: report, balance: balance, balanceError: nil)
        } catch is CancellationError { throw CancellationError() }
        catch {
            try Task.checkCancellation()
            return FetchResult(report: report, balance: nil, balanceError: "The unofficial balance could not be read. The credential may lack billing permission, or the private endpoint may have changed. Open API billing to confirm your balance.")
        }
    }

}
