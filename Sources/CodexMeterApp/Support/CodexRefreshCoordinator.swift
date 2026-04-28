#if os(macOS)
import Foundation

@MainActor
final class CodexRefreshCoordinator {
    private var generation = 0

    func token() -> Int {
        generation
    }

    func invalidate(cancel: () -> Void = {}) {
        generation += 1
        cancel()
    }

    func isCurrent(_ token: Int) -> Bool {
        generation == token
    }
}
#endif
