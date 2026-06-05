import AppKit
import SwiftUI
import XCTest
@testable import CodexMeterApp
@testable import CodexMeterCore

@MainActor
final class PopupReferenceRenderTests: XCTestCase {
    func testReferencePopupRendersNonBlackGlassFrame() throws {
        setenv("CODEXEX_REFERENCE_RENDER", "1", 1)
        defer { unsetenv("CODEXEX_REFERENCE_RENDER") }

        let suiteName = "PopupReferenceRenderTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let model = CodexMenuBarModel(settingsStore: CodexAppSettingsStore(defaults: defaults))

        let view = PopupRootView(
            model: model,
            displayMode: .settingsPreview,
            reduceMotionOverride: true,
            previewReferenceDate: Date(timeIntervalSince1970: 1_800_000_000)
        )
            .frame(width: GlassTokens.popupWidth, height: GlassTokens.popupMaxHeight)
        let renderer = ImageRenderer(content: view)
        renderer.proposedSize = ProposedViewSize(
            width: GlassTokens.popupWidth,
            height: GlassTokens.popupMaxHeight
        )
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.nsImage)
        let tiffData = try XCTUnwrap(image.tiffRepresentation)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: tiffData))

        XCTAssertEqual(bitmap.size.width, GlassTokens.popupWidth, accuracy: 0.5)
        XCTAssertEqual(bitmap.size.height, GlassTokens.popupMaxHeight, accuracy: 0.5)

        let sample = PixelSample(bitmap: bitmap)
        XCTAssertGreaterThan(sample.nonBlackShare, 0.50)
        XCTAssertGreaterThan(sample.brightGlassShare, 0.20)

        let outputDirectory = try XCTUnwrap(
            FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        )
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let pngURL = outputDirectory.appendingPathComponent("codexex-reference-popup-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: pngURL) }
        let pngData = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try pngData.write(to: pngURL, options: .atomic)
        XCTAssertTrue(FileManager.default.fileExists(atPath: pngURL.path))
    }

    func testHistoryModeSelectorShowsSelectedIndicatorInBothAppearances() throws {
        for colorScheme in [ColorScheme.light, .dark] {
            let view = PopupHistoryModeSelector(historyMode: .dailyPeaks, onHistoryModeChange: { _ in })
            .padding(14)
            .background(CodexTheme.window)
            .preferredColorScheme(colorScheme)
            .frame(width: 200, height: 60)

            let renderer = ImageRenderer(content: view)
            renderer.proposedSize = ProposedViewSize(width: 200, height: 60)
            renderer.scale = 2
            let image = try XCTUnwrap(renderer.nsImage, "selector render should produce an image for \(colorScheme)")
            let tiffData = try XCTUnwrap(image.tiffRepresentation)
            let bitmap = try XCTUnwrap(NSBitmapImageRep(data: tiffData))
            let sample = PixelSample(bitmap: bitmap)

            XCTAssertGreaterThan(
                sample.accentBluePixels,
                20,
                "selected history mode indicator should be visible for \(colorScheme)"
            )
        }
    }

    func testFailurePopupRendersReadablePrimaryAction() async throws {
        let model = CodexMenuBarModel(
            service: RenderFailingService(),
            localUsageProvider: RenderLocalUsageProvider()
        )

        await model.refreshNow(manual: true)

        XCTAssertEqual(model.statusCardTitle, "Couldn’t load quota")
        XCTAssertEqual(model.statusCardMessage, "Codexex couldn’t start its bundled helper. Reopen the app or refresh quota.")

        let view = PopupRootView(
            model: model,
            displayMode: .live,
            reduceMotionOverride: true,
            previewReferenceDate: Date(timeIntervalSince1970: 1_800_000_000)
        )
        .frame(width: GlassTokens.popupWidth, height: 260)

        let renderer = ImageRenderer(content: view)
        renderer.proposedSize = ProposedViewSize(width: GlassTokens.popupWidth, height: 260)
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.nsImage)
        let tiffData = try XCTUnwrap(image.tiffRepresentation)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: tiffData))
        let sample = PixelSample(bitmap: bitmap)

        XCTAssertGreaterThan(
            sample.accentBluePixels,
            300,
            "failure popup should render a visible primary Refresh action"
        )
    }

    func testPopupRootReportsContentHeightInsteadOfMaxHeight() throws {
        let suiteName = "PopupReferenceRenderTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let model = CodexMenuBarModel(settingsStore: CodexAppSettingsStore(defaults: defaults))
        model.enablePreviewMode()

        let view = PopupRootView(
            model: model,
            displayMode: .live,
            reduceMotionOverride: true,
            previewReferenceDate: Date(timeIntervalSince1970: 1_800_000_000)
        )
        let hostingController = NSHostingController(rootView: view)
        let fittingSize = hostingController.sizeThatFits(
            in: NSSize(width: GlassTokens.popupWidth, height: GlassTokens.popupMaxHeight)
        )

        XCTAssertLessThan(fittingSize.height, GlassTokens.popupMaxHeight - 24)
        XCTAssertGreaterThan(fittingSize.height, 360)
    }

    func testLivePopupFooterRendersVisibleActionRail() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let model = CodexMenuBarModel(
            service: RenderSuccessfulService(now: now),
            localUsageProvider: RenderLocalUsageProvider()
        )

        await model.refreshNow(manual: true)

        let view = PopupRootView(
            model: model,
            displayMode: .live,
            reduceMotionOverride: true,
            previewReferenceDate: now
        )
        let hostingController = NSHostingController(rootView: view)
        let fittingSize = hostingController.sizeThatFits(
            in: NSSize(width: GlassTokens.popupWidth, height: GlassTokens.popupMaxHeight)
        )
        let renderedView = view.frame(width: GlassTokens.popupWidth, height: fittingSize.height)
        let renderer = ImageRenderer(content: renderedView)
        renderer.proposedSize = ProposedViewSize(width: GlassTokens.popupWidth, height: fittingSize.height)
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.nsImage)
        let tiffData = try XCTUnwrap(image.tiffRepresentation)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: tiffData))
        let sample = PixelSample(bitmap: bitmap)

        XCTAssertGreaterThan(
            sample.lowerAccentBluePixels,
            300,
            "live popup footer should render a visible primary Refresh action near the bottom edge"
        )
    }
}

