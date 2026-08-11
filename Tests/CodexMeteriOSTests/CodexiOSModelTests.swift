import XCTest
import CodexMeterCore
@testable import Codexex

@MainActor
final class CodexiOSModelTests: XCTestCase {
    func testPreviewDataUsesCurrentSparkDisplayName() {
        let snapshot = CodexiOSPreviewData.snapshot(now: Date(timeIntervalSince1970: 1_800_000_000))

        XCTAssertEqual(snapshot.sparkLimit?.displayName, "Spark")
    }

    func testIOSHistoryModesExcludeCycle() {
        XCTAssertEqual(CodexiOSHistoryMode.allCases.map(\.title), ["Peaks", "Month"])
        XCTAssertNil(CodexiOSHistoryMode(rawValue: "thisCycle"))
    }

    func testModelStartsByCheckingSavedAccount() {
        let model = CodexiOSModel(
            service: StubCodexiOSService(),
            defaults: makeDefaults(),
            openURLAction: { _ in },
            copyTextAction: { _ in }
        )

        XCTAssertTrue(model.isCheckingSavedAccount)
        XCTAssertFalse(model.isSignedIn)
        XCTAssertNil(model.snapshot)
        XCTAssertEqual(model.statusMessage, "Checking saved account.")
    }

    func testSignedInLaunchCompletesWithoutSignedOutInterimState() async {
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

        XCTAssertTrue(model.isCheckingSavedAccount)

        await model.start()

        XCTAssertFalse(model.isCheckingSavedAccount)
        XCTAssertTrue(model.isSignedIn)
        XCTAssertTrue(model.hasCompletedOnboarding)
        XCTAssertNotNil(model.snapshot)
        XCTAssertEqual(model.statusMessage, "Signed in.")
    }

