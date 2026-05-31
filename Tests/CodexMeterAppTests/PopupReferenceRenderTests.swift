import AppKit
import SwiftUI
import XCTest
@testable import CodexMeterApp

@MainActor
final class PopupReferenceRenderTests: XCTestCase {
    func testReferencePopupRendersNonBlackGlassFrame() throws {
        setenv("CODEXEX_REFERENCE_RENDER", "1", 1)
        defer { unsetenv("CODEXEX_REFERENCE_RENDER") }

        let model = CodexMenuBarModel()
        model.enablePreviewMode()

        let view = PopupRootView(model: model, reduceMotionOverride: true)
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
        XCTAssertGreaterThan(sample.coloredAccentShare, 0.0002)
        XCTAssertGreaterThan(sample.darkContentShare, 0.001)

        let pngURL = URL(fileURLWithPath: "/private/tmp/codexex-reference-popup.png")
        let pngData = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try pngData.write(to: pngURL, options: .atomic)
        XCTAssertTrue(FileManager.default.fileExists(atPath: pngURL.path))
    }
}

private struct PixelSample {
    let nonBlackShare: Double
    let brightGlassShare: Double
    let coloredAccentShare: Double
    let darkContentShare: Double

    init(bitmap: NSBitmapImageRep) {
        let width = bitmap.pixelsWide
        let height = bitmap.pixelsHigh
        var nonBlack = 0
        var brightGlass = 0
        var coloredAccent = 0
        var darkContent = 0
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
                if max(red, green, blue) - min(red, green, blue) > 0.18,
                   brightness > 0.18 {
                    coloredAccent += 1
                }
                if brightness > 0.05 && brightness < 0.32 {
                    darkContent += 1
                }
            }
        }

        let denominator = Double(max(1, total))
        nonBlackShare = Double(nonBlack) / denominator
        brightGlassShare = Double(brightGlass) / denominator
        coloredAccentShare = Double(coloredAccent) / denominator
        darkContentShare = Double(darkContent) / denominator
    }
}
