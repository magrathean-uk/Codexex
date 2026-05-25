#if os(macOS)
import Foundation

enum CodexAppLinks {
    static let termsURL = URL(string: "https://codexex.eu/terms/")!
    static let privacyURL = URL(string: "https://codexex.eu/privacy/")!
    static let releaseNotesURL = URL(string: "https://codexex.eu/")!
    static let manageSubscriptionURL = URL(string: "https://chatgpt.com/#settings/Subscription")!
    static let appStoreURL = URL(string: "macappstore://apps.apple.com/app/id6762058457")!
}
#endif
