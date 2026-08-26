import Foundation

enum CodexiOSAppResetter {
    static func resetLocalData(
        defaults: UserDefaults = .standard,
        clearTokens: () throws -> Void = {
            try CodexiOSTokenStore().clear()
        },
        clearPendingAuth: () throws -> Void = {
            try CodexiOSPendingAuthStore().clear()
        },
        clearHistory: () throws -> Void = {}
    ) throws {
        var failures: [String] = []
        do { try clearTokens() } catch { failures.append(error.localizedDescription) }
        do { try clearPendingAuth() } catch { failures.append(error.localizedDescription) }
        do { try clearHistory() } catch { failures.append(error.localizedDescription) }

        if let bundleIdentifier = Bundle.main.bundleIdentifier {
            defaults.removePersistentDomain(forName: bundleIdentifier)
        }

        for key in CodexiOSSettingsKeys.all {
            defaults.removeObject(forKey: key)
        }
        defaults.synchronize()

        guard failures.isEmpty else {
            throw CodexiOSError.secureStoreFailure(
                "Some local data could not be deleted. \(failures.joined(separator: " "))"
            )
        }
    }
}
