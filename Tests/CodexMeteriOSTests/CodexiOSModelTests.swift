import XCTest
import CodexMeterCore
@testable import Codexex

@MainActor
final class CodexiOSModelTests: XCTestCase {
    func testPreviewModeSkipsLiveRefreshOnStart() async {
        let service = StubCodexiOSService(
            fetchHandler: {
                CodexServiceSnapshotResponse(authMode: .chatGPT, snapshot: CodexiOSPreviewData.snapshot(), errorMessage: nil)
            }
        )
        let defaults = makeDefaults()
        let model = CodexiOSModel(
            service: service,
            defaults: defaults,
            openURLAction: { _ in },
            copyTextAction: { _ in }
        )

        model.enablePreviewMode()
        await model.start()
        let fetchCount = await service.fetchCallCount()

        XCTAssertNotNil(model.snapshot)
        XCTAssertFalse(model.isSignedIn)
        XCTAssertTrue(model.hasCompletedOnboarding)
        XCTAssertTrue(defaults.bool(forKey: CodexiOSSettingsKeys.hasCompletedOnboarding))
        XCTAssertTrue(defaults.bool(forKey: CodexiOSSettingsKeys.previewModeEnabled))
        XCTAssertEqual(fetchCount, 0)
    }

    func testSceneReturnChecksPendingSignInAndCompletesOnboarding() async {
        let url = URL(string: "https://auth.openai.com/codex/device")!
        let recorder = URLRecorder()
        let copyRecorder = CopyRecorder()
        let service = StubCodexiOSService(
            fetchHandler: {
                CodexServiceSnapshotResponse(authMode: .chatGPT, snapshot: CodexiOSPreviewData.snapshot(), errorMessage: nil)
            },
            beginHandler: {
                CodexiOSDeviceAuthStart(flowID: "flow-1", verificationURL: url, userCode: "ABCD-1234")
            },
            pollHandler: { _ in
                .signedIn
            }
        )
        let model = CodexiOSModel(
            service: service,
            defaults: makeDefaults(),
            openURLAction: { url in
                await recorder.record(url)
            },
            copyTextAction: { text in
                copyRecorder.record(text)
            }
        )

        await model.beginSignIn()
        let openedURLs = await recorder.urls()
        let copiedValues = copyRecorder.values
        XCTAssertTrue(model.hasPendingSignIn)
        XCTAssertEqual(model.deviceCode, "ABCD-1234")
        XCTAssertEqual(copiedValues, ["ABCD-1234"])
        XCTAssertEqual(model.statusMessage, "Device code copied. Paste it in Safari.")
        XCTAssertEqual(openedURLs, [])

        await model.openSignInPage()
        let openedSignInURLs = await recorder.urls()
        XCTAssertEqual(openedSignInURLs, [url])

        await model.handleSceneDidBecomeActive(
            autoCheckSignInOnReturn: true,
            refreshWhenActive: false
        )
        let pollCount = await service.pollCallCount()
        let fetchCount = await service.fetchCallCount()

        XCTAssertTrue(model.isSignedIn)
        XCTAssertTrue(model.hasCompletedOnboarding)
        XCTAssertFalse(model.hasPendingSignIn)
        XCTAssertNotNil(model.snapshot)
        XCTAssertEqual(pollCount, 1)
        XCTAssertEqual(fetchCount, 1)
    }

    func testSignInAfterLeavingPreviewShowsAndCopiesDeviceCode() async {
        let url = URL(string: "https://auth.openai.com/codex/device")!
        let copyRecorder = CopyRecorder()
        let defaults = makeDefaults()
        let service = StubCodexiOSService(
            beginHandler: {
                CodexiOSDeviceAuthStart(flowID: "flow-2", verificationURL: url, userCode: "WXYZ-9876")
            }
        )
        let model = CodexiOSModel(
            service: service,
            defaults: defaults,
            openURLAction: { _ in },
            copyTextAction: { text in
                copyRecorder.record(text)
            }
        )

        model.enablePreviewMode()
        model.disablePreviewMode()
        await model.beginSignIn()

        XCTAssertFalse(model.previewModeEnabled)
        XCTAssertTrue(model.hasPendingSignIn)
        XCTAssertEqual(model.deviceCode, "WXYZ-9876")
        XCTAssertEqual(copyRecorder.values, ["WXYZ-9876"])
        XCTAssertEqual(model.statusMessage, "Device code copied. Paste it in Safari.")
    }

