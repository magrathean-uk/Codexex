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
            openURLAction: { _ in true },
            copyTextAction: { _ in }
        )

        XCTAssertTrue(model.isCheckingSavedAccount)
        XCTAssertFalse(model.isSignedIn)
        XCTAssertNil(model.snapshot)
        XCTAssertEqual(model.statusMessage, "Checking saved account.")
    }

    func testStoredPreviewModeIsSeededBeforeAsynchronousStart() {
        let defaults = makeDefaults()
        defaults.set(true, forKey: CodexiOSSettingsKeys.hasCompletedOnboarding)
        defaults.set(true, forKey: CodexiOSSettingsKeys.previewModeEnabled)

        let model = CodexiOSModel(
            service: StubCodexiOSService(),
            defaults: defaults,
            openURLAction: { _ in true },
            copyTextAction: { _ in }
        )

        XCTAssertTrue(model.previewModeEnabled)
        XCTAssertNotNil(model.snapshot)
        XCTAssertNotNil(model.lastUpdatedAt)
        XCTAssertFalse(model.usageHistory.isEmpty)
        XCTAssertEqual(model.statusMessage, "Preview mode is active.")
    }

    func testExpiredPendingSignInOnLaunchReturnsToSignedOutRecovery() async {
        let service = StubCodexiOSService(
            recoverHandler: { throw CodexiOSError.signInExpired }
        )
        let model = CodexiOSModel(
            service: service,
            defaults: makeDefaults(),
            openURLAction: { _ in true },
            copyTextAction: { _ in }
        )

        await model.start()
        let fetchCount = await service.fetchCallCount()

        XCTAssertEqual(model.liveAccountState, .signedOut)
        XCTAssertNil(model.errorMessage)
        XCTAssertFalse(model.canAutoRefresh)
        XCTAssertEqual(model.statusMessage, "Sign-in code expired. Start again.")
        XCTAssertEqual(fetchCount, 0)
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
            openURLAction: { _ in true },
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
            openURLAction: { _ in true },
            copyTextAction: { _ in }
        )

        await model.start()

        XCTAssertFalse(model.isCheckingSavedAccount)
        XCTAssertFalse(model.isSignedIn)
        XCTAssertFalse(model.hasCompletedOnboarding)
        XCTAssertNil(model.snapshot)
        XCTAssertEqual(model.statusMessage, "Sign in with ChatGPT to read your Codex quota.")
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
            openURLAction: { _ in true },
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
                return true
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
        XCTAssertEqual(copiedValues, [])
        XCTAssertEqual(model.statusMessage, "Safari opened. Enter the device code to continue.")
        XCTAssertEqual(openedURLs, [url])

        await model.openSignInPage()
        let openedSignInURLs = await recorder.urls()
        XCTAssertEqual(openedSignInURLs, [url, url])

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
            openURLAction: { _ in true },
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
        XCTAssertEqual(copyRecorder.values, [])
        XCTAssertEqual(model.statusMessage, "Safari opened. Enter the device code to continue.")
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
            openURLAction: { _ in true },
            copyTextAction: { _ in }
        )

        await model.refresh()

        XCTAssertFalse(model.isSignedIn)
        XCTAssertEqual(model.liveAccountState, .unavailable)
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
            openURLAction: { _ in true },
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
            openURLAction: { _ in true },
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
            openURLAction: { _ in true },
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
            openURLAction: { _ in true },
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
            openURLAction: { _ in true },
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
            openURLAction: { _ in true },
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
            openURLAction: { _ in true },
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
            openURLAction: { _ in true },
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
            openURLAction: { _ in true },
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
            openURLAction: { _ in true },
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

    func testDisablingPreviewRestoresPersistedHistoryInsteadOfLeavingSamples() async throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = root.appendingPathComponent("usage-history.json")
        defer { try? fileManager.removeItem(at: root) }
        let history = CodexUsageHistoryStore(fileURL: fileURL)
        let realSnapshot = makeHistorySnapshot(capturedAt: Date(), usedPercent: 21)
        _ = await history.append(snapshot: realSnapshot)
        let defaults = makeDefaults()
        defaults.set(true, forKey: CodexiOSSettingsKeys.previewModeEnabled)
        let model = CodexiOSModel(
            service: StubCodexiOSService(),
            defaults: defaults,
            historyStore: history,
            liveActivityManager: StubCodexiOSLiveActivityManager(
                state: .init(isAvailable: true, activityID: nil)
            ),
            openURLAction: { _ in true },
            copyTextAction: { _ in }
        )
        await model.start()
        XCTAssertGreaterThan(model.usageHistory.count, 1)

        model.disablePreviewMode()
        while model.isLiveActivityTransitioning {
            await Task.yield()
        }

        XCTAssertEqual(model.usageHistory.count, 1)
        XCTAssertEqual(model.usageHistory.first?.fiveHour?.usedPercent, 21)
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
            openURLAction: { _ in true },
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
            openURLAction: { _ in true },
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
            openURLAction: { _ in true },
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

    func testResetLocalDataClearsIOSSettings() throws {
        let defaults = makeDefaults()
        defaults.set(true, forKey: CodexiOSSettingsKeys.hasCompletedOnboarding)
        defaults.set(true, forKey: CodexiOSSettingsKeys.previewModeEnabled)
        defaults.set(600, forKey: CodexiOSSettingsKeys.refreshIntervalSeconds)

        try CodexiOSAppResetter.resetLocalData(
            defaults: defaults,
            clearTokens: {},
            clearPendingAuth: {},
            clearHistory: {}
        )

        XCTAssertNil(defaults.object(forKey: CodexiOSSettingsKeys.hasCompletedOnboarding))
        XCTAssertNil(defaults.object(forKey: CodexiOSSettingsKeys.previewModeEnabled))
        XCTAssertNil(defaults.object(forKey: CodexiOSSettingsKeys.refreshIntervalSeconds))
    }

    func testTypedAuthExpiryRequiresSignInWithoutShowingNetworkError() async {
        let model = CodexiOSModel(
            service: StubCodexiOSService(outcomeHandler: {
                .authExpired("Sign-in expired. Sign in again.")
            }),
            defaults: makeDefaults(),
            openURLAction: { _ in true },
            copyTextAction: { _ in }
        )

        await model.refresh()

        XCTAssertEqual(model.liveAccountState, .authExpired)
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(model.statusMessage, "Sign-in expired. Sign in again.")
        XCTAssertNil(model.snapshot)
    }

    func testUnavailableOutcomeKeepsLastGoodSnapshotAndRetryDate() async {
        let lastGood = CodexiOSPreviewData.snapshot()
        let retryAt = Date().addingTimeInterval(120)
        let model = CodexiOSModel(
            service: StubCodexiOSService(outcomeHandler: {
                .unavailable(
                    message: "OpenAI is rate-limiting requests. Try again soon.",
                    hasStoredCredentials: true,
                    retry: .init(retryAfter: retryAt, isTransient: true)
                )
            }),
            defaults: makeDefaults(),
            openURLAction: { _ in true },
            copyTextAction: { _ in }
        )
        model.snapshot = lastGood

        await model.refresh()

        XCTAssertEqual(model.liveAccountState, .unavailable)
        XCTAssertEqual(model.snapshot, lastGood)
        XCTAssertEqual(model.retryAvailableAt, retryAt)
        XCTAssertTrue(model.hasCompletedOnboarding)
        XCTAssertTrue(model.canAutoRefresh)
    }

    func testSignOutWinsOverDelayedRefresh() async {
        let gate = SnapshotFetchGate()
        let service = StubCodexiOSService(fetchHandler: {
            await gate.wait()
        })
        let model = CodexiOSModel(
            service: service,
            defaults: makeDefaults(),
            openURLAction: { _ in true },
            copyTextAction: { _ in }
        )

        let refresh = Task { @MainActor in await model.refresh() }
        while await service.fetchCallCount() == 0 { await Task.yield() }
        await model.signOut()
        await gate.release(snapshot: CodexiOSPreviewData.snapshot())
        await refresh.value
        let signOutCount = await service.signOutCallCount()

        XCTAssertEqual(model.liveAccountState, .signedOut)
        XCTAssertNil(model.snapshot)
        XCTAssertEqual(signOutCount, 1)
    }

    func testPreviewWinsOverDelayedRefresh() async {
        let gate = SnapshotFetchGate()
        let service = StubCodexiOSService(fetchHandler: {
            await gate.wait()
        })
        let model = CodexiOSModel(
            service: service,
            defaults: makeDefaults(),
            openURLAction: { _ in true },
            copyTextAction: { _ in }
        )

        let refresh = Task { @MainActor in await model.refresh() }
        while await service.fetchCallCount() == 0 { await Task.yield() }
        model.enablePreviewMode()
        let preview = model.snapshot
        await gate.release(snapshot: CodexiOSPreviewData.snapshot(now: Date().addingTimeInterval(5_000)))
        await refresh.value

        XCTAssertTrue(model.previewModeEnabled)
        XCTAssertEqual(model.snapshot, preview)
    }

    func testStartRecoversPersistedPendingSignIn() async {
        let auth = CodexiOSDeviceAuthStart(
            flowID: String(repeating: "f", count: 43),
            verificationURL: CodexiOSService.verificationURL,
            userCode: "ABCD-1234"
        )
        let service = StubCodexiOSService(
            pollHandler: { _ in .pending("Still waiting.") },
            recoverHandler: { auth }
        )
        let model = CodexiOSModel(
            service: service,
            defaults: makeDefaults(),
            openURLAction: { _ in
                XCTFail("Recovered sign-in must not open Safari without a tap.")
                return false
            },
            copyTextAction: { _ in XCTFail("Recovered sign-in must not copy automatically.") }
        )

        await model.start()
        let pollCount = await service.pollCallCount()

        XCTAssertTrue(model.hasPendingSignIn)
        XCTAssertEqual(model.deviceCode, "ABCD-1234")
        XCTAssertEqual(pollCount, 1)
    }

    func testCancelSignInClearsPendingUIAndSecureFlow() async {
        let service = StubCodexiOSService()
        let model = CodexiOSModel(
            service: service,
            defaults: makeDefaults(),
            openURLAction: { _ in true },
            copyTextAction: { _ in }
        )
        await model.beginSignIn()

        await model.cancelSignIn()
        let cancelCount = await service.cancelCallCount()

        XCTAssertEqual(model.liveAccountState, .signedOut)
        XCTAssertNil(model.flowID)
        XCTAssertNil(model.deviceCode)
        XCTAssertEqual(cancelCount, 1)
    }

    func testCopyIsOnlyPerformedByExplicitCopyAction() async {
        let copyRecorder = CopyRecorder()
        let model = CodexiOSModel(
            service: StubCodexiOSService(),
            defaults: makeDefaults(),
            openURLAction: { _ in true },
            copyTextAction: { copyRecorder.record($0) }
        )

        await model.beginSignIn()
        XCTAssertTrue(copyRecorder.values.isEmpty)

        model.copyCode()
        XCTAssertEqual(copyRecorder.values, ["CODE-0000"])
    }

    func testFailedSafariOpenKeepsPendingSignInAndShowsManualRecovery() async {
        let copyRecorder = CopyRecorder()
        let model = CodexiOSModel(
            service: StubCodexiOSService(),
            defaults: makeDefaults(),
            openURLAction: { _ in false },
            copyTextAction: { copyRecorder.record($0) }
        )

        await model.beginSignIn()

        XCTAssertTrue(model.hasPendingSignIn)
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(
            model.statusMessage,
            "Could not open Safari. Copy the code, then open auth.openai.com/codex/device manually."
        )
        XCTAssertTrue(copyRecorder.values.isEmpty)

        model.copyCode()
        XCTAssertEqual(copyRecorder.values, ["CODE-0000"])
    }

    func testStartIsIdempotentAcrossConcurrentAndRepeatedCalls() async {
        let service = StubCodexiOSService()
        let liveActivity = StubCodexiOSLiveActivityManager(
            state: .init(isAvailable: true, activityID: nil)
        )
        let model = CodexiOSModel(
            service: service,
            defaults: makeDefaults(),
            liveActivityManager: liveActivity,
            openURLAction: { _ in true },
            copyTextAction: { _ in }
        )

        let first = Task { @MainActor in await model.start() }
        let second = Task { @MainActor in await model.start() }
        await first.value
        await second.value
        await model.start()

        let fetchCount = await service.fetchCallCount()
        let calls = await liveActivity.recordedCalls()
        XCTAssertEqual(fetchCount, 1)
        XCTAssertEqual(calls.filter { $0 == .recover }.count, 1)
    }

    func testPreviewWinsOverSuspendedStartupRecovery() async {
        let recoverGate = LiveActivityCallGate()
        let updateGate = LiveActivityCallGate()
        let liveActivity = StubCodexiOSLiveActivityManager(
            state: .init(isAvailable: true, activityID: "recovered"),
            recoverGate: recoverGate,
            updateGate: updateGate,
            updateState: .init(isAvailable: true, activityID: nil)
        )
        let service = StubCodexiOSService(
            recoverHandler: {
                CodexiOSDeviceAuthStart(
                    flowID: String(repeating: "f", count: 43),
                    verificationURL: CodexiOSService.verificationURL,
                    userCode: "ABCD-1234"
                )
            }
        )
        let model = CodexiOSModel(
            service: service,
            defaults: makeDefaults(),
            liveActivityManager: liveActivity,
            openURLAction: { _ in true },
            copyTextAction: { _ in }
        )

        let start = Task { @MainActor in await model.start() }
        while await liveActivity.recordedCalls().contains(.recover) == false {
            await Task.yield()
        }
        model.enablePreviewMode()
        let previewSnapshot = model.snapshot
        await recoverGate.release()
        while await liveActivity.recordedCalls().contains(.update(showFiveHour: false)) == false {
            await Task.yield()
        }
        await start.value
        let pollCount = await service.pollCallCount()

        XCTAssertTrue(model.previewModeEnabled)
        XCTAssertEqual(model.snapshot, previewSnapshot)
        XCTAssertFalse(model.hasPendingSignIn)
        XCTAssertFalse(model.isLiveActivityRunning)
        XCTAssertEqual(pollCount, 0)

        await updateGate.release()
        while model.isLiveActivityTransitioning {
            await Task.yield()
        }
    }

    func testModelsUseOneProcessHistoryWriterByDefault() {
        let first = CodexiOSModel(
            service: StubCodexiOSService(),
            defaults: makeDefaults(),
            openURLAction: { _ in true },
            copyTextAction: { _ in }
        )
        let second = CodexiOSModel(
            service: StubCodexiOSService(),
            defaults: makeDefaults(),
            openURLAction: { _ in true },
            copyTextAction: { _ in }
        )

        XCTAssertTrue(first.historyStore === second.historyStore)
    }

    func testModelsUseOneProcessLiveActivityCoordinatorByDefault() {
        let first = CodexiOSModel(
            service: StubCodexiOSService(),
            defaults: makeDefaults(),
            openURLAction: { _ in true },
            copyTextAction: { _ in }
        )
        let second = CodexiOSModel(
            service: StubCodexiOSService(),
            defaults: makeDefaults(),
            openURLAction: { _ in true },
            copyTextAction: { _ in }
        )

        let firstCoordinator = first.liveActivityManager as? CodexiOSLiveActivitySerialManager
        let secondCoordinator = second.liveActivityManager as? CodexiOSLiveActivitySerialManager
        guard let firstCoordinator, let secondCoordinator else {
            return XCTFail("Expected the process-shared serial coordinator")
        }
        XCTAssertTrue(firstCoordinator === secondCoordinator)
    }

    func testTwoModelsQueueLiveActivityRecoveryThroughSharedCoordinator() async {
        let recoverGate = LiveActivityCallGate()
        let underlying = StubCodexiOSLiveActivityManager(
            state: .init(isAvailable: true, activityID: "existing"),
            recoverGate: recoverGate
        )
        let coordinator = CodexiOSLiveActivitySerialManager(manager: underlying)
        let first = CodexiOSModel(
            service: StubCodexiOSService(),
            defaults: makeDefaults(),
            liveActivityCoordinator: coordinator,
            openURLAction: { _ in true },
            copyTextAction: { _ in }
        )
        let second = CodexiOSModel(
            service: StubCodexiOSService(),
            defaults: makeDefaults(),
            liveActivityCoordinator: coordinator,
            openURLAction: { _ in true },
            copyTextAction: { _ in }
        )

        let firstStart = Task { @MainActor in await first.start() }
        while await underlying.recordedCalls().filter({ $0 == .recover }).count != 1 {
            await Task.yield()
        }
        let secondStart = Task { @MainActor in await second.start() }
        while await coordinator.queuedOperationCount() == 0 {
            await Task.yield()
        }

        let callsBeforeRelease = await underlying.recordedCalls()
        XCTAssertEqual(callsBeforeRelease.filter { $0 == .recover }.count, 1)
        await recoverGate.release()
        await firstStart.value
        await secondStart.value
        let callsAfterRelease = await underlying.recordedCalls()
        XCTAssertEqual(callsAfterRelease.filter { $0 == .recover }.count, 2)
    }

    func testOlderBackgroundCompletionCannotOverwriteNewerForegroundLiveActivity() async {
        let now = Date()
        let older = CodexiOSPreviewData.snapshot(now: now)
        let newer = CodexiOSPreviewData.snapshot(now: now.addingTimeInterval(30))
        let backgroundGate = SnapshotFetchGate()
        let underlying = StubCodexiOSLiveActivityManager(
            state: .init(isAvailable: true, activityID: "existing")
        )
        let coordinator = CodexiOSLiveActivitySerialManager(manager: underlying)
        let background = CodexiOSModel(
            service: StubCodexiOSService(fetchHandler: { await backgroundGate.wait() }),
            defaults: makeDefaults(),
            liveActivityCoordinator: coordinator,
            openURLAction: { _ in true },
            copyTextAction: { _ in }
        )
        let foreground = CodexiOSModel(
            service: StubCodexiOSService(outcomeHandler: { .loaded(newer) }),
            defaults: makeDefaults(),
            liveActivityCoordinator: coordinator,
            openURLAction: { _ in true },
            copyTextAction: { _ in }
        )

        let backgroundRefresh = Task { @MainActor in
            await background.refreshLiveActivityInBackground()
        }
        while await underlying.recordedCalls().contains(.recover) == false {
            await Task.yield()
        }
        await foreground.refresh()
        await backgroundGate.release(snapshot: older)
        _ = await backgroundRefresh.value

        let calls = await underlying.recordedCalls()
        XCTAssertEqual(calls.filter { $0 == .update(showFiveHour: false) }.count, 1)
        XCTAssertEqual(calls.last, .recover)
    }

    func testStoppingLiveActivityStartsNewSnapshotOrderingEpoch() async throws {
        let now = Date()
        let newer = CodexiOSPreviewData.snapshot(now: now.addingTimeInterval(30))
        let olderNewLifecycle = CodexiOSPreviewData.snapshot(now: now)
        let underlying = StubCodexiOSLiveActivityManager(
            state: .init(isAvailable: true, activityID: "old"),
            startState: .init(isAvailable: true, activityID: "new")
        )
        let coordinator = CodexiOSLiveActivitySerialManager(manager: underlying)

        _ = await coordinator.update(
            snapshot: newer,
            showFiveHour: false,
            showUsedQuota: false,
            cadence: 300
        )
        _ = await coordinator.stop()
        let restarted = try await coordinator.start(
            snapshot: olderNewLifecycle,
            showFiveHour: false,
            showUsedQuota: false,
            cadence: 300
        )

        XCTAssertEqual(restarted.activityID, "new")
        let calls = await underlying.recordedCalls()
        XCTAssertEqual(calls, [.update(showFiveHour: false), .stop, .start(showFiveHour: false)])
    }

    func testCancelledQueuedLiveActivityUpdateDoesNotReachActivityKitManager() async {
        let recoverGate = LiveActivityCallGate()
        let underlying = StubCodexiOSLiveActivityManager(
            state: .init(isAvailable: true, activityID: "existing"),
            recoverGate: recoverGate
        )
        let coordinator = CodexiOSLiveActivitySerialManager(manager: underlying)
        let snapshot = CodexiOSPreviewData.snapshot()

        let recover = Task { @Sendable in await coordinator.recover() }
        while await underlying.recordedCalls().contains(.recover) == false {
            await Task.yield()
        }
        let update = Task { @Sendable in
            await coordinator.update(
                snapshot: snapshot,
                showFiveHour: false,
                showUsedQuota: false,
                cadence: 300
            )
        }
        while await coordinator.queuedOperationCount() == 0 {
            await Task.yield()
        }
        update.cancel()
        await recoverGate.release()
        _ = await recover.value
        _ = await update.value

        let calls = await underlying.recordedCalls()
        XCTAssertEqual(calls, [.recover])
    }

    func testForegroundAndBackgroundModelsPreserveConcurrentHistorySamples() async throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = root.appendingPathComponent("usage-history.json")
        defer { try? fileManager.removeItem(at: root) }
        let history = CodexUsageHistoryStore(fileURL: fileURL)
        let now = Date()
        let foregroundSnapshot = makeHistorySnapshot(capturedAt: now, usedPercent: 21)
        let backgroundSnapshot = makeHistorySnapshot(capturedAt: now.addingTimeInterval(1), usedPercent: 67)
        let foreground = CodexiOSModel(
            service: StubCodexiOSService(outcomeHandler: { .loaded(foregroundSnapshot) }),
            defaults: makeDefaults(),
            historyStore: history,
            liveActivityManager: StubCodexiOSLiveActivityManager(
                state: .init(isAvailable: true, activityID: nil)
            ),
            openURLAction: { _ in true },
            copyTextAction: { _ in }
        )
        let background = CodexiOSModel(
            service: StubCodexiOSService(outcomeHandler: { .loaded(backgroundSnapshot) }),
            defaults: makeDefaults(),
            historyStore: history,
            liveActivityManager: StubCodexiOSLiveActivityManager(
                state: .init(isAvailable: true, activityID: "running")
            ),
            openURLAction: { _ in true },
            copyTextAction: { _ in }
        )

        async let foregroundRefresh: Void = foreground.refresh()
        async let backgroundRefresh: Bool = background.refreshLiveActivityInBackground()
        _ = await (foregroundRefresh, backgroundRefresh)

        let samples = await history.load(now: now.addingTimeInterval(2))
        XCTAssertEqual(Set(samples.compactMap { $0.fiveHour?.usedPercent }), Set([21, 67]))
    }

    func testSignOutCanBeRetriedAfterPartialCredentialDeletionFailure() async {
        let attempts = FailingFirstSignOut()
        let service = StubCodexiOSService(
            outcomeHandler: { .loaded(CodexiOSPreviewData.snapshot()) },
            signOutHandler: { try await attempts.run() }
        )
        let model = CodexiOSModel(
            service: service,
            defaults: makeDefaults(),
            openURLAction: { _ in true },
            copyTextAction: { _ in }
        )
        await model.refresh()

        await model.signOut()
        XCTAssertEqual(model.liveAccountState, .unavailable)
        XCTAssertNotNil(model.errorMessage)
        XCTAssertFalse(model.canAutoRefresh)

        await model.signOut()
        let signOutCount = await service.signOutCallCount()
        XCTAssertEqual(model.liveAccountState, .signedOut)
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(signOutCount, 2)
    }

    func testBackgroundFailureAlwaysSubmitsNextRefresh() async {
        let scheduler = StubBackgroundRefreshScheduler()
        let liveActivity = StubCodexiOSLiveActivityManager(
            state: .init(isAvailable: true, activityID: "running")
        )
        let model = CodexiOSModel(
            service: StubCodexiOSService(fetchHandler: {
                throw CodexiOSError.requestFailed(500)
            }),
            defaults: makeDefaults(),
            liveActivityManager: liveActivity,
            backgroundRefreshScheduler: scheduler,
            openURLAction: { _ in true },
            copyTextAction: { _ in }
        )

        let success = await model.refreshLiveActivityInBackground()

        XCTAssertFalse(success)
        XCTAssertEqual(scheduler.scheduledCadences.count, 1)
        XCTAssertEqual(scheduler.scheduledCadences.last, 300)
    }

    func testResetClearsDefaultsHistoryAndCredentialsWithoutExiting() async throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = root.appendingPathComponent("usage-history.json")
        defer { try? fileManager.removeItem(at: root) }
        let history = CodexUsageHistoryStore(fileURL: fileURL)
        _ = await history.append(snapshot: CodexiOSPreviewData.snapshot(), now: Date())
        let defaults = makeDefaults()
        defaults.set(true, forKey: CodexiOSSettingsKeys.hasCompletedOnboarding)
        let service = StubCodexiOSService()
        let model = CodexiOSModel(
            service: service,
            defaults: defaults,
            historyStore: history,
            openURLAction: { _ in true },
            copyTextAction: { _ in }
        )

        await model.resetApp()
        let signOutCount = await service.signOutCallCount()

        XCTAssertEqual(signOutCount, 1)
        XCTAssertFalse(fileManager.fileExists(atPath: fileURL.path))
        XCTAssertNil(defaults.object(forKey: CodexiOSSettingsKeys.hasCompletedOnboarding))
        XCTAssertEqual(model.liveAccountState, .signedOut)
        XCTAssertFalse(model.hasCompletedOnboarding)
        XCTAssertNil(model.errorMessage)
    }

    func testResetSurfacesCredentialDeletionFailureButStillClearsOtherData() async throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = root.appendingPathComponent("usage-history.json")
        defer { try? fileManager.removeItem(at: root) }
        let history = CodexUsageHistoryStore(fileURL: fileURL)
        _ = await history.append(snapshot: CodexiOSPreviewData.snapshot(), now: Date())
        let defaults = makeDefaults()
        defaults.set(true, forKey: CodexiOSSettingsKeys.hasCompletedOnboarding)
        let model = CodexiOSModel(
            service: StubCodexiOSService(signOutHandler: {
                throw CodexiOSError.secureStoreFailure("Keychain deletion failed.")
            }),
            defaults: defaults,
            historyStore: history,
            openURLAction: { _ in true },
            copyTextAction: { _ in }
        )

        await model.resetApp()

        XCTAssertEqual(model.liveAccountState, .unavailable)
        XCTAssertEqual(model.errorMessage, "Some local data could not be deleted. Keychain deletion failed.")
        XCTAssertFalse(fileManager.fileExists(atPath: fileURL.path))
        XCTAssertNil(defaults.object(forKey: CodexiOSSettingsKeys.hasCompletedOnboarding))
        XCTAssertTrue(model.hasCompletedOnboarding)
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "CodexiOSModelTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func makeHistorySnapshot(capturedAt: Date, usedPercent: Double) -> CodexSnapshot {
        CodexSnapshot(
            capturedAt: capturedAt,
            executablePath: "Codexex iOS Tests",
            account: CodexAccount(authType: "chatgpt", email: nil, planType: "pro"),
            limits: [
                CodexLimit(
                    id: "codex",
                    rawLimitName: "Codex",
                    bucket: .codex,
                    primary: CodexQuotaWindow(
                        usedPercent: usedPercent,
                        windowDurationMinutes: 300,
                        resetsAt: nil
                    ),
                    secondary: CodexQuotaWindow(
                        usedPercent: usedPercent,
                        windowDurationMinutes: 10_080,
                        resetsAt: nil
                    )
                )
            ]
        )
    }
}

