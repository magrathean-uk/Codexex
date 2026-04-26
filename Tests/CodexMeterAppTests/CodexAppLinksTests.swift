import XCTest
@testable import CodexMeterApp

final class CodexAppLinksTests: XCTestCase {
    func testExternalLinksAreValid() {
        XCTAssertEqual(CodexAppLinks.appStoreURL.scheme, "macappstore")
        XCTAssertTrue(CodexAppLinks.appStoreURL.absoluteString.contains("6762058457"))
        XCTAssertEqual(CodexAppLinks.releaseNotesURL.scheme, "https")
        XCTAssertEqual(CodexAppLinks.manageSubscriptionURL.scheme, "https")
    }
}
