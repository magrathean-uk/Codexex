#if os(macOS)
import AppKit
import Foundation

enum CodexAppResetter {
    @MainActor
    static func resetAndQuit() {
        resetLocalData()
        NSApp.terminate(nil)
    }

    static func resetLocalData(
        defaults: UserDefaults = .standard,
        fileManager: FileManager = .default,
        applicationSupportURL: URL? = nil,
        bundleIdentifier: String? = Bundle.main.bundleIdentifier
    ) {
        if let bundleIdentifier {
            defaults.removePersistentDomain(forName: bundleIdentifier)
        }

        CodexAppSettings.removeAll(defaults: defaults)
        defaults.synchronize()

        let supportURL = applicationSupportURL ?? defaultApplicationSupportURL(fileManager: fileManager)
        try? fileManager.removeItem(at: supportURL)
    }

    private static func defaultApplicationSupportURL(fileManager: FileManager) -> URL {
        let root = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return root.appendingPathComponent("Codexex", isDirectory: true)
    }
}
#endif