    func testRefreshUsesAuthModeInsteadOfStatusText() async {
        let service = StubCodexiOSService(
            fetchHandler: {
                CodexServiceSnapshotResponse(
                    authMode: .chatGPT,
                    snapshot: nil,
                    errorMessage: "OpenAI is rate-limiting requests. Try again soon."
                )
            }
        )
        let model = CodexiOSModel(
            service: service,
            defaults: makeDefaults(),
            openURLAction: { _ in },
            copyTextAction: { _ in }
        )

        await model.refresh()

        XCTAssertTrue(model.isSignedIn)
        XCTAssertEqual(model.statusMessage, "OpenAI is rate-limiting requests. Try again soon.")
        XCTAssertNil(model.snapshot)
    }

    func testRequestErrorsDoNotLeakRawResponseBody() async {
        let service = StubCodexiOSService(
            fetchHandler: {
                throw CodexiOSError.requestFailed(500, #"{"access_token":"secret"}"#)
            }
        )
        let model = CodexiOSModel(
            service: service,
            defaults: makeDefaults(),
            openURLAction: { _ in },
            copyTextAction: { _ in }
        )

        await model.refresh()

        XCTAssertEqual(model.errorMessage, "OpenAI is having trouble right now. Try again soon.")
        XCTAssertEqual(model.statusMessage, "OpenAI is having trouble right now. Try again soon.")
        XCTAssertFalse(model.statusMessage.contains("access_token"))
    }

    func testResetLocalDataClearsIOSSettings() {
        let defaults = makeDefaults()
        defaults.set(true, forKey: CodexiOSSettingsKeys.hasCompletedOnboarding)
        defaults.set(true, forKey: CodexiOSSettingsKeys.previewModeEnabled)
        defaults.set(600, forKey: CodexiOSSettingsKeys.refreshIntervalSeconds)

        CodexiOSAppResetter.resetLocalData(defaults: defaults, clearTokens: {})

        XCTAssertNil(defaults.object(forKey: CodexiOSSettingsKeys.hasCompletedOnboarding))
        XCTAssertNil(defaults.object(forKey: CodexiOSSettingsKeys.previewModeEnabled))
        XCTAssertNil(defaults.object(forKey: CodexiOSSettingsKeys.refreshIntervalSeconds))
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "CodexiOSModelTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}

actor StubCodexiOSService: CodexiOSServiceProtocol {
    typealias FetchHandler = @Sendable () async throws -> CodexServiceSnapshotResponse
    typealias BeginHandler = @Sendable () async throws -> CodexiOSDeviceAuthStart
    typealias PollHandler = @Sendable (String) async throws -> CodexiOSPollResult
    typealias SignOutHandler = @Sendable () async throws -> Void

    private let fetchHandler: FetchHandler
    private let beginHandler: BeginHandler
    private let pollHandler: PollHandler
    private let signOutHandler: SignOutHandler

    private var fetchCount = 0
    private var pollCount = 0

    init(
        fetchHandler: @escaping FetchHandler = {
            CodexServiceSnapshotResponse(authMode: nil, snapshot: nil, errorMessage: nil)
        },
        beginHandler: @escaping BeginHandler = {
            CodexiOSDeviceAuthStart(
                flowID: "flow-default",
                verificationURL: URL(string: "https://auth.openai.com/codex/device")!,
                userCode: "CODE-0000"
            )
        },
        pollHandler: @escaping PollHandler = { _ in
            .pending("Still waiting. Finish in Safari, then check again.")
        },
        signOutHandler: @escaping SignOutHandler = {}
    ) {
        self.fetchHandler = fetchHandler
        self.beginHandler = beginHandler
        self.pollHandler = pollHandler
        self.signOutHandler = signOutHandler
    }

    func fetchSnapshot() async throws -> CodexServiceSnapshotResponse {
        fetchCount += 1
        return try await fetchHandler()
    }

    func beginSignIn() async throws -> CodexiOSDeviceAuthStart {
        try await beginHandler()
    }

    func pollSignIn(flowID: String) async throws -> CodexiOSPollResult {
        pollCount += 1
        return try await pollHandler(flowID)
    }

    func signOut() async throws {
        try await signOutHandler()
    }

    func fetchCallCount() -> Int {
        fetchCount
    }

    func pollCallCount() -> Int {
        pollCount
    }
}

actor URLRecorder {
    private var values: [URL] = []

    func record(_ url: URL) {
        values.append(url)
    }

    func urls() -> [URL] {
        values
    }
}

@MainActor
final class CopyRecorder {
    private(set) var values: [String] = []

    func record(_ value: String) {
        values.append(value)
    }
}
