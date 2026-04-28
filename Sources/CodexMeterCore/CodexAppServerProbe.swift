import Foundation

// Direct codex app-server capture is compiled only with CODEXEX_ENABLE_LEGACY_PROBE; reducers remain available for tests.

public enum CodexProbeError: Error, LocalizedError, Sendable, Equatable {
    case binaryNotFound(candidates: [String])
    case launchFailed(message: String)
    case rpcError(method: String, code: Int?, message: String)
    case unauthenticated
    case missingRateLimits
    case timeout(seconds: Double, stderr: String?)
    case malformedResponse(message: String)

    public var errorDescription: String? {
        switch self {
        case .binaryNotFound(let candidates):
            let joined = candidates.prefix(6).joined(separator: ", ")
            return "Codex binary not found. Checked: \(joined)"
        case .launchFailed(let message):
            return "Failed to launch codex app-server: \(message)"
        case .rpcError(let method, _, let message):
            return "\(method) failed: \(message)"
        case .unauthenticated:
            return "Codex is not signed in with a ChatGPT account."
        case .missingRateLimits:
            return "Codex returned no rate-limit buckets for this account."
        case .timeout(let seconds, let stderr):
            if let stderr, stderr.isEmpty == false {
                return "Timed out after \(Int(seconds.rounded()))s. \(stderr)"
            }
            return "Timed out after \(Int(seconds.rounded()))s waiting for codex app-server."
        case .malformedResponse(let message):
            return "Malformed codex response: \(message)"
        }
    }
}

#if CODEXEX_ENABLE_LEGACY_PROBE
/// Legacy probe for direct `codex app-server` access.
/// Internal parity only. App Store builds must use the bundled helper/XPC path.
@available(*, deprecated, message: "Legacy/internal parity probe only. Not for the App Store helper path.")
struct CodexAppServerProbe: Sendable {
    init() {}

    /// Captures a snapshot from the legacy external `codex app-server` process.
    /// App Store builds must not depend on this path.
    func capture(
        executablePath: String? = nil,
        timeout: Duration = .seconds(8),
        refreshToken: Bool = false
    ) async throws -> CodexSnapshot {
        try await Task.detached(priority: .utility) {
            try captureSync(
                executablePath: executablePath,
                timeout: timeout,
                refreshToken: refreshToken
            )
        }.value
    }

    private func captureSync(
        executablePath: String?,
        timeout: Duration,
        refreshToken: Bool
    ) throws -> CodexSnapshot {
        let resolvedExecutable = executablePath ?? CodexBinaryLocator.locate()
        guard let resolvedExecutable else {
            throw CodexProbeError.binaryNotFound(candidates: CodexBinaryLocator.candidatePaths())
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: resolvedExecutable)
        process.arguments = ["app-server"]

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            throw CodexProbeError.launchFailed(message: error.localizedDescription)
        }

        let timeoutSeconds = timeout.timeInterval
        let watchdog = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        watchdog.schedule(deadline: .now() + timeoutSeconds)
        watchdog.setEventHandler {
            if process.isRunning {
                process.terminate()
            }
        }
        watchdog.resume()

        defer {
            watchdog.cancel()
        }

        let stdinHandle = stdinPipe.fileHandleForWriting
        try writeAllRequests(to: stdinHandle, refreshToken: refreshToken)
        defer {
            stdinHandle.closeFile()
        }

        var accountResult: _AccountReadResult?
        var rateLimitsResult: _RateLimitsReadResult?
        var capturedError: CodexProbeError?
        var buffer = Data()

        let stdoutHandle = stdoutPipe.fileHandleForReading

