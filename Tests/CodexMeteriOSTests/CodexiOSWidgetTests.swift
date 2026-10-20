import Foundation
import Testing
import CodexMeterCore
@testable import Codexex

@Suite @MainActor struct CodexiOSWidgetTests {
    private func makeModel(installed: Bool, outcome: CodexiOSSnapshotOutcome) -> (CodexiOSModel, WidgetRecorder, StubBackgroundRefreshScheduler, StubCodexiOSService) {
        let defaults = UserDefaults(suiteName: "WidgetTests.\(UUID().uuidString)")!
        let widgets = WidgetRecorder(installed: installed)
        let scheduler = StubBackgroundRefreshScheduler()
        let service = StubCodexiOSService(outcomeHandler: { outcome })
        let api = OpenAIMonitorModel(load: { nil }, persist: { _ in }, delete: {}, loadConsent: { false }, persistConsent: { _ in })
        let model = CodexiOSModel(service: service, defaults: defaults,
            historyStore: CodexUsageHistoryStore(fileURL: URL.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("history.json")),
            liveActivityManager: StubCodexiOSLiveActivityManager(state: .init(isAvailable: true, activityID: nil)),
            backgroundRefreshScheduler: scheduler, widgetPublisher: widgets, apiMonitor: api,
            openURLAction: { _ in true }, copyTextAction: { _ in })
        return (model, widgets, scheduler, service)
    }

    @Test func widgetRefreshesWithoutLiveActivity() async {
        let snapshot = CodexiOSPreviewData.snapshot()
        let (model, widgets, scheduler, service) = makeModel(installed: true, outcome: .loaded(snapshot))
        #expect(await model.refreshLiveActivityInBackground())
        #expect(await service.fetchCallCount() == 1)
        #expect(!model.isLiveActivityRunning)
        #expect(widgets.last?.quotaUpdatedAt == snapshot.capturedAt)
        #expect(widgets.last?.weeklyPercentLeft != nil)
        #expect(!scheduler.scheduledCadences.isEmpty)
    }

    @Test func noWidgetOrActivityDoesNotPoll() async {
        let (model, _, scheduler, service) = makeModel(installed: false, outcome: .signedOut)
        #expect(await model.refreshLiveActivityInBackground())
        #expect(await service.fetchCallCount() == 0)
        #expect(scheduler.scheduledCadences.isEmpty)
    }

    @Test func silentWakeRefreshesQuotaWithoutWaitingForAPIMonitor() async {
        let service = StubCodexiOSService(outcomeHandler: { .loaded(CodexiOSPreviewData.snapshot()) })
        let activity = StubCodexiOSLiveActivityManager(state: .init(isAvailable: true, activityID: "running"))
        let widgets = WidgetRecorder(installed: true)
        let scheduler = StubBackgroundRefreshScheduler()
        let api = OpenAIMonitorModel(client: OpenAIAPIClient(transport: { _ in
            Issue.record("Silent quota wake must not start an unrelated API request")
            throw OpenAIAPIError.unavailable
        }), load: { .init(key: "sk-test-widget-only", kind: .regular) },
            persist: { _ in }, delete: {}, loadConsent: { false }, persistConsent: { _ in })
        let model = CodexiOSModel(service: service,
            defaults: UserDefaults(suiteName: "SilentWakeWidget.\(UUID().uuidString)")!,
            liveActivityManager: activity, backgroundRefreshScheduler: scheduler,
            pushRegistrationManager: WidgetWakeRegistration(), widgetPublisher: widgets, apiMonitor: api,
            openURLAction: { _ in true }, copyTextAction: { _ in })

        #expect(await model.refreshLiveActivityInBackground(refreshAPIWidgets: false))
        #expect(await service.fetchCallCount() == 1)
        #expect(await activity.recordedCalls().contains(.update(showFiveHour: true)))
        #expect(!scheduler.scheduledCadences.isEmpty, "API widgets retain the BG refresh path")
    }

