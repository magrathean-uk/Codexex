import Foundation
import CodexMeterCore

enum CodexSummarySnooze {
    static func fingerprint(for summary: PopupSummaryPresentation) -> String {
        [
            "\(summary.severity.rawValue)",
            summary.title,
            summary.message,
            summary.supportingLabel
        ].joined(separator: "|")
    }

    static func isSnoozed(
        summary: PopupSummaryPresentation,
        storedFingerprint: String?,
        expiresAt: Date?,
        now: Date = Date()
    ) -> Bool {
        guard let storedFingerprint, let expiresAt else { return false }
        guard now < expiresAt else { return false }
        return storedFingerprint == fingerprint(for: summary)
    }

    static func expiryDate(snapshot: CodexSnapshot?, now: Date = Date()) -> Date? {
        now.addingTimeInterval(24 * 60 * 60)
    }
}
