import Darwin
import Foundation

public enum CodexSecureAtomicFile {
    public static func read(
        from fileURL: URL,
        maximumBytes: Int
    ) throws -> Data {
        guard maximumBytes >= 0 else { throw sizeError() }
        let descriptor: Int32 = fileURL.withUnsafeFileSystemRepresentation { path in
            guard let path else { return Int32(-1) }
            while true {
                let result = Darwin.open(path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
                if result < 0, errno == EINTR { continue }
                return result
            }
        }
        guard descriptor >= 0 else { throw posixError(operation: "open secure file") }

        var fileInfo = stat()
        guard fstat(descriptor, &fileInfo) == 0,
              fileInfo.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG) else {
            _ = Darwin.close(descriptor)
            throw posixError(operation: "inspect secure file")
        }
        guard fileInfo.st_size >= 0, UInt64(fileInfo.st_size) <= UInt64(maximumBytes) else {
            _ = Darwin.close(descriptor)
            throw sizeError()
        }

        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        var data = Data()
        data.reserveCapacity(min(maximumBytes, Int(fileInfo.st_size)))
        while data.count <= maximumBytes {
            let remaining = maximumBytes - data.count
            let readSize = remaining >= 64 * 1_024 ? 64 * 1_024 : remaining + 1
            guard let chunk = try handle.read(upToCount: readSize), chunk.isEmpty == false else {
                return data
            }
            data.append(chunk)
        }
        throw sizeError()
    }

    public static func write(
        _ data: Data,
        to fileURL: URL,
        secureParentDirectory: Bool = false
    ) throws {
        let fileManager = FileManager.default
        let directoryURL = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        if secureParentDirectory {
            try setPermissions(0o700, at: directoryURL)
        }

        let temporaryURL = directoryURL.appendingPathComponent(
            ".\(fileURL.lastPathComponent).\(UUID().uuidString).tmp"
        )
        var descriptor: Int32 = temporaryURL.withUnsafeFileSystemRepresentation { path in
            guard let path else { return Int32(-1) }
            return Darwin.open(path, O_WRONLY | O_CREAT | O_EXCL, mode_t(0o600))
        }
        guard descriptor >= 0 else { throw posixError(operation: "create secure temporary file") }

        var shouldRemoveTemporaryFile = true
        defer {
            if descriptor >= 0 {
                _ = Darwin.close(descriptor)
            }
            if shouldRemoveTemporaryFile {
                try? fileManager.removeItem(at: temporaryURL)
            }
        }

        try data.withUnsafeBytes { rawBuffer in
            guard var baseAddress = rawBuffer.baseAddress else { return }
            var remaining = rawBuffer.count
            while remaining > 0 {
                let written = Darwin.write(descriptor, baseAddress, remaining)
                if written < 0, errno == EINTR { continue }
                guard written > 0 else { throw posixError(operation: "write secure temporary file") }
                remaining -= written
                baseAddress = baseAddress.advanced(by: written)
            }
        }
        guard retryOnInterrupt({ Darwin.fsync(descriptor) }) == 0 else {
            throw posixError(operation: "sync secure temporary file")
        }
        guard Darwin.close(descriptor) == 0 else {
            throw posixError(operation: "close secure temporary file")
        }
        descriptor = -1

        let renameResult = retryOnInterrupt {
            temporaryURL.withUnsafeFileSystemRepresentation { sourcePath in
                fileURL.withUnsafeFileSystemRepresentation { destinationPath in
                    guard let sourcePath, let destinationPath else { return Int32(-1) }
                    return Darwin.rename(sourcePath, destinationPath)
                }
            }
        }
        guard renameResult == 0 else { throw posixError(operation: "replace secure file") }
        shouldRemoveTemporaryFile = false
        try setPermissions(0o600, at: fileURL)
        try syncDirectory(directoryURL)
    }

    private static func setPermissions(_ permissions: mode_t, at url: URL) throws {
        let result = retryOnInterrupt {
            url.withUnsafeFileSystemRepresentation { path in
                guard let path else { return Int32(-1) }
                return Darwin.chmod(path, permissions)
            }
        }
        guard result == 0 else { throw posixError(operation: "set secure file permissions") }
    }

    private static func syncDirectory(_ directoryURL: URL) throws {
        let descriptor: Int32 = directoryURL.withUnsafeFileSystemRepresentation { path in
            guard let path else { return Int32(-1) }
            return Darwin.open(path, O_RDONLY)
        }
        guard descriptor >= 0 else { throw posixError(operation: "open secure file directory") }
        defer { _ = Darwin.close(descriptor) }
        guard retryOnInterrupt({ Darwin.fsync(descriptor) }) == 0 else {
            throw posixError(operation: "sync secure file directory")
        }
    }

    private static func retryOnInterrupt(_ operation: () -> Int32) -> Int32 {
        while true {
            let result = operation()
            if result < 0, errno == EINTR { continue }
            return result
        }
    }

    private static func posixError(operation: String) -> NSError {
        let code = errno
        return NSError(
            domain: NSPOSIXErrorDomain,
            code: Int(code),
            userInfo: [NSLocalizedDescriptionKey: "Could not \(operation): \(String(cString: strerror(code)))"]
        )
    }

    private static func sizeError() -> NSError {
        NSError(
            domain: "CodexSecureAtomicFile",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Secure file exceeds its safe size limit."]
        )
    }
}
