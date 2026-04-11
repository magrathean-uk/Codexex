import Foundation

@objc protocol CodexXPCServiceProtocol {
    func fetchSnapshot(reply: @escaping (Data?, String?) -> Void)
    func beginChatGPTSignIn(reply: @escaping (Data?, String?) -> Void)
    func completeChatGPTSignIn(flowID: String, reply: @escaping (String?) -> Void)
    func signOut(reply: @escaping (String?) -> Void)
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
    private let helper = CodexHelperProcess()

    func fetchSnapshot(reply: @escaping (Data?, String?) -> Void) {
        do {
            let response = try helper.send(#"{"method":"fetchSnapshot"}"#)
            let envelope = try decodeEnvelope(from: response)
            switch envelope.type {
            case "snapshot":
                guard let payloadJSON = envelope.payloadJSON else {
                    reply(nil, "Helper returned no snapshot payload.")
                    return
                }
                reply(Data(payloadJSON.utf8), nil)
            case "error":
                reply(nil, envelope.message ?? "Helper fetch failed.")
            default:
                reply(nil, "Unexpected helper response: \(envelope.type)")
            }
        } catch {
            reply(nil, error.localizedDescription)
        }
    }

    func beginChatGPTSignIn(reply: @escaping (Data?, String?) -> Void) {
        do {
            let response = try helper.send(#"{"method":"beginDeviceAuth"}"#)
            let envelope = try decodeEnvelope(from: response)
            switch envelope.type {
            case "deviceAuthStarted":
                reply(Data(response.utf8), nil)
            case "error":
                reply(nil, envelope.message ?? "Helper sign-in failed.")
            default:
                reply(nil, "Unexpected helper response: \(envelope.type)")
            }
        } catch {
            reply(nil, error.localizedDescription)
        }
    }

    func completeChatGPTSignIn(flowID: String, reply: @escaping (String?) -> Void) {
        do {
            let request = try makeRequestLine(
                method: "pollDeviceAuth",
                extra: ["flow_id": flowID]
            )
            let response = try helper.send(request)
            let envelope = try decodeEnvelope(from: response)
            switch envelope.type {
            case "signedIn":
                reply(nil)
            case "error":
                reply(envelope.message ?? "Helper device auth polling failed.")
            default:
                reply("Unexpected helper response: \(envelope.type)")
            }
        } catch {
            reply(error.localizedDescription)
        }
    }

    func signOut(reply: @escaping (String?) -> Void) {
        do {
            let response = try helper.send(#"{"method":"signOut"}"#)
            let envelope = try decodeEnvelope(from: response)
            switch envelope.type {
            case "signedOut":
                reply(nil)
            case "error":
                reply(envelope.message ?? "Helper sign-out failed.")
            default:
                reply("Unexpected helper response: \(envelope.type)")
            }
        } catch {
            reply(error.localizedDescription)
        }
    }

    private func decodeEnvelope(from line: String) throws -> HelperEnvelope {
        try JSONDecoder().decode(HelperEnvelope.self, from: Data(line.utf8))
    }

    private func makeRequestLine(method: String, extra: [String: String]) throws -> String {
        var payload: [String: Any] = ["method": method]
        for (key, value) in extra {
            payload[key] = value
        }
        let data = try JSONSerialization.data(withJSONObject: payload)
        return String(decoding: data, as: UTF8.self)
    }
}

private struct HelperEnvelope: Decodable {
    let type: String
    let payloadJSON: String?
    let message: String?

    enum CodingKeys: String, CodingKey {
        case type
        case payloadJSON = "payloadJson"
        case message
    }
}
