import Foundation

public enum CodexRateLimitPayloadMapper {
    public static func snapshot(
        from data: Data,
        capturedAt: Date = Date(),
        executablePath: String = "iOS",
        account: CodexAccount
    ) throws -> CodexSnapshot {
        let payload = try JSONDecoder().decode(WhamUsagePayload.self, from: data)
        return snapshot(
            from: payload,
            capturedAt: capturedAt,
            executablePath: executablePath,
            account: account
        )
    }

    private static func snapshot(
        from payload: WhamUsagePayload,
        capturedAt: Date,
        executablePath: String,
        account: CodexAccount
    ) -> CodexSnapshot {
        var limits: [CodexLimit] = [
            makeLimit(
                id: "codex",
                name: nil,
                details: payload.rateLimit,
                credits: payload.credits,
                planType: payload.planType,
                capturedAt: capturedAt
            )
        ]

        limits.append(contentsOf: payload.additionalRateLimits.map { additional in
            makeLimit(
                id: additional.meteredFeature ?? additional.limitName ?? UUID().uuidString,
                name: additional.limitName,
                details: additional.rateLimit,
                credits: nil,
                planType: payload.planType,
                capturedAt: capturedAt
            )
        })

        return CodexSnapshot(
            capturedAt: capturedAt,
            executablePath: executablePath,
            account: CodexAccount(
                authType: account.authType,
                email: account.email,
                planType: account.planType ?? payload.planType?.uppercased()
            ),
            limits: limits.filter { limit in
                limit.primary != nil || limit.secondary != nil || limit.credits != nil
            }
        )
    }

    private static func makeLimit(
        id: String,
        name: String?,
        details: RateLimitDetails?,
        credits: CreditsPayload?,
        planType: String?,
        capturedAt: Date
    ) -> CodexLimit {
        CodexLimit(
            id: id,
            rawLimitName: name,
            bucket: CodexLimitBucket.infer(limitId: id, limitName: name),
            primary: window(from: details?.primaryWindow, capturedAt: capturedAt),
            secondary: window(from: details?.secondaryWindow, capturedAt: capturedAt),
            credits: credits.map {
                CodexCredits(
                    hasCredits: $0.hasCredits,
                    unlimited: $0.unlimited,
                    balance: $0.balance
                )
            }
        )
    }

    private static func window(
        from payload: WindowPayload?,
        capturedAt: Date
    ) -> CodexQuotaWindow? {
        guard let payload else { return nil }
        let resetAt = payload.resetAt.map(Date.init(timeIntervalSince1970:))
            ?? payload.resetAfterSeconds.map { capturedAt.addingTimeInterval(TimeInterval($0)) }
        let durationMinutes = payload.limitWindowSeconds.flatMap { seconds -> Int? in
            guard seconds > 0 else { return nil }
            return Int(ceil(Double(seconds) / 60.0))
        }

        return CodexQuotaWindow(
            usedPercent: payload.usedPercent,
            windowDurationMinutes: durationMinutes,
            resetsAt: resetAt
        )
    }
}

private struct WhamUsagePayload: Decodable {
    let planType: String?
    let rateLimit: RateLimitDetails?
    let additionalRateLimits: [AdditionalRateLimitPayload]
    let credits: CreditsPayload?

    enum CodingKeys: String, CodingKey {
        case planType = "plan_type"
        case rateLimit = "rate_limit"
        case additionalRateLimits = "additional_rate_limits"
        case credits
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        planType = try container.decodeIfPresent(String.self, forKey: .planType)
        rateLimit = try container.decodeFlexibleOptional(RateLimitDetails.self, forKey: .rateLimit)
        additionalRateLimits = try container.decodeFlexibleArray(AdditionalRateLimitPayload.self, forKey: .additionalRateLimits)
        credits = try container.decodeFlexibleOptional(CreditsPayload.self, forKey: .credits)
    }
}

private struct AdditionalRateLimitPayload: Decodable {
    let limitName: String?
    let meteredFeature: String?
    let rateLimit: RateLimitDetails?

