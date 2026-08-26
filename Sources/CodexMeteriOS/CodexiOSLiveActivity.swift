import ActivityKit
import CodexMeterCore
import Foundation

struct CodexiOSLiveActivityRuntimeState: Equatable, Sendable {
    let isAvailable: Bool
    let activityID: String?

    var isRunning: Bool { activityID != nil }
}

enum CodexiOSLiveActivityError: LocalizedError {
    case missingWeeklyQuota

    var errorDescription: String? {
        switch self {
        case .missingWeeklyQuota:
            return "Refresh weekly quota before starting Live Activity."
        }
    }
}

protocol CodexiOSLiveActivityManaging: Sendable {
    func recover() async -> CodexiOSLiveActivityRuntimeState
    func start(snapshot: CodexSnapshot, showFiveHour: Bool, showUsedQuota: Bool, cadence: TimeInterval) async throws -> CodexiOSLiveActivityRuntimeState
    func update(snapshot: CodexSnapshot, showFiveHour: Bool, showUsedQuota: Bool, cadence: TimeInterval) async -> CodexiOSLiveActivityRuntimeState
    func markStale(snapshot: CodexSnapshot, showFiveHour: Bool, showUsedQuota: Bool, cadence: TimeInterval) async -> CodexiOSLiveActivityRuntimeState
    func stop() async -> CodexiOSLiveActivityRuntimeState
}