        while true {
            let chunk = stdoutHandle.availableData
            if chunk.isEmpty {
                break
            }

            buffer.append(chunk)

            while let newlineIndex = buffer.firstIndex(of: 0x0A) {
                let line = Data(buffer.prefix(upTo: newlineIndex))
                buffer.removeSubrange(...newlineIndex)

                let trimmed = line.trimmedJSONLine()
                if trimmed.isEmpty {
                    continue
                }

                do {
                    let message = try _RPCMessage(jsonData: trimmed)
                    switch message.id {
                    case 1:
                        if let error = message.error {
                            capturedError = .rpcError(
                                method: "account/read",
                                code: error.code,
                                message: error.message
                            )
                        } else if let result = message.result {
                            accountResult = _AccountReadResult(dictionary: result)
                        }
                    case 2:
                        if let error = message.error {
                            capturedError = .rpcError(
                                method: "account/rateLimits/read",
                                code: error.code,
                                message: error.message
                            )
                        } else if let result = message.result {
                            rateLimitsResult = _RateLimitsReadResult(dictionary: result)
                        }
                    default:
                        break
                    }
                } catch {
                    capturedError = .malformedResponse(message: error.localizedDescription)
                }

                if capturedError != nil || (accountResult != nil && rateLimitsResult != nil) {
                    if process.isRunning {
                        process.terminate()
                    }
                    break
                }
            }

            if capturedError != nil || (accountResult != nil && rateLimitsResult != nil) {
                break
            }
        }

        if !buffer.isEmpty, capturedError == nil {
            let trimmed = buffer.trimmedJSONLine()
            if trimmed.isEmpty == false {
                do {
                    let message = try _RPCMessage(jsonData: trimmed)
                    switch message.id {
                    case 1:
                        if let result = message.result {
                            accountResult = _AccountReadResult(dictionary: result)
                        }
                    case 2:
                        if let result = message.result {
                            rateLimitsResult = _RateLimitsReadResult(dictionary: result)
                        }
                    default:
                        break
                    }
                } catch {
                    capturedError = .malformedResponse(message: error.localizedDescription)
                }
            }
        }

        process.waitUntilExit()

        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        let stderr = String(data: stderrData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let capturedError {
            throw capturedError
        }

        if process.terminationReason == .uncaughtSignal,
           accountResult == nil || rateLimitsResult == nil {
            throw CodexProbeError.timeout(seconds: timeoutSeconds, stderr: stderr)
        }

        guard let accountResult else {
            throw CodexProbeError.malformedResponse(message: "Missing account/read response.")
        }

        guard let rateLimitsResult else {
            throw CodexProbeError.malformedResponse(message: "Missing account/rateLimits/read response.")
        }

        return try _SnapshotReducer.makeSnapshot(
            executablePath: resolvedExecutable,
            account: accountResult,
            rateLimits: rateLimitsResult
        )
    }

    private func writeAllRequests(
        to handle: FileHandle,
        refreshToken: Bool
    ) throws {
        let requests: [[String: Any]] = [
            [
                "method": "initialize",
                "id": 0,
                "params": [
                    "clientInfo": [
                        "name": "codex_meter",
                        "title": "Codex Meter",
                        "version": "0.1.0"
                    ]
                ]
            ],
            [
                "method": "initialized",
                "params": [:]
            ],
            [
                "method": "account/read",
                "id": 1,
                "params": [
                    "refreshToken": refreshToken
                ]
            ],
            [
                "method": "account/rateLimits/read",
                "id": 2,
                "params": [:]
            ]
        ]

        for request in requests {
            let data = try JSONSerialization.data(withJSONObject: request, options: [])
            try handle.write(contentsOf: data)
            try handle.write(contentsOf: Data([0x0A]))
        }
    }
}
#endif

