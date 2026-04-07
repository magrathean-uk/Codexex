import Foundation

public enum CodexFormatting {
    public static func windowDuration(minutes: Int?) -> String {
        guard let minutes, minutes > 0 else {
            return "Unknown window"
        }

        if minutes.isMultiple(of: 1440) {
            let days = minutes / 1440
            return days == 1 ? "1 day window" : "\(days) day window"
        }

        if minutes.isMultiple(of: 60) {
            let hours = minutes / 60
            return hours == 1 ? "1 hour window" : "\(hours) hour window"
        }

        return minutes == 1 ? "1 minute window" : "\(minutes) minute window"
    }

    public static func relativeResetText(now: Date, resetAt: Date?) -> String {
        guard let resetAt else {
            return "Reset unknown"
        }

        let delta = Int(resetAt.timeIntervalSince(now).rounded())
        if abs(delta) < 30 {
            return "resets now"
        }

        let prefix = delta >= 0 ? "in " : ""
        return "resets \(prefix)\(compactDuration(seconds: abs(delta)))"
    }

    public static func compactDuration(seconds: Int) -> String {
        let seconds = max(0, seconds)

        if seconds < 60 {
            return "\(seconds)s"
        }

        let minutes = seconds / 60
        if minutes < 60 {
            return "\(minutes)m"
        }

        let hours = minutes / 60
        if hours < 24 {
            let remMinutes = minutes % 60
            if remMinutes == 0 {
                return "\(hours)h"
            }
            return "\(hours)h \(remMinutes)m"
        }

        let days = hours / 24
        let remHours = hours % 24
        if remHours == 0 {
            return "\(days)d"
        }
        return "\(days)d \(remHours)h"
    }

    public static func absoluteResetText(
        _ date: Date?,
        timeZone: TimeZone = .current
    ) -> String {
        guard let date else {
            return "Reset unknown"
        }

        let formatter = DateFormatter()
        formatter.timeZone = timeZone
        formatter.locale = Locale.autoupdatingCurrent
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    public static func percent(_ value: Double) -> String {
        "\(Int(value.rounded()))%"
    }
}
