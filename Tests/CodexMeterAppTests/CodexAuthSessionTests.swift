import Foundation
import XCTest
@testable import CodexMeterApp

final class CodexAuthSessionTests: XCTestCase {
    func testSuccessfulDeviceCodeLifecyclePreservesContextUntilSignedIn() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let context = CodexDeviceCodeContext(
            flowID: "flow-1",
            verificationURL: URL(string: "https://auth.openai.com/device")!,
            userCode: "ABCD-12345",
            createdAt: now
        )
        var session = CodexAuthSession()

        session.apply(.beginRequested, now: now)
        XCTAssertTrue(session.isSigningIn)
        XCTAssertNil(session.currentDeviceCode)

        session.apply(.beginSucceeded(context), now: now)
        XCTAssertEqual(session.userCode, "ABCD-12345")
        XCTAssertFalse(session.isSigningIn)

        session.apply(.pollingRequested, now: now)
        XCTAssertTrue(session.isSigningIn)
        XCTAssertEqual(session.userCode, "ABCD-12345")

        session.apply(.pollingPending("Still waiting for approval. Finish in Safari, then check again."), now: now)
        XCTAssertFalse(session.isSigningIn)
        XCTAssertEqual(session.userCode, "ABCD-12345")
        XCTAssertEqual(session.statusMessage, "Still waiting for approval. Finish in Safari, then check again.")

        session.apply(.signedIn, now: now)
        XCTAssertTrue(session.isSignedIn)
        XCTAssertNil(session.currentDeviceCode)
        XCTAssertEqual(session.statusMessage, "Signed in with ChatGPT.")
    }

    func testPollingFailureKeepsRecoveryContext() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let context = CodexDeviceCodeContext(
            flowID: "flow-1",
            verificationURL: URL(string: "https://auth.openai.com/device")!,
            userCode: "ABCD-12345",
            createdAt: now
        )
        var session = CodexAuthSession()
        session.apply(.beginSucceeded(context), now: now)

        session.apply(.pollingRequested, now: now)
        session.apply(.pollingFailed("network issue"), now: now)

        XCTAssertEqual(session.lastError, "network issue")
        XCTAssertEqual(session.userCode, "ABCD-12345")
        XCTAssertFalse(session.isSignedIn)
        XCTAssertFalse(session.isSigningIn)
    }
}
