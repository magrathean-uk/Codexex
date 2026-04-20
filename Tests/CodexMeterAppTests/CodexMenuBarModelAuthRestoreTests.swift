import XCTest
@testable import CodexMeterApp
@testable import CodexMeterCore

@MainActor
final class CodexMenuBarModelAuthRestoreTests: XCTestCase {
    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: "codexex.previewModeEnabled")
    }

    func testRefreshFailureDoesNotResolveAuthToSignedOut() async {
        let model = CodexMenuBarModel(service: FailingService())

        await model.refreshNow()

        XCTAssertFalse(model.hasResolvedAuthState)
        XCTAssertFalse(model.isSignedIn)
        XCTAssertEqual(model.lastError, "network down")
        XCTAssertEqual(model.authStatusMessage, "Ready.")
    }
}

private struct FailingService: CodexServiceClient {
    func fetchSnapshotResponse() async throws -> CodexServiceSnapshotResponse {
        throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "network down"])
    }

    func beginChatGPTSignIn() async throws -> CodexDeviceAuthStart {
        fatalError("unused")
    }

    func completeChatGPTSignIn(flowID: String) async throws -> CodexDeviceAuthPollResult {
        fatalError("unused")
    }

    func signOut() async throws {
        fatalError("unused")
    }
}
