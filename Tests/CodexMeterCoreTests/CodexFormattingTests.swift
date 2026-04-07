import XCTest
@testable import CodexMeterCore

final class CodexFormattingTests: XCTestCase {
    func testWindowFormatting() {
        XCTAssertEqual(CodexFormatting.windowDuration(minutes: 15), "15 minute window")
        XCTAssertEqual(CodexFormatting.windowDuration(minutes: 60), "1 hour window")
        XCTAssertEqual(CodexFormatting.windowDuration(minutes: 1440), "1 day window")
    }

    func testCompactDuration() {
        XCTAssertEqual(CodexFormatting.compactDuration(seconds: 59), "59s")
        XCTAssertEqual(CodexFormatting.compactDuration(seconds: 3600), "1h")
        XCTAssertEqual(CodexFormatting.compactDuration(seconds: 3660), "1h 1m")
        XCTAssertEqual(CodexFormatting.compactDuration(seconds: 90061), "1d 1h")
    }

    func testBucketInference() {
        XCTAssertEqual(CodexLimitBucket.infer(limitId: "codex", limitName: nil), .codex)
        XCTAssertEqual(CodexLimitBucket.infer(limitId: "gpt-5.3-codex-spark", limitName: "Codex Spark"), .spark)
        XCTAssertEqual(CodexLimitBucket.infer(limitId: "other_meter", limitName: nil), .other)
    }
}
