#if os(macOS)
import Foundation
import CodexMeterCore

enum CodexXPCRequestGuards {
    private static let flowIDRegex = try! NSRegularExpression(pattern: #"^[A-Za-z0-9_-]{16,96}$"#)

    static func validatedFlowID(_ flowID: String) throws -> String {
        let trimmed = flowID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed == flowID, trimmed.isEmpty == false else {
            throw error("Sign-in code expired. Start again.")
        }
        let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
        guard flowIDRegex.firstMatch(in: trimmed, range: range) != nil else {
            throw error("Sign-in code expired. Start again.")
        }
        return trimmed
    }

    static func redactedError(_ error: Error) -> String {
        CodexSensitiveRedactor.safeErrorDescription(error)
    }

    private static func error(_ message: String) -> NSError {
        NSError(domain: "CodexXPCRequestGuards", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}

final class CodexXPCResetThrottle {
    private let minimumInterval: TimeInterval
    private var lastResetAt: Date?

    init(minimumInterval: TimeInterval = 0.75) {
        self.minimumInterval = minimumInterval
    }

    func shouldReset(now: Date = Date()) -> Bool {
        guard let lastResetAt else {
            self.lastResetAt = now
            return true
        }
        guard now.timeIntervalSince(lastResetAt) >= minimumInterval else {
            return false
        }
        self.lastResetAt = now
        return true
    }
}
#endif
