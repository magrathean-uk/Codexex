#if os(macOS)
import Foundation

enum CodexAppLinks {
    static let termsURL = URL(string: "https://magrathean.uk/apps/codexex/terms/")!
    static let privacyURL = URL(string: "https://magrathean.uk/apps/codexex/privacy/")!
    static let releaseNotesURL = URL(string: "https://magrathean.uk/apps/codexex/release-notes/")!
    static let manageSubscriptionURL = URL(string: "https://chatgpt.com/#settings/Subscription")!
    static let appStoreURL = URL(string: "macappstore://apps.apple.com/app/id6762058457")!
}
#endif
