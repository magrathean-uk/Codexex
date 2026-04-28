import XCTest
@testable import CodexMeterCore

final class CodexServiceContractsTests: XCTestCase {
    func testTypedWireResponseValidatesPayloadShape() throws {
        let data = Data(#"{"protocolVersion":1,"requestId":"request-1","type":"deviceAuthPending","message":"still waiting"}"#.utf8)
        let request = CodexHelperRequest(method: .pollDeviceAuth, flowID: "flow-1", requestID: "request-1")

        let typed = try JSONDecoder()
            .decode(CodexHelperResponseEnvelope.self, from: data)
            .validated(against: request)
            .typedResponse()

        XCTAssertEqual(
            typed,
            .deviceAuthPending(CodexDeviceAuthPollResult(status: .pending, message: "still waiting"))
        )
    }

    func testTypedWireResponseRejectsMissingDeviceAuthFields() throws {
        let data = Data(#"{"protocolVersion":1,"requestId":"request-1","type":"deviceAuthStarted","flowId":"flow-1","userCode":"ABCD"}"#.utf8)
        let request = CodexHelperRequest(method: .beginDeviceAuth, requestID: "request-1")
        let envelope = try JSONDecoder().decode(CodexHelperResponseEnvelope.self, from: data).validated(against: request)

        XCTAssertThrowsError(try envelope.typedResponse()) { error in
            XCTAssertEqual(error as? CodexHelperWireError, .missingField("verificationUri"))
        }
    }

    func testPollDeviceAuthRequestEncodesVersionAndLegacyFlowKey() throws {
        let request = CodexHelperRequest(method: .pollDeviceAuth, flowID: "flow-123", requestID: "request-123")

        let data = try JSONEncoder().encode(request)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(object["protocolVersion"] as? Int, CodexHelperProtocol.currentVersion)
        XCTAssertEqual(object["requestId"] as? String, "request-123")
        XCTAssertEqual(object["method"] as? String, "pollDeviceAuth")
        XCTAssertEqual(object["flow_id"] as? String, "flow-123")
        XCTAssertNil(object["flowId"])
    }

    func testSnapshotEnvelopeDecodesEmbeddedPayload() throws {
        let payloadObject: [String: Any?] = ["authMode": "chatGPT", "snapshot": nil, "errorMessage": nil]
        let payloadData = try JSONSerialization.data(withJSONObject: payloadObject.compactMapValues { $0 })
        let payload = String(decoding: payloadData, as: UTF8.self)
        let envelopeData = try JSONSerialization.data(withJSONObject: [
            "protocolVersion": CodexHelperProtocol.currentVersion,
            "requestId": "request-123",
            "type": "snapshot",
            "payloadJson": payload,
        ])

        let envelope = try JSONDecoder().decode(CodexHelperResponseEnvelope.self, from: envelopeData)
        let response = try envelope.validated(
            against: CodexHelperRequest(method: .fetchSnapshot, requestID: "request-123")
        ).decodedSnapshotResponse()

        XCTAssertEqual(envelope.protocolVersion, CodexHelperProtocol.currentVersion)
        XCTAssertEqual(envelope.requestID, "request-123")
        XCTAssertEqual(envelope.type, CodexHelperResponseType.snapshot)
        XCTAssertEqual(response.authMode, CodexAuthMode.chatGPT)
        XCTAssertNil(response.snapshot)
        XCTAssertNil(response.errorMessage)
    }

    func testDeviceAuthEnvelopeBuildsTypedPayload() throws {
        let data = Data(#"{"protocolVersion":1,"requestId":"request-1","type":"deviceAuthStarted","flowId":"flow-1","verificationUri":"https://auth.openai.com/device","userCode":"ABCD-12345"}"#.utf8)
        let request = CodexHelperRequest(method: .beginDeviceAuth, requestID: "request-1")
        let envelope = try JSONDecoder().decode(CodexHelperResponseEnvelope.self, from: data).validated(against: request)
        let auth = try envelope.decodedDeviceAuthStart()

        XCTAssertEqual(auth.flowID, "flow-1")
        XCTAssertEqual(auth.verificationURL, URL(string: "https://auth.openai.com/device")!)
        XCTAssertEqual(auth.userCode, "ABCD-12345")
    }

    func testPendingDeviceAuthEnvelopeBuildsTypedPollResult() throws {
        let data = Data(#"{"protocolVersion":1,"type":"deviceAuthPending","message":"still waiting"}"#.utf8)

        let envelope = try JSONDecoder().decode(CodexHelperResponseEnvelope.self, from: data)
        let result = try envelope.decodedDeviceAuthPollResult()

        XCTAssertEqual(result.status, .pending)
        XCTAssertEqual(result.message, "still waiting")
    }

    func testHelperErrorEnvelopeThrowsHelpfulError() throws {
        let data = Data(#"{"protocolVersion":1,"type":"error","message":"rate limited"}"#.utf8)
        let envelope = try JSONDecoder().decode(CodexHelperResponseEnvelope.self, from: data)

        XCTAssertThrowsError(try envelope.requireResponse(.signedIn)) { error in
            XCTAssertEqual(error as? CodexHelperWireError, .helper(message: "rate limited"))
        }
    }

    func testMismatchedRequestIDThrowsBeforePayloadDecode() throws {
        let data = Data(#"{"protocolVersion":1,"requestId":"actual","type":"signedOut"}"#.utf8)
        let envelope = try JSONDecoder().decode(CodexHelperResponseEnvelope.self, from: data)
        let request = CodexHelperRequest(method: .signOut, requestID: "expected")

        XCTAssertThrowsError(try envelope.validated(against: request)) { error in
            XCTAssertEqual(error as? CodexHelperWireError, .requestIDMismatch(expected: "expected", actual: "actual"))
        }
    }

    func testUnsupportedProtocolVersionThrowsBeforePayloadDecode() throws {
        let data = Data(#"{"protocolVersion":99,"type":"signedOut"}"#.utf8)
        let envelope = try JSONDecoder().decode(CodexHelperResponseEnvelope.self, from: data)
        let request = CodexHelperRequest(method: .signOut, requestID: "request-1")

        XCTAssertThrowsError(try envelope.validated(against: request)) { error in
            XCTAssertEqual(error as? CodexHelperWireError, .unsupportedProtocolVersion(expected: 1, actual: 99))
        }
    }
}
