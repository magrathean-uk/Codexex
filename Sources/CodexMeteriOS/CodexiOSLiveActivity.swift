import Foundation
import ActivityKit
import CodexMeterCore

@MainActor
enum CodexiOSLiveActivity {
    static var isRunning: Bool { Activity<CodexLiveActivityAttributes>.activities.isEmpty == false }
    static var isAvailable: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }
    static func start(snapshot: CodexSnapshot, showFiveHour: Bool, cadence: TimeInterval) async throws {
        guard let state = CodexLiveActivityPresentation.state(snapshot: snapshot, showFiveHour: showFiveHour) else { return }
        if let activity = await recoverOneActivity() {
            await update(activity, state: state, snapshot: snapshot, cadence: cadence)
            return
        }
        guard isAvailable else { return }
        _ = try Activity.request(
            attributes: CodexLiveActivityAttributes(),
            content: .init(state: state, staleDate: CodexLiveActivityPresentation.staleDate(capturedAt: snapshot.capturedAt, cadence: cadence)),
            pushType: nil
        )
    }

    static func update(snapshot: CodexSnapshot, showFiveHour: Bool, cadence: TimeInterval) async {
        guard let state = CodexLiveActivityPresentation.state(snapshot: snapshot, showFiveHour: showFiveHour) else { return }
        guard let activity = await recoverOneActivity() else { return }
        await update(activity, state: state, snapshot: snapshot, cadence: cadence)
    }

    static func stop() async {
        for activity in Activity<CodexLiveActivityAttributes>.activities { await activity.end(nil, dismissalPolicy: .immediate) }
    }

    static func markStale(snapshot: CodexSnapshot, showFiveHour: Bool, cadence: TimeInterval) async {
        guard let state = CodexLiveActivityPresentation.state(snapshot: snapshot, showFiveHour: showFiveHour, stale: true),
              let activity = await recoverOneActivity() else { return }
        await update(activity, state: state, snapshot: snapshot, cadence: cadence)
    }

    private static func recoverOneActivity() async -> Activity<CodexLiveActivityAttributes>? {
        let activities = Activity<CodexLiveActivityAttributes>.activities
        guard let activity = activities.first else { return nil }
        for duplicate in activities.dropFirst() { await duplicate.end(nil, dismissalPolicy: .immediate) }
        return activity
    }

    private static func update(_ activity: Activity<CodexLiveActivityAttributes>, state: CodexLiveActivityAttributes.ContentState, snapshot: CodexSnapshot, cadence: TimeInterval) async {
        await activity.update(.init(state: state, staleDate: CodexLiveActivityPresentation.staleDate(capturedAt: snapshot.capturedAt, cadence: cadence)))
    }
}
