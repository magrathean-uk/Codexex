import Darwin
import CryptoKit
import Foundation

public enum CodexLocalUsageDirectoryReader {
    public static let defaultMaximumFiles = 120
    public static let defaultMaximumBytesPerScan: UInt64 = 64 * 1_024 * 1_024
    public static let defaultMaximumRetainedEntries = 20_000
    private static let readChunkBytes = 64 * 1_024
    private static let maximumBufferedLineBytes = 8 * 1_024 * 1_024
    private static let retainedEntryTrimBatch = 4_096
    private static let fingerprintSampleBytes = 4 * 1_024

    public struct IncrementalResult: Sendable, Equatable {
        public let summary: CodexLocalUsageSummary
        public let index: CodexLocalUsageIndexSnapshot
    }

    public static func entries(
        in rootURL: URL,
        maximumFiles: Int? = nil
    ) throws -> [CodexLocalUsageEntry] {
        try incrementalSummary(
            in: rootURL,
            previous: nil,
            maximumFiles: maximumFiles ?? Int.max,
            maximumBytes: .max,
            maximumRetainedEntries: .max
        ).index.entries
    }

    public static func summary(
        in rootURL: URL,
        capturedAt: Date = Date(),
        calendar: Calendar = .autoupdatingCurrent,
        hooksInstalled: Bool = false,
        maximumFiles: Int? = nil
    ) throws -> CodexLocalUsageSummary {
        let result = try incrementalSummary(
            in: rootURL,
            previous: nil,
            capturedAt: capturedAt,
            calendar: calendar,
            hooksInstalled: hooksInstalled,
            maximumFiles: maximumFiles ?? Int.max,
            maximumBytes: .max,
            maximumRetainedEntries: .max
        )
        return result.summary
    }