actor SnapshotFetchGate {
    private var continuation: CheckedContinuation<CodexServiceSnapshotResponse, Never>?
    private var queuedResponse: CodexServiceSnapshotResponse?

    func wait() async -> CodexServiceSnapshotResponse {
        if let queuedResponse {
            self.queuedResponse = nil
            return queuedResponse
        }
        return await withCheckedContinuation { continuation = $0 }
    }

    func release(snapshot: CodexSnapshot) {
        let response = CodexServiceSnapshotResponse(
            authMode: .chatGPT,
            snapshot: snapshot,
            errorMessage: nil
        )
        if let continuation {
            self.continuation = nil
            continuation.resume(returning: response)
        } else {
            queuedResponse = response
        }
    }
}

actor FailingFirstSignOut {
    private var attemptCount = 0

    func run() throws {
        attemptCount += 1
        if attemptCount == 1 {
            throw CodexiOSError.secureStoreFailure("Could not delete saved sign-in.")
        }
    }
}

actor LiveActivityCallGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var isReleased = false

    func wait() async {
        guard isReleased == false else { return }
        await withCheckedContinuation { continuation = $0 }
    }

    func release() {
        isReleased = true
        continuation?.resume()
        continuation = nil
    }
}

@MainActor
final class StubBackgroundRefreshScheduler: CodexiOSBackgroundRefreshScheduling {
    private(set) var scheduledCadences: [TimeInterval] = []
    private(set) var cancelCount = 0

