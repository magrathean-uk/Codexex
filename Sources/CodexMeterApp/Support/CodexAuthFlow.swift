#if os(macOS)
import Foundation
import CodexMeterCore

struct CodexAuthBeginFailure: Equatable {
    let message: String
    let retryNotBefore: Date?
}

enum CodexAuthFlow {
    static func beginFailure(_ error: Error, now: Date = Date()) -> CodexAuthBeginFailure {
        if error.localizedDescription.contains("429") {
            return CodexAuthBeginFailure(
                message: "OpenAI is rate-limiting sign-in right now. Wait 10 seconds and try again.",
                retryNotBefore: now.addingTimeInterval(10)
            )
        }
        return CodexAuthBeginFailure(
            message: error.localizedDescription,
            retryNotBefore: nil
        )
    }

    static func shouldPreservePendingDeviceCode(
        response: CodexServiceSnapshotResponse,
        hasPendingDeviceCode: Bool
    ) -> Bool {
        hasPendingDeviceCode && response.authMode == nil
    }

    static func signedOutMessage(for response: CodexServiceSnapshotResponse) -> String {
        response.errorMessage ?? "Not signed in. Use the button below."
    }
}
#endif
