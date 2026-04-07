import XCTest
@testable import CodexMeterCore

final class CodexBinaryLocatorTests: XCTestCase {
    func testOverrideComesFirst() {
        let paths = CodexBinaryLocator.candidatePaths(environment: [
            "HOME": "/Users/test",
            "PATH": "/usr/local/bin:/opt/homebrew/bin",
            "CODEXMETER_CODEX_PATH": "/custom/codex"
        ])

        XCTAssertEqual(paths.first, "/custom/codex")
    }

    func testApplicationsBundlePathIncluded() {
        let paths = CodexBinaryLocator.candidatePaths(environment: [
            "HOME": "/Users/test"
        ])

        XCTAssertTrue(paths.contains("/Applications/Codex.app/Contents/Resources/codex"))
        XCTAssertTrue(paths.contains("/Users/test/Applications/Codex.app/Contents/Resources/codex"))
    }
}
