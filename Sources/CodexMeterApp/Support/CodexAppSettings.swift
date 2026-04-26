#if os(macOS)
import Foundation
import CodexMeterCore

enum PopupHistoryMode: String, CaseIterable {
    case dailyPeaks
    case thisCycle

    var title: String {
        switch self {
        case .dailyPeaks:
            return "Daily peaks"
        case .thisCycle:
            return "This cycle"
        }
    }
}

enum CodexMenuBarDisplayMode: String, CaseIterable {
    case used
    case remaining
    case pace

    var title: String {
        switch self {
        case .used:
            return "Used"
        case .remaining:
            return "Left"
        case .pace:
            return "Pace"
        }
    }
}

enum CodexResetDisplayStyle: String, CaseIterable {
    case relative
    case absolute

    var title: String {
        switch self {
        case .relative:
            return "Relative"
        case .absolute:
            return "Clock"
        }
    }

    func resetText(now: Date, resetAt: Date?) -> String {
        switch self {
        case .relative:
            return CodexFormatting.relativeResetText(now: now, resetAt: resetAt)
        case .absolute:
            guard let resetAt else { return "Reset unknown" }
            let formatter = DateFormatter()
            formatter.locale = Locale.autoupdatingCurrent
            formatter.timeZone = .current
            formatter.dateStyle = Calendar.autoupdatingCurrent.isDate(resetAt, inSameDayAs: now) ? .none : .short
            formatter.timeStyle = .short
            return "resets \(formatter.string(from: resetAt))"
        }
    }
}

enum CodexAppSettings {
    private enum Key {
        static let hasCompletedOnboarding = "codexex.hasCompletedOnboarding"
        static let previewModeEnabled = "codexex.previewModeEnabled"
        static let autoRefreshEnabled = "codexex.autoRefreshEnabled"
        static let refreshIntervalSeconds = "codexex.refreshIntervalSeconds"
        static let launchAtLoginEnabled = "codexex.launchAtLoginEnabled"
        static let showHistoryEnabled = "codexex.showHistoryEnabled"
        static let showHistoryChartEnabled = "codexex.showHistoryChartEnabled"
        static let showInsightsEnabled = "codexex.showInsightsEnabled"
        static let showSparkEnabled = "codexex.showSparkEnabled"
        static let showFiveHourInMenubar = "codexex.showFiveHourInMenubar"
        static let showWeeklyInMenubar = "codexex.showWeeklyInMenubar"
        static let menuBarDisplayMode = "codexex.menuBarDisplayMode"
        static let resetDisplayStyle = "codexex.resetDisplayStyle"
        static let defaultHistoryMode = "codexex.defaultHistoryMode"
        static let showPaceConfidence = "codexex.showPaceConfidence"
        static let hideIdleSecondaryLimits = "codexex.hideIdleSecondaryLimits"
        static let summarySnoozeFingerprint = "codexex.summarySnoozeFingerprint"
        static let summarySnoozeExpiresAt = "codexex.summarySnoozeExpiresAt"
    }

    static let refreshIntervals: [Int] = [300, 600, 3600]

    static var hasCompletedOnboarding: Bool {
        get { UserDefaults.standard.bool(forKey: Key.hasCompletedOnboarding) }
        set { UserDefaults.standard.set(newValue, forKey: Key.hasCompletedOnboarding) }
    }

