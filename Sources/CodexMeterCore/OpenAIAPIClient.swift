import Foundation

public enum OpenAIAPIKeyKind: String, Codable, CaseIterable, Sendable {
    case regular, admin, billingSession
}

public enum OpenAIAPIError: Error, LocalizedError, Sendable {
    case invalidKey, unauthorized, permissionDenied, rateLimited, unavailable, malformedResponse, paginationLimit, unofficialAccessDisabled
    public var errorDescription: String? {
        switch self {
        case .invalidKey: "Enter the selected OpenAI API key or billing session token without spaces or control characters."
        case .unauthorized: "OpenAI rejected this key. Check or replace it."
        case .permissionDenied: "This key does not have permission for the selected read-only API."
        case .rateLimited: "OpenAI limited requests. Try again later."
        case .unavailable: "OpenAI could not be reached. Try again later."
        case .malformedResponse: "OpenAI returned an unsupported report."
        case .paginationLimit: "The report is too large to load completely. Narrow the reporting period."
        case .unofficialAccessDisabled: "Unofficial balance access is disabled. Review and accept the account-risk warning before enabling it."
        }
    }
}

public struct OpenAIAPIUsage: Equatable, Sendable {
    public var requests: Int64 = 0
    public var inputTokens: Int64 = 0
    public var cachedInputTokens: Int64 = 0
    public var outputTokens: Int64 = 0
    public var byModel: [String: Int64] = [:]
}

public struct OpenAIAPIReport: Equatable, Sendable {
    public let fetchedAt: Date
    public let usageStart: Date
    public let costStart: Date
    public let end: Date
    public let usage: OpenAIAPIUsage
    public let costsByCurrency: [String: Decimal]
}

public struct OpenAICreditBalance: Equatable, Sendable {
    /// Provider-reported dollars available from the explicitly enabled private billing route.
    public let remainingUSD: Decimal
    public let fetchedAt: Date
    public init(remainingUSD: Decimal, fetchedAt: Date) { self.remainingUSD = remainingUSD; self.fetchedAt = fetchedAt }
}

