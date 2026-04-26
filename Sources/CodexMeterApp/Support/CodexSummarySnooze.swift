#if os(macOS)
import Foundation
import CodexMeterCore

enum CodexSummarySnooze {
    static func fingerprint(for summary: PopupSummaryPresentation) -> String {
        [
            "\(summary.severity.rawValue)",
            summary.title,
            summary.message,
            summary.supportingLabel,
            summary.supportingValue,
            summary.supportingDetail ?? ""
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
        snapshot?.limits
            .filter { $0.bucket == .codex }
            .flatMap { [$0.fiveHourWindow?.resetsAt, $0.weeklyWindow?.resetsAt] }
            .compactMap { $0 }
            .filter { $0 > now }
            .min()
    }
}
#endif
