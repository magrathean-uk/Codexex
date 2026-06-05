import XCTest
@testable import CodexMeterApp

final class CodexAppLinksTests: XCTestCase {
    func testExternalLinksAreValid() {
        XCTAssertEqual(CodexAppLinks.termsURL.scheme, "https")
        XCTAssertEqual(CodexAppLinks.privacyURL.scheme, "https")
        XCTAssertEqual(CodexAppLinks.manageSubscriptionURL.scheme, "https")
    }
}