    func schedule(cadence: TimeInterval) {
        scheduledCadences.append(cadence)
    }

    func cancel() {
        cancelCount += 1
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
    private let recoverGate: LiveActivityCallGate?
    private let updateGate: LiveActivityCallGate?
    private let updateState: CodexiOSLiveActivityRuntimeState?
    private var calls: [Call] = []
    private var showUsedQuotaValues: [Bool] = []

    init(
        state: CodexiOSLiveActivityRuntimeState,
        startState: CodexiOSLiveActivityRuntimeState? = nil,
        startDelay: Duration? = nil,
        recoverGate: LiveActivityCallGate? = nil,
        updateGate: LiveActivityCallGate? = nil,
        updateState: CodexiOSLiveActivityRuntimeState? = nil
    ) {
        self.state = state
        self.startState = startState ?? state
        self.startDelay = startDelay
        self.recoverGate = recoverGate
        self.updateGate = updateGate
        self.updateState = updateState
    }

    func recover() async -> CodexiOSLiveActivityRuntimeState {
        calls.append(.recover)
        if let recoverGate { await recoverGate.wait() }
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
        if let updateGate { await updateGate.wait() }
        if let updateState { state = updateState }
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
    typealias OutcomeHandler = @Sendable () async throws -> CodexiOSSnapshotOutcome
    typealias BeginHandler = @Sendable () async throws -> CodexiOSDeviceAuthStart
    typealias PollHandler = @Sendable (String) async throws -> CodexiOSPollResult
    typealias SignOutHandler = @Sendable () async throws -> Void
    typealias RecoverHandler = @Sendable () async throws -> CodexiOSDeviceAuthStart?
    typealias CancelHandler = @Sendable () async throws -> Void

    private let fetchHandler: FetchHandler
    private let outcomeHandler: OutcomeHandler?
    private let beginHandler: BeginHandler
    private let pollHandler: PollHandler
    private let signOutHandler: SignOutHandler
    private let recoverHandler: RecoverHandler
    private let cancelHandler: CancelHandler

    private var fetchCount = 0
    private var pollCount = 0
    private var signOutCount = 0
    private var cancelCount = 0

    init(
        fetchHandler: @escaping FetchHandler = {
            CodexServiceSnapshotResponse(authMode: nil, snapshot: nil, errorMessage: nil)
        },
        outcomeHandler: OutcomeHandler? = nil,
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
        signOutHandler: @escaping SignOutHandler = {},
        recoverHandler: @escaping RecoverHandler = { nil },
        cancelHandler: @escaping CancelHandler = {}
    ) {
        self.fetchHandler = fetchHandler
        self.outcomeHandler = outcomeHandler
        self.beginHandler = beginHandler
        self.pollHandler = pollHandler
        self.signOutHandler = signOutHandler
        self.recoverHandler = recoverHandler
        self.cancelHandler = cancelHandler
    }

    func fetchSnapshot() async throws -> CodexiOSSnapshotOutcome {
        fetchCount += 1
        if let outcomeHandler { return try await outcomeHandler() }
        return .legacy(try await fetchHandler())
    }

    func recoverPendingSignIn() async throws -> CodexiOSDeviceAuthStart? {
        try await recoverHandler()
    }

    func beginSignIn() async throws -> CodexiOSDeviceAuthStart {
        try await beginHandler()
    }

    func pollSignIn(flowID: String) async throws -> CodexiOSPollResult {
        pollCount += 1
        return try await pollHandler(flowID)
    }

    func cancelSignIn() async throws {
        cancelCount += 1
        try await cancelHandler()
    }

    func signOut() async throws {
        signOutCount += 1
        try await signOutHandler()
    }

    func fetchCallCount() -> Int {
        fetchCount
    }

    func pollCallCount() -> Int {
        pollCount
    }

    func signOutCallCount() -> Int {
        signOutCount
    }

    func cancelCallCount() -> Int {
        cancelCount
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