enum _SnapshotReducer {
    static func makeSnapshot(
        executablePath: String,
        account: _AccountReadResult,
        rateLimits: _RateLimitsReadResult,
        now: Date = Date()
    ) throws -> CodexSnapshot {
        guard let accountPayload = account.account else {
            throw CodexProbeError.unauthenticated
        }
        guard accountPayload.type.caseInsensitiveCompare("chatgpt") == .orderedSame else {
            throw CodexProbeError.unauthenticated
        }

        let buckets: [_RateLimitPayload]
        if let byId = rateLimits.rateLimitsByLimitId, byId.isEmpty == false {
            buckets = byId
                .sorted(by: { $0.key < $1.key })
                .map(\.value)
        } else if let single = rateLimits.rateLimits {
            buckets = [single]
        } else {
            buckets = []
        }

        let rawLimits = buckets.map { payload -> CodexRawQuotaLimit in
            let limitId = payload.limitId ?? payload.limitName ?? "unknown"

            let primary = payload.primary.map {
                CodexRawQuotaWindow(
                    usedPercent: $0.usedPercent ?? 0,
                    windowDurationMinutes: $0.windowDurationMins,
                    resetsAt: $0.resetsAt.map(Date.init(timeIntervalSince1970:))
                )
            }

            let secondary = payload.secondary.map {
                CodexRawQuotaWindow(
                    usedPercent: $0.usedPercent ?? 0,
                    windowDurationMinutes: $0.windowDurationMins,
                    resetsAt: $0.resetsAt.map(Date.init(timeIntervalSince1970:))
                )
            }

            let credits = payload.credits.map {
                CodexCredits(
                    hasCredits: $0.hasCredits,
                    unlimited: $0.unlimited,
                    balance: $0.balance
                )
            }

            return CodexRawQuotaLimit(
                id: limitId,
                rawLimitName: payload.limitName,
                primary: primary,
                secondary: secondary,
                credits: credits
            )
        }
        let snapshot = CodexQuotaSnapshotBuilder.snapshot(
            capturedAt: now,
            executablePath: executablePath,
            account: CodexAccount(
                authType: accountPayload.type,
                email: accountPayload.email,
                planType: accountPayload.planType
            ),
            rawLimits: rawLimits
        )

        guard snapshot.limits.isEmpty == false else {
            throw CodexProbeError.missingRateLimits
        }

        return snapshot
    }
}

struct _RPCMessage {
    let id: Int?
    let result: [String: Any]?
    let error: _RPCError?

    init(jsonData: Data) throws {
        let object = try JSONSerialization.jsonObject(with: jsonData, options: [])
        guard let dictionary = object as? [String: Any] else {
            throw CodexProbeError.malformedResponse(message: "Top-level JSON is not an object.")
        }

        self.id = dictionary.intValue(forKey: "id")
        self.result = dictionary.dictionaryValue(forKey: "result")
        self.error = dictionary.dictionaryValue(forKey: "error").map(_RPCError.init(dictionary:))
    }
}

struct _RPCError {
    let code: Int?
    let message: String

    init(dictionary: [String: Any]) {
        self.code = dictionary.intValue(forKey: "code")
        self.message = dictionary.stringValue(forKey: "message") ?? "Unknown error"
    }
}

struct _AccountReadResult {
    let account: _AccountPayload?
    let requiresOpenaiAuth: Bool?

    init(dictionary: [String: Any]) {
        self.account = dictionary.dictionaryValue(forKey: "account").map(_AccountPayload.init(dictionary:))
        self.requiresOpenaiAuth = dictionary.boolValue(forKey: "requiresOpenaiAuth")
    }
}

struct _AccountPayload {
    let type: String
    let email: String?
    let planType: String?

    init(dictionary: [String: Any]) {
        self.type = dictionary.stringValue(forKey: "type") ?? "unknown"
        self.email = dictionary.stringValue(forKey: "email")
        self.planType = dictionary.stringValue(forKey: "planType")
    }
}

struct _RateLimitsReadResult {
    let rateLimits: _RateLimitPayload?
    let rateLimitsByLimitId: [String: _RateLimitPayload]?

