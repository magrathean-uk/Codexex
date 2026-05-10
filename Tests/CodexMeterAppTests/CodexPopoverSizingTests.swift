import XCTest
import AppKit
@testable import CodexMeterApp

@MainActor
final class CodexPopoverSizingTests: XCTestCase {
    func testHeightClampsToMaxHeight() {
        XCTAssertEqual(
            CodexPopoverSizing.height(fittingHeight: 900.2, maxHeight: 640),
            640
        )
    }

    func testHeightRoundsFittingHeightUp() {
        XCTAssertEqual(
            CodexPopoverSizing.height(fittingHeight: 512.2, maxHeight: 640),
            513
        )
    }

    func testMaxHeightUsesSafeScreenBounds() {
        let maxHeight = CodexPopoverSizing.maxHeight(for: nil)

        XCTAssertGreaterThanOrEqual(maxHeight, GlassTokens.popupMinimumUsableHeight)
        XCTAssertLessThanOrEqual(maxHeight, GlassTokens.popupMaxHeight)
    }

    func testClampedPreferredHeightKeepsSmallAvailableHeight() {
        XCTAssertEqual(
            CodexPopoverSizing.clampedPreferredHeight(forAvailableHeight: 300),
            300
        )
    }

    func testClampedPreferredHeightRespectsPopupMaxHeight() {
        XCTAssertEqual(
            CodexPopoverSizing.clampedPreferredHeight(forAvailableHeight: 4_000),
            GlassTokens.popupMaxHeight
        )
    }
}
