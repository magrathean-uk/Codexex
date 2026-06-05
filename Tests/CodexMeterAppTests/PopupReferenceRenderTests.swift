import AppKit
import SwiftUI
import XCTest
@testable import CodexMeterApp

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
}

private struct PixelSample {
    let nonBlackShare: Double
    let brightGlassShare: Double

    init(bitmap: NSBitmapImageRep) {
        let width = bitmap.pixelsWide
        let height = bitmap.pixelsHigh
        var nonBlack = 0
        var brightGlass = 0
        var total = 0
        let step = 8

        for y in stride(from: 0, to: height, by: step) {
            for x in stride(from: 0, to: width, by: step) {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else {
                    continue
                }
                total += 1
                let red = color.redComponent
                let green = color.greenComponent
                let blue = color.blueComponent
                let brightness = (red + green + blue) / 3

                if brightness > 0.03 {
                    nonBlack += 1
                }
                if brightness > 0.78 && abs(red - green) < 0.14 && abs(green - blue) < 0.18 {
                    brightGlass += 1
                }
            }
        }

        let denominator = Double(max(1, total))
        nonBlackShare = Double(nonBlack) / denominator
        brightGlassShare = Double(brightGlass) / denominator
    }
}
