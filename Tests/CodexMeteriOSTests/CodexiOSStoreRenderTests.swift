import Foundation
import SwiftUI
import UIKit
import XCTest
import CodexMeterCore
@testable import Codexex

/// Native, full-resolution store captures. Provider responses and all credential,
/// background, clipboard and URL-opening dependencies are local fixtures.
/// The framing pipeline discloses Sample data; no extra app UI is introduced here.
@MainActor
final class CodexiOSStoreRenderTests: XCTestCase {
    func testCaptureAppStoreScreenshots() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["CODEXEX_STORE_CAPTURE"] == "1" else {
            throw XCTSkip("Opt in with CODEXEX_STORE_CAPTURE=1.")
        }
        let output = environment["CODEXEX_STORE_RENDER_OUTPUT"].map { URL(fileURLWithPath: $0, isDirectory: true) }
        if let output { try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true) }
        let dark = environment["CODEXEX_STORE_APPEARANCE"] != "light"
        let medium = environment["CODEXEX_STORE_IPHONE_SIZE"] == "medium"
        let family = environment["CODEXEX_STORE_FAMILY"] ?? "all"
        let configurations = [
            StoreViewport(family: "iphone", points: medium ? .init(width: 402, height: 874) : .init(width: 440, height: 956), scale: 3),
            StoreViewport(family: "ipad", points: .init(width: 1032, height: 1376), scale: 2)
        ].filter { family == "all" || family == $0.family }
        XCTAssertFalse(configurations.isEmpty, "Unknown store capture family")
        let reference = Date()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("CodexexStoreCapture-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        var suites: [String] = []
        defer { suites.forEach { UserDefaults(suiteName: $0)?.removePersistentDomain(forName: $0) } }
        func preferences(preview: Bool) -> UserDefaults {
            let suite = "CodexexStoreCapture.\(UUID().uuidString)"; suites.append(suite)
            let defaults = UserDefaults(suiteName: suite)!
            defaults.set(dark ? "dark" : "light", forKey: CodexiOSSettingsKeys.appearanceMode)
            defaults.set(preview, forKey: CodexiOSSettingsKeys.previewModeEnabled)
            defaults.set(false, forKey: CodexiOSSettingsKeys.refreshWhenActive)
            defaults.set(false, forKey: CodexiOSSettingsKeys.autoCheckSignInOnReturn)
            defaults.set(false, forKey: CodexiOSSettingsKeys.matrixThemeEnabled)
            defaults.set(true, forKey: CodexiOSSettingsKeys.showHistory)
            return defaults
        }
        let quotaPreferences = preferences(preview: true)
        let weeklyPreferences = preferences(preview: true)
        let onboardingPreferences = preferences(preview: false)
        let apiPreferences = preferences(preview: false)
        let quota = makeModel(defaults: quotaPreferences, directory: directory)
        let weekly = makeModel(defaults: weeklyPreferences, directory: directory)
        let onboarding = makeModel(defaults: onboardingPreferences, directory: directory)
        await quota.start(); await weekly.start(); await onboarding.start()
        quota.snapshot = CodexiOSPreviewData.snapshot(now: reference, planType: "PLUS")
        let dashboard = try XCTUnwrap(quota.snapshot)
        quota.usageHistory = Array(CodexiOSPreviewData.history(now: reference).dropLast()) + [
            CodexUsageHistorySample(capturedAt: dashboard.capturedAt,
                fiveHour: dashboard.codexLimit?.fiveHourWindow.map(CodexUsageHistoryWindow.init(from:)),
                weekly: dashboard.codexLimit?.weeklyWindow.map(CodexUsageHistoryWindow.init(from:)),
                codexCreditsBalance: dashboard.codexLimit?.credits?.balance)
        ]
        XCTAssertEqual(quota.usageHistory.last?.fiveHour?.usedPercent, dashboard.codexLimit?.fiveHourWindow?.usedPercent)
        XCTAssertEqual(quota.usageHistory.last?.weekly?.usedPercent, dashboard.codexLimit?.weeklyWindow?.usedPercent)
        weekly.snapshot = CodexiOSPreviewData.snapshot(now: reference, planType: "PRO")
        weekly.usageHistory = quota.usageHistory
        let api = makeAPI(connected: true)
        api.refresh(); await api.waitForPendingRequest()
        XCTAssertTrue(api.isValidated)
        XCTAssertNotNil(api.balance)
        XCTAssertNotNil(api.report)
        XCTAssertNil(api.error)
        let fixtures: [(String, AnyView, UserDefaults)] = [
            ("01-quota", AnyView(CodexiOSRootView(model: quota)), quotaPreferences),
            ("02-weekly", AnyView(CodexiOSRootView(model: weekly)), weeklyPreferences),
            ("03-history", pushed(parent: "Codexex", CodexiOSHistoryScreen(model: quota)), quotaPreferences),
            ("04-api-balance", pushed(parent: "OpenAI API", CodexiOSConnectionDesignFixtures.balance(monitor: api)), apiPreferences),
            ("05-settings", pushed(parent: "Codexex", CodexiOSSettingsView(model: quota)), quotaPreferences),
            ("06-onboarding", AnyView(CodexiOSOnboardingView(model: onboarding)), onboardingPreferences),
            ("07-api-setup", pushed(parent: "Settings", CodexiOSAPIConnectionView(monitor: api)), apiPreferences)
        ]
        for configuration in configurations {
            let folder = output?.appendingPathComponent(configuration.family, isDirectory: true)
            if let folder { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
            for (name, view, defaults) in fixtures {
                let image = try await capture(view, viewport: configuration, dark: dark, defaults: defaults)
                let pixels = try XCTUnwrap(image.cgImage)
                XCTAssertEqual(pixels.width, Int(configuration.points.width * configuration.scale))
                XCTAssertEqual(pixels.height, Int(configuration.points.height * configuration.scale))
                let attachment = XCTAttachment(image: image)
                attachment.name = "codexex-store-\(configuration.family)-\(name)"
                attachment.lifetime = .keepAlways
                add(attachment)
                if let folder { try XCTUnwrap(image.pngData()).write(to: folder.appendingPathComponent(name + ".png"), options: .atomic) }
            }
        }
    }

    private func pushed<V: View>(parent: String, _ screen: V) -> AnyView {
        AnyView(StoreNavigationCapture(parentTitle: parent, screen: AnyView(screen)))
    }

    private func capture(_ view: AnyView, viewport: StoreViewport, dark: Bool, defaults: UserDefaults) async throws -> UIImage {
        let host = UIHostingController(rootView: view.defaultAppStorage(defaults)
            .environment(\.dynamicTypeSize, .large)
            .transaction { $0.disablesAnimations = true }
            .preferredColorScheme(dark ? .dark : .light))
        let container = UIViewController()
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let previousKeyWindow = scenes.flatMap(\.windows).first { $0.isKeyWindow }
        let window: UIWindow
        if let scene = scenes.first {
            window = UIWindow(windowScene: scene)
            window.frame = scene.coordinateSpace.bounds
        } else {
            window = UIWindow(frame: UIScreen.main.bounds)
        }
        window.overrideUserInterfaceStyle = dark ? .dark : .light
        window.rootViewController = container
        container.view.frame = window.bounds
        container.addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        container.view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: container.view.leadingAnchor),
            host.view.topAnchor.constraint(equalTo: container.view.topAnchor),
            host.view.widthAnchor.constraint(equalToConstant: viewport.points.width),
            host.view.heightAnchor.constraint(equalToConstant: viewport.points.height)
        ])
        host.didMove(toParent: container)
        container.setOverrideTraitCollection(UITraitCollection(traitsFrom: [
            UITraitCollection(horizontalSizeClass: viewport.family == "ipad" ? .regular : .compact),
            UITraitCollection(verticalSizeClass: .regular),
            UITraitCollection(userInterfaceIdiom: viewport.family == "ipad" ? .pad : .phone)
        ]), forChild: host)
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true; window.rootViewController = nil
            host.willMove(toParent: nil); host.view.removeFromSuperview(); host.removeFromParent()
            previousKeyWindow?.makeKey()
        }
        for _ in 0..<2 {
            container.view.setNeedsLayout(); container.view.layoutIfNeeded()
            host.view.setNeedsLayout(); host.view.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(250))
        }
        container.view.layoutIfNeeded(); host.view.layoutIfNeeded()
        XCTAssertEqual(host.view.bounds, CGRect(origin: .zero, size: viewport.points), "Store capture viewport must match requested dimensions")
        let format = UIGraphicsImageRendererFormat()
        format.scale = viewport.scale; format.opaque = true
        return UIGraphicsImageRenderer(size: viewport.points, format: format).image { _ in
            XCTAssertTrue(host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true))
        }
    }

    private func makeModel(defaults: UserDefaults, directory: URL) -> CodexiOSModel {
        let activity = StubCodexiOSLiveActivityManager(state: .init(isAvailable: true, activityID: nil))
        return CodexiOSModel(service: StubCodexiOSService(outcomeHandler: { .signedOut }), defaults: defaults,
            historyStore: CodexUsageHistoryStore(fileURL: directory.appendingPathComponent("history-\(UUID().uuidString).json")),
            liveActivityManager: activity, liveActivityCoordinator: activity,
            backgroundRefreshScheduler: StubBackgroundRefreshScheduler(), pushRegistrationManager: StoreWakeRegistration(),
            widgetPublisher: StoreWidgetPublisher(), apiMonitor: makeAPI(connected: false),
            openURLAction: { _ in XCTFail("Store capture cannot open provider authorization"); return false },
            copyTextAction: { _ in XCTFail("Store capture cannot modify the clipboard") })
    }
    private func makeAPI(connected: Bool) -> OpenAIMonitorModel {
        OpenAIMonitorModel(client: .init(transport: { request in
            let body: String
            switch request.url?.path {
            case "/v1/models": body = #"{"data":[]}"#
            case "/v1/dashboard/billing/credit_grants": body = #"{"total_available":2.37}"#
            case "/v1/organization/usage/completions":
                body = #"{"data":[{"results":[{"input_tokens":125000,"input_cached_tokens":25000,"output_tokens":34000,"num_model_requests":12,"model":"sample-model"}]}],"has_more":false}"#
            case "/v1/organization/costs":
                body = #"{"data":[{"results":[{"amount":{"value":0.63,"currency":"usd"}}]}],"has_more":false}"#
            default: throw OpenAIAPIError.unavailable
            }
            return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }), load: { connected ? .init(key: "sk-store-fixture-only", kind: .admin) : nil },
            persist: { _ in XCTFail("Store capture cannot persist credentials") }, delete: {},
            loadConsent: { connected }, persistConsent: { _ in XCTFail("Store capture cannot change consent") })
    }
}

private struct StoreViewport {
    let family: String
    let points: CGSize
    let scale: CGFloat
}

/// The destination is a real native push, so SwiftUI supplies its actual back
/// control. The blank parent is never captured and draws no imitation app UI.
private struct StoreNavigationCapture: View {
    let parentTitle: String
    let screen: AnyView
    @State private var path: [Int] = [1]

    var body: some View {
        NavigationStack(path: $path) {
            Color.clear
                .navigationTitle(parentTitle)
                .navigationBarTitleDisplayMode(.inline)
                .navigationDestination(for: Int.self) { _ in screen }
        }
        .tint(CodexiOSTheme.actionTint)
    }
}
@MainActor private struct StoreWakeRegistration: CodexiOSPushRegistering {
    func enable() async { XCTFail("Store capture cannot enroll APNs") }
    func disable() async {}
    func didRegister(deviceToken: Data) async { XCTFail("Store capture cannot register a device") }
}
@MainActor private struct StoreWidgetPublisher: CodexiOSWidgetPublishing {
    func publish(_ snapshot: MonitoringWidgetSnapshot) {}
    func clear() {}
    func hasInstalledWidgets() async -> Bool { false }
}