    public static func incrementalSummary(
        in rootURL: URL,
        previous: CodexLocalUsageIndexSnapshot?,
        capturedAt: Date = Date(),
        calendar: Calendar = .autoupdatingCurrent,
        hooksInstalled: Bool = false,
        maximumFiles: Int = defaultMaximumFiles,
        maximumBytes: UInt64 = defaultMaximumBytesPerScan,
        maximumRetainedEntries: Int = defaultMaximumRetainedEntries
    ) throws -> IncrementalResult {
        let previous = previous?.version == CodexLocalUsageIndex.currentVersion ? previous : nil
        let selection = try sessionFileSelection(in: rootURL, maximumFiles: maximumFiles)
        let selected = selection.selected
        let selectedPaths = Set(selected.map { $0.url.path })
        let previousEntries = Dictionary(grouping: previous?.entries ?? [], by: \.sourcePath)
        let retentionLimit = max(0, maximumRetainedEntries)

        var nextFiles: [String: CodexLocalUsageFileState] = [:]
        var nextParserStates: [String: CodexLocalUsageParserState] = [:]
        var nextEntries: [CodexLocalUsageEntry] = []
        var nextOmittedEntryCounts: [String: Int] = [:]
        var bytesRead: UInt64 = 0

        for candidate in selected {
            try Task.checkCancellation()
            let path = candidate.url.path
            let oldFile = previous?.files[path]
            let oldParserState = previous?.parserStates[path] ?? CodexLocalUsageParserState()
            let oldEntries = previousEntries[path] ?? []
            let plan = CodexLocalUsageIndex.plan(previous: oldFile, current: candidate.state)
            let remainingBudget = maximumBytes > bytesRead ? maximumBytes - bytesRead : 0

            switch plan {
            case .skip:
                nextFiles[path] = oldFile
                nextParserStates[path] = oldParserState
                nextEntries.append(contentsOf: oldEntries)
                carryOmittedEntryCount(
                    from: previous,
                    path: path,
                    into: &nextOmittedEntryCounts
                )

            case .fullRead:
                guard remainingBudget > 0 else { continue }
                let read = try streamEntries(
                    from: candidate.url,
                    startingAt: 0,
                    fileSize: candidate.state.size,
                    expectedInode: candidate.state.inode,
                    maximumBytes: remainingBudget,
                    maximumRetainedEntries: retentionLimit,
                    initialState: CodexLocalUsageParserState()
                )
                bytesRead += read.bytesRead
                nextFiles[path] = CodexLocalUsageFileState(
                    path: path,
                    inode: candidate.state.inode,
                    size: read.committedOffset,
                    modifiedAt: candidate.state.modifiedAt,
                    appendFingerprint: read.appendFingerprint
                )
                nextParserStates[path] = read.parserState
                nextEntries.append(contentsOf: read.entries)
                if read.omittedEntryCount > 0 {
                    nextOmittedEntryCounts[path] = read.omittedEntryCount
                }

            case .append(let offset):
                guard remainingBudget > 0 else {
                    if let oldFile {
                        nextFiles[path] = oldFile
                        nextParserStates[path] = oldParserState
                        nextEntries.append(contentsOf: oldEntries)
                        carryOmittedEntryCount(
                            from: previous,
                            path: path,
                            into: &nextOmittedEntryCounts
                        )
                    }
                    continue
                }
                let read: StreamReadResult
                do {
                    read = try streamEntries(
                        from: candidate.url,
                        startingAt: offset,
                        fileSize: candidate.state.size,
                        expectedInode: candidate.state.inode,
                        maximumBytes: remainingBudget,
                        maximumRetainedEntries: retentionLimit,
                        initialState: oldParserState,
                        expectedPreviousFingerprint: oldFile.flatMap { file in
                            file.appendFingerprint.map { (file.size, $0) }
                        }
                    )
                } catch SessionFileReadError.fingerprintMismatch {
                    read = try streamEntries(
                        from: candidate.url,
                        startingAt: 0,
                        fileSize: candidate.state.size,
                        expectedInode: candidate.state.inode,
                        maximumBytes: remainingBudget,
                        maximumRetainedEntries: retentionLimit,
                        initialState: CodexLocalUsageParserState()
                    )
                }
                bytesRead += read.bytesRead
                nextFiles[path] = CodexLocalUsageFileState(
                    path: path,
                    inode: candidate.state.inode,
                    size: read.committedOffset,
                    modifiedAt: candidate.state.modifiedAt,
                    appendFingerprint: read.appendFingerprint
                )
                nextParserStates[path] = read.parserState
                if read.startedAtOffset > 0 {
                    nextEntries.append(contentsOf: oldEntries)
                }
                nextEntries.append(contentsOf: read.entries)
                let oldOmitted = read.startedAtOffset > 0
                    ? previous?.omittedEntryCountsByFile[path] ?? 0
                    : 0
                let totalOmitted = codexSaturatingNonnegativeAdd(oldOmitted, read.omittedEntryCount)
                if totalOmitted > 0 {
                    nextOmittedEntryCounts[path] = totalOmitted
                }
            }
        }

        nextEntries = nextEntries
            .filter { selectedPaths.contains($0.sourcePath) }
            .sorted { lhs, rhs in
                if lhs.timestamp != rhs.timestamp { return lhs.timestamp < rhs.timestamp }
                return lhs.id < rhs.id
            }
        trimOldestEntries(
            &nextEntries,
            to: retentionLimit,
            omittedEntryCounts: &nextOmittedEntryCounts
        )
        nextOmittedEntryCounts = nextOmittedEntryCounts.filter {
            selectedPaths.contains($0.key) && $0.value > 0
        }

        let indexedFileCount = selected.reduce(into: 0) { count, candidate in
            if let state = nextFiles[candidate.url.path],
               let parserState = nextParserStates[candidate.url.path],
               state.size >= candidate.state.size,
               parserState.pendingLineByteCount == 0,
               parserState.isDiscardingOversizedLine == false {
                count += 1
            }
        }
        let coverage = CodexLocalUsageCoverage(
            indexedFileCount: indexedFileCount,
            selectedFileCount: selected.count,
            discoveredFileCount: selection.discoveredFileCount,
            bytesRead: bytesRead,
            retainedEntryCount: nextEntries.count,
            omittedEntryCount: nextOmittedEntryCounts.values.reduce(0, codexSaturatingNonnegativeAdd)
        )
        let latestActivityAt = nextEntries.map(\.timestamp).max()
        let configReport = CodexLocalConfigDoctor.report(
            hasSessionData: nextEntries.isEmpty == false,
            hooksInstalled: hooksInstalled,
            configPath: defaultConfigURL().path,
            sessionsPath: rootURL.path,
            latestSessionActivityAt: latestActivityAt,
            now: capturedAt
        )
        let summary = CodexLocalUsageAggregator.snapshot(
            entries: nextEntries,
            dataPath: rootURL.path,
            capturedAt: capturedAt,
            calendar: calendar,
            configReport: configReport,
            coverage: coverage
        )
        let index = CodexLocalUsageIndexSnapshot(
            capturedAt: capturedAt,
            rootPath: rootURL.path,
            files: nextFiles,
            parserStates: nextParserStates,
            entries: nextEntries,
            omittedEntryCountsByFile: nextOmittedEntryCounts
        )
        return IncrementalResult(summary: summary, index: index)
    }

