#if os(macOS)
import SwiftUI

enum CodexDesignToneAdditions {
    static let badgeHeight: CGFloat = 22
    static let badgeHorizontalPadding: CGFloat = 8
    static let calloutSpacing: CGFloat = 12
    static let compactAnimationDuration: Double = 0.12
    static let stateAnimationDuration: Double = 0.18
}

extension CodexMenuBarModel {
    var designStateBadgeKind: CodexStateBadgeKind {
        if previewModeEnabled { return .preview }
        if lastError != nil { return snapshot == nil ? .error : .stale }
        if authDeviceCode != nil || isSigningIn { return .waiting }
        if isDataStale { return .stale }
        return .live
    }
}
#endif