    func testSignedOutLaunchOnlyShowsSignedOutAfterCheckFinishes() async {
        let service = StubCodexiOSService(
            fetchHandler: {
                CodexServiceSnapshotResponse(authMode: nil, snapshot: nil, errorMessage: "Not signed in.")
            }
        )
        let model = CodexiOSModel(
            service: service,
            defaults: makeDefaults(),
            openURLAction: { _ in },
            copyTextAction: { _ in }
        )

        await model.start()

        XCTAssertFalse(model.isCheckingSavedAccount)
        XCTAssertFalse(model.isSignedIn)
        XCTAssertFalse(model.hasCompletedOnboarding)
        XCTAssertNil(model.snapshot)
        XCTAssertEqual(model.statusMessage, "Not signed in.")
    }

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
        XCTAssertTrue(model.hasCompletedOnboarding)
        XCTAssertNil(model.snapshot)
    }

    func testRequestErrorsDoNotLeakRawResponseBody() async {
        let service = StubCodexiOSService(
            fetchHandler: {
                throw CodexiOSError.requestFailed(500)
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

    func testLaunchRecoversExistingActivityAndPreviewRefreshUpdatesIt() async {
        let defaults = makeDefaults()
        defaults.set(true, forKey: CodexiOSSettingsKeys.previewModeEnabled)
        let liveActivity = StubCodexiOSLiveActivityManager(
            state: .init(isAvailable: true, activityID: "existing")
        )
        let model = CodexiOSModel(
            service: StubCodexiOSService(),
            defaults: defaults,
            liveActivityManager: liveActivity,
            openURLAction: { _ in },
            copyTextAction: { _ in }
        )

        await model.start()

        XCTAssertTrue(model.hasCheckedLiveActivityAvailability)
        XCTAssertTrue(model.isLiveActivityAvailable)
        XCTAssertTrue(model.isLiveActivityRunning)
        XCTAssertEqual(model.liveActivityID, "existing")
        let launchCalls = await liveActivity.recordedCalls()
        XCTAssertEqual(launchCalls, [.recover, .update(showFiveHour: false)])

        await liveActivity.resetCalls()
        await model.refresh()

        let refreshCalls = await liveActivity.recordedCalls()
        XCTAssertEqual(refreshCalls, [.update(showFiveHour: false)])
        XCTAssertEqual(model.liveActivityID, "existing")
    }

    func testAuthorizationDeniedDoesNotClaimLiveActivityStarted() async {
        let defaults = makeDefaults()
        defaults.set(true, forKey: CodexiOSSettingsKeys.previewModeEnabled)
        let unavailable = CodexiOSLiveActivityRuntimeState(
            isAvailable: false,
            activityID: nil
        )
        let liveActivity = StubCodexiOSLiveActivityManager(
            state: unavailable,
            startState: unavailable
        )
        let model = CodexiOSModel(
            service: StubCodexiOSService(),
            defaults: defaults,
            liveActivityManager: liveActivity,
            openURLAction: { _ in },
            copyTextAction: { _ in }
        )
        await model.start()
        await liveActivity.resetCalls()

        await model.startLiveActivity()

        XCTAssertFalse(model.isLiveActivityAvailable)
        XCTAssertFalse(model.isLiveActivityRunning)
        XCTAssertNil(model.liveActivityID)
        let startCalls = await liveActivity.recordedCalls()
        XCTAssertEqual(startCalls, [.start(showFiveHour: false)])
        XCTAssertEqual(model.statusMessage, "Live Activities are unavailable on this device.")
    }

    func testRapidStartRequestsAreSerialized() async {
        let defaults = makeDefaults()
        defaults.set(true, forKey: CodexiOSSettingsKeys.previewModeEnabled)
        let liveActivity = StubCodexiOSLiveActivityManager(
            state: .init(isAvailable: true, activityID: nil),
            startState: .init(isAvailable: true, activityID: "started"),
            startDelay: .milliseconds(100)
        )
        let model = CodexiOSModel(
            service: StubCodexiOSService(),
            defaults: defaults,
            liveActivityManager: liveActivity,
            openURLAction: { _ in },
            copyTextAction: { _ in }
        )
        await model.start()
        await liveActivity.resetCalls()

        let firstStart = Task { @MainActor in
            await model.startLiveActivity()
        }
        while model.isLiveActivityTransitioning == false {
            await Task.yield()
        }

        await model.startLiveActivity()
        await firstStart.value

        let calls = await liveActivity.recordedCalls()
        XCTAssertEqual(calls, [.start(showFiveHour: false)])
        XCTAssertFalse(model.isLiveActivityTransitioning)
        XCTAssertTrue(model.isLiveActivityRunning)
        XCTAssertEqual(model.liveActivityID, "started")
    }

    func testSuccessfulRefreshUpdatesSameRecoveredActivity() async {
        let snapshot = CodexiOSPreviewData.snapshot()
        let service = StubCodexiOSService(
            fetchHandler: {
                CodexServiceSnapshotResponse(
                    authMode: .chatGPT,
                    snapshot: snapshot,
                    errorMessage: nil
                )
            }
        )
        let liveActivity = StubCodexiOSLiveActivityManager(
            state: .init(isAvailable: true, activityID: "same-id")
        )
        let model = CodexiOSModel(
            service: service,
            defaults: makeDefaults(),
            liveActivityManager: liveActivity,
            openURLAction: { _ in },
            copyTextAction: { _ in }
        )

        await model.refresh()

        let calls = await liveActivity.recordedCalls()
        XCTAssertEqual(calls, [.update(showFiveHour: false)])
        XCTAssertTrue(model.isLiveActivityRunning)
        XCTAssertEqual(model.liveActivityID, "same-id")
    }

    func testTransientRefreshMarksActivityStaleAndKeepsLastGoodSnapshot() async {
        let liveActivity = StubCodexiOSLiveActivityManager(
            state: .init(isAvailable: true, activityID: "same-id")
        )
        let model = CodexiOSModel(
            service: StubCodexiOSService(fetchHandler: {
                throw CodexiOSError.requestFailed(500)
            }),
            defaults: makeDefaults(),
            liveActivityManager: liveActivity,
            openURLAction: { _ in },
            copyTextAction: { _ in }
        )
        let lastGood = CodexiOSPreviewData.snapshot()
        model.snapshot = lastGood

        await model.refresh()

        XCTAssertEqual(model.snapshot, lastGood)
        let calls = await liveActivity.recordedCalls()
        XCTAssertEqual(calls, [.markStale(showFiveHour: false)])
        XCTAssertTrue(model.isLiveActivityRunning)
        XCTAssertEqual(model.liveActivityID, "same-id")
    }

    func testRefreshDiscoveredAuthLossEndsActivity() async {
        let liveActivity = StubCodexiOSLiveActivityManager(
            state: .init(isAvailable: true, activityID: "existing")
        )
        let model = CodexiOSModel(
            service: StubCodexiOSService(fetchHandler: {
                CodexServiceSnapshotResponse(
                    authMode: nil,
                    snapshot: nil,
                    errorMessage: "Not signed in."
                )
            }),
            defaults: makeDefaults(),
            liveActivityManager: liveActivity,
            openURLAction: { _ in },
            copyTextAction: { _ in }
        )
        model.snapshot = CodexiOSPreviewData.snapshot()

        await model.refresh()

        let calls = await liveActivity.recordedCalls()
        XCTAssertEqual(calls, [.stop])
        XCTAssertFalse(model.isLiveActivityRunning)
        XCTAssertNil(model.snapshot)
    }

    func testExplicitSignOutEndsActivityEvenWhenServiceFails() async {
        let liveActivity = StubCodexiOSLiveActivityManager(
            state: .init(isAvailable: true, activityID: "existing")
        )
        let model = CodexiOSModel(
            service: StubCodexiOSService(signOutHandler: {
                throw CodexiOSError.requestFailed(500)
            }),
            defaults: makeDefaults(),
            liveActivityManager: liveActivity,
            openURLAction: { _ in },
            copyTextAction: { _ in }
        )

        await model.signOut()

        let calls = await liveActivity.recordedCalls()
        XCTAssertEqual(calls, [.stop])
        XCTAssertFalse(model.isLiveActivityRunning)
        XCTAssertEqual(model.errorMessage, "OpenAI is having trouble right now. Try again soon.")
    }

    func testSignOutWinsOverAnInFlightStart() async {
        let defaults = makeDefaults()
        defaults.set(true, forKey: CodexiOSSettingsKeys.previewModeEnabled)
        let liveActivity = StubCodexiOSLiveActivityManager(
            state: .init(isAvailable: true, activityID: nil),
            startState: .init(isAvailable: true, activityID: "orphan"),
            startDelay: .milliseconds(100)
        )
        let model = CodexiOSModel(
            service: StubCodexiOSService(),
            defaults: defaults,
            liveActivityManager: liveActivity,
            openURLAction: { _ in },
            copyTextAction: { _ in }
        )
        await model.start()
        await liveActivity.resetCalls()

        let startTask = Task { @MainActor in
            await model.startLiveActivity()
        }
        while model.isLiveActivityTransitioning == false {
            await Task.yield()
        }
        let signOutTask = Task { @MainActor in
            await model.signOut()
        }
        await startTask.value
        await signOutTask.value

        XCTAssertFalse(model.isLiveActivityRunning)
        XCTAssertNil(model.liveActivityID)
        XCTAssertEqual(model.liveAccountState, .signedOut)
        let calls = await liveActivity.recordedCalls()
        XCTAssertTrue(calls.contains(.stop))
    }

    func testDisablingPreviewEndsExistingActivityBeforeRefreshing() async {
        let defaults = makeDefaults()
        defaults.set(true, forKey: CodexiOSSettingsKeys.previewModeEnabled)
        let liveActivity = StubCodexiOSLiveActivityManager(
            state: .init(isAvailable: true, activityID: "preview")
        )
        let model = CodexiOSModel(
            service: StubCodexiOSService(),
            defaults: defaults,
            liveActivityManager: liveActivity,
            openURLAction: { _ in },
            copyTextAction: { _ in }
        )
        await model.start()
        await liveActivity.resetCalls()

        model.disablePreviewMode()
        while model.isLiveActivityTransitioning {
            await Task.yield()
        }
        await Task.yield()

        XCTAssertFalse(model.previewModeEnabled)
        XCTAssertFalse(model.isLiveActivityRunning)
        let calls = await liveActivity.recordedCalls()
        XCTAssertEqual(calls.first, .stop)
    }

    func testStaleActivityStaysStaleWhenFiveHourPresentationChanges() async {
        let defaults = makeDefaults()
        let sequence = FetchSequence([
            .success(CodexiOSPreviewData.snapshot()),
            .failure(500)
        ])
        let liveActivity = StubCodexiOSLiveActivityManager(
            state: .init(isAvailable: true, activityID: "stale")
        )
        let model = CodexiOSModel(
            service: StubCodexiOSService(fetchHandler: {
                try await sequence.next()
            }),
            defaults: defaults,
            liveActivityManager: liveActivity,
            openURLAction: { _ in },
            copyTextAction: { _ in }
        )
        await model.start()
        await liveActivity.resetCalls()

        await model.refresh()
        await liveActivity.resetCalls()

        await model.updateLiveActivityPresentation(showFiveHour: true)

        XCTAssertTrue(model.isLiveActivityStale)
        let calls = await liveActivity.recordedCalls()
        XCTAssertEqual(calls, [.markStale(showFiveHour: true)])
    }

    func testUsedQuotaPresentationUpdatesRunningLiveActivityImmediately() async {
        let defaults = makeDefaults()
        defaults.set(true, forKey: CodexiOSSettingsKeys.previewModeEnabled)
        let liveActivity = StubCodexiOSLiveActivityManager(
            state: .init(isAvailable: true, activityID: "existing")
        )
        let model = CodexiOSModel(
            service: StubCodexiOSService(),
            defaults: defaults,
            liveActivityManager: liveActivity,
            openURLAction: { _ in },
            copyTextAction: { _ in }
        )
        await model.start()
        await liveActivity.resetCalls()

        await model.updateLiveActivityPresentation(showFiveHour: false, showUsedQuota: true)

        XCTAssertTrue(model.isLiveActivityRunning)
        let calls = await liveActivity.recordedCalls()
        let showUsedQuotaValues = await liveActivity.recordedShowUsedQuota()
        XCTAssertEqual(calls, [.update(showFiveHour: false)])
        XCTAssertEqual(showUsedQuotaValues, [true])
    }

    func testBackgroundRefreshUpdatesRecoveredLiveActivity() async {
        let service = StubCodexiOSService(
            fetchHandler: {
                CodexServiceSnapshotResponse(
                    authMode: .chatGPT,
                    snapshot: CodexiOSPreviewData.snapshot(),
                    errorMessage: nil
                )
            }
        )
        let liveActivity = StubCodexiOSLiveActivityManager(
            state: .init(isAvailable: true, activityID: "existing")
        )
        let model = CodexiOSModel(
            service: service,
            defaults: makeDefaults(),
            liveActivityManager: liveActivity,
            openURLAction: { _ in },
            copyTextAction: { _ in }
        )

        let didRefresh = await model.refreshLiveActivityInBackground()
        let fetchCount = await service.fetchCallCount()
        let calls = await liveActivity.recordedCalls()

        XCTAssertTrue(didRefresh)
        XCTAssertEqual(fetchCount, 1)
        XCTAssertEqual(calls, [.recover, .update(showFiveHour: false)])
        XCTAssertTrue(model.isLiveActivityRunning)
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

actor StubCodexiOSLiveActivityManager: CodexiOSLiveActivityManaging {
    enum Call: Equatable, Sendable {
        case recover
        case start(showFiveHour: Bool)
        case update(showFiveHour: Bool)
        case markStale(showFiveHour: Bool)
        case stop
    }

    private var state: CodexiOSLiveActivityRuntimeState
    private let startState: CodexiOSLiveActivityRuntimeState
    private let startDelay: Duration?
    private var calls: [Call] = []
    private var showUsedQuotaValues: [Bool] = []

    init(
        state: CodexiOSLiveActivityRuntimeState,
        startState: CodexiOSLiveActivityRuntimeState? = nil,
        startDelay: Duration? = nil
    ) {
        self.state = state
        self.startState = startState ?? state
        self.startDelay = startDelay
    }

    func recover() async -> CodexiOSLiveActivityRuntimeState {
        calls.append(.recover)
        return state
    }

    func start(
        snapshot: CodexSnapshot,
        showFiveHour: Bool,
        showUsedQuota: Bool,
        cadence: TimeInterval
    ) async throws -> CodexiOSLiveActivityRuntimeState {
        calls.append(.start(showFiveHour: showFiveHour))
        showUsedQuotaValues.append(showUsedQuota)
        if let startDelay {
            try? await Task.sleep(for: startDelay)
        }
        state = startState
        return state
    }

    func update(
        snapshot: CodexSnapshot,
        showFiveHour: Bool,
        showUsedQuota: Bool,
        cadence: TimeInterval
    ) async -> CodexiOSLiveActivityRuntimeState {
        calls.append(.update(showFiveHour: showFiveHour))
        showUsedQuotaValues.append(showUsedQuota)
        return state
    }

    func markStale(
        snapshot: CodexSnapshot,
        showFiveHour: Bool,
        showUsedQuota: Bool,
        cadence: TimeInterval
    ) async -> CodexiOSLiveActivityRuntimeState {
        calls.append(.markStale(showFiveHour: showFiveHour))
        showUsedQuotaValues.append(showUsedQuota)
        return state
    }

    func stop() async -> CodexiOSLiveActivityRuntimeState {
        calls.append(.stop)
        state = CodexiOSLiveActivityRuntimeState(
            isAvailable: state.isAvailable,
            activityID: nil
        )
        return state
    }

    func resetCalls() {
        calls = []
        showUsedQuotaValues = []
    }

    func recordedCalls() -> [Call] {
        calls
    }

    func recordedShowUsedQuota() -> [Bool] {
        showUsedQuotaValues
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

actor FetchSequence {
    enum Result: Sendable {
        case success(CodexSnapshot)
        case failure(Int)
    }

    private var results: [Result]

    init(_ results: [Result]) {
        self.results = results
    }

    func next() throws -> CodexServiceSnapshotResponse {
        let result = results.isEmpty ? .failure(500) : results.removeFirst()
        switch result {
        case .success(let snapshot):
            return CodexServiceSnapshotResponse(
                authMode: .chatGPT,
                snapshot: snapshot,
                errorMessage: nil
            )
        case .failure(let status):
            throw CodexiOSError.requestFailed(status)
        }
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
