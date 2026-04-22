import Foundation

final class CodexHelperProcess {
    private let sendLock = NSLock()
    private let stateLock = NSLock()
    private let maxResponseBytes = 1_048_576
    private var process: Process?
    private var stdinHandle: FileHandle?
    private var stdoutHandle: FileHandle?

    deinit {
        shutdown()
    }

    func send(_ line: String) throws -> String {
        sendLock.lock()
        defer { sendLock.unlock() }

        try ensureStarted()
        let handles = try currentHandles()

        do {
            try handles.stdin.write(contentsOf: Data((line + "\n").utf8))
        } catch {
            shutdown()
            throw error
        }

        var buffer = Data()
        while true {
            let chunk: Data
            do {
                guard let data = try handles.stdout.read(upToCount: 1), data.isEmpty == false else {
                    shutdown()
                    throw helperError("Helper process closed unexpectedly.", code: 2)
                }
                chunk = data
            } catch {
                shutdown()
                throw error
            }

            if chunk.first == 0x0A { break }
            buffer.append(chunk)

            if buffer.count > maxResponseBytes {
                shutdown()
                throw helperError("Helper response exceeded the maximum line size.", code: 3)
            }
        }

        return String(decoding: buffer, as: UTF8.self)
    }

    func reset() {
        shutdown()
    }

    private func ensureStarted() throws {
        if isRunning { return }

        shutdown()

        let helperURL = try locateHelperURL()

        let process = Process()
        process.executableURL = helperURL

        let stdin = Pipe()
        let stdout = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = Pipe()

        try process.run()

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
            throw helperError("Helper process handles are unavailable.", code: 1)
        }
        return (stdinHandle, stdoutHandle)
    }

    private func shutdown() {
        stateLock.lock()
        let process = self.process
        let stdinHandle = self.stdinHandle
        let stdoutHandle = self.stdoutHandle
        self.process = nil
        self.stdinHandle = nil
        self.stdoutHandle = nil
        stateLock.unlock()

        stdinHandle?.closeFile()
        stdoutHandle?.closeFile()
        if let process, process.isRunning {
            process.terminate()
        }
    }

    private func helperError(_ message: String, code: Int) -> NSError {
        NSError(domain: "CodexHelperProcess", code: code, userInfo: [NSLocalizedDescriptionKey: message])
    }

    private func locateHelperURL() throws -> URL {
        let fileManager = FileManager.default
        let candidateURLs = helperCandidateURLs()

        if let helperURL = candidateURLs.first(where: { fileManager.fileExists(atPath: $0.path()) }) {
            return helperURL
        }

        let searchedPaths = candidateURLs.map(\.path).joined(separator: ", ")
        throw helperError("Embedded helper is missing. Checked: \(searchedPaths)", code: 4)
    }

    private func helperCandidateURLs() -> [URL] {
        var candidates: [URL] = []

        if let executableURL = Bundle.main.executableURL {
            candidates.append(
                executableURL
                    .deletingLastPathComponent()
                    .deletingLastPathComponent()
                    .appending(path: "Helpers/codexex-helper")
            )
            candidates.append(
                executableURL
                    .deletingLastPathComponent()
                    .deletingLastPathComponent()
                    .deletingLastPathComponent()
                    .deletingLastPathComponent()
                    .deletingLastPathComponent()
                    .appending(path: "Helpers/codexex-helper")
            )
        }

        let bundleURL = Bundle.main.bundleURL
        candidates.append(
            bundleURL
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appending(path: "Helpers/codexex-helper")
        )
        candidates.append(
            bundleURL
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appending(path: "Helpers/codexex-helper")
        )

        return Array(NSOrderedSet(array: candidates)) as? [URL] ?? candidates
    }
}
