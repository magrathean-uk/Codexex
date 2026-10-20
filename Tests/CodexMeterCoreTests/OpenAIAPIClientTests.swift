import Foundation
import Testing
@testable import CodexMeterCore

struct OpenAIAPIClientTests {
    @Test func standardValidationIsReadOnlyAndHostPinned() async throws {
        let client = OpenAIAPIClient { request in
            #expect(request.url?.absoluteString == "https://api.openai.com/v1/models")
            #expect(request.httpMethod == "GET")
            #expect(request.httpBody == nil)
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer sk-test-fixture")
            return (Data(#"{"data":[{"id":"example"}]}"#.utf8), Self.response(request))
        }
        try await client.validate(key: "sk-test-fixture")
    }
    @Test func wrongProviderKeyCannotReachTransport() async {
        let client = OpenAIAPIClient { _ in
            Issue.record("A different provider’s secret reached OpenAI")
            throw OpenAIAPIError.unavailable
        }
        await #expect(throws: OpenAIAPIError.self) { try await client.validate(key: "sk-ant-api03-fixture") }
    }
    @Test func invalidKeyCannotReachTransport() async {
        let client = OpenAIAPIClient { _ in
            Issue.record("A malformed key reached the transport")
            throw OpenAIAPIError.unavailable
        }
        await #expect(throws: OpenAIAPIError.self) { try await client.validate(key: "fixture\r\nInjected: value") }
    }
    @Test func providerBodyAndTransportErrorsNeverAppearInErrors() async {
        let client = OpenAIAPIClient { request in
            (Data("secret fixture credential".utf8), Self.response(request, status: 401))
        }
        do { try await client.validate(key: "sk-test-fixture"); Issue.record("Expected rejection") }
        catch { #expect(error.localizedDescription == "OpenAI rejected this key. Check or replace it.") }
        let network = OpenAIAPIClient { _ in throw NSError(domain: "secret fixture credential", code: 1) }
        do { try await network.validate(key: "sk-test-fixture"); Issue.record("Expected rejection") }
        catch { #expect(!error.localizedDescription.contains("secret")) }
    }
    @Test func crossHostResponseIsRejected() async {
        let client = OpenAIAPIClient { _ in
            (Data(#"{"data":[]}"#.utf8), HTTPURLResponse(url: URL(string: "https://other.example/v1/models")!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        await #expect(throws: OpenAIAPIError.self) { try await client.validate(key: "sk-test-fixture") }
    }
    @Test func adminReportUsesHourBucketsAndDecimalCurrency() async throws {
        let client = OpenAIAPIClient { request in
            let items = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
            #expect(request.httpMethod == "GET")
            #expect(items.contains { $0.name == "start_time" && Int($0.value!) != nil })
            let body: String
            if request.url!.path.contains("usage") {
                #expect(items.contains(URLQueryItem(name: "bucket_width", value: "1h")))
                #expect(items.contains(URLQueryItem(name: "group_by", value: "model")))
                body = #"{"data":[{"results":[{"input_tokens":100,"input_cached_tokens":40,"output_tokens":25,"num_model_requests":2,"model":"example"}]}],"has_more":false,"next_page":null}"#
            } else {
                #expect(request.url!.path == "/v1/organization/costs")
                #expect(items.contains(URLQueryItem(name: "bucket_width", value: "1d")))
                body = #"{"data":[{"results":[{"amount":{"value":0.1,"currency":"usd"}},{"amount":{"value":0.2,"currency":"usd"}}]}],"has_more":false,"next_page":null}"#
            }
            return (Data(body.utf8), Self.response(request))
        }
        let report = try await client.report(key: "sk-test-fixture", now: Date(timeIntervalSince1970: 1_800_000_000))
        #expect(report.usage.inputTokens == 100)
        #expect(report.usage.cachedInputTokens == 40)
        #expect(report.usage.outputTokens == 25)
        #expect(report.usage.requests == 2)
        #expect(report.usage.byModel == ["example": 2])
        #expect(report.costsByCurrency == ["USD": Decimal(string: "0.3")!])
        #expect(report.costStart <= report.usageStart)
        #expect(report.end.timeIntervalSince(report.usageStart) == 86_400)
    }
    @Test func repeatedPaginationCursorFailsWithoutReturningPartialReport() async {
        let client = OpenAIAPIClient { request in
            (Data(#"{"data":[],"has_more":true,"next_page":"repeated"}"#.utf8), Self.response(request))
        }
        await #expect(throws: OpenAIAPIError.self) { try await client.report(key: "sk-test-fixture") }
    }
    @Test func integerOverflowIsRejected() async {
        let client = OpenAIAPIClient { request in
            let body = request.url!.path.contains("usage") ? #"{"data":[{"results":[{"input_tokens":9223372036854775807,"output_tokens":0,"num_model_requests":0},{"input_tokens":1,"output_tokens":0,"num_model_requests":0}]}],"has_more":false}"# : #"{"data":[],"has_more":false}"#
            return (Data(body.utf8), Self.response(request))
        }
        await #expect(throws: OpenAIAPIError.self) { try await client.report(key: "sk-test-fixture") }
    }
    @Test func sessionCannotBeSentToModelsOrAdminReporting() async {
        let client = OpenAIAPIClient { _ in
            Issue.record("Billing token reached a public API")
            throw OpenAIAPIError.unavailable
        }
        await #expect(throws: OpenAIAPIError.self) { try await client.validate(key: "sess-test-fixture") }
        await #expect(throws: OpenAIAPIError.self) { try await client.report(key: "sess-test-fixture") }
    }
    @Test func billingCredentialRequiresSessionSyntax() throws {
        try OpenAIAPIClient.validateCredential("sess-test-fixture", kind: .billingSession)
        #expect(throws: OpenAIAPIError.self) { try OpenAIAPIClient.validateCredential("sk-test-fixture", kind: .billingSession) }
    }
    @Test func existingCredentialWithoutOrganizationDecodesWithoutChangingScope() throws {
        let credential = try JSONDecoder().decode(OpenAIAPICredential.self, from: Data(#"{"key":"sk-test-fixture","kind":"regular"}"#.utf8))
        #expect(credential.organizationID == nil)
    }
    @Test func obsoleteStoredCredentialRemainsDecodableForRemoval() throws {
        let credential = try JSONDecoder().decode(OpenAIAPICredential.self, from: Data(#"{"key":"sess-test-fixture","kind":"billingSession","organizationID":"org-test"}"#.utf8))
        #expect(credential.kind == .billingSession)
        #expect(credential.organizationID == "org-test")
    }
    @Test func unofficialBalanceIsDeniedByDefaultBeforeTransport() async {
        let client = OpenAIAPIClient { _ in
            Issue.record("Unofficial balance reached transport without consent")
            throw OpenAIAPIError.unavailable
        }
        await #expect(throws: OpenAIAPIError.unofficialAccessDisabled) { try await client.balance(key: "sess-test-fixture") }
        await #expect(throws: OpenAIAPIError.unofficialAccessDisabled) { try await client.balance(key: "sk-test-fixture", allowUnofficial: false) }
    }
    @Test func enabledBalancePreservesDecimalAndSelectedOrganization() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let client = OpenAIAPIClient { request in
            #expect(request.url?.absoluteString == "https://api.openai.com/v1/dashboard/billing/credit_grants")
            #expect(request.httpMethod == "GET" && request.httpBody == nil)
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer sess-test-fixture")
            #expect(request.value(forHTTPHeaderField: "OpenAI-Organization") == "org-selected")
            return (Data(#"{"total_available":2.00017}"#.utf8), Self.response(request))
        }
        let balance = try await client.balance(key: "sess-test-fixture", organizationID: "org-selected", now: now, allowUnofficial: true)
        #expect(balance.remainingUSD == Decimal(string: "2.00017"))
        #expect(balance.fetchedAt == now)
    }
    @Test func unknownBalanceDoesNotBecomeZeroOrCostEstimate() async {
        let client = OpenAIAPIClient { request in
            (Data(#"{"total_granted":10,"total_used":8}"#.utf8), Self.response(request))
        }
        await #expect(throws: OpenAIAPIError.malformedResponse) { try await client.balance(key: "sk-test-fixture", allowUnofficial: true) }
    }
    @Test func zeroAndNegativeReportedBalancesArePreserved() async throws {
        for dollars in ["0", "-0.25"] {
            let client = OpenAIAPIClient { request in
                (Data("{\"total_available\":\(dollars)}".utf8), Self.response(request))
            }
            #expect(try await client.balance(key: "sk-test-fixture", allowUnofficial: true).remainingUSD == Decimal(string: dollars))
        }
    }
    @Test func invalidBillingScopeIsRejectedBeforeTransport() async {
        let client = OpenAIAPIClient { _ in
            Issue.record("Malformed organization reached transport")
            throw OpenAIAPIError.unavailable
        }
        await #expect(throws: OpenAIAPIError.invalidKey) { try await client.balance(key: "sess-test-fixture", organizationID: "org-test\r\nInjected: value", allowUnofficial: true) }
    }

    private static func response(_ request: URLRequest, status: Int = 200) -> HTTPURLResponse {
        HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
    }
}