    static func sessionFileSelection(
        in rootURL: URL,
        maximumFiles: Int
    ) throws -> SessionFileSelection {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return SessionFileSelection(
                selected: [],
                discoveredFileCount: 0,
                peakRetainedCandidateCount: 0
            )
        }

        var candidates = SessionFileCandidateHeap(limit: max(0, maximumFiles))
        var discoveredFileCount = 0
        for case let fileURL as URL in enumerator {
            try Task.checkCancellation()
            guard fileURL.pathExtension == "jsonl" else { continue }
            var fileInfo = stat()
            guard lstat(fileURL.path, &fileInfo) == 0,
                  fileInfo.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG) else {
                continue
            }
            let values = try fileURL.resourceValues(forKeys: [
                .isRegularFileKey,
                .contentModificationDateKey,
                .fileSizeKey
            ])
            guard values.isRegularFile == true else { continue }
            let state = CodexLocalUsageFileState(
                path: fileURL.path,
                inode: UInt64(fileInfo.st_ino),
                size: UInt64(max(0, values.fileSize ?? 0)),
                modifiedAt: values.contentModificationDate ?? .distantPast
            )
            discoveredFileCount = codexSaturatingNonnegativeAdd(discoveredFileCount, 1)
            candidates.insert(SessionFileCandidate(url: fileURL, state: state))
        }

        return SessionFileSelection(
            selected: candidates.sortedCandidates,
            discoveredFileCount: discoveredFileCount,
            peakRetainedCandidateCount: candidates.peakRetainedCount
        )
    }

    private static func streamEntries(
        from fileURL: URL,
        startingAt offset: UInt64,
        fileSize: UInt64,
        expectedInode: UInt64,
        maximumBytes: UInt64,
        maximumRetainedEntries: Int,
        initialState: CodexLocalUsageParserState,
        expectedPreviousFingerprint: (size: UInt64, value: String)? = nil
    ) throws -> StreamReadResult {
        let handle = try openSessionFileForReading(fileURL, expectedInode: expectedInode)
        defer { try? handle.close() }
        if let expectedPreviousFingerprint {
            let actual = try appendFingerprint(
                descriptor: handle.fileDescriptor,
                committedSize: expectedPreviousFingerprint.size
            )
            guard actual == expectedPreviousFingerprint.value else {
                throw SessionFileReadError.fingerprintMismatch
            }
        }
        try handle.seek(toOffset: offset)

        var parserState = initialState
        var entries: [CodexLocalUsageEntry] = []
        var omittedEntryCount = 0
        let replayByteCount = UInt64(
            min(max(0, parserState.pendingLineByteCount), maximumBufferedLineBytes)
        )
        parserState.pendingLineByteCount = 0
        var buffer = Data()
        var streamOffset = offset
        var committedOffset = offset
        var physicalBytesRead: UInt64 = 0
        let physicalReadLimit = maximumBytes.addingReportingOverflow(replayByteCount).overflow
            ? UInt64.max
            : maximumBytes + replayByteCount

        while physicalBytesRead < physicalReadLimit {
            try Task.checkCancellation()
            let remainingBudget = physicalReadLimit - physicalBytesRead
            let readCount = Int(min(UInt64(readChunkBytes), remainingBudget))
            guard readCount > 0,
                  let chunk = try handle.read(upToCount: readCount),
                  chunk.isEmpty == false else {
                break
            }
            let chunkStartOffset = streamOffset
            streamOffset += UInt64(chunk.count)
            physicalBytesRead += UInt64(chunk.count)

            var chunkToProcess = chunk
            if parserState.hasParsedUnterminatedLine {
                if chunkToProcess.first == 0x0A {
                    chunkToProcess.removeFirst()
                    committedOffset += 1
                }
                parserState.hasParsedUnterminatedLine = false
            }

            if parserState.isDiscardingOversizedLine {
                if let newline = chunkToProcess.firstIndex(of: 0x0A) {
                    parserState.parsedLineCount += 1
                    parserState.isDiscardingOversizedLine = false
                    let afterNewline = chunkToProcess.index(after: newline)
                    let consumed = chunkToProcess.distance(from: chunkToProcess.startIndex, to: afterNewline)
                    committedOffset = chunkStartOffset + UInt64(chunk.count - chunkToProcess.count + consumed)
                    buffer.append(contentsOf: chunkToProcess[afterNewline...])
                } else {
                    committedOffset = streamOffset
                    continue
                }
            } else {
                buffer.append(chunkToProcess)
            }

            while let newline = buffer.firstIndex(of: 0x0A) {
                let lineByteCount = buffer.distance(from: buffer.startIndex, to: newline)
                let afterNewline = buffer.index(after: newline)
                let consumed = buffer.distance(from: buffer.startIndex, to: afterNewline)
                if lineByteCount >= maximumBufferedLineBytes {
                    parserState.parsedLineCount += 1
                    buffer = Data(buffer[afterNewline...])
                    committedOffset += UInt64(consumed)
                    continue
                }
                var line = Data(buffer[..<newline])
                if line.last == 0x0D { line.removeLast() }
                if let entry = CodexLocalUsageTranscriptParser.consume(
                    lineData: line,
                    sourcePath: fileURL.path,
                    state: &parserState
                ) {
                    appendRetainedEntry(
                        entry,
                        to: &entries,
                        maximumRetainedEntries: maximumRetainedEntries,
                        omittedEntryCount: &omittedEntryCount
                    )
                }
                buffer = Data(buffer[afterNewline...])
                committedOffset += UInt64(consumed)
            }

            if buffer.count >= maximumBufferedLineBytes {
                buffer.removeAll(keepingCapacity: false)
                parserState.isDiscardingOversizedLine = true
                committedOffset = streamOffset
            }
        }

        if parserState.isDiscardingOversizedLine == false,
           buffer.isEmpty == false,
           streamOffset >= fileSize,
           (try? JSONSerialization.jsonObject(with: buffer)) != nil {
            if let entry = CodexLocalUsageTranscriptParser.consume(
                lineData: buffer,
                sourcePath: fileURL.path,
                state: &parserState
            ) {
                appendRetainedEntry(
                    entry,
                    to: &entries,
                    maximumRetainedEntries: maximumRetainedEntries,
                    omittedEntryCount: &omittedEntryCount
                )
            }
            buffer.removeAll(keepingCapacity: false)
            committedOffset = streamOffset
            parserState.hasParsedUnterminatedLine = true
        }
        parserState.pendingLineByteCount = buffer.count

        let replayedBytes = min(replayByteCount, physicalBytesRead)
        let bytesRead = physicalBytesRead - replayedBytes
        trimOldestEntries(
            &entries,
            to: maximumRetainedEntries,
            omittedEntryCount: &omittedEntryCount
        )

        let fingerprint = try appendFingerprint(
            descriptor: handle.fileDescriptor,
            committedSize: committedOffset
        )
        return StreamReadResult(
            entries: entries,
            parserState: parserState,
            startedAtOffset: offset,
            committedOffset: committedOffset,
            bytesRead: bytesRead,
            omittedEntryCount: omittedEntryCount,
            appendFingerprint: fingerprint
        )
    }

    private static func appendFingerprint(
        descriptor: Int32,
        committedSize: UInt64
    ) throws -> String {
        var sampled = Data()
        var encodedSize = committedSize.bigEndian
        withUnsafeBytes(of: &encodedSize) { sampled.append(contentsOf: $0) }

        let sampleLimit = UInt64(fingerprintSampleBytes)
        if committedSize <= sampleLimit * 2 {
            sampled.append(try readFingerprintBytes(
                descriptor: descriptor,
                offset: 0,
                count: Int(committedSize)
            ))
        } else {
            sampled.append(try readFingerprintBytes(
                descriptor: descriptor,
                offset: 0,
                count: fingerprintSampleBytes
            ))
            sampled.append(try readFingerprintBytes(
                descriptor: descriptor,
                offset: committedSize - sampleLimit,
                count: fingerprintSampleBytes
            ))
        }

        return SHA256.hash(data: sampled).map { String(format: "%02x", $0) }.joined()
    }

    private static func readFingerprintBytes(
        descriptor: Int32,
        offset: UInt64,
        count: Int
    ) throws -> Data {
        guard offset <= UInt64(Int64.max), count >= 0 else {
            throw SessionFileReadError.fingerprintMismatch
        }
        var data = Data(count: count)
        var totalRead = 0
        try data.withUnsafeMutableBytes { bytes in
            guard let baseAddress = bytes.baseAddress else { return }
            while totalRead < count {
                let result = Darwin.pread(
                    descriptor,
                    baseAddress.advanced(by: totalRead),
                    count - totalRead,
                    off_t(offset) + off_t(totalRead)
                )
                if result < 0, errno == EINTR { continue }
                guard result > 0 else {
                    throw SessionFileReadError.fingerprintMismatch
                }
                totalRead += result
            }
        }
        return data
    }

    private static func appendRetainedEntry(
        _ entry: CodexLocalUsageEntry,
        to entries: inout [CodexLocalUsageEntry],
        maximumRetainedEntries: Int,
        omittedEntryCount: inout Int
    ) {
        guard maximumRetainedEntries > 0 else {
            omittedEntryCount = codexSaturatingNonnegativeAdd(omittedEntryCount, 1)
            return
        }
        entries.append(entry)
        guard maximumRetainedEntries != .max else { return }
        let (threshold, overflow) = maximumRetainedEntries.addingReportingOverflow(retainedEntryTrimBatch)
        if overflow == false, entries.count > threshold {
            trimOldestEntries(
                &entries,
                to: maximumRetainedEntries,
                omittedEntryCount: &omittedEntryCount
            )
        }
    }

    private static func trimOldestEntries(
        _ entries: inout [CodexLocalUsageEntry],
        to limit: Int,
        omittedEntryCount: inout Int
    ) {
        guard limit != .max, entries.count > limit else { return }
        entries.sort { lhs, rhs in
            if lhs.timestamp != rhs.timestamp { return lhs.timestamp < rhs.timestamp }
            return lhs.id < rhs.id
        }
        let removalCount = entries.count - limit
        entries = Array(entries.dropFirst(removalCount))
        omittedEntryCount = codexSaturatingNonnegativeAdd(omittedEntryCount, removalCount)
    }

    private static func trimOldestEntries(
        _ entries: inout [CodexLocalUsageEntry],
        to limit: Int,
        omittedEntryCounts: inout [String: Int]
    ) {
        guard limit != .max, entries.count > limit else { return }
        let removalCount = entries.count - limit
        for entry in entries.prefix(removalCount) {
            omittedEntryCounts[entry.sourcePath] = codexSaturatingNonnegativeAdd(
                omittedEntryCounts[entry.sourcePath] ?? 0,
                1
            )
        }
        entries = Array(entries.dropFirst(removalCount))
    }

    private static func carryOmittedEntryCount(
        from previous: CodexLocalUsageIndexSnapshot?,
        path: String,
        into counts: inout [String: Int]
    ) {
        let count = previous?.omittedEntryCountsByFile[path] ?? 0
        if count > 0 {
            counts[path] = count
        }
    }

    private struct StreamReadResult {
        let entries: [CodexLocalUsageEntry]
        let parserState: CodexLocalUsageParserState
        let startedAtOffset: UInt64
        let committedOffset: UInt64
        let bytesRead: UInt64
        let omittedEntryCount: Int
        let appendFingerprint: String
    }

    private enum SessionFileReadError: Error {
        case fingerprintMismatch
    }

    static func openSessionFileForReading(_ fileURL: URL, expectedInode: UInt64? = nil) throws -> FileHandle {
        let descriptor: Int32 = fileURL.withUnsafeFileSystemRepresentation { path in
            guard let path else { return Int32(-1) }
            while true {
                let result = Darwin.open(path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
                if result < 0, errno == EINTR { continue }
                return result
            }
        }
        guard descriptor >= 0 else {
            throw sessionFileError("Session file could not be opened safely.")
        }

        var fileInfo = stat()
        guard fstat(descriptor, &fileInfo) == 0,
              fileInfo.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
              expectedInode.map({ UInt64(fileInfo.st_ino) == $0 }) ?? true else {
            Darwin.close(descriptor)
            throw sessionFileError("Session file changed before it could be read safely.")
        }
        return FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
    }

    private static func sessionFileError(_ description: String) -> NSError {
        NSError(
            domain: "CodexLocalUsageDirectoryReader",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: description]
        )
    }

    public static func defaultSessionsURL() -> URL {
        if let codexHome = ProcessInfo.processInfo.environment["CODEX_HOME"],
           codexHome.isEmpty == false {
            return URL(fileURLWithPath: codexHome).appending(path: "sessions", directoryHint: .isDirectory)
        }
        return defaultCodexHomeURL()
            .appending(path: ".codex", directoryHint: .isDirectory)
            .appending(path: "sessions", directoryHint: .isDirectory)
    }

    public static func defaultConfigURL() -> URL {
        if let codexHome = ProcessInfo.processInfo.environment["CODEX_HOME"],
           codexHome.isEmpty == false {
            return URL(fileURLWithPath: codexHome).appending(path: "config.toml")
        }
        return defaultCodexHomeURL()
            .appending(path: ".codex", directoryHint: .isDirectory)
            .appending(path: "config.toml")
    }

    private static func defaultCodexHomeURL() -> URL {
        if let passwd = getpwuid(getuid()),
           let home = passwd.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: home), isDirectory: true)
        }
        return URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
    }
}

