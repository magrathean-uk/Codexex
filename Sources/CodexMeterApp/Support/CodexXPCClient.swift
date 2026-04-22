#if os(macOS)
import Foundation
import CodexMeterCore

@objc protocol CodexXPCServiceProtocol {
    func fetchSnapshot(reply: @escaping (Data?, String?) -> Void)
    func beginChatGPTSignIn(reply: @escaping (Data?, String?) -> Void)
    func completeChatGPTSignIn(flowID: String, reply: @escaping (Data?, String?) -> Void)
    func signOut(reply: @escaping (String?) -> Void)
    func cancelPendingOperations(reply: @escaping () -> Void)
}

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
    private let queue = DispatchQueue(label: "Codexex.xpc.client")
    private let serviceName = "com.magrathean.CodexexApp.CodexexXPCService"
    private var connection: NSXPCConnection?

    deinit {
        connection?.invalidate()
    }

    func fetchSnapshotResponse() async throws -> CodexServiceSnapshotResponse {
        let data = try await dataReply { service, reply in
            service.fetchSnapshot(reply: reply)
        }
        return try Self.decoder.decode(CodexServiceSnapshotResponse.self, from: data)
    }

    func beginChatGPTSignIn() async throws -> CodexDeviceAuthStart {
        let data = try await dataReply { service, reply in
            service.beginChatGPTSignIn(reply: reply)
        }
        return try Self.decoder.decode(CodexDeviceAuthStart.self, from: data)
    }

    func completeChatGPTSignIn(flowID: String) async throws -> CodexDeviceAuthPollResult {
        let data = try await dataReply { service, reply in
            service.completeChatGPTSignIn(flowID: flowID, reply: reply)
        }
        return try Self.decoder.decode(CodexDeviceAuthPollResult.self, from: data)
    }

    func signOut() async throws {
        try await errorOnlyReply { service, reply in
            service.signOut(reply: reply)
        }
    }

    func cancelPendingOperations() {
        queue.async { [weak self] in
            guard let self else { return }
            let invalidate: () -> Void = { [weak self] in
                self?.invalidateConnection()
            }
            guard let service = self.connection?.remoteObjectProxyWithErrorHandler { error in
                CodexLog.helper.error("xpc cancel failed message=\(error.localizedDescription, privacy: .public)")
                invalidate()
            } as? CodexXPCServiceProtocol else {
                invalidate()
                return
            }
            service.cancelPendingOperations(reply: invalidate)
        }
    }

    private static let decoder = JSONDecoder()

    private func dataReply(
        _ operation: @escaping @Sendable (CodexXPCServiceProtocol, @escaping @Sendable (Data?, String?) -> Void) -> Void
    ) async throws -> Data {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            let reply = CodexXPCReplyBox<Data>(continuation)
            queue.async { [weak self] in
                guard let self else {
                    reply.resume(throwing: Self.helperError("XPC client was released."))
                    return
                }

                do {
                    let service = try self.serviceProxyLocked { error in
                        reply.resume(throwing: error)
                        self.invalidateConnection()
                    }
                    operation(service) { data, message in
                        if let message {
                            reply.resume(throwing: Self.helperError(message))
                            return
                        }
                        guard let data else {
                            reply.resume(throwing: Self.helperError("XPC service returned no data."))
                            return
                        }
                        reply.resume(returning: data)
                    }
                } catch {
                    reply.resume(throwing: error)
                }
            }
        }
    }

    private func errorOnlyReply(
        _ operation: @escaping @Sendable (CodexXPCServiceProtocol, @escaping @Sendable (String?) -> Void) -> Void
    ) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let reply = CodexXPCReplyBox<Void>(continuation)
            queue.async { [weak self] in
                guard let self else {
                    reply.resume(throwing: Self.helperError("XPC client was released."))
                    return
                }

                do {
                    let service = try self.serviceProxyLocked { error in
                        reply.resume(throwing: error)
                        self.invalidateConnection()
                    }
                    operation(service) { message in
                        if let message {
                            reply.resume(throwing: Self.helperError(message))
                        } else {
                            reply.resume(returning: ())
                        }
                    }
                } catch {
                    reply.resume(throwing: error)
                }
            }
        }
    }

    private func serviceProxyLocked(errorHandler: @escaping @Sendable (Error) -> Void) throws -> CodexXPCServiceProtocol {
        let connection = connectionLocked()
        guard let service = connection.remoteObjectProxyWithErrorHandler(errorHandler) as? CodexXPCServiceProtocol else {
            throw Self.helperError("XPC service proxy is unavailable.")
        }
        return service
    }

    private func connectionLocked() -> NSXPCConnection {
        if let connection {
            return connection
        }

        let connection = NSXPCConnection(serviceName: serviceName)
        connection.remoteObjectInterface = NSXPCInterface(with: CodexXPCServiceProtocol.self)
        connection.interruptionHandler = { [weak self] in
            CodexLog.helper.error("xpc connection interrupted")
            self?.invalidateConnection()
        }
        connection.invalidationHandler = { [weak self] in
            self?.invalidateConnection()
        }
        connection.resume()
        self.connection = connection
        return connection
    }

    private func invalidateConnection() {
        queue.async { [weak self] in
            guard let self else { return }
            self.connection?.invalidate()
            self.connection = nil
        }
    }

    private static func helperError(_ message: String) -> NSError {
        NSError(domain: "CodexXPCClient", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}

private final class CodexXPCReplyBox<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, Error>?

    init(_ continuation: CheckedContinuation<T, Error>) {
        self.continuation = continuation
    }

    func resume(returning value: T) {
        take()?.resume(returning: value)
    }

    func resume(throwing error: Error) {
        take()?.resume(throwing: error)
    }

    private func take() -> CheckedContinuation<T, Error>? {
        lock.lock()
        defer { lock.unlock() }
        let continuation = self.continuation
        self.continuation = nil
        return continuation
    }
}
#endif