/// Serializes every lifecycle call, including calls that arrive while an
/// ActivityKit operation is suspended.
actor CodexiOSLiveActivitySerialManager: CodexiOSLiveActivityManaging {
    private let manager: any CodexiOSLiveActivityManaging
    private var isLocked = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var newestSnapshotDate: Date?
    private var latestRuntimeState = CodexiOSLiveActivityRuntimeState(
        isAvailable: false,
        activityID: nil
    )

    init(manager: any CodexiOSLiveActivityManaging) {
        self.manager = manager
    }

    func recover() async -> CodexiOSLiveActivityRuntimeState {
        await acquire()
        defer { release() }
        guard Task.isCancelled == false else { return latestRuntimeState }
        return await recoverCurrentState()
    }

    func start(
        snapshot: CodexSnapshot,
        showFiveHour: Bool,
        showUsedQuota: Bool,
        cadence: TimeInterval
    ) async throws -> CodexiOSLiveActivityRuntimeState {
        await acquire()
        defer { release() }
        try Task.checkCancellation()
        guard isCurrent(snapshot) else { return await recoverCurrentState() }
        let state = try await manager.start(
            snapshot: snapshot,
            showFiveHour: showFiveHour,
            showUsedQuota: showUsedQuota,
            cadence: cadence
        )
        record(snapshot)
        latestRuntimeState = state
        return state
    }

    func update(
        snapshot: CodexSnapshot,
        showFiveHour: Bool,
        showUsedQuota: Bool,
        cadence: TimeInterval
    ) async -> CodexiOSLiveActivityRuntimeState {
        await acquire()
        defer { release() }
        guard Task.isCancelled == false else { return latestRuntimeState }
        guard isCurrent(snapshot) else { return await recoverCurrentState() }
        let state = await manager.update(
            snapshot: snapshot,
            showFiveHour: showFiveHour,
            showUsedQuota: showUsedQuota,
            cadence: cadence
        )
        record(snapshot)
        latestRuntimeState = state
        return state
    }

    func markStale(
        snapshot: CodexSnapshot,
        showFiveHour: Bool,
        showUsedQuota: Bool,
        cadence: TimeInterval
    ) async -> CodexiOSLiveActivityRuntimeState {
        await acquire()
        defer { release() }
        guard Task.isCancelled == false else { return latestRuntimeState }
        guard isCurrent(snapshot) else { return await recoverCurrentState() }
        let state = await manager.markStale(
            snapshot: snapshot,
            showFiveHour: showFiveHour,
            showUsedQuota: showUsedQuota,
            cadence: cadence
        )
        record(snapshot)
        latestRuntimeState = state
        return state
    }

    func stop() async -> CodexiOSLiveActivityRuntimeState {
        await acquire()
        defer { release() }
        guard Task.isCancelled == false else { return latestRuntimeState }
        let state = await manager.stop()
        newestSnapshotDate = nil
        latestRuntimeState = state
        return state
    }

    private func acquire() async {
        guard isLocked else {
            isLocked = true
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    private func release() {
        guard waiters.isEmpty == false else {
            isLocked = false
            return
        }
        waiters.removeFirst().resume()
    }

    func queuedOperationCount() -> Int {
        waiters.count
    }

    private func isCurrent(_ snapshot: CodexSnapshot) -> Bool {
        newestSnapshotDate.map { snapshot.capturedAt >= $0 } ?? true
    }

    private func record(_ snapshot: CodexSnapshot) {
        newestSnapshotDate = max(newestSnapshotDate ?? snapshot.capturedAt, snapshot.capturedAt)
    }

    private func recoverCurrentState() async -> CodexiOSLiveActivityRuntimeState {
        let state = await manager.recover()
        latestRuntimeState = state
        return state
    }
}

/// Keeps non-Sendable `Activity` instances local to each async operation so
/// ActivityKit's concurrent update and end methods can safely consume them.
struct CodexiOSLiveActivity: CodexiOSLiveActivityManaging, Sendable {
    func recover() async -> CodexiOSLiveActivityRuntimeState {
        let plan = CodexLiveActivityLifecyclePolicy.recoveryPlan(
            existingIDs: Activity<CodexLiveActivityAttributes>.activities.map(\.id)
        )

        for duplicateID in plan.duplicateIDs {
            guard let duplicate = Activity<CodexLiveActivityAttributes>.activities
                .first(where: { $0.id == duplicateID }) else { continue }
            await duplicate.end(nil, dismissalPolicy: .immediate)
        }

        let remainingID = Activity<CodexLiveActivityAttributes>.activities
            .first(where: { $0.id == plan.primaryID })?
            .id
        return runtimeState(activityID: remainingID)
    }

    func start(
        snapshot: CodexSnapshot,
        showFiveHour: Bool,
        showUsedQuota: Bool,
        cadence: TimeInterval
    ) async throws -> CodexiOSLiveActivityRuntimeState {
        guard let state = CodexLiveActivityPresentation.state(
            snapshot: snapshot,
            showFiveHour: showFiveHour,
            showUsedQuota: showUsedQuota
        ) else {
            throw CodexiOSLiveActivityError.missingWeeklyQuota
        }

        let recovered = await recover()
        if let activityID = recovered.activityID,
           let activity = Activity<CodexLiveActivityAttributes>.activities.first(where: { $0.id == activityID }) {
            await activity.update(content(state: state, snapshot: snapshot, cadence: cadence))
            return runtimeState(activityID: activityID)
        }

        guard authorizationAvailable else { return runtimeState(activityID: nil) }
        let activity = try Activity.request(
            attributes: CodexLiveActivityAttributes(),
            content: content(state: state, snapshot: snapshot, cadence: cadence),
            pushType: nil
        )
        return runtimeState(activityID: activity.id)
    }

    func update(
        snapshot: CodexSnapshot,
        showFiveHour: Bool,
        showUsedQuota: Bool,
        cadence: TimeInterval
    ) async -> CodexiOSLiveActivityRuntimeState {
        await updateContent(
            snapshot: snapshot,
            showFiveHour: showFiveHour,
            showUsedQuota: showUsedQuota,
            cadence: cadence,
            stale: false
        )
    }

    func markStale(
        snapshot: CodexSnapshot,
        showFiveHour: Bool,
        showUsedQuota: Bool,
        cadence: TimeInterval
    ) async -> CodexiOSLiveActivityRuntimeState {
        await updateContent(
            snapshot: snapshot,
            showFiveHour: showFiveHour,
            showUsedQuota: showUsedQuota,
            cadence: cadence,
            stale: true
        )
    }

    func stop() async -> CodexiOSLiveActivityRuntimeState {
        let activityIDs = Activity<CodexLiveActivityAttributes>.activities.map(\.id)
        for activityID in activityIDs {
            guard let activity = Activity<CodexLiveActivityAttributes>.activities
                .first(where: { $0.id == activityID }) else { continue }
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        return runtimeState(activityID: nil)
    }

    private func updateContent(
        snapshot: CodexSnapshot,
        showFiveHour: Bool,
        showUsedQuota: Bool,
        cadence: TimeInterval,
        stale: Bool
    ) async -> CodexiOSLiveActivityRuntimeState {
        guard let state = CodexLiveActivityPresentation.state(
            snapshot: snapshot,
            showFiveHour: showFiveHour,
            showUsedQuota: showUsedQuota,
            stale: stale
        ) else {
            return await stop()
        }

        let recovered = await recover()
        guard let activityID = recovered.activityID,
              let activity = Activity<CodexLiveActivityAttributes>.activities.first(where: { $0.id == activityID }) else {
            return recovered
        }

        await activity.update(content(state: state, snapshot: snapshot, cadence: cadence))
        return runtimeState(activityID: activityID)
    }

    private var authorizationAvailable: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    private func runtimeState(activityID: String?) -> CodexiOSLiveActivityRuntimeState {
        CodexiOSLiveActivityRuntimeState(
            isAvailable: authorizationAvailable,
            activityID: activityID
        )
    }

    private func content(
        state: CodexLiveActivityAttributes.ContentState,
        snapshot: CodexSnapshot,
        cadence: TimeInterval
    ) -> ActivityContent<CodexLiveActivityAttributes.ContentState> {
        ActivityContent(
            state: state,
            staleDate: CodexLiveActivityPresentation.staleDate(
                capturedAt: snapshot.capturedAt,
                cadence: cadence
            )
        )
    }
}