/// Public read-only reporting, plus an explicitly gated unofficial billing reader.
public struct OpenAIAPIClient: Sendable {
    public typealias Transport = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)
    private let transport: Transport
    public init(transport: @escaping Transport = { try await OpenAIAPIClient.performRequest($0) }) { self.transport = transport }
    public static func validateKey(_ key: String) throws {
        guard key.hasPrefix("sk-"), !key.hasPrefix("sk-ant-"), key.utf8.count <= 4096,
              key.unicodeScalars.allSatisfy({ $0.value >= 33 && $0.value <= 126 }) else {
            throw OpenAIAPIError.invalidKey
        }
    }
    public static func validateCredential(_ key: String, kind: OpenAIAPIKeyKind) throws {
        if kind == .billingSession {
            guard key.hasPrefix("sess-"), key.utf8.count <= 4096,
                  key.unicodeScalars.allSatisfy({ $0.value >= 33 && $0.value <= 126 }) else { throw OpenAIAPIError.invalidKey }
        } else { try validateKey(key) }
    }
    public static func validateOrganizationID(_ identifier: String?) throws {
        guard let identifier else { return }
        guard identifier.hasPrefix("org-"), (5...128).contains(identifier.utf8.count),
              identifier.unicodeScalars.allSatisfy({ (65...90).contains($0.value) || (97...122).contains($0.value) || (48...57).contains($0.value) || $0 == "-" || $0 == "_" }) else { throw OpenAIAPIError.invalidKey }
    }
    /// Unsupported dashboard endpoint. Callers must explicitly authorize this route.
    /// The default denies access before validation or transport, including saved sessions.
    public func balance(key: String, organizationID: String? = nil, now: Date = Date(), allowUnofficial: Bool = false) async throws -> OpenAICreditBalance {
        guard allowUnofficial else { throw OpenAIAPIError.unofficialAccessDisabled }
        try Task.checkCancellation()
        let data = try await request(path: "/v1/dashboard/billing/credit_grants", key: key, query: [], billing: true, organizationID: organizationID)
        struct Credits: Decodable {
            let available: Decimal
            enum CodingKeys: String, CodingKey { case available = "total_available" }
        }
        guard let credits = try? JSONDecoder().decode(Credits.self, from: data), !credits.available.isNaN else { throw OpenAIAPIError.malformedResponse }
        return OpenAICreditBalance(remainingUSD: credits.available, fetchedAt: now)
    }
    public func validate(key: String) async throws {
        let data = try await request(path: "/v1/models", key: key, query: [])
        struct Models: Decodable { let data: [Model]; struct Model: Decodable { let id: String } }
        guard (try? JSONDecoder().decode(Models.self, from: data)) != nil else { throw OpenAIAPIError.malformedResponse }
    }
    public func report(key: String, now: Date = Date()) async throws -> OpenAIAPIReport {
        let usageStart = now.addingTimeInterval(-86_400)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let costStart = calendar.startOfDay(for: usageStart)
        let usagePages = try await pages(path: "/v1/organization/usage/completions", key: key, start: usageStart, end: now, width: "1h", groupBy: "model", limit: "24")
        let costPages = try await pages(path: "/v1/organization/costs", key: key, start: costStart, end: now, width: "1d", groupBy: nil, limit: "7")
        var usage = OpenAIAPIUsage()
        for result in usagePages.flatMap(\.data).flatMap(\.results) {
            guard let input = result.inputTokens, let output = result.outputTokens, let count = result.requests,
                  input >= 0, output >= 0, count >= 0, (result.cachedInputTokens ?? 0) >= 0 else { throw OpenAIAPIError.malformedResponse }
            try Self.add(input, to: &usage.inputTokens)
            try Self.add(output, to: &usage.outputTokens)
            try Self.add(count, to: &usage.requests)
            try Self.add(result.cachedInputTokens ?? 0, to: &usage.cachedInputTokens)
            let model = result.model ?? "Unspecified"
            var modelCount = usage.byModel[model, default: 0]
            try Self.add(count, to: &modelCount)
            usage.byModel[model] = modelCount
        }
        var costs: [String: Decimal] = [:]
        for result in costPages.flatMap(\.data).flatMap(\.results) {
            guard let amount = result.amount, amount.currency.utf8.count == 3,
                  amount.currency.unicodeScalars.allSatisfy({ (65...90).contains($0.value) || (97...122).contains($0.value) }),
                  !amount.value.isNaN else { throw OpenAIAPIError.malformedResponse }
            let currency = amount.currency.uppercased()
            let total = costs[currency, default: 0] + amount.value
            guard !total.isNaN else { throw OpenAIAPIError.malformedResponse }
            costs[currency] = total
        }
        return OpenAIAPIReport(fetchedAt: now, usageStart: usageStart, costStart: costStart, end: now, usage: usage, costsByCurrency: costs)
    }
    private static func add(_ value: Int64, to total: inout Int64) throws {
        let sum = total.addingReportingOverflow(value)
        guard !sum.overflow else { throw OpenAIAPIError.malformedResponse }
        total = sum.partialValue
    }
    private func pages(path: String, key: String, start: Date, end: Date, width: String, groupBy: String?, limit: String) async throws -> [Page] {
        var output: [Page] = []
        var cursor: String?
        var seen: Set<String> = []
        for _ in 0..<10 {
            var query = [URLQueryItem(name: "start_time", value: String(Int(start.timeIntervalSince1970))),
                         URLQueryItem(name: "end_time", value: String(Int(end.timeIntervalSince1970))),
                         URLQueryItem(name: "bucket_width", value: width), URLQueryItem(name: "limit", value: limit)]
            if let groupBy { query.append(URLQueryItem(name: "group_by", value: groupBy)) }
            if let cursor { query.append(URLQueryItem(name: "page", value: cursor)) }
            let data = try await request(path: path, key: key, query: query)
            guard let page = try? JSONDecoder().decode(Page.self, from: data) else { throw OpenAIAPIError.malformedResponse }
            output.append(page)
            if !page.hasMore { return output }
            guard let next = page.nextPage, !next.isEmpty, seen.insert(next).inserted else { throw OpenAIAPIError.malformedResponse }
            cursor = next
        }
        throw OpenAIAPIError.paginationLimit
    }
    private func request(path: String, key: String, query: [URLQueryItem], billing: Bool = false, organizationID: String? = nil) async throws -> Data {
        try Self.validateCredential(key, kind: billing && key.hasPrefix("sess-") ? .billingSession : .regular)
        try Self.validateOrganizationID(organizationID)
        var components = URLComponents(string: "https://api.openai.com")!
        components.path = path
        components.queryItems = query.isEmpty ? nil : query
        var request = URLRequest(url: components.url!, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        request.httpMethod = "GET"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        if let organizationID { request.setValue(organizationID, forHTTPHeaderField: "OpenAI-Organization") }
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let data: Data
        let response: HTTPURLResponse
        try Task.checkCancellation()
        do { (data, response) = try await transport(request) }
        catch is CancellationError { throw CancellationError() }
        catch { throw OpenAIAPIError.unavailable }
        guard response.url?.scheme == "https", response.url?.host == "api.openai.com", response.url?.port == nil else { throw OpenAIAPIError.unavailable }
        switch response.statusCode {
        case 200: guard data.count <= 8_388_608 else { throw OpenAIAPIError.malformedResponse }; return data
        case 401: throw OpenAIAPIError.unauthorized
        case 403: throw OpenAIAPIError.permissionDenied
        case 429: throw OpenAIAPIError.rateLimited
        default: throw OpenAIAPIError.unavailable
        }
    }
    public static func performRequest(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.urlCache = nil
        config.urlCredentialStorage = nil
        let session = URLSession(configuration: config, delegate: RejectRedirects(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw OpenAIAPIError.unavailable }
        return (data, response)
    }
    private struct Page: Decodable {
        let data: [Bucket]; let hasMore: Bool; let nextPage: String?
        enum CodingKeys: String, CodingKey { case data; case hasMore = "has_more"; case nextPage = "next_page" }
    }
    private struct Bucket: Decodable { let results: [Result] }
    private struct Result: Decodable {
        let inputTokens: Int64?; let cachedInputTokens: Int64?; let outputTokens: Int64?; let requests: Int64?; let model: String?; let amount: Amount?
        enum CodingKeys: String, CodingKey {
            case inputTokens = "input_tokens", cachedInputTokens = "input_cached_tokens", outputTokens = "output_tokens", requests = "num_model_requests", model, amount
        }
    }
    private struct Amount: Decodable { let currency: String; let value: Decimal }
}
private final class RejectRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}
