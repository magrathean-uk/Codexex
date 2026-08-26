import Foundation
import CodexMeterCore

final class CodexHelperProcess: @unchecked Sendable {
    private let sendLock = NSLock()
    private let stateLock = NSLock()
    private let maxResponseBytes = 1_048_576
    private let responseTimeout: TimeInterval = 15
    private let helperURLProvider: (() throws -> URL)?
    private let beforePublishingLaunch: (() -> Void)?
    private var process: Process?
    private var stdinHandle: FileHandle?
    private var stdoutHandle: FileHandle?
    private var stderrHandle: FileHandle?
    private var resetGeneration: UInt64 = 0

    init(
        helperURLProvider: (() throws -> URL)? = nil,
        beforePublishingLaunch: (() -> Void)? = nil
    ) {
        self.helperURLProvider = helperURLProvider
        self.beforePublishingLaunch = beforePublishingLaunch
    }

    deinit {
        _ = shutdown(captureStderr: false)
    }

    func send(_ line: String) throws -> String {
        sendLock.lock()
        defer { sendLock.unlock() }

        try ensureStarted()
        let handles = try currentHandles()

        do {
            try handles.stdin.write(contentsOf: Data((line + "\n").utf8))
        } catch {
            _ = shutdown(captureStderr: false)
            throw error
        }

        do {
            return try CodexHelperLineReader.readLine(
                from: handles.stdout,
                timeout: responseTimeout,
                maxBytes: maxResponseBytes
            )
        } catch {
            let stderr = shutdown(captureStderr: true)
            let message = stderr.map { "\(error.localizedDescription) \($0)" } ?? error.localizedDescription
            throw helperError(CodexSensitiveRedactor.redacted(message), code: 2)
        }
    }

    func reset() {
        // Cancellation must interrupt a blocked stdout read. `sendLock` keeps
        // later sends out until that read unwinds; `stateLock` makes shutdown
        // safe while the current send still owns `sendLock`.
        stateLock.lock()
        resetGeneration &+= 1
        stateLock.unlock()
        _ = shutdown(captureStderr: false)
    }

    private func ensureStarted() throws {
        stateLock.lock()
        if process?.isRunning == true {
            stateLock.unlock()
            return
        }
        let launchGeneration = resetGeneration
        stateLock.unlock()

        _ = shutdown(captureStderr: false)

        let helperURL = try helperURLProvider?() ?? locateHelperURL()

        let process = Process()
        process.executableURL = helperURL

        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        beforePublishingLaunch?()

        stateLock.lock()
        guard resetGeneration == launchGeneration else {
            stateLock.unlock()
            stdin.fileHandleForWriting.closeFile()
            stdout.fileHandleForReading.closeFile()
            stderr.fileHandleForReading.closeFile()
            if process.isRunning {
                process.terminate()
            }
            throw helperError("Helper operation was cancelled.", code: 5)
        }
        self.process = process
        stdinHandle = stdin.fileHandleForWriting
        stdoutHandle = stdout.fileHandleForReading
        stderrHandle = stderr.fileHandleForReading
        stateLock.unlock()
    }

    private func currentHandles() throws -> (stdin: FileHandle, stdout: FileHandle) {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard let stdinHandle, let stdoutHandle else {
            throw helperError("Helper process handles are unavailable.", code: 1)
        }
        return (stdinHandle, stdoutHandle)
    }

    @discardableResult
    private func shutdown(captureStderr: Bool) -> String? {
        stateLock.lock()
        let process = self.process
        let stdinHandle = self.stdinHandle
        let stdoutHandle = self.stdoutHandle
        let stderrHandle = self.stderrHandle
        self.process = nil
        self.stdinHandle = nil
        self.stdoutHandle = nil
        self.stderrHandle = nil
        stateLock.unlock()

        stdinHandle?.closeFile()
        stdoutHandle?.closeFile()
        if let process, process.isRunning {
            process.terminate()
        }
        guard captureStderr, let stderrHandle else {
            stderrHandle?.closeFile()
            return nil
        }
        let data = stderrHandle.readDataToEndOfFile()
        stderrHandle.closeFile()
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
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
                .appending(path: "Contents/Helpers/codexex-helper")
        )
        candidates.append(
            bundleURL
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appending(path: "Helpers/codexex-helper")
        )

        return Array(NSOrderedSet(array: candidates)) as? [URL] ?? candidates
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
