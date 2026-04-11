import XCTest
@testable import CodexMeterCore

final class CodexServiceContractsTests: XCTestCase {
    func testAuthModeDecodesHelperWireValue() throws {
        let data = Data(#""chatGPT""#.utf8)

        let decoded = try JSONDecoder().decode(CodexAuthMode.self, from: data)

        XCTAssertEqual(decoded, .chatGPT)
    }

    func testAuthModeEncodesHelperWireValue() throws {
        let data = try JSONEncoder().encode(CodexAuthMode.chatGPT)

        XCTAssertEqual(String(decoding: data, as: UTF8.self), #""chatGPT""#)
    }

    func testServiceSnapshotResponseDecodesSignedOutState() {
        let data = Data(#"{"authMode":null,"snapshot":null,"errorMessage":"signed out"}"#.utf8)

        let decoded = try? JSONDecoder().decode(CodexServiceSnapshotResponse.self, from: data)

        XCTAssertNotNil(decoded)
        XCTAssertNil(decoded?.authMode)
        XCTAssertNil(decoded?.snapshot)
        XCTAssertEqual(decoded?.errorMessage, "signed out")
    }

    func testDeviceAuthStartDecodesHelperWireKeys() throws {
        let data = Data(
            #"{"flowId":"flow-1","verificationUri":"https://auth.openai.com/device","userCode":"ABCD-12345"}"#.utf8
        )

        let decoded = try JSONDecoder().decode(CodexDeviceAuthStart.self, from: data)

        XCTAssertEqual(decoded.flowID, "flow-1")
        XCTAssertEqual(decoded.verificationURL, URL(string: "https://auth.openai.com/device")!)
        XCTAssertEqual(decoded.userCode, "ABCD-12345")
    }

    func testDeviceAuthStartEncodesHelperWireKeys() throws {
        let value = CodexDeviceAuthStart(
            flowID: "flow-1",
            verificationURL: URL(string: "https://auth.openai.com/device")!,
            userCode: "ABCD-12345"
        )

        let data = try JSONEncoder().encode(value)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: String])

        XCTAssertEqual(object["flowId"], "flow-1")
        XCTAssertEqual(object["verificationUri"], "https://auth.openai.com/device")
        XCTAssertEqual(object["userCode"], "ABCD-12345")
        XCTAssertNil(object["flowID"])
        XCTAssertNil(object["verificationURL"])
    }
}
