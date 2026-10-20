import Foundation
import Testing
@testable import CodexMeterApp
import CodexMeterCore

@MainActor
struct OpenAIMonitorModelTests {
    @Test func previewCannotSaveRefreshOrDisconnectCredentials() {
        let client = OpenAIAPIClient { _ in
            Issue.record("Preview made an API request")
            throw OpenAIAPIError.unavailable
        }
        let monitor = OpenAIMonitorModel(client: client, store: OpenAIAPICredentialStore(service: "preview-test-unused"), preview: true, loadConsent: { false }, persistConsent: { _ in })
        monitor.saveKey("sk-test-fixture", kind: .admin)
        monitor.refresh()
        monitor.disconnect()
        monitor.setUnofficialBalanceEnabled(true)
        #expect(!monitor.hasKey)
        #expect(!monitor.isValidated)
        #expect(!monitor.isRefreshing)
        #expect(monitor.report == nil)
        #expect(monitor.error == nil)
        #expect(!monitor.unofficialBalanceEnabled)
    }
}

@MainActor
struct OpenAIMonitorLifecycleTests {
    @Test func savedCredentialBecomesUsableAfterUnlock() async {
        var locked = true
        let credential = OpenAIAPICredential(key: "sk-test-fixture", kind: .regular)
        let monitor = OpenAIMonitorModel(client: OpenAIAPIClient { request in
            #expect(request.url?.path == "/v1/models")
            return (Data(#"{"data":[]}"#.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }, load: {
            if locked { throw OpenAIAPICredentialStore.CredentialError.unavailable }
            return credential
        }, persist: { _ in Issue.record("Unlock retry rewrote the credential") }, delete: {}, loadConsent: { false }, persistConsent: { _ in })
        #expect(!monitor.hasKey)
        monitor.refresh()
        #expect(!monitor.isValidated)
        locked = false
        monitor.refresh()
        await monitor.waitForPendingRequest()
        #expect(monitor.hasKey && monitor.isValidated)
        #expect(monitor.balance == nil)
    }

    @Test func standardKeyIsPersistedOnlyAfterSuccessfulReadOnlyValidation() async {
        let gate = OpenAIMonitorTestGate()
        var saved: OpenAIAPICredential?
        let monitor = OpenAIMonitorModel(client: OpenAIAPIClient { request in
            #expect(request.url?.path == "/v1/models")
            let data = await gate.responseData()
            return (data, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }, load: { saved }, persist: { saved = $0 }, delete: { saved = nil }, loadConsent: { false }, persistConsent: { _ in })
        monitor.saveKey("sk-test-fixture", kind: .regular)
        await gate.waitForRequest()
        #expect(saved == nil)
        #expect(!monitor.hasKey)
        await gate.complete()
        await monitor.waitForPendingRequest()
        #expect(saved?.key == "sk-test-fixture")
        #expect(saved?.kind == .regular)
        #expect(monitor.hasKey)
        #expect(monitor.isValidated)
    }

    @Test func standardKeyUsesOnlyDocumentedModelsAndDoesNotInventBalance() async {
        var saved: OpenAIAPICredential?
        let monitor = OpenAIMonitorModel(client: OpenAIAPIClient { request in
            #expect(request.url?.path == "/v1/models")
            return (Data(#"{"data":[]}"#.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }, load: { saved }, persist: { saved = $0 }, delete: { saved = nil }, loadConsent: { false }, persistConsent: { _ in })
        monitor.saveKey("sk-test-fixture", kind: .regular)
        await monitor.waitForPendingRequest()
        #expect(monitor.hasKey && monitor.isValidated)
        #expect(monitor.balance == nil)
        #expect(monitor.balanceError?.contains("documented public APIs") == true)
        #expect(monitor.error == nil)
    }

    @Test func storedBillingSessionIsNeverSentAndCanBeDisconnected() async {
        var saved: OpenAIAPICredential? = OpenAIAPICredential(key: "sess-test-fixture", kind: .billingSession, organizationID: "org-selected")
        let monitor = OpenAIMonitorModel(client: OpenAIAPIClient { _ in
            Issue.record("An obsolete billing session reached the network")
            throw OpenAIAPIError.unavailable
        }, load: { saved }, persist: { saved = $0 }, delete: { saved = nil }, loadConsent: { false }, persistConsent: { _ in })
        monitor.refresh()
        await monitor.waitForPendingRequest()
        #expect(saved?.kind == .billingSession)
        #expect(monitor.balance == nil)
        #expect(monitor.report == nil)
        #expect(!monitor.isValidated)
        #expect(monitor.error?.contains("is disabled") == true)
        monitor.setPreview(true)
        monitor.setPreview(false)
        monitor.refresh()
        await monitor.waitForPendingRequest()
        #expect(!monitor.isValidated)
        monitor.disconnect()
        #expect(monitor.balance == nil && saved == nil)
    }

    @Test func newBillingSessionIsRejectedBeforeNetworkingOrPersistence() async {
        var saved: OpenAIAPICredential?
        let monitor = OpenAIMonitorModel(client: OpenAIAPIClient { _ in
            Issue.record("A new billing session reached the network")
            throw OpenAIAPIError.unavailable
        }, load: { saved }, persist: { saved = $0 }, delete: { saved = nil }, loadConsent: { false }, persistConsent: { _ in })
        monitor.saveKey("sess-test-fixture", kind: .billingSession)
        await monitor.waitForPendingRequest()
        #expect(saved == nil && monitor.balance == nil)
        #expect(!monitor.hasKey && !monitor.isValidated)
    }

    @Test func deniedAdminCapabilityDoesNotPersistCredential() async {
        var saved: OpenAIAPICredential?
        let monitor = OpenAIMonitorModel(client: OpenAIAPIClient { request in
            #expect(request.url?.path == "/v1/organization/usage/completions")
            return (Data(), HTTPURLResponse(url: request.url!, statusCode: 403, httpVersion: nil, headerFields: nil)!)
        }, load: { saved }, persist: { saved = $0 }, delete: { saved = nil }, loadConsent: { false }, persistConsent: { _ in })
        monitor.saveKey("sk-test-fixture", kind: .admin)
        await monitor.waitForPendingRequest()
        #expect(saved == nil)
        #expect(!monitor.hasKey)
        #expect(!monitor.isValidated)
        #expect(monitor.error == OpenAIAPIError.permissionDenied.localizedDescription)
    }

    @Test func enteringPreviewWhileValidationWaitsPreventsPersistence() async {
        let gate = OpenAIMonitorTestGate()
        var saved: OpenAIAPICredential?
        let monitor = OpenAIMonitorModel(client: OpenAIAPIClient { request in
            let data = await gate.responseData()
            return (data, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }, load: { saved }, persist: { saved = $0 }, delete: { saved = nil }, loadConsent: { false }, persistConsent: { _ in })
        monitor.saveKey("sk-test-fixture", kind: .regular)
        await gate.waitForRequest()
        monitor.setPreview(true)
        await gate.complete()
        await monitor.waitForPendingRequest()
        #expect(saved == nil)
        #expect(!monitor.hasKey)
        #expect(!monitor.isValidated)
    }

    @Test func disconnectWhileValidationWaitsPreventsPersistence() async {
        let gate = OpenAIMonitorTestGate()
        var saved: OpenAIAPICredential?
        let monitor = OpenAIMonitorModel(client: OpenAIAPIClient { request in
            let data = await gate.responseData()
            return (data, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }, load: { saved }, persist: { saved = $0 }, delete: { saved = nil }, loadConsent: { false }, persistConsent: { _ in })
        monitor.saveKey("sk-test-fixture", kind: .regular)
        await gate.waitForRequest()
        monitor.disconnect()
        await gate.complete()
        await monitor.waitForPendingRequest()
        #expect(saved == nil)
        #expect(!monitor.hasKey)
        #expect(!monitor.isValidated)
    }

    @Test func failedKeyDeletionStopsMonitoringAndCanBeRetried() async {
        let counter = OpenAIMonitorRequestCounter()
        var failDeletion = true
        var saved: OpenAIAPICredential? = OpenAIAPICredential(key: "sk-test-fixture", kind: .regular)
        let monitor = OpenAIMonitorModel(client: OpenAIAPIClient { request in
            await counter.increment()
            return (Data(#"{"data":[]}"#.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }, load: { saved }, persist: { saved = $0 }, delete: {
            if failDeletion { throw OpenAIAPICredentialStore.CredentialError.unavailable }
            saved = nil
        }, loadConsent: { false }, persistConsent: { _ in })
        monitor.disconnect()
        monitor.refresh()
        await monitor.waitForPendingRequest()
        #expect(!monitor.hasKey)
        #expect(monitor.deletionPending)
        #expect(await counter.count == 0)
        failDeletion = false
        monitor.disconnect()
        #expect(!monitor.deletionPending)
        #expect(saved == nil)
    }

    @Test func cooldownPreventsRepeatedRefreshAfterSavingValidatedKey() async {
        let counter = OpenAIMonitorRequestCounter()
        var saved: OpenAIAPICredential?
        let monitor = OpenAIMonitorModel(client: OpenAIAPIClient { request in
            await counter.increment()
            return (Data(#"{"data":[]}"#.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }, load: { saved }, persist: { saved = $0 }, delete: { saved = nil }, loadConsent: { false }, persistConsent: { _ in })
        monitor.saveKey("sk-test-fixture", kind: .regular)
        await monitor.waitForPendingRequest()
        monitor.refresh()
        monitor.refresh()
        await monitor.waitForPendingRequest()
        #expect(await counter.count == 1)
    }

    @Test func explicitConsentPersistsBeforeSessionBalanceAndCanBeRevoked() async {
        var consent = false
        var saved: OpenAIAPICredential?
        let monitor = OpenAIMonitorModel(client: OpenAIAPIClient { request in
            #expect(request.url?.path == "/v1/dashboard/billing/credit_grants")
            #expect(request.value(forHTTPHeaderField: "OpenAI-Organization") == "org-selected")
            return (Data(#"{"total_available":2.37}"#.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }, load: { saved }, persist: { saved = $0 }, delete: { saved = nil }, loadConsent: { consent }, persistConsent: { consent = $0 })
        #expect(!monitor.unofficialBalanceEnabled)
        monitor.setUnofficialBalanceEnabled(true)
        #expect(consent && monitor.unofficialBalanceEnabled)
        monitor.saveKey("sess-test-fixture", kind: .billingSession, organizationID: "org-selected")
        await monitor.waitForPendingRequest()
        #expect(saved?.kind == .billingSession)
        #expect(monitor.balance?.remainingUSD == Decimal(string: "2.37"))
        monitor.setUnofficialBalanceEnabled(false)
        #expect(!consent && !monitor.unofficialBalanceEnabled)
        #expect(monitor.balance == nil && !monitor.isValidated)
        #expect(saved != nil) // Revocation does not delete an owner's credential.
        monitor.refresh()
        await monitor.waitForPendingRequest()
        #expect(monitor.balance == nil)
    }

    @Test func withdrawalWhileBalanceWaitsCannotPublishOrPersistItsResult() async {
        let gate = OpenAIMonitorTestGate()
        var consent = false
        var saved: OpenAIAPICredential?
        let monitor = OpenAIMonitorModel(client: OpenAIAPIClient { request in
            #expect(request.url?.path == "/v1/dashboard/billing/credit_grants")
            let data = await gate.responseData()
            return (data, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }, load: { saved }, persist: { saved = $0 }, delete: { saved = nil }, loadConsent: { consent }, persistConsent: { consent = $0 })
        monitor.setUnofficialBalanceEnabled(true)
        monitor.saveKey("sess-test-fixture", kind: .billingSession)
        await gate.waitForRequest()
        monitor.setUnofficialBalanceEnabled(false)
        await gate.complete(data: Data(#"{"total_available":2.37}"#.utf8))
        await monitor.waitForPendingRequest()
        #expect(saved == nil && monitor.balance == nil)
        #expect(!monitor.hasKey && !monitor.unofficialBalanceEnabled)
    }

    @Test func withdrawalDuringPublicValidationPreventsLaterPrivateRequest() async {
        let gate = OpenAIMonitorTestGate()
        var consent = false
        var saved: OpenAIAPICredential?
        let monitor = OpenAIMonitorModel(client: OpenAIAPIClient { request in
            #expect(request.url?.path == "/v1/models")
            let data = await gate.responseData()
            return (data, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }, load: { saved }, persist: { saved = $0 }, delete: { saved = nil }, loadConsent: { consent }, persistConsent: { consent = $0 })
        monitor.setUnofficialBalanceEnabled(true)
        monitor.saveKey("sk-test-fixture", kind: .regular)
        await gate.waitForRequest()
        monitor.setUnofficialBalanceEnabled(false)
        await gate.complete()
        await monitor.waitForPendingRequest()
        #expect(saved == nil && monitor.balance == nil)
        #expect(!monitor.unofficialBalanceEnabled)
    }

    @Test func failedConsentPersistenceCannotEnableAccess() async {
        let monitor = OpenAIMonitorModel(client: OpenAIAPIClient { _ in
            Issue.record("Failed consent persistence allowed a request")
            throw OpenAIAPIError.unavailable
        }, load: { nil }, persist: { _ in Issue.record("A credential was persisted") }, delete: {}, loadConsent: { false }, persistConsent: { _ in throw OpenAIAPIError.unavailable })
        monitor.setUnofficialBalanceEnabled(true)
        monitor.saveKey("sess-test-fixture", kind: .billingSession)
        await monitor.waitForPendingRequest()
        #expect(!monitor.unofficialBalanceEnabled && !monitor.hasKey)
    }

    @Test func failedRevocationWriteStillBlocksAccessAfterPreviewExit() async {
        let saved = OpenAIAPICredential(key: "sess-test-fixture", kind: .billingSession)
        let monitor = OpenAIMonitorModel(client: OpenAIAPIClient { _ in
            Issue.record("Revocation failure re-enabled network access")
            throw OpenAIAPIError.unavailable
        }, load: { saved }, persist: { _ in }, delete: {}, loadConsent: { true }, persistConsent: { _ in throw OpenAIAPIError.unavailable })
        monitor.setUnofficialBalanceEnabled(false)
        monitor.setPreview(true)
        monitor.setPreview(false)
        monitor.refresh()
        await monitor.waitForPendingRequest()
        #expect(!monitor.unofficialBalanceEnabled)
        #expect(monitor.balance == nil && !monitor.isValidated)
    }
}

private actor OpenAIMonitorRequestCounter {
    var count = 0
    func increment() { count += 1 }
}

private actor OpenAIMonitorTestGate {
    private var continuation: CheckedContinuation<Data, Never>?
    func responseData() async -> Data {
        await withCheckedContinuation { continuation = $0 }
    }
    func waitForRequest() async {
        while continuation == nil { await Task.yield() }
    }
    func complete(data: Data = Data(#"{"data":[]}"#.utf8)) {
        continuation?.resume(returning: data)
        continuation = nil
    }
}
