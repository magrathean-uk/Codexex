#if os(macOS)
import Foundation
import CodexMeterCore

@MainActor
enum CodexResetTextFormatting {
    private static let shortClockFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale.autoupdatingCurrent
        formatter.timeZone = .current
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    private static let shortDateClockFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale.autoupdatingCurrent
        formatter.timeZone = .current
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()

    static func resetText(style: CodexResetDisplayStyle, now: Date, resetAt: Date?) -> String {
        switch style {
        case .relative:
            return CodexFormatting.relativeResetText(now: now, resetAt: resetAt)
        case .absolute:
            guard let resetAt else { return "Reset unknown" }
            let formatter = Calendar.autoupdatingCurrent.isDate(resetAt, inSameDayAs: now)
                ? shortClockFormatter
                : shortDateClockFormatter
            return "at \(formatter.string(from: resetAt))"
        }
    }
}
#endif
