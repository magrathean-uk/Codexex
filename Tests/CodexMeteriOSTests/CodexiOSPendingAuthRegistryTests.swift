import XCTest
@testable import CodexMeteriOS

final class CodexiOSPendingAuthRegistryTests: XCTestCase {
    func testFlowIDDoesNotExposePendingAuthState() throws {
        var registry = CodexiOSPendingAuthRegistry(ttl: 60)
        let flowID = try registry.insert(
            verificationURL: URL(string: "https://auth.openai.com/codex/device")!,
            userCode: "ABCD-1234",
            deviceAuthID: "device-secret",
            interval: 3
        )

        XCTAssertFalse(flowID.contains("ABCD"))
        XCTAssertFalse(flowID.contains("device-secret"))
        XCTAssertFalse(flowID.contains("{"))

        let flow = try registry.resolve(flowID)
        XCTAssertEqual(flow.userCode, "ABCD-1234")
        XCTAssertEqual(flow.deviceAuthID, "device-secret")
    }

    func testExpiredAndRemovedFlowsFailClosed() throws {
        let now = Date(timeIntervalSince1970: 100)
        var registry = CodexiOSPendingAuthRegistry(ttl: 1)
        let flowID = try registry.insert(
            verificationURL: URL(string: "https://auth.openai.com/codex/device")!,
            userCode: "ABCD-1234",
            deviceAuthID: "device-secret",
            interval: 3,
            now: now
        )

        XCTAssertThrowsError(try registry.resolve(flowID, now: now.addingTimeInterval(2)))

        let second = try registry.insert(
            verificationURL: URL(string: "https://auth.openai.com/codex/device")!,
            userCode: "WXYZ-9876",
            deviceAuthID: "second-secret",
            interval: 3,
            now: now
        )
        registry.remove(second)
        XCTAssertThrowsError(try registry.resolve(second, now: now))
    }
}
