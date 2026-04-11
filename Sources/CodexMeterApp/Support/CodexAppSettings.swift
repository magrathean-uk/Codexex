#if os(macOS)
import Foundation
import CodexMeterCore

enum CodexAppSettings {
    private enum Key {
        static let hasCompletedOnboarding = "codexex.hasCompletedOnboarding"
        static let previewModeEnabled = "codexex.previewModeEnabled"
        static let autoRefreshEnabled = "codexex.autoRefreshEnabled"
        static let refreshIntervalSeconds = "codexex.refreshIntervalSeconds"
        static let launchAtLoginEnabled = "codexex.launchAtLoginEnabled"
        static let showHistoryEnabled = "codexex.showHistoryEnabled"
        static let showFiveHourInMenubar = "codexex.showFiveHourInMenubar"
        static let showWeeklyInMenubar = "codexex.showWeeklyInMenubar"
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
}
#endif