    static var previewModeEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: Key.previewModeEnabled) == nil {
                return false
            }
            return UserDefaults.standard.bool(forKey: Key.previewModeEnabled)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Key.previewModeEnabled)
        }
    }

    static var autoRefreshEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: Key.autoRefreshEnabled) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: Key.autoRefreshEnabled)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Key.autoRefreshEnabled)
        }
    }

    static var refreshIntervalSeconds: Int {
        get {
            let seconds = UserDefaults.standard.object(forKey: Key.refreshIntervalSeconds) as? Int
                ?? 300
            return max(seconds, 300)
        }
        set {
            UserDefaults.standard.set(max(newValue, 300), forKey: Key.refreshIntervalSeconds)
        }
    }

    static var refreshInterval: Duration {
        .seconds(Double(refreshIntervalSeconds))
    }

    static var refreshIntervalLabel: String {
        CodexFormatting.compactDuration(seconds: refreshIntervalSeconds)
    }

    static var launchAtLoginEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: Key.launchAtLoginEnabled) == nil {
                return false
            }
            return UserDefaults.standard.bool(forKey: Key.launchAtLoginEnabled)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Key.launchAtLoginEnabled)
        }
    }

    static var showHistoryEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: Key.showHistoryEnabled) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: Key.showHistoryEnabled)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Key.showHistoryEnabled)
        }
    }

    static var showInsightsEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: Key.showInsightsEnabled) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: Key.showInsightsEnabled)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Key.showInsightsEnabled)
        }
    }

    static var showHistoryChartEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: Key.showHistoryChartEnabled) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: Key.showHistoryChartEnabled)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Key.showHistoryChartEnabled)
        }
    }

    static var showSparkEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: Key.showSparkEnabled) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: Key.showSparkEnabled)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Key.showSparkEnabled)
        }
    }

    static var showFiveHourInMenubar: Bool {
        get {
            if UserDefaults.standard.object(forKey: Key.showFiveHourInMenubar) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: Key.showFiveHourInMenubar)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Key.showFiveHourInMenubar)
        }
    }

    static var showWeeklyInMenubar: Bool {
        get {
            if UserDefaults.standard.object(forKey: Key.showWeeklyInMenubar) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: Key.showWeeklyInMenubar)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Key.showWeeklyInMenubar)
        }
    }

    static var menuBarDisplayMode: CodexMenuBarDisplayMode {
        get {
            guard let rawValue = UserDefaults.standard.string(forKey: Key.menuBarDisplayMode),
                  let mode = CodexMenuBarDisplayMode(rawValue: rawValue) else {
                return .used
            }
            return mode
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: Key.menuBarDisplayMode)
        }
    }

    static var resetDisplayStyle: CodexResetDisplayStyle {
        get {
            guard let rawValue = UserDefaults.standard.string(forKey: Key.resetDisplayStyle),
                  let style = CodexResetDisplayStyle(rawValue: rawValue) else {
                return .relative
            }
            return style
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: Key.resetDisplayStyle)
        }
    }

    static var defaultHistoryMode: PopupHistoryMode {
        get {
            guard let rawValue = UserDefaults.standard.string(forKey: Key.defaultHistoryMode),
                  let mode = PopupHistoryMode(rawValue: rawValue) else {
                return .dailyPeaks
            }
            return mode
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: Key.defaultHistoryMode)
        }
    }

    static var showPaceConfidence: Bool {
        get {
            if UserDefaults.standard.object(forKey: Key.showPaceConfidence) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: Key.showPaceConfidence)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Key.showPaceConfidence)
        }
    }

    static var hideIdleSecondaryLimits: Bool {
        get {
            if UserDefaults.standard.object(forKey: Key.hideIdleSecondaryLimits) == nil {
                return false
            }
            return UserDefaults.standard.bool(forKey: Key.hideIdleSecondaryLimits)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Key.hideIdleSecondaryLimits)
        }
    }

    static var summarySnoozeFingerprint: String? {
        get { UserDefaults.standard.string(forKey: Key.summarySnoozeFingerprint) }
        set {
            if let newValue {
                UserDefaults.standard.set(newValue, forKey: Key.summarySnoozeFingerprint)
            } else {
                UserDefaults.standard.removeObject(forKey: Key.summarySnoozeFingerprint)
            }
        }
    }

    static var summarySnoozeExpiresAt: Date? {
        get { UserDefaults.standard.object(forKey: Key.summarySnoozeExpiresAt) as? Date }
        set {
            if let newValue {
                UserDefaults.standard.set(newValue, forKey: Key.summarySnoozeExpiresAt)
            } else {
                UserDefaults.standard.removeObject(forKey: Key.summarySnoozeExpiresAt)
            }
        }
    }

    static func clearSummarySnooze() {
        summarySnoozeFingerprint = nil
        summarySnoozeExpiresAt = nil
    }
}
#endif
