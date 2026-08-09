import Foundation
import ActivityKit
import CodexMeterCore

extension CodexLiveActivityAttributes: ActivityAttributes {}

@MainActor
enum CodexiOSLiveActivity {
    static var isRunning: Bool { Activity<CodexLiveActivityAttributes>.activities.isEmpty == false }
    static func start(snapshot: CodexSnapshot, showFiveHour: Bool, cadence: TimeInterval) async throws {
        guard let state = CodexLiveActivityPresentation.state(snapshot: snapshot, showFiveHour: showFiveHour) else { return }
        let activities = Activity<CodexLiveActivityAttributes>.activities
        for activity in activities.dropFirst() { await activity.end(nil, dismissalPolicy: .immediate) }
        if let activity = activities.first {
            await update(activity, state: state, snapshot: snapshot, cadence: cadence)
            return
        }
        _ = try Activity.request(
            attributes: CodexLiveActivityAttributes(),
            content: .init(state: state, staleDate: CodexLiveActivityPresentation.staleDate(capturedAt: snapshot.capturedAt, cadence: cadence)),
            pushType: nil
        )
    }

    static func update(snapshot: CodexSnapshot, showFiveHour: Bool, cadence: TimeInterval) async {
        guard let state = CodexLiveActivityPresentation.state(snapshot: snapshot, showFiveHour: showFiveHour) else { return }
        let activities = Activity<CodexLiveActivityAttributes>.activities
        for activity in activities.dropFirst() { await activity.end(nil, dismissalPolicy: .immediate) }
        if let activity = activities.first { await update(activity, state: state, snapshot: snapshot, cadence: cadence) }
    }

    static func stop() async {
        for activity in Activity<CodexLiveActivityAttributes>.activities { await activity.end(nil, dismissalPolicy: .immediate) }
    }

    private static func update(_ activity: Activity<CodexLiveActivityAttributes>, state: CodexLiveActivityAttributes.ContentState, snapshot: CodexSnapshot, cadence: TimeInterval) async {
        await activity.update(.init(state: state, staleDate: CodexLiveActivityPresentation.staleDate(capturedAt: snapshot.capturedAt, cadence: cadence)))
    }
}
