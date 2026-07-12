#if os(macOS)
import Foundation

extension CodexMenuBarModel {
    var canStartChatGPTSignIn: Bool {
        isSigningIn == false && !(hasResolvedAuthState == false && isRefreshing)
    }

    var canCheckPendingChatGPTSignIn: Bool {
        authFlowID != nil && previewModeEnabled == false && isSigningIn == false
    }

    var shouldShowStatusCard: Bool {
        if previewModeEnabled,
           snapshot != nil,
           authDeviceCode == nil,
           isSigningIn == false,
           lastError == nil {
            return false
        }
        return snapshot == nil || authDeviceCode != nil || isSigningIn || lastError != nil
    }

    var statusCardTitle: String {
        if previewModeEnabled {
            return "Preview Mode"
        }
        if authDeviceCode != nil {
            return isSigningIn ? "Waiting for approval" : "Finish sign-in"
        }
        if isSigningIn {
            return "Signing in"
        }
        if lastError != nil, snapshot == nil {
            return "Couldn’t load quota"
        }
        if isSignedIn == false, hasResolvedAuthState {
            return "Sign in required"
        }
        if isRefreshing {
            return "Checking quota"
        }
        if snapshot == nil {
            return "Waiting for quota data"
        }
        return "Account"
    }

    var statusCardMessage: String {
        if let code = authDeviceCode {
            if isSigningIn {
                return "Use code \(code) in Safari. This check will stop on its own so you can try again here."
            }
            return "Use code \(code) in Safari, then check status here."
        }
        if let lastError {
            return userFacingStatusMessage(for: lastError)
        }
        if isRefreshing, snapshot == nil, isSignedIn {
            return "Reading current limits."
        }
        return authStatusMessage
    }

    var accountHeadline: String {
        if previewModeEnabled {
            return "Preview Mode"
        }
        if authDeviceCode != nil {
            return isSigningIn ? "Waiting for approval" : "Open Safari"
        }
        if isSigningIn {
            return "Signing in"
        }
        if let snapshot,
           let email = snapshot.account.email,
           email.isEmpty == false {
            return email
        }
        if isSignedIn {
            return "Signed in"
        }
        if hasResolvedAuthState {
            return "Not signed in"
        }
        return "Checking"
    }

    var accountDetail: String? {
        if previewModeEnabled {
            return "Sample data is active. Leave Preview Mode to read your live quota."
        }
        if let deviceCode = authDeviceCode {
            if isSigningIn {
                return "Code \(deviceCode) · Waiting for approval from Safari."
            }
            return "Code \(deviceCode) · Open Safari, approve sign-in, then check status here."
        }
        if isSigningIn {
            return "Requesting a device code from ChatGPT."
        }
        if let snapshot {
            return snapshot.account.displaySubtitle
        }
        if let lastError {
            return lastError
        }
        if hasResolvedAuthState {
            return "Sign in to load quota."
        }
        return nil
    }

    func cancelPendingChatGPTSignIn() {
        clearAuthCode()
    }

    private func userFacingStatusMessage(for error: String) -> String {
        let lowercased = error.lowercased()
        if lowercased.contains("codexex-helper") || lowercased.contains("embedded helper") {
            return "Codexex couldn’t start its bundled helper. Reopen the app or refresh quota."
        }
        return error
    }
}
#endif
