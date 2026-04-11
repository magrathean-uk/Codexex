#if os(macOS)
import ServiceManagement

struct CodexLaunchAtLoginChangeResult {
    let isEnabled: Bool
    let errorMessage: String?
}

enum CodexLaunchAtLoginManager {
    @discardableResult
    static func setEnabled(_ enabled: Bool) -> CodexLaunchAtLoginChangeResult {
        var errorMessage: String?

        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        let actual = isEnabled
        CodexAppSettings.launchAtLoginEnabled = actual
        return CodexLaunchAtLoginChangeResult(isEnabled: actual, errorMessage: errorMessage)
    }

    @discardableResult
    static func syncStoredState() -> Bool {
        let actual = isEnabled
        CodexAppSettings.launchAtLoginEnabled = actual
        return actual
    }

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }
}
#endif
