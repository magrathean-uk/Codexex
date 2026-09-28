import SwiftUI
import UIKit
import OSLog

@MainActor
final class CodexiOSAppDelegate: NSObject, UIApplicationDelegate {
    private static let logger = Logger(
        subsystem: "com.magrathean.CodexexApp",
        category: "APNs registration"
    )
    private static let silentPushWakeThrottle = CodexiOSSilentPushWakeThrottle()

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        CodexiOSBackgroundRefresh.register()
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Task { await codexiOSSharedPushRegistrationManager.didRegister(deviceToken: deviceToken) }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: any Error
    ) {
        Self.logger.error("APNs registration failed: \(error.localizedDescription, privacy: .private)")
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        Task { await codexiOSSharedPushRegistrationManager.retryPendingRegistration() }
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        let receivedAt = Date()
        Self.recordWake(receivedAt: receivedAt, outcome: "received")
        guard Self.silentPushWakeThrottle.begin() else {
            Self.logger.notice("Background wake coalesced before quota refresh.")
            Self.recordWake(receivedAt: receivedAt, outcome: "coalesced")
            completionHandler(.noData)
            return
        }
        CodexiOSSilentPushWakeRunner.run {
            let model = CodexiOSModel()
            let success = await model.refreshLiveActivityInBackground()
            let updated = success && model.lastUpdatedAt != nil
            Self.logger.notice("Background wake completed; refreshed: \(updated, privacy: .public)")
            Self.recordWake(
                receivedAt: receivedAt,
                outcome: updated ? "refreshed" : (success ? "no-active-activity" : "failed"),
                snapshotCapturedAt: updated ? model.lastUpdatedAt : nil
            )
            return updated ? .newData : (success ? .noData : .failed)
        } onDeadline: {
            Self.logger.error("Background wake exceeded its local deadline.")
            Self.recordWake(receivedAt: receivedAt, outcome: "timed-out")
        } completion: { result in
            Self.silentPushWakeThrottle.finish()
            completionHandler(result)
        }
    }

    /// A single local debug receipt verifies real delivery without exporting account or quota data.
    private static func recordWake(receivedAt: Date, outcome: String, snapshotCapturedAt: Date? = nil) {
        #if DEBUG
        var receipt: [String: Any] = [
            "receivedAt": receivedAt.timeIntervalSince1970,
            "recordedAt": Date().timeIntervalSince1970,
            "outcome": outcome,
        ]
        if let snapshotCapturedAt {
            receipt["snapshotCapturedAt"] = snapshotCapturedAt.timeIntervalSince1970
        }
        do {
            let url = URL.cachesDirectory.appending(path: "CodexexAPNsWake.json")
            try JSONSerialization.data(withJSONObject: receipt, options: .sortedKeys)
                .write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            Self.logger.error("Could not save local background-wake receipt.")
        }
        #endif
    }
}

/// Limits APNs wake-triggered quota refreshes only. Foreground and user-initiated
/// refreshes intentionally bypass this in-process guard.
@MainActor
final class CodexiOSSilentPushWakeThrottle {
    static let minimumInterval: TimeInterval = 60

    private let minimumInterval: TimeInterval
    private var isRefreshing = false
    private var lastStartedAt: Date?

    init(minimumInterval: TimeInterval = CodexiOSSilentPushWakeThrottle.minimumInterval) {
        self.minimumInterval = minimumInterval
    }

    func begin(now: Date = .now) -> Bool {
        guard isRefreshing == false else { return false }
        if let lastStartedAt, now.timeIntervalSince(lastStartedAt) < minimumInterval {
            return false
        }
        isRefreshing = true
        lastStartedAt = now
        return true
    }

    func finish() {
        isRefreshing = false
    }
}

/// Completes a silent-push fetch within a conservative deadline. The gate keeps
/// UIKit's completion callback exactly-once even when cancellation races the
/// network refresh finishing.
@MainActor
enum CodexiOSSilentPushWakeRunner {
    static let timeout: Duration = .seconds(25)

    static func run(
        timeout: Duration = CodexiOSSilentPushWakeRunner.timeout,
        operation: @escaping @MainActor @Sendable () async -> UIBackgroundFetchResult,
        onDeadline: @escaping @MainActor @Sendable () -> Void = {},
        completion: @escaping @MainActor @Sendable (UIBackgroundFetchResult) -> Void
    ) {
        let gate = CodexiOSSilentPushCompletionGate(
            onDeadline: onDeadline,
            completion: completion
        )
        let operationTask = Task { @MainActor in
            gate.finish(await operation())
        }
        let deadlineTask = Task { @MainActor in
            do {
                try await Task.sleep(for: timeout)
            } catch {
                return
            }
            operationTask.cancel()
            gate.finish(.failed, afterDeadline: true)
        }
        gate.install(deadlineTask: deadlineTask)
    }
}

@MainActor
private final class CodexiOSSilentPushCompletionGate {
    private let onDeadline: @MainActor @Sendable () -> Void
    private let completion: @MainActor @Sendable (UIBackgroundFetchResult) -> Void
    private var deadlineTask: Task<Void, Never>?
    private var hasFinished = false

    init(
        onDeadline: @escaping @MainActor @Sendable () -> Void,
        completion: @escaping @MainActor @Sendable (UIBackgroundFetchResult) -> Void
    ) {
        self.onDeadline = onDeadline
        self.completion = completion
    }

    func install(deadlineTask: Task<Void, Never>) {
        self.deadlineTask = deadlineTask
        if hasFinished {
            deadlineTask.cancel()
        }
    }

    func finish(_ result: UIBackgroundFetchResult, afterDeadline: Bool = false) {
        guard hasFinished == false else { return }
        hasFinished = true
        deadlineTask?.cancel()
        if afterDeadline {
            onDeadline()
        }
        completion(result)
    }
}

@main
struct CodexexiOSApp: App {
    @UIApplicationDelegateAdaptor(CodexiOSAppDelegate.self) private var appDelegate
    @State private var model = CodexiOSModel()

    var body: some Scene {
        WindowGroup {
            CodexiOSShellView(model: model)
        }
    }
}
