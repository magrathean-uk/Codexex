import XCTest
@testable import CodexMeterApp
@testable import CodexMeterCore

@MainActor
final class CodexRefreshCoordinatorTests: XCTestCase {
    func testInvalidationCancelsOldTokens() {
        let coordinator = CodexRefreshCoordinator()
        let token = coordinator.token()

        XCTAssertTrue(coordinator.isCurrent(token))

        coordinator.invalidate()

        XCTAssertFalse(coordinator.isCurrent(token))
        XCTAssertTrue(coordinator.isCurrent(coordinator.token()))
    }

    func testInvalidateCanCancelHelperWork() {
        let coordinator = CodexRefreshCoordinator()
        var cancelCount = 0

        coordinator.invalidate {
            cancelCount += 1
        }

        XCTAssertEqual(cancelCount, 1)
    }

    func testRefreshScheduleReactsImmediatelyAndHasNoDisabledWake() async throws {
        let driver = TestMenuBarClockDriver(now: Date(timeIntervalSince1970: 1_900_000_000))
        let service = CountingSnapshotService(snapshot: schedulerSnapshot(at: driver.currentDate))
        let (model, defaults) = schedulerModel(
            service: service,
            driver: driver,
            autoRefreshEnabled: true,
            interval: 3_600
        )
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }

        await model.start()
        try await waitUntil { driver.recordedDurations.contains(3_600) }

        let callsBeforeChange = driver.recordedDurations.count
        model.setRefreshIntervalSeconds(300)
        try await waitUntil { driver.recordedDurations.dropFirst(callsBeforeChange).contains(300) }
        XCTAssertEqual(model.refreshIntervalSeconds, 300)

        model.setAutoRefreshEnabled(false)
        try await waitUntil { driver.activeWaiterDurations.contains(300) == false }
        let callsWhileDisabled = driver.recordedDurations.count
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(driver.recordedDurations.count, callsWhileDisabled)

        model.setAutoRefreshEnabled(true)
        try await waitUntil { driver.activeWaiterDurations.contains(300) }
        driver.advance(by: 300)
        try await waitUntil { await service.fetchCount == 2 }
    }

    func testStaleDeadlineUpdatesWithoutRefreshLoop() async throws {
        let driver = TestMenuBarClockDriver(now: Date(timeIntervalSince1970: 1_900_000_000))
        let service = CountingSnapshotService(snapshot: schedulerSnapshot(at: driver.currentDate))
        let (model, defaults) = schedulerModel(
            service: service,
            driver: driver,
            autoRefreshEnabled: false,
            interval: 300
        )
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }

        await model.start()
        XCTAssertFalse(model.isDataStale)
        try await waitUntil { driver.recordedDurations.contains(900) }

        driver.advance(by: 900)
        try await waitUntil { model.staleDeadlineReached }
        XCTAssertTrue(model.isDataStale)
    }

    private func schedulerModel(
        service: CountingSnapshotService,
        driver: TestMenuBarClockDriver,
        autoRefreshEnabled: Bool,
        interval: Int
    ) -> (CodexMenuBarModel, UserDefaults) {
        let suite = "CodexRefreshScheduler.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.set(suite, forKey: "test-suite-name")
        let settings = CodexAppSettingsStore(defaults: defaults)
        settings.setAutoRefreshEnabled(autoRefreshEnabled)
        settings.setRefreshIntervalSeconds(interval)
        let historyURL = FileManager.default.temporaryDirectory
            .appending(path: "codex-refresh-history-\(UUID().uuidString).json")
        let model = CodexMenuBarModel(
            service: service,
            localUsageProvider: SchedulerLocalUsageProvider(),
            settingsStore: settings,
            historyRepository: CodexHistoryRepository(store: CodexUsageHistoryStore(fileURL: historyURL)),
            notificationDelivery: CodexNoopQuotaNotificationDelivery(),
            clock: driver.clock
        )
        return (model, defaults)
    }

    private func defaultsSuiteName(_ defaults: UserDefaults) -> String {
        defaults.string(forKey: "test-suite-name")!
    }

    private func schedulerSnapshot(at date: Date) -> CodexSnapshot {
        CodexSnapshot(
            capturedAt: date,
            executablePath: "/tmp/helper",
            account: CodexAccount(authType: "chatGPT", email: nil, planType: "PRO"),
            limits: []
        )
    }

    private func waitUntil(
        timeout: TimeInterval = 1,
        condition: @escaping @MainActor () async -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("Timed out waiting for scheduler state")
    }
}

private struct SchedulerLocalUsageProvider: CodexLocalUsageProviding {
    func fetchLocalUsageSummary() async -> CodexLocalUsageFetchResult {
        .unavailable("Unavailable in scheduler test.")
    }
}

private actor CountingSnapshotService: CodexServiceClient {
    let snapshot: CodexSnapshot
    private(set) var fetchCount = 0

    init(snapshot: CodexSnapshot) {
        self.snapshot = snapshot
    }

    func fetchSnapshotResponse() async throws -> CodexServiceSnapshotResponse {
        fetchCount += 1
        return CodexServiceSnapshotResponse(authMode: .chatGPT, snapshot: snapshot, errorMessage: nil)
    }

    func beginChatGPTSignIn() async throws -> CodexDeviceAuthStart { throw SchedulerUnusedError() }
    func completeChatGPTSignIn(flowID: String) async throws -> CodexDeviceAuthPollResult { throw SchedulerUnusedError() }
    func signOut() async throws { throw SchedulerUnusedError() }
}

private struct SchedulerUnusedError: Error {}

private final class TestMenuBarClockDriver: @unchecked Sendable {
    private struct Waiter {
        let id: UUID
        let seconds: TimeInterval
        let continuation: CheckedContinuation<Void, Error>
    }

    private let lock = NSLock()
    private var date: Date
    private var waiters: [Waiter] = []
    private var durations: [TimeInterval] = []

    init(now: Date) {
        date = now
    }

    var clock: CodexMenuBarClock {
        CodexMenuBarClock(
            now: { [weak self] in self?.currentDate ?? .distantPast },
            sleep: { [weak self] seconds in
                guard let self else { throw CancellationError() }
                try await self.sleep(seconds: seconds)
            }
        )
    }

    var currentDate: Date {
        lock.withLock { date }
    }

    var recordedDurations: [TimeInterval] {
        lock.withLock { durations }
    }

    var activeWaiterDurations: [TimeInterval] {
        lock.withLock { waiters.map(\.seconds) }
    }

    func advance(by seconds: TimeInterval) {
        let continuations: [CheckedContinuation<Void, Error>] = lock.withLock {
            date = date.addingTimeInterval(seconds)
            let continuations = waiters.map(\.continuation)
            waiters.removeAll()
            return continuations
        }
        continuations.forEach { $0.resume(returning: ()) }
    }

    private func sleep(seconds: TimeInterval) async throws {
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let shouldCancel = lock.withLock { () -> Bool in
                    durations.append(seconds)
                    guard Task.isCancelled == false else { return true }
                    waiters.append(Waiter(id: id, seconds: seconds, continuation: continuation))
                    return false
                }
                if shouldCancel {
                    continuation.resume(throwing: CancellationError())
                }
            }
        } onCancel: {
            self.cancel(id: id)
        }
    }

    private func cancel(id: UUID) {
        let continuation: CheckedContinuation<Void, Error>? = lock.withLock {
            guard let index = waiters.firstIndex(where: { $0.id == id }) else { return nil }
            return waiters.remove(at: index).continuation
        }
        continuation?.resume(throwing: CancellationError())
    }
}
