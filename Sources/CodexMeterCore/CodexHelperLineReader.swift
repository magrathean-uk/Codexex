import Darwin
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
        guard maxBytes >= 0 else {
            throw CodexHelperLineReaderError.responseTooLarge
        }
        let descriptor = handle.fileDescriptor
        guard descriptor >= 0 else {
            throw CodexHelperLineReaderError.closed
        }

        let timeoutNanoseconds = UInt64(
            min(max(0, timeout) * 1_000_000_000, Double(UInt64.max))
        )
        let start = DispatchTime.now().uptimeNanoseconds
        let deadlineResult = start.addingReportingOverflow(timeoutNanoseconds)
        let deadline = deadlineResult.overflow ? UInt64.max : deadlineResult.partialValue
        let readableEvents = Int16(POLLIN | POLLHUP | POLLERR)
        var buffer = Data()

        while true {
            let now = DispatchTime.now().uptimeNanoseconds
            let pollTimeout: Int32
            if timeoutNanoseconds == 0 {
                pollTimeout = 0
            } else {
                guard now < deadline else {
                    throw CodexHelperLineReaderError.timeout
                }
                let remaining = deadline - now
                let roundedMilliseconds = remaining / 1_000_000
                    + (remaining.isMultiple(of: 1_000_000) ? 0 : 1)
                pollTimeout = Int32(min(UInt64(Int32.max), roundedMilliseconds))
            }

            var state = pollfd(fd: descriptor, events: readableEvents, revents: 0)
            let pollResult = Darwin.poll(&state, 1, pollTimeout)
            if pollResult == 0 {
                throw CodexHelperLineReaderError.timeout
            }
            if pollResult < 0 {
                if errno == EINTR { continue }
                throw CodexHelperLineReaderError.closed
            }
            if state.revents & Int16(POLLNVAL) != 0 {
                throw CodexHelperLineReaderError.closed
            }
            guard state.revents & readableEvents != 0 else { continue }

            let remainingCapacity = maxBytes > buffer.count ? maxBytes - buffer.count : 0
            let readLimit = min(64 * 1_024, remainingCapacity == Int.max ? Int.max : remainingCapacity + 1)
            var bytes = [UInt8](repeating: 0, count: max(1, readLimit))
            let bytesRead = Darwin.read(descriptor, &bytes, bytes.count)
            if bytesRead < 0 {
                if errno == EINTR || errno == EAGAIN { continue }
                throw CodexHelperLineReaderError.closed
            }
            guard bytesRead > 0 else {
                throw CodexHelperLineReaderError.closed
            }

            let chunk = Data(bytes.prefix(bytesRead))
            if let newlineIndex = chunk.firstIndex(of: 0x0A) {
                let prefix = chunk.prefix(upTo: newlineIndex)
                let availableCapacity = maxBytes - buffer.count
                guard prefix.count <= availableCapacity else {
                    throw CodexHelperLineReaderError.responseTooLarge
                }
                buffer.append(prefix)
                return String(decoding: buffer, as: UTF8.self)
            }

            buffer.append(chunk)
            if buffer.count > maxBytes {
                throw CodexHelperLineReaderError.responseTooLarge
            }
        }
    }
}
