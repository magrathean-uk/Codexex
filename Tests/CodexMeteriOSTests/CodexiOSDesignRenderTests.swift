import XCTest
import SwiftUI
import UIKit
import CodexMeterCore
@testable import Codexex

/// Opt-in native evidence capture. These are real SwiftUI/UIKit views, not layout replicas.
/// Every provider, credential, URL-opening, APNs, ActivityKit and WidgetKit dependency is isolated.
@MainActor
final class CodexiOSDesignRenderTests: XCTestCase {
    func testCaptureNativeDesignFixtures() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["HIG_DESIGN_RENDER_OUTPUT"] != nil || environment["HIG_DESIGN_CAPTURE"] == "1" else {
            throw XCTSkip("Set HIG_DESIGN_RENDER_OUTPUT to opt into native design evidence capture.")
        }
        let output = environment["HIG_DESIGN_RENDER_OUTPUT"].map { URL(fileURLWithPath: $0, isDirectory: true) }
        if let output { try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true) }
        let fixtureRoot = output ?? FileManager.default.temporaryDirectory.appendingPathComponent("CodexexHIG-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: fixtureRoot, withIntermediateDirectories: true)
        let suite = "CodexexHIG.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: CodexiOSSettingsKeys.hasCompletedOnboarding)

        let disconnected = makeModel(defaults: defaults, historyRoot: fixtureRoot, outcome: .signedOut)
        await disconnected.start()
        let pending = makeModel(defaults: defaults, historyRoot: fixtureRoot, outcome: .signedOut, pending: true)
        await pending.start()
        let copied = makeModel(defaults: defaults, historyRoot: fixtureRoot, outcome: .signedOut, pending: true)
        await copied.start()
        copied.copyCode()
        let expired = makeModel(defaults: defaults, historyRoot: fixtureRoot, outcome: .signedOut)
        await expired.start()
        expired.statusMessage = CodexiOSError.signInExpired.localizedDescription
        let failed = makeModel(defaults: defaults, historyRoot: fixtureRoot, outcome: .signedOut)
        await failed.start()
        failed.errorMessage = "Could not connect. Check your connection and try again."
        let plus = makeModel(defaults: defaults, historyRoot: fixtureRoot, outcome: .loaded(Self.snapshot(plan: "PLUS")))
        await plus.start()
        let weekly = makeModel(defaults: defaults, historyRoot: fixtureRoot, outcome: .loaded(Self.snapshot(plan: "PRO")))
        await weekly.start()
        let api = makeAPI(connected: true)
        api.refresh()
        await api.waitForPendingRequest()
        XCTAssertTrue(api.isValidated, "Canned provider responses must produce the intended connected fixture.")
        XCTAssertNotNil(api.balance)
        XCTAssertNotNil(api.report)
        let keyAPI = makeAPI(connected: false)
        let rejectedAPI = makeAPI(connected: false)
        rejectedAPI.saveKey("invalid-fixture", kind: .regular)

        let fixtures: [(String, AnyView)] = [
            ("onboarding", AnyView(CodexiOSOnboardingView(model: disconnected))),
            ("subscription-disconnected", navigation(CodexiOSSubscriptionConnectionView(model: disconnected))),
            ("subscription-pending-code", navigation(CodexiOSSubscriptionConnectionView(model: pending))),
            ("subscription-code-copied", navigation(CodexiOSSubscriptionConnectionView(model: copied))),
            ("subscription-code-expired", navigation(CodexiOSSubscriptionConnectionView(model: expired))),
            ("subscription-error", navigation(CodexiOSSubscriptionConnectionView(model: failed))),
            ("subscription-connected", navigation(CodexiOSSubscriptionConnectionView(model: plus))),
            ("settings", navigation(CodexiOSSettingsView(model: plus))),
            ("settings-bottom", navigation(CodexiOSSettingsView(model: plus))),
            ("usage-history", navigation(CodexiOSHistoryScreen(model: plus))),
            ("api-landing", navigation(CodexiOSAPIConnectionView(monitor: api))),
            ("api-key", navigation(CodexiOSConnectionDesignFixtures.key(monitor: keyAPI))),
            ("api-key-connected", navigation(CodexiOSConnectionDesignFixtures.key(monitor: api))),
            ("api-key-rejected", navigation(CodexiOSConnectionDesignFixtures.key(monitor: rejectedAPI, initialKey: "invalid-fixture"))),
            ("api-balance", navigation(CodexiOSConnectionDesignFixtures.balance(monitor: api))),
            ("api-reports", navigation(CodexiOSConnectionDesignFixtures.reports(monitor: api))),
            ("dashboard-plus", AnyView(CodexiOSRootView(model: plus))),
            ("dashboard-weekly-only", AnyView(CodexiOSRootView(model: weekly)))
        ]
        let configurations: [CaptureConfiguration] = [
            .init(name: "iphone", size: CGSize(width: 393, height: 852), dynamicType: .large),
            .init(name: "narrow", size: CGSize(width: 375, height: 667), dynamicType: .large),
            .init(name: "ipad-landscape", size: CGSize(width: 1024, height: 768), dynamicType: .large),
            .init(name: "iphone-ax3", size: CGSize(width: 393, height: 852), dynamicType: .accessibility3)
        ]
        for configuration in configurations {
            for scheme in [ColorScheme.light, .dark] {
                defaults.set(scheme == .dark ? "dark" : "light", forKey: CodexiOSSettingsKeys.appearanceMode)
                for (fixtureName, view) in fixtures {
                    let name = "\(fixtureName)-\(configuration.name)-\(scheme == .dark ? "dark" : "light")"
                    let image = try await capture(view, configuration: configuration, scheme: scheme, defaults: defaults,
                        scrollToBottom: fixtureName == "settings-bottom")
                    let png = try XCTUnwrap(image.pngData())
                    if let output { try png.write(to: output.appendingPathComponent(name + ".png"), options: .atomic) }
                    let attachment = XCTAttachment(image: image)
                    attachment.name = name
                    attachment.lifetime = .keepAlways
                    add(attachment)
                }
            }
        }
    }

    private struct CaptureConfiguration {
        let name: String
        let size: CGSize
        let dynamicType: DynamicTypeSize
    }

    private func navigation<V: View>(_ view: V) -> AnyView { AnyView(NavigationStack { view }) }

    private func capture(_ view: AnyView, configuration: CaptureConfiguration, scheme: ColorScheme, defaults: UserDefaults, scrollToBottom: Bool) async throws -> UIImage {
        let hosted = view.defaultAppStorage(defaults)
            .environment(\.dynamicTypeSize, configuration.dynamicType)
            .transaction { $0.disablesAnimations = true }
            .preferredColorScheme(scheme)
        let controller = UIHostingController(rootView: hosted)
        let container = UIViewController()
        let window: UIWindow
        if let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first {
            window = UIWindow(windowScene: scene)
        } else {
            window = UIWindow(frame: CGRect(origin: .zero, size: configuration.size))
        }
        window.frame = CGRect(origin: .zero, size: configuration.size)
        window.overrideUserInterfaceStyle = scheme == .dark ? .dark : .light
        window.rootViewController = container
        container.addChild(controller)
        controller.view.frame = CGRect(origin: .zero, size: configuration.size)
        controller.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        container.view.addSubview(controller.view)
        controller.didMove(toParent: container)
        container.setOverrideTraitCollection(UITraitCollection(traitsFrom: [
            UITraitCollection(horizontalSizeClass: configuration.size.width >= 768 ? .regular : .compact),
            UITraitCollection(verticalSizeClass: .regular),
            UITraitCollection(userInterfaceIdiom: configuration.size.width >= 768 ? .pad : .phone)
        ]), forChild: controller)
        window.isHidden = false
        defer { window.isHidden = true; window.rootViewController = nil }
        container.view.setNeedsLayout()
        container.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(250))
        container.view.layoutIfNeeded()
        if scrollToBottom {
            let candidates = scrollViews(in: controller.view)
            let collection = candidates.compactMap { $0 as? UICollectionView }.max { $0.contentSize.height < $1.contentSize.height }
            let preferredScrollView: UIScrollView? = collection ?? candidates.max { $0.contentSize.height < $1.contentSize.height }
            let scrollView = try XCTUnwrap(preferredScrollView,
                "Settings must contain its native Form scroll view.")
            var previousHeight: CGFloat = -1
            var stablePasses = 0
            // Native Form row heights are lazy. Request the actual final item before settling the content extent.
            for _ in 0..<10 {
                if let collection,
                   let section = (0..<collection.numberOfSections).reversed().first(where: { collection.numberOfItems(inSection: $0) > 0 }) {
                    collection.scrollToItem(at: IndexPath(item: collection.numberOfItems(inSection: section) - 1, section: section),
                        at: .bottom, animated: false)
                } else if let table = scrollView as? UITableView,
                          let section = (0..<table.numberOfSections).reversed().first(where: { table.numberOfRows(inSection: $0) > 0 }) {
                    table.scrollToRow(at: IndexPath(row: table.numberOfRows(inSection: section) - 1, section: section), at: .bottom, animated: false)
                }
                let maximumOffset = max(-scrollView.adjustedContentInset.top,
                    scrollView.contentSize.height - scrollView.bounds.height + scrollView.adjustedContentInset.bottom)
                scrollView.setContentOffset(CGPoint(x: 0, y: maximumOffset), animated: false)
                try await Task.sleep(for: .milliseconds(150))
                container.view.layoutIfNeeded()
                let settledMaximum = max(-scrollView.adjustedContentInset.top,
                    scrollView.contentSize.height - scrollView.bounds.height + scrollView.adjustedContentInset.bottom)
                if abs(scrollView.contentSize.height - previousHeight) < 0.5 && abs(scrollView.contentOffset.y - settledMaximum) < 0.5 {
                    stablePasses += 1
                    if stablePasses >= 2 { break }
                } else { stablePasses = 0 }
                previousHeight = scrollView.contentSize.height
            }
        }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        let renderer = UIGraphicsImageRenderer(size: configuration.size, format: format)
        return renderer.image { _ in
            XCTAssertTrue(window.drawHierarchy(in: CGRect(origin: .zero, size: configuration.size), afterScreenUpdates: true))
        }
    }

    private func scrollViews(in view: UIView) -> [UIScrollView] {
        ((view as? UIScrollView).map { [$0] } ?? []) + view.subviews.flatMap { scrollViews(in: $0) }
    }

    private func makeModel(defaults: UserDefaults, historyRoot: URL, outcome: CodexiOSSnapshotOutcome, pending: Bool = false) -> CodexiOSModel {
        let service = StubCodexiOSService(outcomeHandler: { outcome }, recoverHandler: {
            pending ? CodexiOSDeviceAuthStart(flowID: "fixture-flow", verificationURL: URL(string: "https://fixture.invalid/device")!, userCode: "ABCD-1234") : nil
        })
        return CodexiOSModel(service: service, defaults: defaults,
            historyStore: CodexUsageHistoryStore(fileURL: historyRoot.appendingPathComponent("fixture-history-\(UUID().uuidString).json")),
            liveActivityManager: StubCodexiOSLiveActivityManager(state: .init(isAvailable: true, activityID: nil)),
            backgroundRefreshScheduler: StubBackgroundRefreshScheduler(),
            pushRegistrationManager: DesignWakeRegistration(), widgetPublisher: DesignWidgetPublisher(),
            apiMonitor: makeAPI(connected: false), openURLAction: { _ in false }, copyTextAction: { _ in })
    }

    private func makeAPI(connected: Bool) -> OpenAIMonitorModel {
        OpenAIMonitorModel(client: OpenAIAPIClient(transport: { request in
            let path = request.url?.path ?? ""
            let body: String
            switch path {
            case "/v1/models": body = #"{"data":[]}"#
            case "/v1/dashboard/billing/credit_grants": body = #"{"total_available":2.37}"#
            case "/v1/organization/usage/completions":
                body = #"{"data":[{"results":[{"input_tokens":125000,"input_cached_tokens":25000,"output_tokens":34000,"num_model_requests":12,"model":"sample-model"}]}],"has_more":false}"#
            case "/v1/organization/costs":
                body = #"{"data":[{"results":[{"amount":{"value":0.63,"currency":"usd"}}]}],"has_more":false}"#
            default: throw OpenAIAPIError.unavailable
            }
            return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }), load: { connected ? .init(key: "sk-design-fixture", kind: .admin) : nil },
            persist: { _ in }, delete: {}, loadConsent: { connected }, persistConsent: { _ in })
    }

    private static func snapshot(plan: String) -> CodexSnapshot {
        let preview = CodexiOSPreviewData.snapshot(now: Date(), planType: plan)
        return CodexSnapshot(capturedAt: preview.capturedAt, executablePath: "Design fixture",
            account: .init(authType: "chatGPT", email: nil, planType: plan), limits: preview.limits)
    }
}

@MainActor private final class DesignWakeRegistration: CodexiOSPushRegistering {
    func enable() async {}
    func disable() async {}
    func didRegister(deviceToken: Data) async {}
}

@MainActor private struct DesignWidgetPublisher: CodexiOSWidgetPublishing {
    func publish(_ value: MonitoringWidgetSnapshot) {}
    func clear() {}
    func hasInstalledWidgets() async -> Bool { false }
}
