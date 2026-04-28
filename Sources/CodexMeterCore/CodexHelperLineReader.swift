import Foundation

public enum CodexHelperLineReaderError: LocalizedError, Sendable, Equatable {
    case timeout
    case responseTooLarge
    case closed

    public var errorDescription: String? {
        switch self {
        case .timeout:
            return "Helper timed out before returning a response."
        case .responseTooLarge:
            return "Helper response exceeded the maximum line size."
        case .closed:
            return "Helper process closed unexpectedly."
        }
    }
}

public enum CodexHelperLineReader {
    public static func readLine(
        from handle: FileHandle,
        timeout: TimeInterval,
        maxBytes: Int
    ) throws -> String {
        let state = State()
        let semaphore = DispatchSemaphore(value: 0)

        handle.readabilityHandler = { readableHandle in
            let data = readableHandle.availableData
            state.append(data, maxBytes: maxBytes)
            if state.isComplete {
                semaphore.signal()
            }
        }

        let result = semaphore.wait(timeout: .now() + timeout)
        handle.readabilityHandler = nil

        if result == .timedOut {
            throw CodexHelperLineReaderError.timeout
        }

        return try state.result()
    }

    private final class State: @unchecked Sendable {
        private let lock = NSLock()
        private var buffer = Data()
        private var error: CodexHelperLineReaderError?
        private var line: String?

        var isComplete: Bool {
            lock.lock()
            defer { lock.unlock() }
            return line != nil || error != nil
        }

        func append(_ data: Data, maxBytes: Int) {
            lock.lock()
            defer { lock.unlock() }

            guard line == nil, error == nil else { return }

            guard data.isEmpty == false else {
                error = .closed
                return
            }

            if let newlineIndex = data.firstIndex(of: 0x0A) {
                let prefix = data.prefix(upTo: newlineIndex)
                guard buffer.count + prefix.count <= maxBytes else {
                    error = .responseTooLarge
                    return
                }
                buffer.append(prefix)
                line = String(decoding: buffer, as: UTF8.self)
                return
            }

            buffer.append(data)
            if buffer.count > maxBytes {
                error = .responseTooLarge
            }
        }

        func result() throws -> String {
            lock.lock()
            defer { lock.unlock() }

            if let error {
                throw error
            }
            if let line {
                return line
            }
            throw CodexHelperLineReaderError.closed
        }
    }
}
