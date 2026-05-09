#if os(macOS)
import Foundation
import SwiftUI
import CodexMeterCore

enum PopupHistoryMode: String, CaseIterable {
    case dailyPeaks
    case thisCycle
    case monthly

    var title: String {
        switch self {
        case .dailyPeaks:
            return "Daily peaks"
        case .thisCycle:
            return "This cycle"
        case .monthly:
            return "Monthly"
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
            return CodexQuotaPresentationRules.resetText(style: .relative, now: now, resetAt: resetAt)
        case .absolute:
            return CodexQuotaPresentationRules.resetText(
                style: .absolute(prefix: "resets"),
                now: now,
                resetAt: resetAt
            )
        }
    }
}

enum CodexAppearanceMode: String, CaseIterable {
    case system
    case light
    case dark

    var title: String {
        switch self {
        case .system:
            return "System"
        case .light:
            return "Light"
        case .dark:
            return "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system:
            return nil
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }
}

enum CodexAppSettings {
    fileprivate enum Key {
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
        static let appearanceMode = "codexex.appearanceMode"
        static let defaultHistoryMode = "codexex.defaultHistoryMode"
        static let showPaceConfidence = "codexex.showPaceConfidence"
        static let hideIdleSecondaryLimits = "codexex.hideIdleSecondaryLimits"
        static let codexSessionsPath = "codexex.codexSessionsPath"
        static let summarySnoozeFingerprint = "codexex.summarySnoozeFingerprint"
        static let summarySnoozeExpiresAt = "codexex.summarySnoozeExpiresAt"

        static let all = [
            hasCompletedOnboarding,
            previewModeEnabled,
            autoRefreshEnabled,
            refreshIntervalSeconds,
            launchAtLoginEnabled,
            showHistoryEnabled,
            showHistoryChartEnabled,
            showInsightsEnabled,
            showSparkEnabled,
            showFiveHourInMenubar,
            showWeeklyInMenubar,
            menuBarDisplayMode,
            resetDisplayStyle,
            appearanceMode,
            defaultHistoryMode,
            showPaceConfidence,
            hideIdleSecondaryLimits,
            codexSessionsPath,
            summarySnoozeFingerprint,
            summarySnoozeExpiresAt
        ]
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
                return .remaining
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

    static var appearanceMode: CodexAppearanceMode {
        get {
            guard let rawValue = UserDefaults.standard.string(forKey: Key.appearanceMode),
                  let mode = CodexAppearanceMode(rawValue: rawValue) else {
                return .system
            }
            return mode
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: Key.appearanceMode)
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

    static var codexSessionsPath: String? {
        get { UserDefaults.standard.string(forKey: Key.codexSessionsPath) }
        set {
            if let newValue {
                UserDefaults.standard.set(newValue, forKey: Key.codexSessionsPath)
            } else {
                UserDefaults.standard.removeObject(forKey: Key.codexSessionsPath)
            }
        }
    }

    static var codexSessionsURL: URL {
        if let codexSessionsPath {
            return URL(fileURLWithPath: codexSessionsPath)
        }
        return CodexLocalUsageDirectoryReader.defaultSessionsURL()
    }

    static func removeAll(defaults: UserDefaults = .standard) {
        for key in Key.all {
            defaults.removeObject(forKey: key)
        }
    }
}

struct CodexAppSettingsSnapshot: Equatable {
    let hasCompletedOnboarding: Bool
    let previewModeEnabled: Bool
    let autoRefreshEnabled: Bool
    let refreshIntervalSeconds: Int
    let launchAtLoginEnabled: Bool
    let showHistoryEnabled: Bool
    let showHistoryChartEnabled: Bool
    let showInsightsEnabled: Bool
    let showSparkEnabled: Bool
    let showFiveHourInMenubar: Bool
    let showWeeklyInMenubar: Bool
    let menuBarDisplayMode: CodexMenuBarDisplayMode
    let resetDisplayStyle: CodexResetDisplayStyle
    let appearanceMode: CodexAppearanceMode
    let defaultHistoryMode: PopupHistoryMode
    let showPaceConfidence: Bool
    let hideIdleSecondaryLimits: Bool
    let codexSessionsPath: String?
    let summarySnoozeFingerprint: String?
    let summarySnoozeExpiresAt: Date?
}

struct CodexAppSettingsStore {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func snapshot() -> CodexAppSettingsSnapshot {
        CodexAppSettingsSnapshot(
            hasCompletedOnboarding: hasCompletedOnboarding,
            previewModeEnabled: previewModeEnabled,
            autoRefreshEnabled: autoRefreshEnabled,
            refreshIntervalSeconds: refreshIntervalSeconds,
            launchAtLoginEnabled: launchAtLoginEnabled,
            showHistoryEnabled: showHistoryEnabled,
            showHistoryChartEnabled: showHistoryChartEnabled,
            showInsightsEnabled: showInsightsEnabled,
            showSparkEnabled: showSparkEnabled,
            showFiveHourInMenubar: showFiveHourInMenubar,
            showWeeklyInMenubar: showWeeklyInMenubar,
            menuBarDisplayMode: menuBarDisplayMode,
            resetDisplayStyle: resetDisplayStyle,
            appearanceMode: appearanceMode,
            defaultHistoryMode: defaultHistoryMode,
            showPaceConfidence: showPaceConfidence,
            hideIdleSecondaryLimits: hideIdleSecondaryLimits,
            codexSessionsPath: codexSessionsPath,
            summarySnoozeFingerprint: summarySnoozeFingerprint,
            summarySnoozeExpiresAt: summarySnoozeExpiresAt
        )
    }

    var hasCompletedOnboarding: Bool {
        defaults.bool(forKey: CodexAppSettings.Key.hasCompletedOnboarding)
    }

    var previewModeEnabled: Bool {
        bool(forKey: CodexAppSettings.Key.previewModeEnabled, defaultValue: false)
    }

    var autoRefreshEnabled: Bool {
        bool(forKey: CodexAppSettings.Key.autoRefreshEnabled, defaultValue: true)
    }

    var refreshIntervalSeconds: Int {
        max(defaults.object(forKey: CodexAppSettings.Key.refreshIntervalSeconds) as? Int ?? 300, 300)
    }

    var launchAtLoginEnabled: Bool {
        bool(forKey: CodexAppSettings.Key.launchAtLoginEnabled, defaultValue: false)
    }

    var showHistoryEnabled: Bool {
        bool(forKey: CodexAppSettings.Key.showHistoryEnabled, defaultValue: true)
    }

    var showHistoryChartEnabled: Bool {
        bool(forKey: CodexAppSettings.Key.showHistoryChartEnabled, defaultValue: true)
    }

    var showInsightsEnabled: Bool {
        bool(forKey: CodexAppSettings.Key.showInsightsEnabled, defaultValue: true)
    }

    var showSparkEnabled: Bool {
        bool(forKey: CodexAppSettings.Key.showSparkEnabled, defaultValue: true)
    }

    var showFiveHourInMenubar: Bool {
        bool(forKey: CodexAppSettings.Key.showFiveHourInMenubar, defaultValue: true)
    }

    var showWeeklyInMenubar: Bool {
        bool(forKey: CodexAppSettings.Key.showWeeklyInMenubar, defaultValue: true)
    }

    var codexSessionsPath: String? {
        defaults.string(forKey: CodexAppSettings.Key.codexSessionsPath)
    }

    var menuBarDisplayMode: CodexMenuBarDisplayMode {
        enumValue(
            forKey: CodexAppSettings.Key.menuBarDisplayMode,
            defaultValue: CodexMenuBarDisplayMode.remaining
        )
    }

    var resetDisplayStyle: CodexResetDisplayStyle {
        enumValue(
            forKey: CodexAppSettings.Key.resetDisplayStyle,
            defaultValue: CodexResetDisplayStyle.relative
        )
    }

    var appearanceMode: CodexAppearanceMode {
        enumValue(
            forKey: CodexAppSettings.Key.appearanceMode,
            defaultValue: CodexAppearanceMode.system
        )
    }

    var defaultHistoryMode: PopupHistoryMode {
        enumValue(
            forKey: CodexAppSettings.Key.defaultHistoryMode,
            defaultValue: PopupHistoryMode.dailyPeaks
        )
    }

    var showPaceConfidence: Bool {
        bool(forKey: CodexAppSettings.Key.showPaceConfidence, defaultValue: true)
    }

    var hideIdleSecondaryLimits: Bool {
        bool(forKey: CodexAppSettings.Key.hideIdleSecondaryLimits, defaultValue: false)
    }

    var summarySnoozeFingerprint: String? {
        defaults.string(forKey: CodexAppSettings.Key.summarySnoozeFingerprint)
    }

    var summarySnoozeExpiresAt: Date? {
        defaults.object(forKey: CodexAppSettings.Key.summarySnoozeExpiresAt) as? Date
    }

    func setHasCompletedOnboarding(_ value: Bool) {
        defaults.set(value, forKey: CodexAppSettings.Key.hasCompletedOnboarding)
    }

    func setPreviewModeEnabled(_ value: Bool) {
        defaults.set(value, forKey: CodexAppSettings.Key.previewModeEnabled)
    }

    func setAutoRefreshEnabled(_ value: Bool) {
        defaults.set(value, forKey: CodexAppSettings.Key.autoRefreshEnabled)
    }

    func setRefreshIntervalSeconds(_ value: Int) {
        defaults.set(max(value, 300), forKey: CodexAppSettings.Key.refreshIntervalSeconds)
    }

    func setLaunchAtLoginEnabled(_ value: Bool) {
        defaults.set(value, forKey: CodexAppSettings.Key.launchAtLoginEnabled)
    }

    func setShowHistoryEnabled(_ value: Bool) {
        defaults.set(value, forKey: CodexAppSettings.Key.showHistoryEnabled)
    }

    func setShowHistoryChartEnabled(_ value: Bool) {
        defaults.set(value, forKey: CodexAppSettings.Key.showHistoryChartEnabled)
    }

    func setShowInsightsEnabled(_ value: Bool) {
        defaults.set(value, forKey: CodexAppSettings.Key.showInsightsEnabled)
    }

    func setShowSparkEnabled(_ value: Bool) {
        defaults.set(value, forKey: CodexAppSettings.Key.showSparkEnabled)
    }

    func setShowFiveHourInMenubar(_ value: Bool) {
        defaults.set(value, forKey: CodexAppSettings.Key.showFiveHourInMenubar)
    }

    func setShowWeeklyInMenubar(_ value: Bool) {
        defaults.set(value, forKey: CodexAppSettings.Key.showWeeklyInMenubar)
    }

    func setMenuBarDisplayMode(_ value: CodexMenuBarDisplayMode) {
        defaults.set(value.rawValue, forKey: CodexAppSettings.Key.menuBarDisplayMode)
    }

    func setResetDisplayStyle(_ value: CodexResetDisplayStyle) {
        defaults.set(value.rawValue, forKey: CodexAppSettings.Key.resetDisplayStyle)
    }

    func setAppearanceMode(_ value: CodexAppearanceMode) {
        defaults.set(value.rawValue, forKey: CodexAppSettings.Key.appearanceMode)
    }

    func setDefaultHistoryMode(_ value: PopupHistoryMode) {
        defaults.set(value.rawValue, forKey: CodexAppSettings.Key.defaultHistoryMode)
    }

    func setShowPaceConfidence(_ value: Bool) {
        defaults.set(value, forKey: CodexAppSettings.Key.showPaceConfidence)
    }

    func setCodexSessionsPath(_ value: String?) {
        setOptional(value, forKey: CodexAppSettings.Key.codexSessionsPath)
    }

    func setHideIdleSecondaryLimits(_ value: Bool) {
        defaults.set(value, forKey: CodexAppSettings.Key.hideIdleSecondaryLimits)
    }

    func setSummarySnoozeFingerprint(_ value: String?) {
        setOptional(value, forKey: CodexAppSettings.Key.summarySnoozeFingerprint)
    }

    func setSummarySnoozeExpiresAt(_ value: Date?) {
        setOptional(value, forKey: CodexAppSettings.Key.summarySnoozeExpiresAt)
    }

    func clearSummarySnooze() {
        setSummarySnoozeFingerprint(nil)
        setSummarySnoozeExpiresAt(nil)
    }

    func removeAll() {
        for key in CodexAppSettings.Key.all {
            defaults.removeObject(forKey: key)
        }
    }

    private func bool(forKey key: String, defaultValue: Bool) -> Bool {
        if defaults.object(forKey: key) == nil {
            return defaultValue
        }
        return defaults.bool(forKey: key)
    }

    private func enumValue<Value: RawRepresentable>(
        forKey key: String,
        defaultValue: Value
    ) -> Value where Value.RawValue == String {
        guard let rawValue = defaults.string(forKey: key),
              let value = Value(rawValue: rawValue) else {
            return defaultValue
        }
        return value
    }

    private func setOptional(_ value: Any?, forKey key: String) {
        if let value {
            defaults.set(value, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }
}
#endif
