#if os(macOS)
import AppKit
import Foundation

struct CodexAppResetResult: Equatable {
    let errors: [String]

    var succeeded: Bool { errors.isEmpty }
    var message: String { errors.joined(separator: " ") }

    static let success = CodexAppResetResult(errors: [])
}

enum CodexAppResetter {
    @discardableResult
    @MainActor
    static func resetAndQuit(
        disableLaunchAtLogin: () -> CodexLaunchAtLoginChangeResult = {
            CodexLaunchAtLoginManager.isEnabled
                ? CodexLaunchAtLoginManager.setEnabled(false)
                : CodexLaunchAtLoginChangeResult(isEnabled: false, errorMessage: nil)
        },
        resetData: () -> CodexAppResetResult = { resetLocalData() },
        terminate: () -> Void = { NSApp.terminate(nil) }
    ) -> CodexAppResetResult {
        let launchResult = disableLaunchAtLogin()
        var errors: [String] = []
        if launchResult.isEnabled {
            errors.append("Launch at login is still enabled.")
        }
        if let errorMessage = launchResult.errorMessage {
            errors.append("Could not disable launch at login: \(errorMessage)")
        }
        errors.append(contentsOf: resetData().errors)

        let result = CodexAppResetResult(errors: errors)
        if result.succeeded {
            terminate()
        }
        return result
    }

    @discardableResult
    static func resetLocalData(
        defaults: UserDefaults = .standard,
        fileManager: FileManager = .default,
        applicationSupportURL: URL? = nil,
        bundleIdentifier: String? = Bundle.main.bundleIdentifier,
        removeItem: ((URL) throws -> Void)? = nil
    ) -> CodexAppResetResult {
        var errors: [String] = []
        if let bundleIdentifier {
            defaults.removePersistentDomain(forName: bundleIdentifier)
        }

        CodexAppSettings.removeAll(defaults: defaults)
        if defaults.synchronize() == false {
            errors.append("Settings could not be flushed.")
        }

        let supportURL = applicationSupportURL ?? defaultApplicationSupportURL(fileManager: fileManager)
        if fileManager.fileExists(atPath: supportURL.path) {
            do {
                if let removeItem {
                    try removeItem(supportURL)
                } else {
                    try fileManager.removeItem(at: supportURL)
                }
            } catch {
                errors.append("Application data could not be deleted: \(error.localizedDescription)")
            }
        }
        return CodexAppResetResult(errors: errors)
    }

    private static func defaultApplicationSupportURL(fileManager: FileManager) -> URL {
        let root = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return root.appendingPathComponent("Codexex", isDirectory: true)
    }
}
#endif
