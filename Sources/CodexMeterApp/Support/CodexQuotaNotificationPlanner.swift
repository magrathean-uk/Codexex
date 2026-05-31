#if os(macOS)
import Foundation
import UserNotifications
import CodexMeterCore

enum CodexQuotaNotificationKind: String, Sendable, Equatable, CaseIterable {
    case fiveHourPressure
    case fiveHourResetSoon
    case weeklyForecastRisk
}

struct CodexQuotaNotification: Identifiable, Sendable, Equatable {
    let id: String
    let kind: CodexQuotaNotificationKind
    let title: String
    let body: String
    let fingerprint: String
}

struct CodexQuotaNotificationPlan: Sendable, Equatable {
    let notifications: [CodexQuotaNotification]
}

struct CodexQuotaNotificationPreferences: Sendable, Equatable {
    let isEnabled: Bool
    let fiveHourPressureEnabled: Bool
    let resetReminderEnabled: Bool
    let weeklyForecastEnabled: Bool

    static let disabled = CodexQuotaNotificationPreferences(isEnabled: false)
    static let enabled = CodexQuotaNotificationPreferences(isEnabled: true)

    init(
        isEnabled: Bool,
        fiveHourPressureEnabled: Bool = true,
        resetReminderEnabled: Bool = true,
        weeklyForecastEnabled: Bool = true
    ) {
        self.isEnabled = isEnabled
        self.fiveHourPressureEnabled = fiveHourPressureEnabled
        self.resetReminderEnabled = resetReminderEnabled
        self.weeklyForecastEnabled = weeklyForecastEnabled
    }
}

struct CodexQuotaNotificationReceipts: Sendable, Equatable {
    static let empty = CodexQuotaNotificationReceipts(deliveredFingerprints: [:])

    let deliveredFingerprints: [CodexQuotaNotificationKind: String]

    init(deliveredFingerprints: [CodexQuotaNotificationKind: String]) {
        self.deliveredFingerprints = deliveredFingerprints
    }

    init(rawFingerprints: [String: String]) {
        var resolved: [CodexQuotaNotificationKind: String] = [:]
        for (rawKind, fingerprint) in rawFingerprints {
            guard let kind = CodexQuotaNotificationKind(rawValue: rawKind) else { continue }
            resolved[kind] = fingerprint
        }
        deliveredFingerprints = resolved
    }

    var rawFingerprints: [String: String] {
        Dictionary(uniqueKeysWithValues: deliveredFingerprints.map { kind, fingerprint in
            (kind.rawValue, fingerprint)
        })
    }

    func hasDelivered(_ notification: CodexQuotaNotification) -> Bool {
        deliveredFingerprints[notification.kind] == notification.fingerprint
    }

    func recording(_ notification: CodexQuotaNotification) -> CodexQuotaNotificationReceipts {
        var updated = deliveredFingerprints
        updated[notification.kind] = notification.fingerprint
        return CodexQuotaNotificationReceipts(deliveredFingerprints: updated)
    }
}

enum CodexQuotaNotificationPlanner {
    private static let pressureThreshold = 90.0
    private static let resetSoonThreshold = 70.0
    private static let resetSoonSeconds: TimeInterval = 15 * 60
    private static let pressureResetGuardSeconds: TimeInterval = 30 * 60
    private static let weeklyProjectionThreshold = 100.0

    static func plan(
        snapshot: CodexSnapshot?,
        insights: CodexUsageInsights?,
        preferences: CodexQuotaNotificationPreferences,
        receipts: CodexQuotaNotificationReceipts,
        now: Date
    ) -> CodexQuotaNotificationPlan {
        guard preferences.isEnabled,
              let snapshot,
              let codexLimit = snapshot.codexLimit else {
            return CodexQuotaNotificationPlan(notifications: [])
        }

        let candidates = [
            resetSoonNotification(
                limit: codexLimit,
                enabled: preferences.resetReminderEnabled,
                now: now
            ),
            pressureNotification(
                limit: codexLimit,
                enabled: preferences.fiveHourPressureEnabled,
                now: now
            ),
            weeklyForecastNotification(
                limit: codexLimit,
                insights: insights,
                enabled: preferences.weeklyForecastEnabled
            )
        ].compactMap { $0 }

        return CodexQuotaNotificationPlan(
            notifications: candidates.filter { receipts.hasDelivered($0) == false }
        )
    }

    private static func pressureNotification(
        limit: CodexLimit,
        enabled: Bool,
        now: Date
    ) -> CodexQuotaNotification? {
        guard enabled,
              let window = limit.fiveHourWindow,
              window.clampedUsedPercent >= pressureThreshold else {
            return nil
        }

        if let resetsAt = window.resetsAt,
           resetsAt.timeIntervalSince(now) <= pressureResetGuardSeconds {
            return nil
        }

        let percent = Int(window.clampedUsedPercent.rounded())
        let resetText = CodexFormatting.relativeResetText(now: now, resetAt: window.resetsAt)
        let fingerprint = fingerprint(
            kind: .fiveHourPressure,
            resetAt: window.resetsAt,
            percent: window.clampedUsedPercent
        )
        return CodexQuotaNotification(
            id: fingerprint,
            kind: .fiveHourPressure,
            title: "Codex 5H near limit",
            body: "\(percent)% used, \(resetText).",
            fingerprint: fingerprint
        )
    }