    @Test func backgroundQuotaUpdatesBeforeAPIWidgetRequestAndSurvivesAPIFailure() async {
        let service = StubCodexiOSService(outcomeHandler: { .loaded(CodexiOSPreviewData.snapshot()) })
        let activity = StubCodexiOSLiveActivityManager(state: .init(isAvailable: true, activityID: "running"))
        let api = OpenAIMonitorModel(client: OpenAIAPIClient(transport: { _ in
            #expect(await service.fetchCallCount() == 1)
            #expect(await activity.recordedCalls().contains(.update(showFiveHour: true)))
            throw OpenAIAPIError.unavailable
        }), load: { .init(key: "sk-test-widget-only", kind: .regular) },
            persist: { _ in }, delete: {}, loadConsent: { false }, persistConsent: { _ in })
        let model = CodexiOSModel(service: service,
            defaults: UserDefaults(suiteName: "QuotaFirstWidget.\(UUID().uuidString)")!,
            liveActivityManager: activity, backgroundRefreshScheduler: StubBackgroundRefreshScheduler(),
            pushRegistrationManager: WidgetWakeRegistration(), widgetPublisher: WidgetRecorder(installed: true),
            apiMonitor: api, openURLAction: { _ in true }, copyTextAction: { _ in })

        #expect(await model.refreshLiveActivityInBackground())
        #expect(api.error != nil)
        #expect(!model.isLiveActivityStale)
    }

    @Test func cancelledBackgroundRecoveryDoesNotUnregisterThePhone() async {
        let push = WidgetWakeRegistration()
        let model = CodexiOSModel(service: StubCodexiOSService(outcomeHandler: { .signedOut }),
            defaults: UserDefaults(suiteName: "CancelledWake.\(UUID().uuidString)")!,
            liveActivityManager: StubCodexiOSLiveActivityManager(state: .init(isAvailable: true, activityID: "running")),
            backgroundRefreshScheduler: StubBackgroundRefreshScheduler(), pushRegistrationManager: push,
            widgetPublisher: WidgetRecorder(installed: false),
            apiMonitor: OpenAIMonitorModel(load: { nil }, persist: { _ in }, delete: {}, loadConsent: { false }, persistConsent: { _ in }),
            openURLAction: { _ in true }, copyTextAction: { _ in })
        let operation = Task { await model.refreshLiveActivityInBackground() }
        operation.cancel()
        #expect(await operation.value == false)
        #expect(push.disableCount == 0)
    }

    @Test func signOutClearsQuotaAndResetClearsAll() async {
        let (model, widgets, _, _) = makeModel(installed: true, outcome: .loaded(CodexiOSPreviewData.snapshot()))
        await model.refresh()
        #expect(widgets.last?.weeklyPercentLeft != nil)
        await model.signOut()
        #expect(widgets.last?.weeklyPercentLeft == nil)
        await model.resetApp()
        #expect(widgets.clearCount > 0)
        #expect(widgets.last?.apiRemainingUSD == nil)
    }

    @Test func inaccessibleCredentialRetainsLastObservationAsStale() async {
        let (_, widgets, _, _) = makeModel(installed: true, outcome: .signedOut)
        let date = Date().addingTimeInterval(-60)
        widgets.last = .init(apiRemainingUSD: Decimal(string: "2.37"), apiUpdatedAt: date)
        let inaccessible = OpenAIMonitorModel(load: { throw OpenAIAPICredentialStore.CredentialError.unavailable },
            persist: { _ in }, delete: {}, loadConsent: { false }, persistConsent: { _ in })
        let lockedModel = CodexiOSModel(service: StubCodexiOSService(outcomeHandler: { .signedOut }),
            defaults: UserDefaults(suiteName: "LockedWidget.\(UUID().uuidString)")!,
            liveActivityManager: StubCodexiOSLiveActivityManager(state: .init(isAvailable: true, activityID: nil)),
            backgroundRefreshScheduler: StubBackgroundRefreshScheduler(), widgetPublisher: widgets, apiMonitor: inaccessible,
            openURLAction: { _ in true }, copyTextAction: { _ in })
        #expect(await lockedModel.refreshLiveActivityInBackground() == false)
        #expect(widgets.last?.apiRemainingUSD == Decimal(string: "2.37"))
        #expect(widgets.last?.apiUpdatedAt == date)
        #expect(widgets.last?.apiStale == true)
    }
}

@MainActor private final class WidgetRecorder: CodexiOSWidgetPublishing {
    let installed: Bool
    var last: MonitoringWidgetSnapshot?
    var clearCount = 0
    init(installed: Bool) { self.installed = installed }
    func publish(_ value: MonitoringWidgetSnapshot) { last = value }
    func clear() { last = .empty; clearCount += 1 }
    func hasInstalledWidgets() async -> Bool { installed }
    func currentSnapshot() -> MonitoringWidgetSnapshot? { last }
}

@MainActor private final class WidgetWakeRegistration: CodexiOSPushRegistering {
    var disableCount = 0
    func enable() async {}
    func disable() async { disableCount += 1 }
    func didRegister(deviceToken: Data) async {}
}
