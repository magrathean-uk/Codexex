import Foundation
import CodexMeterCore

@objc protocol CodexXPCServiceProtocol {
    func fetchSnapshot(reply: @escaping (Data?, String?) -> Void)
    func beginChatGPTSignIn(reply: @escaping (Data?, String?) -> Void)
    func completeChatGPTSignIn(flowID: String, reply: @escaping (Data?, String?) -> Void)
    func signOut(reply: @escaping (String?) -> Void)
    func cancelPendingOperations(reply: @escaping () -> Void)
}

final class CodexXPCServiceDelegate: NSObject, NSXPCListenerDelegate {
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        newConnection.exportedInterface = NSXPCInterface(with: CodexXPCServiceProtocol.self)
        newConnection.exportedObject = CodexXPCService()
        newConnection.resume()
        return true
    }
}

final class CodexXPCService: NSObject, CodexXPCServiceProtocol {
    private let helper: any CodexHelperSession

    init(helper: any CodexHelperSession = CodexHelperProcessSession()) {
        self.helper = helper
    }

    func fetchSnapshot(reply: @escaping (Data?, String?) -> Void) {
        do {
            let envelope = try helper.send(CodexHelperRequest(method: .fetchSnapshot))
            let response = try envelope.decodedSnapshotResponse()
            reply(try JSONEncoder().encode(response), nil)
        } catch {
            reply(nil, error.localizedDescription)
        }
    }

    func beginChatGPTSignIn(reply: @escaping (Data?, String?) -> Void) {
        do {
            let envelope = try helper.send(CodexHelperRequest(method: .beginDeviceAuth))
            let auth = try envelope.decodedDeviceAuthStart()
            reply(try JSONEncoder().encode(auth), nil)
        } catch {
            reply(nil, error.localizedDescription)
        }
    }

    func completeChatGPTSignIn(flowID: String, reply: @escaping (Data?, String?) -> Void) {
        do {
            let envelope = try helper.send(CodexHelperRequest(method: .pollDeviceAuth, flowID: flowID))
            let result = try envelope.decodedDeviceAuthPollResult()
            reply(try JSONEncoder().encode(result), nil)
        } catch {
            reply(nil, error.localizedDescription)
        }
    }

    func signOut(reply: @escaping (String?) -> Void) {
        do {
            let envelope = try helper.send(CodexHelperRequest(method: .signOut))
            try envelope.requireResponse(.signedOut)
            reply(nil)
        } catch {
            reply(error.localizedDescription)
        }
    }

    func cancelPendingOperations(reply: @escaping () -> Void) {
        helper.reset()
        reply()
    }
}