    private static func resetSoonNotification(
        limit: CodexLimit,
        enabled: Bool,
        now: Date
    ) -> CodexQuotaNotification? {
        guard enabled,
              let window = limit.fiveHourWindow,
              window.clampedUsedPercent >= resetSoonThreshold,
              let resetsAt = window.resetsAt else {
            return nil
        }

        let secondsUntilReset = resetsAt.timeIntervalSince(now)
        guard secondsUntilReset >= 0,
              secondsUntilReset <= resetSoonSeconds else {
            return nil
        }

        let percent = Int(window.clampedUsedPercent.rounded())
        let resetText = CodexFormatting.relativeResetText(now: now, resetAt: resetsAt)
        let fingerprint = fingerprint(
            kind: .fiveHourResetSoon,
            resetAt: resetsAt,
            percent: window.clampedUsedPercent
        )
        return CodexQuotaNotification(
            id: fingerprint,
            kind: .fiveHourResetSoon,
            title: "Codex 5H resets soon",
            body: "\(percent)% used, \(resetText).",
            fingerprint: fingerprint
        )
    }

    private static func weeklyForecastNotification(
        limit: CodexLimit,
        insights: CodexUsageInsights?,
        enabled: Bool
    ) -> CodexQuotaNotification? {
        guard enabled,
              let forecast = insights?.weeklyPace else {
            return nil
        }

        let projection = forecast.projectedPercentAtReset
        guard forecast.tone == .danger || (projection ?? 0) >= weeklyProjectionThreshold else {
            return nil
        }

        let percent = Int((projection ?? forecast.currentPercent ?? 0).rounded())
        let resetAt = forecast.resetAt ?? limit.weeklyWindow?.resetsAt
        let fingerprint = fingerprint(
            kind: .weeklyForecastRisk,
            resetAt: resetAt,
            percent: Double(percent)
        )
        return CodexQuotaNotification(
            id: fingerprint,
            kind: .weeklyForecastRisk,
            title: "Codex weekly pace risky",
            body: forecast.message,
            fingerprint: fingerprint
        )
    }

    private static func fingerprint(
        kind: CodexQuotaNotificationKind,
        resetAt: Date?,
        percent: Double
    ) -> String {
        let resetBucket = resetAt.map { String(Int($0.timeIntervalSince1970.rounded())) } ?? "unknown"
        return "\(kind.rawValue)|\(resetBucket)|\(Int(percent.rounded()))"
    }
}

struct CodexQuotaNotificationDeliveryResult: Sendable, Equatable {
    let notification: CodexQuotaNotification
    let delivered: Bool
}

protocol CodexQuotaNotificationDelivering: Sendable {
    func deliver(_ notifications: [CodexQuotaNotification]) async -> [CodexQuotaNotificationDeliveryResult]
}

struct CodexNoopQuotaNotificationDelivery: CodexQuotaNotificationDelivering {
    func deliver(_ notifications: [CodexQuotaNotification]) async -> [CodexQuotaNotificationDeliveryResult] {
        notifications.map { CodexQuotaNotificationDeliveryResult(notification: $0, delivered: true) }
    }
}

final class CodexUserNotificationDelivery: CodexQuotaNotificationDelivering, @unchecked Sendable {
    private let centerProvider: @Sendable () -> UNUserNotificationCenter

    init(centerProvider: @escaping @Sendable () -> UNUserNotificationCenter = { .current() }) {
        self.centerProvider = centerProvider
    }

    func deliver(_ notifications: [CodexQuotaNotification]) async -> [CodexQuotaNotificationDeliveryResult] {
        let center = centerProvider()
        guard notifications.isEmpty == false,
              await canDeliver(center: center) else {
            return notifications.map {
                CodexQuotaNotificationDeliveryResult(notification: $0, delivered: false)
            }
        }

        var results: [CodexQuotaNotificationDeliveryResult] = []
        for notification in notifications {
            let content = UNMutableNotificationContent()
            content.title = notification.title
            content.body = notification.body
            content.sound = .default
            let request = UNNotificationRequest(
                identifier: notification.id,
                content: content,
                trigger: nil
            )
            let delivered = await add(request, center: center)
            results.append(CodexQuotaNotificationDeliveryResult(notification: notification, delivered: delivered))
        }
        return results
    }

    private func canDeliver(center: UNUserNotificationCenter) async -> Bool {
        switch await authorizationStatus(center: center) {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined:
            return await requestAuthorization(center: center)
        case .denied:
            return false
        @unknown default:
            return false
        }
    }

    private func authorizationStatus(center: UNUserNotificationCenter) async -> UNAuthorizationStatus {
        await withCheckedContinuation { continuation in
            center.getNotificationSettings { settings in
                continuation.resume(returning: settings.authorizationStatus)
            }
        }
    }

    private func requestAuthorization(center: UNUserNotificationCenter) async -> Bool {
        await withCheckedContinuation { continuation in
            center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
                continuation.resume(returning: granted)
            }
        }
    }

    private func add(_ request: UNNotificationRequest, center: UNUserNotificationCenter) async -> Bool {
        await withCheckedContinuation { continuation in
            center.add(request) { error in
                continuation.resume(returning: error == nil)
            }
        }
    }
}
#endif
