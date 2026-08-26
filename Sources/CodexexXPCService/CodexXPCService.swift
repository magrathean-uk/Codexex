import Foundation
import CodexMeterCore

@objc protocol CodexXPCServiceProtocol {
    func fetchSnapshot(reply: @escaping @Sendable (Data?, String?) -> Void)
    func beginChatGPTSignIn(reply: @escaping @Sendable (Data?, String?) -> Void)
    func completeChatGPTSignIn(flowID: String, reply: @escaping @Sendable (Data?, String?) -> Void)
    func cancelChatGPTSignIn(flowID: String, reply: @escaping @Sendable (String?) -> Void)
    func signOut(reply: @escaping @Sendable (String?) -> Void)
    func cancelPendingOperations(reply: @escaping @Sendable () -> Void)
}

final class CodexXPCServiceDelegate: NSObject, NSXPCListenerDelegate {
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        if #available(macOS 13.0, *) {
            if CodexXPCClientIdentityRequirement.allowsDevelopmentBypass() {
                NSLog("Codexex XPC code-signing requirement disabled for debug development.")
            } else {
                newConnection.setCodeSigningRequirement(CodexXPCClientIdentityRequirement.mainAppRequirement)
            }
        }
        newConnection.exportedInterface = NSXPCInterface(with: CodexXPCServiceProtocol.self)
        newConnection.exportedObject = CodexXPCService()
        newConnection.resume()
        return true
    }
}

final class CodexXPCService: NSObject, CodexXPCServiceProtocol, @unchecked Sendable {
    private let helper: any CodexHelperSession
    private let operationQueue = DispatchQueue(label: "Codexex.xpc.service.operations")

    init(helper: any CodexHelperSession = CodexHelperProcessSession()) {
        self.helper = helper
    }

    func fetchSnapshot(reply: @escaping @Sendable (Data?, String?) -> Void) {
        operationQueue.async { [self] in
            do {
                let envelope = try helper.send(CodexHelperRequest(method: .fetchSnapshot))
                let response = try envelope.decodedSnapshotResponse()
                reply(try JSONEncoder().encode(response), nil)
            } catch {
                reply(nil, CodexXPCRequestGuards.redactedError(error))
            }
        }
    }

    func beginChatGPTSignIn(reply: @escaping @Sendable (Data?, String?) -> Void) {
        operationQueue.async { [self] in
            do {
                let envelope = try helper.send(CodexHelperRequest(method: .beginDeviceAuth))
                let auth = try envelope.decodedDeviceAuthStart()
                reply(try JSONEncoder().encode(auth), nil)
            } catch {
                reply(nil, CodexXPCRequestGuards.redactedError(error))
            }
        }
    }

    func completeChatGPTSignIn(flowID: String, reply: @escaping @Sendable (Data?, String?) -> Void) {
        operationQueue.async { [self] in
            do {
                let safeFlowID = try CodexXPCRequestGuards.validatedFlowID(flowID)
                let envelope = try helper.send(CodexHelperRequest(method: .pollDeviceAuth, flowID: safeFlowID))
                let result = try envelope.decodedDeviceAuthPollResult()
                reply(try JSONEncoder().encode(result), nil)
            } catch {
                reply(nil, CodexXPCRequestGuards.redactedError(error))
            }
        }
    }

    func cancelChatGPTSignIn(flowID: String, reply: @escaping @Sendable (String?) -> Void) {
        operationQueue.async { [self] in
            do {
                let safeFlowID = try CodexXPCRequestGuards.validatedFlowID(flowID)
                let envelope = try helper.send(
                    CodexHelperRequest(method: .cancelDeviceAuth, flowID: safeFlowID)
                )
                try envelope.requireResponse(.deviceAuthCancelled)
                reply(nil)
            } catch {
                reply(CodexXPCRequestGuards.redactedError(error))
            }
        }
    }

    func signOut(reply: @escaping @Sendable (String?) -> Void) {
        operationQueue.async { [self] in
            do {
                let envelope = try helper.send(CodexHelperRequest(method: .signOut))
                try envelope.requireResponse(.signedOut)
                reply(nil)
            } catch {
                reply(CodexXPCRequestGuards.redactedError(error))
            }
        }
    }

    func cancelPendingOperations(reply: @escaping @Sendable () -> Void) {
        // Reset outside `operationQueue` so it can interrupt the currently
        // blocked helper read. The queued reply is a drain barrier: it runs
        // after that send unwinds and before later serialized sends.
        helper.reset()
        operationQueue.async {
            reply()
        }
    }
}
