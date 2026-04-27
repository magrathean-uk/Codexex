import Foundation
import Observation
import UIKit
import CodexMeterCore

@MainActor
@Observable
final class CodexiOSModel {
    var snapshot: CodexSnapshot?
    var isRefreshing = false
    var isSigningIn = false
    var statusMessage = "Sign in with ChatGPT to read Codex usage on this device."
    var errorMessage: String?
    var deviceCode: String?
    var verificationURL: URL?
    var flowID: String?
    var lastUpdatedAt: Date?

    private let service = CodexiOSService()

    var isSignedIn: Bool {
        snapshot != nil || statusMessage == "Signed in."
    }

    func start() async {
        await refresh()
    }

    func refresh() async {
        guard isRefreshing == false else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            let response = try await service.fetchSnapshot()
            if let snapshot = response.snapshot {
                self.snapshot = snapshot
                lastUpdatedAt = snapshot.capturedAt
                errorMessage = nil
                statusMessage = "Signed in."
                deviceCode = nil
                verificationURL = nil
                flowID = nil
            } else {
                snapshot = nil
                errorMessage = response.errorMessage
                statusMessage = response.errorMessage ?? "No quota data yet."
            }
        } catch {
            errorMessage = error.localizedDescription
            statusMessage = error.localizedDescription
        }
    }

    func beginSignIn() {
        guard isSigningIn == false else { return }
        isSigningIn = true
        errorMessage = nil
        statusMessage = "Starting ChatGPT sign-in."

        Task {
            defer { isSigningIn = false }
            do {
                let auth = try await service.beginSignIn()
                deviceCode = auth.userCode
                verificationURL = auth.verificationURL
                flowID = auth.flowID
                statusMessage = "Open Safari, approve sign-in, then check status."
                await UIApplication.shared.open(auth.verificationURL)
            } catch {
                errorMessage = error.localizedDescription
                statusMessage = error.localizedDescription
            }
        }
    }

    func checkSignIn() {
        guard let flowID else { return }
        guard isSigningIn == false else { return }
        isSigningIn = true
        errorMessage = nil

        Task {
            defer { isSigningIn = false }
            do {
                switch try await service.pollSignIn(flowID: flowID) {
                case .pending(let message):
                    statusMessage = message
                case .signedIn:
                    statusMessage = "Signed in."
                    deviceCode = nil
                    verificationURL = nil
                    self.flowID = nil
                    await refresh()
                }
            } catch {
                errorMessage = error.localizedDescription
                statusMessage = error.localizedDescription
            }
        }
    }

    func checkSignInAfterReturn() {
        guard flowID != nil else { return }
        statusMessage = "Checking sign-in."
        checkSignIn()
    }

    func copyCode() {
        guard let deviceCode else { return }
        UIPasteboard.general.string = deviceCode
        statusMessage = "Code copied. Paste it in Safari."
    }

    func openSignInPage() {
        guard let verificationURL else { return }
        Task {
            await UIApplication.shared.open(verificationURL)
        }
    }

    func signOut() {
        Task {
            do {
                try await service.signOut()
                snapshot = nil
                lastUpdatedAt = nil
                errorMessage = nil
                deviceCode = nil
                verificationURL = nil
                flowID = nil
                statusMessage = "Signed out."
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