    enum CodingKeys: String, CodingKey {
        case limitName = "limit_name"
        case meteredFeature = "metered_feature"
        case rateLimit = "rate_limit"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        limitName = try container.decodeIfPresent(String.self, forKey: .limitName)
        meteredFeature = try container.decodeIfPresent(String.self, forKey: .meteredFeature)
        rateLimit = try container.decodeFlexibleOptional(RateLimitDetails.self, forKey: .rateLimit)
    }
}

private struct RateLimitDetails: Decodable {
    let primaryWindow: WindowPayload?
    let secondaryWindow: WindowPayload?

    enum CodingKeys: String, CodingKey {
        case primaryWindow = "primary_window"
        case secondaryWindow = "secondary_window"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        primaryWindow = try container.decodeFlexibleOptional(WindowPayload.self, forKey: .primaryWindow)
        secondaryWindow = try container.decodeFlexibleOptional(WindowPayload.self, forKey: .secondaryWindow)
    }
}

private struct WindowPayload: Decodable {
    let usedPercent: Double
    let limitWindowSeconds: Int?
    let resetAfterSeconds: Int?
    let resetAt: TimeInterval?

    enum CodingKeys: String, CodingKey {
        case usedPercent = "used_percent"
        case limitWindowSeconds = "limit_window_seconds"
        case resetAfterSeconds = "reset_after_seconds"
        case resetAt = "reset_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        usedPercent = try container.decodeLossyDouble(forKey: .usedPercent) ?? 0
        limitWindowSeconds = try container.decodeLossyInt(forKey: .limitWindowSeconds)
        resetAfterSeconds = try container.decodeLossyInt(forKey: .resetAfterSeconds)
        resetAt = try container.decodeLossyDouble(forKey: .resetAt)
    }
}

private struct CreditsPayload: Decodable {
    let hasCredits: Bool
    let unlimited: Bool
    let balance: String?

    enum CodingKeys: String, CodingKey {
        case hasCredits = "has_credits"
        case unlimited
        case balance
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hasCredits = (try? container.decode(Bool.self, forKey: .hasCredits)) ?? false
        unlimited = (try? container.decode(Bool.self, forKey: .unlimited)) ?? false
        balance = try container.decodeLossyString(forKey: .balance)
    }
}

private extension KeyedDecodingContainer {
    func decodeFlexibleOptional<T: Decodable>(_ type: T.Type, forKey key: Key) throws -> T? {
        guard contains(key) else { return nil }
        if try decodeNil(forKey: key) {
            return nil
        }
        return try decodeIfPresent(T.self, forKey: key)
    }

    func decodeFlexibleArray<T: Decodable>(_ type: T.Type, forKey key: Key) throws -> [T] {
        guard contains(key) else { return [] }
        if try decodeNil(forKey: key) {
            return []
        }
        return (try? decode([T].self, forKey: key)) ?? []
    }

    func decodeLossyDouble(forKey key: Key) throws -> Double? {
        if let value = try? decode(Double.self, forKey: key) {
            return value
        }
        if let value = try? decode(Int.self, forKey: key) {
            return Double(value)
        }
        if let value = try? decode(String.self, forKey: key) {
            return Double(value)
        }
        return nil
    }

    func decodeLossyInt(forKey key: Key) throws -> Int? {
        if let value = try? decode(Int.self, forKey: key) {
            return value
        }
        if let value = try? decode(Double.self, forKey: key) {
            return Int(value)
        }
        if let value = try? decode(String.self, forKey: key) {
            return Int(value)
        }
        return nil
    }

    func decodeLossyString(forKey key: Key) throws -> String? {
        if let value = try? decode(String.self, forKey: key) {
            return value
        }
        if let value = try? decode(Double.self, forKey: key) {
            return "\(value)"
        }
        if let value = try? decode(Int.self, forKey: key) {
            return "\(value)"
        }
        return nil
    }
}