    init(dictionary: [String: Any]) {
        self.rateLimits = dictionary.dictionaryValue(forKey: "rateLimits").map(_RateLimitPayload.init(dictionary:))

        if let rawBuckets = dictionary.dictionaryValue(forKey: "rateLimitsByLimitId") {
            var parsed: [String: _RateLimitPayload] = [:]
            for (key, value) in rawBuckets {
                if let bucket = value as? [String: Any] {
                    parsed[key] = _RateLimitPayload(dictionary: bucket)
                }
            }
            self.rateLimitsByLimitId = parsed.isEmpty ? nil : parsed
        } else {
            self.rateLimitsByLimitId = nil
        }
    }
}

struct _RateLimitPayload {
    let limitId: String?
    let limitName: String?
    let primary: _QuotaWindowPayload?
    let secondary: _QuotaWindowPayload?
    let credits: _CreditsPayload?

    init(dictionary: [String: Any]) {
        self.limitId = dictionary.stringValue(forKey: "limitId")
        self.limitName = dictionary.stringValue(forKey: "limitName")
        self.primary = dictionary.dictionaryValue(forKey: "primary").map(_QuotaWindowPayload.init(dictionary:))
        self.secondary = dictionary.dictionaryValue(forKey: "secondary").map(_QuotaWindowPayload.init(dictionary:))
        self.credits = dictionary.dictionaryValue(forKey: "credits").map(_CreditsPayload.init(dictionary:))
    }
}

struct _CreditsPayload {
    let hasCredits: Bool
    let unlimited: Bool
    let balance: String?

    init(dictionary: [String: Any]) {
        self.hasCredits = dictionary.boolValue(forKey: "hasCredits") ?? false
        self.unlimited = dictionary.boolValue(forKey: "unlimited") ?? false
        self.balance = dictionary.stringValue(forKey: "balance")
    }
}

struct _QuotaWindowPayload {
    let usedPercent: Double?
    let windowDurationMins: Int?
    let resetsAt: Double?

    init(dictionary: [String: Any]) {
        self.usedPercent = dictionary.doubleValue(forKey: "usedPercent")
        self.windowDurationMins = dictionary.intValue(forKey: "windowDurationMins")
        self.resetsAt = dictionary.doubleValue(forKey: "resetsAt")
    }
}

private extension Data {
    func trimmedJSONLine() -> Data {
        var start = startIndex
        var end = endIndex

        while start < end, Self.isTrimByte(self[start]) {
            start = index(after: start)
        }

        while start < end {
            let previous = index(before: end)
            if Self.isTrimByte(self[previous]) {
                end = previous
            } else {
                break
            }
        }

        return Data(self[start..<end])
    }

    static func isTrimByte(_ byte: UInt8) -> Bool {
        byte == 0x0A || byte == 0x0D || byte == 0x20 || byte == 0x09
    }
}

private extension Dictionary where Key == String, Value == Any {
    func stringValue(forKey key: String) -> String? {
        self[key] as? String
    }

    func boolValue(forKey key: String) -> Bool? {
        if let bool = self[key] as? Bool {
            return bool
        }
        if let number = self[key] as? NSNumber {
            return number.boolValue
        }
        return nil
    }

    func intValue(forKey key: String) -> Int? {
        if let int = self[key] as? Int {
            return int
        }
        if let number = self[key] as? NSNumber {
            return number.intValue
        }
        if let string = self[key] as? String, let int = Int(string) {
            return int
        }
        return nil
    }

    func doubleValue(forKey key: String) -> Double? {
        if let double = self[key] as? Double {
            return double
        }
        if let number = self[key] as? NSNumber {
            return number.doubleValue
        }
        if let string = self[key] as? String, let double = Double(string) {
            return double
        }
        return nil
    }

    func dictionaryValue(forKey key: String) -> [String: Any]? {
        self[key] as? [String: Any]
    }
}

private extension Duration {
    var timeInterval: TimeInterval {
        let components = self.components
        return Double(components.seconds) + Double(components.attoseconds) / 1_000_000_000_000_000_000
    }
}