struct SessionFileSelection {
    let selected: [SessionFileCandidate]
    let discoveredFileCount: Int
    let peakRetainedCandidateCount: Int
}

struct SessionFileCandidate {
    let url: URL
    let state: CodexLocalUsageFileState
}

private struct SessionFileCandidateHeap {
    let limit: Int
    private(set) var peakRetainedCount = 0
    private var storage: [SessionFileCandidate] = []

    mutating func insert(_ candidate: SessionFileCandidate) {
        guard limit > 0 else { return }
        if storage.count < limit {
            storage.append(candidate)
            siftUp(from: storage.count - 1)
            peakRetainedCount = max(peakRetainedCount, storage.count)
            return
        }
        guard let worst = storage.first,
              sessionCandidateRanksBefore(candidate, worst) else {
            return
        }
        storage[0] = candidate
        siftDown(from: 0)
    }

    var sortedCandidates: [SessionFileCandidate] {
        storage.sorted(by: sessionCandidateRanksBefore)
    }

    private mutating func siftUp(from start: Int) {
        var child = start
        while child > 0 {
            let parent = (child - 1) / 2
            guard sessionCandidateIsWorse(storage[child], than: storage[parent]) else { return }
            storage.swapAt(child, parent)
            child = parent
        }
    }

    private mutating func siftDown(from start: Int) {
        var parent = start
        while true {
            let left = parent * 2 + 1
            guard left < storage.count else { return }
            let right = left + 1
            let worseChild = right < storage.count
                && sessionCandidateIsWorse(storage[right], than: storage[left]) ? right : left
            guard sessionCandidateIsWorse(storage[worseChild], than: storage[parent]) else { return }
            storage.swapAt(parent, worseChild)
            parent = worseChild
        }
    }
}

private func sessionCandidateRanksBefore(
    _ lhs: SessionFileCandidate,
    _ rhs: SessionFileCandidate
) -> Bool {
    if lhs.state.modifiedAt != rhs.state.modifiedAt {
        return lhs.state.modifiedAt > rhs.state.modifiedAt
    }
    if lhs.state.size != rhs.state.size {
        return lhs.state.size > rhs.state.size
    }
    return lhs.url.path < rhs.url.path
}

private func sessionCandidateIsWorse(
    _ lhs: SessionFileCandidate,
    than rhs: SessionFileCandidate
) -> Bool {
    sessionCandidateRanksBefore(rhs, lhs)
}
