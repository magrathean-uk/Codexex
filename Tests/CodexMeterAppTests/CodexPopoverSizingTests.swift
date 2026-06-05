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

    func testGlassTokensMatchCompactMenuBarReferenceDesign() {
        XCTAssertEqual(GlassTokens.popupWidth, 430)
        XCTAssertEqual(GlassTokens.popupMaxHeight, 760)
        XCTAssertEqual(GlassTokens.pagePadding, 14)
        XCTAssertEqual(GlassTokens.contentSpacing, 10)
        XCTAssertEqual(GlassTokens.cardPadding, 14)
        XCTAssertEqual(GlassTokens.cardRadius, 10)
        XCTAssertEqual(GlassTokens.popupRadius, 10)
        XCTAssertEqual(GlassTokens.infoChipHeight, 50)
        XCTAssertEqual(GlassTokens.emptyStateHeight, 66)
        XCTAssertEqual(GlassTokens.statusIconSize, 34)
        XCTAssertEqual(GlassTokens.summaryBannerMinHeight, 0)
        XCTAssertEqual(GlassTokens.summaryIconSize, 32)
        XCTAssertEqual(GlassTokens.quotaHeadlineSize, 20)
        XCTAssertEqual(GlassTokens.quotaBarHeight, 7)
        XCTAssertEqual(GlassTokens.limitCardMinHeight, 94)
        XCTAssertEqual(GlassTokens.historyGraphHeight, 76)
        XCTAssertEqual(GlassTokens.revealOffset, 10)
        XCTAssertEqual(GlassTokens.revealDuration, 0.32)
        XCTAssertEqual(GlassTokens.cardHighlightOpacity, 0)
        XCTAssertEqual(GlassTokens.cardShadowRadius, 0)
        XCTAssertEqual(GlassTokens.barGlowRadius, 0)
        XCTAssertEqual(GlassTokens.shimmerDuration, 0)
        XCTAssertEqual(GlassTokens.quotaBarFillDuration, 0)
        XCTAssertEqual(GlassTokens.cardInnerGlowOpacity, 0)
        XCTAssertEqual(GlassTokens.popupShadowRadius, 0)
        XCTAssertEqual(GlassTokens.popupShadowYOffset, 0)
        XCTAssertEqual(GlassTokens.ambientBlobBlurRadius, 0)
        XCTAssertEqual(GlassTokens.ambientAccentOpacity, 0)
        XCTAssertEqual(GlassTokens.cardHoverLift, 0)
        XCTAssertEqual(GlassTokens.cardHoverScale, 1)
        XCTAssertEqual(GlassTokens.cardHoverAnimationDuration, 0)
        XCTAssertEqual(GlassTokens.cardRevealOffset, 0)
        XCTAssertEqual(GlassTokens.cardRevealStagger, 0)
        XCTAssertEqual(GlassTokens.summaryIconPulseScale, 1)
        XCTAssertEqual(GlassTokens.summaryIconPulseDuration, 0)
        XCTAssertEqual(GlassTokens.summaryWaveDriftOffset, 0)
        XCTAssertEqual(GlassTokens.summaryWaveDriftDuration, 0)
        XCTAssertEqual(GlassTokens.historyGraphDrawDuration, 0)
        XCTAssertEqual(GlassTokens.refreshSpinDuration, 0.85)
    }
}
