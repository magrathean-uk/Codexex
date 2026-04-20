#if os(macOS)
import Foundation
import CodexMeterCore

protocol CodexServiceClient: Sendable {
    func fetchSnapshotResponse() async throws -> CodexServiceSnapshotResponse
    func beginChatGPTSignIn() async throws -> CodexDeviceAuthStart
    func completeChatGPTSignIn(flowID: String) async throws -> CodexDeviceAuthPollResult
    func signOut() async throws
    func cancelPendingOperations()
}

extension CodexServiceClient {
    func cancelPendingOperations() {}
}

final class CodexXPCClient: CodexServiceClient, @unchecked Sendable {
    private let transport = CodexEmbeddedHelperTransport()

    func fetchSnapshotResponse() async throws -> CodexServiceSnapshotResponse {
        CodexLog.helper.log("request fetchSnapshot")
        let envelope = try await send(CodexHelperRequest(method: .fetchSnapshot))
        let response = try envelope.decodedSnapshotResponse()
        CodexLog.helper.log("response fetchSnapshot ok")
        return response
    }

    func beginChatGPTSignIn() async throws -> CodexDeviceAuthStart {
        CodexLog.auth.log("request beginDeviceAuth")
        let envelope = try await send(CodexHelperRequest(method: .beginDeviceAuth))
        let auth = try envelope.decodedDeviceAuthStart()
        CodexLog.auth.log("response beginDeviceAuth ok flow=\(auth.flowID, privacy: .private(mask: .hash))")
        return auth
    }

    func completeChatGPTSignIn(flowID: String) async throws -> CodexDeviceAuthPollResult {
        CodexLog.auth.log("request pollDeviceAuth flow=\(flowID, privacy: .private(mask: .hash))")
        let envelope = try await send(CodexHelperRequest(method: .pollDeviceAuth, flowID: flowID))
        let result = try envelope.decodedDeviceAuthPollResult()
        CodexLog.auth.log("response pollDeviceAuth status=\(result.status.rawValue, privacy: .public)")
        return result
    }

    func signOut() async throws {
        CodexLog.auth.log("request signOut")
        let envelope = try await send(CodexHelperRequest(method: .signOut))
        try envelope.requireResponse(.signedOut)
        CodexLog.auth.log("response signOut signedOut")
    }

    func cancelPendingOperations() {
        CodexLog.helper.log("reset helper transport")
        transport.reset()
    }

    private func send(_ request: CodexHelperRequest) async throws -> CodexHelperResponseEnvelope {
        let line = try Self.requestLine(for: request)
        let response = try await transport.send(line)
        let envelope = try Self.decoder.decode(CodexHelperResponseEnvelope.self, from: Data(response.utf8))
        if envelope.type == .error {
            CodexLog.helper.error(
                "helper error method=\(request.method.rawValue, privacy: .public) message=\(envelope.message ?? "unknown", privacy: .public)"
            )
        }
        return envelope
    }

    private static func requestLine(for request: CodexHelperRequest) throws -> String {
        let data = try JSONEncoder().encode(request)
        return String(decoding: data, as: UTF8.self)
    }

    private static let decoder = JSONDecoder()
}

private final class CodexEmbeddedHelperTransport: @unchecked Sendable {
    private let queue = DispatchQueue(label: "Codexex.helper.transport")
    private let stateLock = NSLock()
    private var process: Process?
    private var stdinHandle: FileHandle?
    private var stdoutHandle: FileHandle?

    deinit {
        shutdownNow()
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

    func reset() {
        shutdownNow()
    }

    private func sendLocked(_ line: String) throws -> String {
        try ensureStartedLocked()
        let handles = try currentHandles()

        do {
            try handles.stdin.write(contentsOf: Data((line + "\n").utf8))
        } catch {
            CodexLog.helper.error("write to helper failed")
            shutdownNow()
            throw error
        }

        var buffer = Data()
        while true {
            let chunk: Data
            do {
                guard let data = try handles.stdout.read(upToCount: 1) else {
                    shutdownNow()
                    throw helperError("Helper process closed unexpectedly.")
                }
                chunk = data
            } catch {
                shutdownNow()
                throw error
            }

            if chunk.isEmpty {
                CodexLog.helper.error("helper closed unexpectedly")
                shutdownNow()
                throw helperError("Helper process closed unexpectedly.")
            }
            if chunk.first == 0x0A {
                break
            }
            buffer.append(chunk)
        }

        return String(decoding: buffer, as: UTF8.self)
    }

    private func ensureStartedLocked() throws {
        if isRunning {
            return
        }

        shutdownNow()

        let helperURL = Bundle.main.bundleURL.appending(path: "Contents/Helpers/codexex-helper")
        guard FileManager.default.isExecutableFile(atPath: helperURL.path()) else {
            CodexLog.helper.error("embedded helper missing at \(helperURL.path(), privacy: .public)")
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
        CodexLog.helper.log("helper started pid=\(process.processIdentifier, privacy: .public)")

        stateLock.lock()
        self.process = process
        stdinHandle = stdin.fileHandleForWriting
        stdoutHandle = stdout.fileHandleForReading
        stateLock.unlock()
    }

    private var isRunning: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return process?.isRunning == true
    }

    private func currentHandles() throws -> (stdin: FileHandle, stdout: FileHandle) {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard let stdinHandle, let stdoutHandle else {
            throw helperError("Helper process handles are unavailable.")
        }
        return (stdinHandle, stdoutHandle)
    }

    private func shutdownNow() {
        stateLock.lock()
        let process = self.process
        let stdinHandle = self.stdinHandle
        let stdoutHandle = self.stdoutHandle
        self.process = nil
        self.stdinHandle = nil
        self.stdoutHandle = nil
        stateLock.unlock()

        if let process, process.isRunning {
            CodexLog.helper.log("helper stopping pid=\(process.processIdentifier, privacy: .public)")
        }

        stdinHandle?.closeFile()
        stdoutHandle?.closeFile()
        if let process, process.isRunning {
            process.terminate()
        }
    }

    private func helperError(_ message: String) -> NSError {
        NSError(
            domain: "CodexEmbeddedHelperTransport",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }
}
#endif
