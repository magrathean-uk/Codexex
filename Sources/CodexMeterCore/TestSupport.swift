import Foundation

#if DEBUG
enum CodexTestSupport {
    static func snapshotFromJSON(
        executablePath: String,
        accountJSON: String,
        rateLimitsJSON: String,
        now: Date = Date(timeIntervalSince1970: 1_730_947_000)
    ) throws -> CodexSnapshot {
        let accountObject = try JSONSerialization.jsonObject(with: Data(accountJSON.utf8), options: [])
        let rateLimitsObject = try JSONSerialization.jsonObject(with: Data(rateLimitsJSON.utf8), options: [])

        guard let accountDictionary = accountObject as? [String: Any] else {
            throw CodexProbeError.malformedResponse(message: "Bad account JSON")
        }

        guard let rateLimitsDictionary = rateLimitsObject as? [String: Any] else {
            throw CodexProbeError.malformedResponse(message: "Bad rateLimits JSON")
        }

        return try _SnapshotReducer.makeSnapshot(
            executablePath: executablePath,
            account: _AccountReadResult(dictionary: accountDictionary),
            rateLimits: _RateLimitsReadResult(dictionary: rateLimitsDictionary),
            now: now
        )
    }
}
#endif
