import CodexMeterCore
import SwiftUI
import UIKit
import WidgetKit
import XCTest

/// Opt-in evidence from the production SwiftUI bodies, with display-only sample observations.
@MainActor
final class CodexWidgetDesignRenderTests: XCTestCase {
    func testCaptureWidgetAndLiveActivityPresentations() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["HIG_DESIGN_CAPTURE"] == "1" || environment["HIG_DESIGN_RENDER_OUTPUT"] != nil else {
            throw XCTSkip("Set HIG_DESIGN_CAPTURE=1 or HIG_DESIGN_RENDER_OUTPUT to capture widget design evidence.")
        }
        let output = environment["HIG_DESIGN_RENDER_OUTPUT"].map { URL(fileURLWithPath: $0, isDirectory: true) }
        if let output { try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true) }
        let now = Date()
        let textSizes: [(String, DynamicTypeSize)] = [("large", .large), ("ax3", .accessibility3)]
        let widgetSizes: [(String, WidgetFamily, CGSize)] = [
            ("small", .systemSmall, CGSize(width: 158, height: 158)),
            ("medium", .systemMedium, CGSize(width: 338, height: 158))
        ]

        for (textName, textSize) in textSizes {
            for (sizeName, family, size) in widgetSizes {
                for status in ["fresh", "stale", "empty"] {
                    for showsAPI in [false, true] {
                        let name = "codexex-widget-\(showsAPI ? "api" : "subscription")-\(status)-\(sizeName)-\(textName)"
                        let view = CodexWidgetDesignFixtures.home(
                            snapshot: snapshot(status: status, now: now), date: now, family: family, showsAPI: showsAPI
                        )
                        .padding(16)
                        .background(CodexWidgetDesignFixtures.homeBackground)
                        try await attach(view, name: name, size: size, textSize: textSize, output: output)
                    }
                }
            }
            for isStale in [false, true] {
                for showsUsedQuota in [false, true] {
                    for expanded in [false, true] {
                        let name = "codexex-live-activity-\(showsUsedQuota ? "used" : "left")-\(isStale ? "stale" : "fresh")-\(expanded ? "expanded" : "lockscreen")-\(textName)"
                        let view = CodexWidgetDesignFixtures.activity(
                            state: activityState(stale: isStale, showsUsedQuota: showsUsedQuota, now: now), isStale: isStale
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .background(expanded ? Color.black : CodexWidgetDesignFixtures.activityBackground)
                        try await attach(view, name: name, size: CGSize(width: 361, height: 180), textSize: textSize, output: output)
                    }
                }
            }
        }
    }

    private func snapshot(status: String, now: Date) -> MonitoringWidgetSnapshot {
        guard status != "empty" else { return .empty }
        let stale = status == "stale"
        let capturedAt = stale ? now.addingTimeInterval(-3_600) : now
        let quota = CodexSnapshot(
            capturedAt: capturedAt, executablePath: "Design fixture",
            account: .init(authType: "preview", email: nil, planType: nil),
            limits: [.init(id: "codex", rawLimitName: nil, bucket: .codex,
                primary: .init(usedPercent: 20, windowDurationMinutes: 300, resetsAt: now.addingTimeInterval(7_200)),
                secondary: .init(usedPercent: 32, windowDurationMinutes: 10_080, resetsAt: now.addingTimeInterval(86_400)), credits: nil)]
        )
        return .init(snapshot: quota, quotaStale: stale, apiRemainingUSD: Decimal(string: "2.37"), apiUpdatedAt: capturedAt, apiStale: stale)
    }

    private func activityState(stale: Bool, showsUsedQuota: Bool, now: Date) -> CodexLiveActivityAttributes.ContentState {
        .init(weeklyPercentLeft: 68, weeklyUsedFraction: 0.32, weeklyResetAt: now.addingTimeInterval(86_400),
            fiveHourPercentLeft: 80, fiveHourResetAt: now.addingTimeInterval(7_200), isStale: stale,
            showsUsedQuota: showsUsedQuota, lastUpdatedAt: stale ? now.addingTimeInterval(-3_600) : now)
    }

    private func attach<V: View>(_ view: V, name: String, size: CGSize, textSize: DynamicTypeSize, output: URL?) async throws {
        let hosted = view
            .environment(\.dynamicTypeSize, textSize)
            .preferredColorScheme(.dark)
            .frame(width: size.width, height: size.height)
            .ignoresSafeArea()
            .transaction { $0.disablesAnimations = true }
        let controller = UIHostingController(rootView: hosted)
        controller.safeAreaRegions = []
        controller.view.backgroundColor = .clear
        let container = UIViewController()
        container.view.backgroundColor = .clear
        let previousKeyWindow = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
        let window: UIWindow
        if let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first {
            window = UIWindow(windowScene: scene)
            window.frame = scene.coordinateSpace.bounds
        } else {
            window = UIWindow(frame: UIScreen.main.bounds)
        }
        window.overrideUserInterfaceStyle = .dark
        window.rootViewController = container
        container.view.frame = window.bounds
        container.addChild(controller)
        controller.view.translatesAutoresizingMaskIntoConstraints = false
        container.view.addSubview(controller.view)
        NSLayoutConstraint.activate([
            controller.view.leadingAnchor.constraint(equalTo: container.view.leadingAnchor),
            controller.view.topAnchor.constraint(equalTo: container.view.topAnchor),
            controller.view.widthAnchor.constraint(equalToConstant: size.width),
            controller.view.heightAnchor.constraint(equalToConstant: size.height)
        ])
        controller.didMove(toParent: container)
        container.setOverrideTraitCollection(UITraitCollection(traitsFrom: [
            UITraitCollection(horizontalSizeClass: .compact),
            UITraitCollection(verticalSizeClass: .regular),
            UITraitCollection(preferredContentSizeCategory: textSize == .accessibility3 ? .accessibilityExtraLarge : .large)
        ]), forChild: controller)
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
            previousKeyWindow?.makeKey()
        }
        for _ in 0..<2 {
            container.view.setNeedsLayout()
            container.view.layoutIfNeeded()
            controller.view.setNeedsLayout()
            controller.view.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(250))
        }
        container.view.layoutIfNeeded()
        controller.view.layoutIfNeeded()
        XCTAssertEqual(controller.view.bounds, CGRect(origin: .zero, size: size), "Capture viewport must match the widget or Live Activity bounds.")
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        let image = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            XCTAssertTrue(controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true))
        }
        if let output {
            try XCTUnwrap(image.pngData()).write(to: output.appendingPathComponent(name + ".png"), options: .atomic)
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
