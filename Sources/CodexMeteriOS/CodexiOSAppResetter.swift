import Foundation
import UIKit

enum CodexiOSAppResetter {
    static func resetAndClose(defaults: UserDefaults = .standard, tokenStore: CodexiOSTokenStore = CodexiOSTokenStore()) {
        resetLocalData(defaults: defaults) {
            try tokenStore.clear()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            exit(0)
        }
    }

    static func resetLocalData(
        defaults: UserDefaults = .standard,
        clearTokens: () throws -> Void = {
            try CodexiOSTokenStore().clear()
        }
    ) {
        if let bundleIdentifier = Bundle.main.bundleIdentifier {
            defaults.removePersistentDomain(forName: bundleIdentifier)
        }

        for key in CodexiOSSettingsKeys.all {
            defaults.removeObject(forKey: key)
        }
        defaults.synchronize()
        try? clearTokens()
    }
}
