#if os(macOS)
import Foundation
import CodexMeterCore

enum CodexAppSettings {
    private enum Key {
        static let autoRefreshEnabled = "codexex.autoRefreshEnabled"
        static let refreshIntervalSeconds = "codexex.refreshIntervalSeconds"
    }

    static let refreshIntervals: [Int] = [30, 60, 300]

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
                ?? 60
            return max(seconds, 10)
        }
        set {
            UserDefaults.standard.set(max(newValue, 10), forKey: Key.refreshIntervalSeconds)
        }
    }

    static var refreshInterval: Duration {
        .seconds(Double(refreshIntervalSeconds))
    }

    static var refreshIntervalLabel: String {
        CodexFormatting.compactDuration(seconds: refreshIntervalSeconds)
    }
}
#endif
