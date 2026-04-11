import Foundation
import CodexMeterCore

protocol CodexServiceClient: Sendable {
    func fetchSnapshotResponse() async throws -> CodexServiceSnapshotResponse
    func beginChatGPTSignIn() async throws -> CodexDeviceAuthStart
    func completeChatGPTSignIn(flowID: String) async throws
    func signOut() async throws
}

private struct HelperEnvelope: Decodable {
    let type: String
    let payloadJson: String?
    let message: String?
    let flowId: String?
    let verificationUri: URL?
    let userCode: String?
}

final class CodexXPCClient: CodexServiceClient, @unchecked Sendable {
    private let transport = CodexEmbeddedHelperTransport()

    func fetchSnapshotResponse() async throws -> CodexServiceSnapshotResponse {
        let envelope = try await send(method: "fetchSnapshot")
        guard envelope.type == "snapshot", let payload = envelope.payloadJson else {
            throw Self.helperError("Helper returned an unexpected snapshot response.")
        }
        return try Self.decoder.decode(CodexServiceSnapshotResponse.self, from: Data(payload.utf8))
    }

    func beginChatGPTSignIn() async throws -> CodexDeviceAuthStart {
        let envelope = try await send(method: "beginDeviceAuth")
        guard
            envelope.type == "deviceAuthStarted",
            let flowID = envelope.flowId,
            let verificationURL = envelope.verificationUri,
            let userCode = envelope.userCode
        else {
            throw Self.helperError("Helper returned an unexpected sign-in response.")
        }

        return CodexDeviceAuthStart(
            flowID: flowID,
            verificationURL: verificationURL,
            userCode: userCode
        )
    }

    func completeChatGPTSignIn(flowID: String) async throws {
        let envelope = try await send(method: "pollDeviceAuth", flowID: flowID)
        guard envelope.type == "signedIn" else {
            throw Self.helperError("Helper did not confirm sign-in.")
        }
    }

    func signOut() async throws {
        let envelope = try await send(method: "signOut")
        guard envelope.type == "signedOut" else {
            throw Self.helperError("Helper did not confirm sign-out.")
        }
    }

    private func send(method: String, flowID: String? = nil) async throws -> HelperEnvelope {
        let line = try Self.requestLine(method: method, flowID: flowID)
        let response = try await transport.send(line)
        let envelope = try Self.decoder.decode(HelperEnvelope.self, from: Data(response.utf8))
        if envelope.type == "error" {
            throw Self.helperError(envelope.message ?? "Helper returned an unknown error.")
        }
        return envelope
    }

    private static func requestLine(method: String, flowID: String?) throws -> String {
        var object: [String: String] = ["method": method]
        if let flowID {
            object["flow_id"] = flowID
        }
        let data = try JSONSerialization.data(withJSONObject: object, options: [])
        return String(decoding: data, as: UTF8.self)
    }

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }()

    private static func helperError(_ message: String) -> NSError {
        NSError(
            domain: "CodexHelperClient",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }
}

private final class CodexEmbeddedHelperTransport: @unchecked Sendable {
    private let queue = DispatchQueue(label: "Codexex.helper.transport")
    private var process: Process?
    private var stdinHandle: FileHandle?
    private var stdoutHandle: FileHandle?

    deinit {
        queue.sync {
            shutdownLocked()
        }
    }

    func send(_ line: String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    continuation.resume(returning: try self.sendLocked(line))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func sendLocked(_ line: String) throws -> String {
        try ensureStartedLocked()

        guard let stdinHandle, let stdoutHandle else {
            throw helperError("Helper process handles are unavailable.")
        }

        do {
            try stdinHandle.write(contentsOf: Data((line + "\n").utf8))
        } catch {
            shutdownLocked()
            throw error
        }

        var buffer = Data()
        while true {
            guard let chunk = try stdoutHandle.read(upToCount: 1), chunk.isEmpty == false else {
                shutdownLocked()
                throw helperError("Helper process closed unexpectedly.")
            }
            if chunk.first == 0x0A { break }
            buffer.append(chunk)
        }

        return String(decoding: buffer, as: UTF8.self)
    }

    private func ensureStartedLocked() throws {
        if let process, process.isRunning {
            return
        }

        shutdownLocked()

        let helperURL = Bundle.main.bundleURL.appending(path: "Contents/Helpers/codexex-helper")
        guard FileManager.default.isExecutableFile(atPath: helperURL.path()) else {
            throw helperError("Embedded helper is missing.")
        }

        let process = Process()
        process.executableURL = helperURL

        let stdin = Pipe()
        let stdout = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = Pipe()

        try process.run()

        self.process = process
        stdinHandle = stdin.fileHandleForWriting
        stdoutHandle = stdout.fileHandleForReading
    }

    private func shutdownLocked() {
        stdinHandle?.closeFile()
        stdoutHandle?.closeFile()
        if let process, process.isRunning {
            process.terminate()
        }
        process = nil
        stdinHandle = nil
        stdoutHandle = nil
    }

    private func helperError(_ message: String) -> NSError {
        NSError(
            domain: "CodexEmbeddedHelperTransport",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }
}