private struct RenderSuccessfulService: CodexServiceClient {
    let now: Date

    func fetchSnapshotResponse() async throws -> CodexServiceSnapshotResponse {
        CodexServiceSnapshotResponse(
            authMode: .chatGPT,
            snapshot: CodexPreviewData.snapshot(now: now),
            errorMessage: nil
        )
    }

    func beginChatGPTSignIn() async throws -> CodexDeviceAuthStart {
        throw NSError(domain: "RenderSuccessfulService", code: 1)
    }

    func completeChatGPTSignIn(flowID: String) async throws -> CodexDeviceAuthPollResult {
        throw NSError(domain: "RenderSuccessfulService", code: 2)
    }

    func signOut() async throws {
        throw NSError(domain: "RenderSuccessfulService", code: 3)
    }
}

private struct RenderFailingService: CodexServiceClient {
    func fetchSnapshotResponse() async throws -> CodexServiceSnapshotResponse {
        throw NSError(
            domain: "RenderFailingService",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "The file \"codexex-helper\" doesn't exist."]
        )
    }

    func beginChatGPTSignIn() async throws -> CodexDeviceAuthStart {
        throw NSError(domain: "RenderFailingService", code: 2)
    }

    func completeChatGPTSignIn(flowID: String) async throws -> CodexDeviceAuthPollResult {
        throw NSError(domain: "RenderFailingService", code: 3)
    }

    func signOut() async throws {
        throw NSError(domain: "RenderFailingService", code: 4)
    }
}

private struct RenderLocalUsageProvider: CodexLocalUsageProviding {
    func fetchLocalUsageSummary() async -> CodexLocalUsageSummary? {
        nil
    }
}

private struct PixelSample {
    let nonBlackShare: Double
    let brightGlassShare: Double
    let accentBluePixels: Int
    let lowerAccentBluePixels: Int

    init(bitmap: NSBitmapImageRep) {
        let width = bitmap.pixelsWide
        let height = bitmap.pixelsHigh
        var nonBlack = 0
        var brightGlass = 0
        var accentBlue = 0
        var lowerAccentBlue = 0
        var total = 0
        let step = 8
        let lowerBandStart = Int(Double(height) * 0.68)

        for y in 0..<height {
            for x in 0..<width {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else {
                    continue
                }
                let red = color.redComponent
                let green = color.greenComponent
                let blue = color.blueComponent

                if blue > 0.65 && red < 0.45 && green < 0.78 && blue - red > 0.25 {
                    accentBlue += 1
                    if y >= lowerBandStart {
                        lowerAccentBlue += 1
                    }
                }

                if y.isMultiple(of: step), x.isMultiple(of: step) {
                    total += 1
                    let brightness = (red + green + blue) / 3

                    if brightness > 0.03 {
                        nonBlack += 1
                    }
                    if brightness > 0.78 && abs(red - green) < 0.14 && abs(green - blue) < 0.18 {
                        brightGlass += 1
                    }
                }
            }
        }

        let denominator = Double(max(1, total))
        nonBlackShare = Double(nonBlack) / denominator
        brightGlassShare = Double(brightGlass) / denominator
        accentBluePixels = accentBlue
        lowerAccentBluePixels = lowerAccentBlue
    }
}
