import Foundation
import XCTest
@testable import CodexMeterApp
@testable import CodexMeterCore

final class PopupPresentationTests: XCTestCase {
    func testPopupOrdersSparkAfterPrimaryLimits() {
        let ordered = PopupPresentation.orderedLimits([
            makeLimit(id: "spark", name: "Codex Spark", bucket: .spark, fiveHour: 12, weekly: 18),
            makeLimit(id: "other", name: "Research", bucket: .other, fiveHour: 42, weekly: 55),
            makeLimit(id: "codex", name: "Codex", bucket: .codex, fiveHour: 34, weekly: 69)
        ])

        XCTAssertEqual(ordered.map(\.bucket), [.codex, .other, .spark])
    }

    func testSparkUsesCompactCardWhenIdle() {
        let presentation = PopupPresentation.presentation(
            for: makeLimit(id: "spark", name: "Codex Spark", bucket: .spark, fiveHour: 0, weekly: 0)
        )

        XCTAssertEqual(presentation.style, .compact)
    }

    func testSparkUsesFullCardWhenActive() {
        let presentation = PopupPresentation.presentation(
            for: makeLimit(id: "spark", name: "Codex Spark", bucket: .spark, fiveHour: 8, weekly: 0)
        )

        XCTAssertEqual(presentation.style, .standard)
    }

    func testZeroAndUnlimitedCreditsStayHidden() {
        let zeroCredits = PopupPresentation.presentation(
            for: makeLimit(
                id: "codex",
                name: "Codex",
                bucket: .codex,
                fiveHour: 10,
                weekly: 20,
                credits: CodexCredits(hasCredits: true, unlimited: false, balance: "0")
            )
        )
        let unlimitedCredits = PopupPresentation.presentation(
            for: makeLimit(
                id: "codex",
                name: "Codex",
                bucket: .codex,
                fiveHour: 10,
                weekly: 20,
                credits: CodexCredits(hasCredits: true, unlimited: true, balance: nil)
            )
        )

        XCTAssertNil(zeroCredits.visibleCredits)
        XCTAssertNil(unlimitedCredits.visibleCredits)
    }

    func testMeaningfulCreditsStayVisible() {
        let presentation = PopupPresentation.presentation(
            for: makeLimit(
                id: "codex",
                name: "Codex",
                bucket: .codex,
                fiveHour: 10,
                weekly: 20,
                credits: CodexCredits(hasCredits: true, unlimited: false, balance: "12.50")
            )
        )

        XCTAssertEqual(presentation.visibleCredits?.displayText, "12.50")
    }

    func testSupplementalSectionsPutHistoryBeforeInsights() {
        XCTAssertEqual(
            PopupPresentation.supplementalSections(showHistory: true, showInsights: true),
            [.history, .insights]
        )
    }

    func testHistoryLegendUsesCurrentPercentNotForecastWarning() {
        let forecast = CodexUsageForecast(
            message: "Likely over in 6h",
            tone: .danger,
            currentPercent: 91,
            projectedPercentAtReset: 100,
            paceVariancePercent: 82
        )

        XCTAssertEqual(PopupPresentation.historyLegendValue(for: forecast), "91%")
    }

    func testHistoryGraphBarsAreBottomAligned() {
        let rect = PopupPresentation.historyBarRect(
            usedPercent: 25,
            index: 0,
            count: 10,
            size: CGSize(width: 100, height: 40)
        )

        XCTAssertEqual(rect.minY, 30)
        XCTAssertEqual(rect.maxY, 40)
        XCTAssertEqual(rect.height, 10)
    }

    private func makeLimit(
        id: String,
        name: String,
        bucket: CodexLimitBucket,
        fiveHour: Double,
        weekly: Double,
        credits: CodexCredits? = nil
    ) -> CodexLimit {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        return CodexLimit(
            id: id,
            rawLimitName: name,
            bucket: bucket,
            primary: CodexQuotaWindow(
                usedPercent: fiveHour,
                windowDurationMinutes: 300,
                resetsAt: now.addingTimeInterval(4 * 60 * 60)
            ),
            secondary: CodexQuotaWindow(
                usedPercent: weekly,
                windowDurationMinutes: 10_080,
                resetsAt: now.addingTimeInterval(24 * 60 * 60)
            ),
            credits: credits
        )
    }
}
