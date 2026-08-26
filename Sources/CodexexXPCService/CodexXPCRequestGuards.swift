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

#endif
