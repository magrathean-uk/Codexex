import XCTest
@testable import CodexMeterCore

final class CodexServiceContractsTests: XCTestCase {
    func testPollDeviceAuthRequestEncodesLegacyFlowKey() throws {
        let request = CodexHelperRequest(method: .pollDeviceAuth, flowID: "flow-123")

        let data = try JSONEncoder().encode(request)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: String])

        XCTAssertEqual(object["method"], "pollDeviceAuth")
        XCTAssertEqual(object["flow_id"], "flow-123")
        XCTAssertNil(object["flowId"])
    }

    func testSnapshotEnvelopeDecodesEmbeddedPayload() throws {
        let payloadObject: [String: Any?] = [
            "authMode": "chatGPT",
            "snapshot": nil,
            "errorMessage": nil,
        ]
        let payloadData = try JSONSerialization.data(withJSONObject: payloadObject.compactMapValues { $0 })
        let payload = String(decoding: payloadData, as: UTF8.self)
        let envelopeData = try JSONSerialization.data(withJSONObject: [
            "type": "snapshot",
            "payloadJson": payload,
        ])

        let envelope = try JSONDecoder().decode(CodexHelperResponseEnvelope.self, from: envelopeData)
        let response = try envelope.decodedSnapshotResponse()

        XCTAssertEqual(envelope.type, CodexHelperResponseType.snapshot)
        XCTAssertEqual(response.authMode, CodexAuthMode.chatGPT)
        XCTAssertNil(response.snapshot)
        XCTAssertNil(response.errorMessage)
    }

    func testDeviceAuthEnvelopeBuildsTypedPayload() throws {
        let data = Data(
            #"{"type":"deviceAuthStarted","flowId":"flow-1","verificationUri":"https://auth.openai.com/device","userCode":"ABCD-12345"}"#.utf8
        )

        let envelope = try JSONDecoder().decode(CodexHelperResponseEnvelope.self, from: data)
        let auth = try envelope.decodedDeviceAuthStart()

        XCTAssertEqual(auth.flowID, "flow-1")
        XCTAssertEqual(auth.verificationURL, URL(string: "https://auth.openai.com/device")!)
        XCTAssertEqual(auth.userCode, "ABCD-12345")
    }

    func testPendingDeviceAuthEnvelopeBuildsTypedPollResult() throws {
        let data = Data(#"{"type":"deviceAuthPending","message":"still waiting"}"#.utf8)

        let envelope = try JSONDecoder().decode(CodexHelperResponseEnvelope.self, from: data)
        let result = try envelope.decodedDeviceAuthPollResult()

        XCTAssertEqual(result.status, .pending)
        XCTAssertEqual(result.message, "still waiting")
    }

    func testHelperErrorEnvelopeThrowsHelpfulError() throws {
        let data = Data(#"{"type":"error","message":"rate limited"}"#.utf8)
        let envelope = try JSONDecoder().decode(CodexHelperResponseEnvelope.self, from: data)

        XCTAssertThrowsError(try envelope.requireResponse(.signedIn)) { error in
            XCTAssertEqual(error as? CodexHelperWireError, .helper(message: "rate limited"))
        }
    }
}
