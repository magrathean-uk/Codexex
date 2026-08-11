import BackgroundTasks
import Foundation
import OSLog

enum CodexiOSBackgroundRefreshPolicy {
    static let minimumInterval: TimeInterval = 15 * 60

    static func earliestBeginDate(now: Date = Date(), cadence: TimeInterval) -> Date {
        now.addingTimeInterval(max(minimumInterval, cadence))
    }
}

@MainActor
enum CodexiOSBackgroundRefresh {
    static let identifier = "com.magrathean.CodexexApp.quota-refresh"
    private static var isRegistered = false
    private static let logger = Logger(
        subsystem: "com.magrathean.CodexexApp",
        category: "background-refresh"
    )

    static func register() {
        guard isRegistered == false else { return }
        isRegistered = BGTaskScheduler.shared.register(
            forTaskWithIdentifier: identifier,
            using: .main
        ) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            handle(refreshTask)
        }
    }

    static func schedule(cadence: TimeInterval) {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = CodexiOSBackgroundRefreshPolicy.earliestBeginDate(
            cadence: cadence
        )
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            logger.error("Background refresh scheduling failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    static func cancel() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier)
    }

    private static func handle(_ task: BGAppRefreshTask) {
        let refreshOperation = Task { @MainActor in
            let model = CodexiOSModel()
            let success = await model.refreshLiveActivityInBackground()
            task.setTaskCompleted(success: success)
        }
        task.expirationHandler = {
            refreshOperation.cancel()
        }
    }
}
