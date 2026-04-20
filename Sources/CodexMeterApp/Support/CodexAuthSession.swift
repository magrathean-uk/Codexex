import Foundation

struct CodexDeviceCodeContext: Equatable, Sendable {
    let flowID: String
    let verificationURL: URL
    let userCode: String
    let createdAt: Date
}

enum CodexAuthSessionPhase: Equatable, Sendable {
    case unresolved
    case starting(message: String)
    case codeReady(CodexDeviceCodeContext, message: String)
    case polling(CodexDeviceCodeContext, message: String)
    case signedIn(message: String)
    case signedOut(message: String)
    case signingOut(message: String)
    case failed(message: String, deviceCode: CodexDeviceCodeContext?)
    case preview(message: String)
}

enum CodexAuthSessionEvent: Equatable, Sendable {
    case beginRequested
    case beginBlocked(message: String)
    case beginSucceeded(CodexDeviceCodeContext)
    case beginFailed(message: String, retryNotBefore: Date?)
    case pollingRequested
    case pollingPending(String)
    case pollingFailed(String)
    case clearDeviceCode
    case signOutRequested
    case signedIn
    case signedOut(String)
    case previewEnabled
    case previewDisabled
}

struct CodexAuthSession: Equatable, Sendable {
    private(set) var phase: CodexAuthSessionPhase = .unresolved
    private(set) var retryNotBefore: Date?

    mutating func apply(_ event: CodexAuthSessionEvent, now: Date = Date()) {
        switch event {
        case .beginRequested:
            phase = .starting(message: "Starting ChatGPT sign-in.")

        case .beginBlocked(let message):
            phase = .failed(message: message, deviceCode: currentDeviceCode)

        case .beginSucceeded(let context):
            retryNotBefore = nil
            phase = .codeReady(context, message: "Open Safari and approve sign-in.")

        case .beginFailed(let message, let retryNotBefore):
            self.retryNotBefore = retryNotBefore
            phase = .failed(message: message, deviceCode: nil)

        case .pollingRequested:
            guard let context = currentDeviceCode else {
                phase = .failed(message: "Start sign-in again to get a new code.", deviceCode: nil)
                return
            }
            phase = .polling(context, message: "Checking sign-in status.")

        case .pollingPending(let message):
            guard let context = currentDeviceCode else {
                phase = .signedOut(message: "Sign in to load quota.")
                return
            }
            phase = .codeReady(context, message: message)

        case .pollingFailed(let message):
            phase = .failed(message: message, deviceCode: currentDeviceCode)

        case .clearDeviceCode:
            phase = .signedOut(message: "Sign in to load quota.")

        case .signOutRequested:
            retryNotBefore = nil
            phase = .signingOut(message: "Signing out…")

        case .signedIn:
            retryNotBefore = nil
            phase = .signedIn(message: "Signed in with ChatGPT.")

        case .signedOut(let message):
            retryNotBefore = nil
            phase = .signedOut(message: message)

        case .previewEnabled:
            retryNotBefore = nil
            phase = .preview(message: "Preview mode.")

        case .previewDisabled:
            phase = .unresolved
        }
    }

    var currentDeviceCode: CodexDeviceCodeContext? {
        switch phase {
        case .codeReady(let context, _),
             .polling(let context, _),
             .failed(_, let context?):
            return context
        case .unresolved,
             .starting,
             .signedIn,
             .signedOut,
             .signingOut,
             .preview,
             .failed(_, nil):
            return nil
        }
    }

    var statusMessage: String {
        switch phase {
        case .unresolved:
            return "Ready."
        case .starting(let message),
             .codeReady(_, let message),
             .polling(_, let message),
             .signedIn(let message),
             .signedOut(let message),
             .signingOut(let message),
             .failed(let message, _),
             .preview(let message):
            return message
        }
    }

    var lastError: String? {
        if case .failed(let message, _) = phase {
            return message
        }
        return nil
    }

    var isSigningIn: Bool {
        switch phase {
        case .starting, .polling:
            return true
        case .unresolved,
             .codeReady,
             .signedIn,
             .signedOut,
             .signingOut,
             .failed,
             .preview:
            return false
        }
    }

    var isSignedIn: Bool {
        switch phase {
        case .signedIn, .preview:
            return true
        case .unresolved,
             .starting,
             .codeReady,
             .polling,
             .signedOut,
             .signingOut,
             .failed:
            return false
        }
    }

    var hasResolvedState: Bool {
        phase != .unresolved
    }

    var cooldownMessage: String? {
        guard let retryNotBefore, retryNotBefore > Date() else {
            return nil
        }
        let seconds = max(Int(retryNotBefore.timeIntervalSinceNow.rounded(.up)), 1)
        return "Please wait \(seconds)s before trying sign-in again."
    }

    var userCode: String? {
        currentDeviceCode?.userCode
    }

    var verificationURL: URL? {
        currentDeviceCode?.verificationURL
    }

    var flowID: String? {
        currentDeviceCode?.flowID
    }
}
