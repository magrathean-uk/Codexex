import XCTest
@testable import CodexMeterApp

@MainActor
final class CodexLocalUsageCardPolicyTests: XCTestCase {
    func testMissingSessionAccessStillShowsConfidencePillInHeader() {
        let accessory = CodexLocalUsageHeaderAccessory.resolve(
            needsSessionsAccess: true,
            contextWindowPercent: nil,
            attributionConfidenceTitle: "Unknown confidence"
        )

        XCTAssertEqual(accessory, .confidence("Unknown confidence"))
    }

    func testContextPressureWinsOverConfidencePill() {
        let accessory = CodexLocalUsageHeaderAccessory.resolve(
            needsSessionsAccess: false,
            contextWindowPercent: 72,
            attributionConfidenceTitle: "High confidence"
        )

        XCTAssertEqual(accessory, .context("Context 72%"))
    }
}
