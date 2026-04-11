import Foundation

final class CodexHelperProcess {
    private let lock = NSLock()
    private var process: Process?
    private var stdinHandle: FileHandle?
    private var stdoutHandle: FileHandle?

    deinit {
        shutdown()
    }

    func send(_ line: String) throws -> String {
        lock.lock()
        defer { lock.unlock() }

        try ensureStarted()

        guard let stdinHandle, let stdoutHandle else {
            throw NSError(
                domain: "CodexHelperProcess",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Helper process handles are unavailable."]
            )
        }

        try stdinHandle.write(contentsOf: Data((line + "\n").utf8))

        var buffer = Data()
        while true {
            guard let chunk = try stdoutHandle.read(upToCount: 1), chunk.isEmpty == false else {
                throw NSError(
                    domain: "CodexHelperProcess",
                    code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "Helper process closed unexpectedly."]
                )
            }
            if chunk.first == 0x0A { break }
            buffer.append(chunk)
        }

        return String(decoding: buffer, as: UTF8.self)
    }

    private func ensureStarted() throws {
        if let process, process.isRunning {
            return
        }

        shutdown()

        let helperURL = Bundle.main.bundleURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Helpers/codexex-helper")

        let process = Process()
        process.executableURL = helperURL

        let stdin = Pipe()
        let stdout = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout

        try process.run()

        self.process = process
        stdinHandle = stdin.fileHandleForWriting
        stdoutHandle = stdout.fileHandleForReading
    }

    private func shutdown() {
        stdinHandle?.closeFile()
        stdoutHandle?.closeFile()
        if let process, process.isRunning {
            process.terminate()
        }
        process = nil
        stdinHandle = nil
        stdoutHandle = nil
    }
}
