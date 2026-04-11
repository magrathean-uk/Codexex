#if os(macOS)
import AppKit
import Foundation

enum CodexDeviceAuthCoordinator {
    static func startSignIn(
        client: CodexXPCClient,
        update: @escaping @Sendable (_ statusMessage: String, _ deviceCode: String?) -> Void
    ) {
        Task(priority: .userInitiated) {
            do {
                let auth = try await client.beginChatGPTSignIn()
                await MainActor.run {
                    update("Enter the code in your browser.", auth.userCode)
                    NSWorkspace.shared.open(auth.verificationURL)
                }
            } catch {
                await MainActor.run {
                    update(error.localizedDescription, nil)
                }
            }
        }
    }
}
#endif
