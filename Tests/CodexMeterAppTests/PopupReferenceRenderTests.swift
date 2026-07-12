import AppKit
import SwiftUI
import XCTest
@testable import CodexMeterApp
@testable import CodexMeterCore

@MainActor
final class PopupReferenceRenderTests: XCTestCase {
    func testReferencePopupRendersNonBlackGlassFrameInLightAndDark() throws {
        setenv("CODEXEX_REFERENCE_RENDER", "1", 1)
        defer { unsetenv("CODEXEX_REFERENCE_RENDER") }

        for appearanceMode in [CodexAppearanceMode.light, .dark] {
            let suiteName = "PopupReferenceRenderTests.\(UUID().uuidString)"
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
            defaults.removePersistentDomain(forName: suiteName)
            defer { defaults.removePersistentDomain(forName: suiteName) }
            let model = CodexMenuBarModel(settingsStore: CodexAppSettingsStore(defaults: defaults))
            model.setAppearanceMode(appearanceMode)

            let view = PopupRootView(
                model: model,
                displayMode: .settingsPreview,
                reduceMotionOverride: true,
                previewReferenceDate: Date(timeIntervalSince1970: 1_800_000_000)
            )
            let bitmap = try renderedBitmap(
                for: view,
                width: GlassTokens.popupWidth,
                height: GlassTokens.popupMaxHeight
            )

            XCTAssertEqual(bitmap.size.width, GlassTokens.popupWidth, accuracy: 0.5)
            XCTAssertEqual(bitmap.size.height, GlassTokens.popupMaxHeight, accuracy: 0.5)

            let sample = PixelSample(bitmap: bitmap)
            XCTAssertGreaterThan(sample.nonBlackShare, 0.50, "popup should render content in \(appearanceMode.title)")
            XCTAssertGreaterThan(
                sample.brightGlassShare,
                appearanceMode == .light ? 0.20 : 0.01,
                "popup should render readable glass/text highlights in \(appearanceMode.title)"
            )

            let outputDirectory = try XCTUnwrap(
                FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            )
            try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
            let pngURL = outputDirectory.appendingPathComponent(
                "codexex-reference-popup-\(appearanceMode.rawValue)-\(UUID().uuidString).png"
            )
            defer { try? FileManager.default.removeItem(at: pngURL) }
            let pngData = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            try pngData.write(to: pngURL, options: .atomic)
            XCTAssertTrue(FileManager.default.fileExists(atPath: pngURL.path))
        }
    }

    func testHistoryModeSelectorRendersCompactCurrentModeInBothAppearances() throws {
        for colorScheme in [ColorScheme.light, .dark] {
            for historyMode in PopupHistoryMode.allCases {
                let view = PopupHistoryModeSelector(historyMode: historyMode, onHistoryModeChange: { _ in })
                    .padding(10)
                    .background(CodexTheme.window)
                    .preferredColorScheme(colorScheme)
                let hostingController = NSHostingController(rootView: view)
                let fittingSize = hostingController.sizeThatFits(in: NSSize(width: 220, height: 44))

                XCTAssertGreaterThanOrEqual(
                    fittingSize.width,
                    70,
                    "history mode control should reserve width for \(historyMode.title) in \(colorScheme)"
                )
                XCTAssertLessThanOrEqual(
                    fittingSize.width,
                    128,
                    "history mode control should fit as a compact menu-sized control for \(historyMode.title) in \(colorScheme)"
                )
                XCTAssertLessThanOrEqual(
                    fittingSize.height,
                    44,
                    "history mode control should keep a compact height for \(historyMode.title) in \(colorScheme)"
                )

                let bitmap = try renderedBitmap(for: view, width: 128, height: 44)
                let sample = PixelSample(bitmap: bitmap)

                XCTAssertGreaterThan(
                    sample.labelAccentBluePixels,
                    12,
                    "current history mode label should be visible for \(historyMode.title) in \(colorScheme)"
                )
                XCTAssertGreaterThan(
                    sample.accentBluePixels,
                    sample.lowerAccentBluePixels,
                    "selected history mode evidence should not be only a lower accent mark for \(historyMode.title) in \(colorScheme)"
                )
            }
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
        let bitmap = try renderedBitmap(for: view, width: GlassTokens.popupWidth, height: 260)
        let sample = PixelSample(bitmap: bitmap)

        XCTAssertGreaterThan(
            sample.accentBluePixels,
            300,
            "failure popup should render a visible primary Refresh action"
        )
    }

    func testPreviewModePopupFitsUnder600PointsInAllHistoryModes() throws {
        for historyMode in PopupHistoryMode.allCases {
            let suiteName = "PopupReferenceRenderTests.\(UUID().uuidString)"
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
            defaults.removePersistentDomain(forName: suiteName)
            defer { defaults.removePersistentDomain(forName: suiteName) }
            let model = CodexMenuBarModel(settingsStore: CodexAppSettingsStore(defaults: defaults))
            model.enablePreviewMode()
            model.setDefaultHistoryMode(historyMode)

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

            XCTAssertLessThan(
                fittingSize.height,
                540,
                "Preview Mode popup should fit under 540pt in \(historyMode.title)"
            )
            XCTAssertGreaterThan(fittingSize.height, 320)
            XCTAssertLessThan(fittingSize.height, GlassTokens.popupMaxHeight)
        }
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
        let bitmap = try renderedBitmap(for: view, width: GlassTokens.popupWidth, height: fittingSize.height)
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

@MainActor
private func renderedBitmap<Content: View>(
    for view: Content,
    width: CGFloat,
    height: CGFloat
) throws -> NSBitmapImageRep {
    let renderedView = view.frame(width: width, height: height)
    let renderer = ImageRenderer(content: renderedView)
    renderer.proposedSize = ProposedViewSize(width: width, height: height)
    renderer.scale = 2
    let image = try XCTUnwrap(renderer.nsImage)
    let tiffData = try XCTUnwrap(image.tiffRepresentation)
    return try XCTUnwrap(NSBitmapImageRep(data: tiffData))
}

private struct PixelSample {
    let nonBlackShare: Double
    let brightGlassShare: Double
    let accentBluePixels: Int
    let labelAccentBluePixels: Int
    let lowerAccentBluePixels: Int

    init(bitmap: NSBitmapImageRep) {
        let width = bitmap.pixelsWide
        let height = bitmap.pixelsHigh
        var nonBlack = 0
        var brightGlass = 0
        var accentBlue = 0
        var labelAccentBlue = 0
        var lowerAccentBlue = 0
        var total = 0
        let step = 8
        let labelBandXStart = Int(Double(width) * 0.24)
        let labelBandXEnd = Int(Double(width) * 0.84)
        let labelBandYStart = Int(Double(height) * 0.32)
        let labelBandYEnd = Int(Double(height) * 0.68)
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
                    if x >= labelBandXStart,
                       x <= labelBandXEnd,
                       y >= labelBandYStart,
                       y <= labelBandYEnd {
                        labelAccentBlue += 1
                    }
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
        labelAccentBluePixels = labelAccentBlue
        lowerAccentBluePixels = lowerAccentBlue
    }
}
