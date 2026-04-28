import Foundation

public enum CodexAuthMode: String, Codable, Sendable {
    case chatGPT
}

public struct CodexServiceSnapshotResponse: Codable, Sendable, Equatable {
    public let authMode: CodexAuthMode?
    public let snapshot: CodexSnapshot?
    public let errorMessage: String?

    public init(authMode: CodexAuthMode?, snapshot: CodexSnapshot?, errorMessage: String?) {
        self.authMode = authMode
        self.snapshot = snapshot
        self.errorMessage = errorMessage
    }
}

public struct CodexDeviceAuthStart: Codable, Sendable, Equatable {
    public let flowID: String
    public let verificationURL: URL
    public let userCode: String

    public init(flowID: String, verificationURL: URL, userCode: String) {
        self.flowID = flowID
        self.verificationURL = verificationURL
        self.userCode = userCode
    }

    enum CodingKeys: String, CodingKey {
        case flowID = "flowId"
        case verificationURL = "verificationUri"
        case userCode
    }
}

public enum CodexDeviceAuthPollStatus: String, Codable, Sendable, Equatable {
    case pending
    case signedIn
}

public struct CodexDeviceAuthPollResult: Codable, Sendable, Equatable {
    public let status: CodexDeviceAuthPollStatus
    public let message: String?

    public init(status: CodexDeviceAuthPollStatus, message: String? = nil) {
        self.status = status
        self.message = message
    }
}

public enum CodexHelperRequestMethod: String, Codable, Sendable, Equatable {
    case fetchSnapshot
    case beginDeviceAuth
    case pollDeviceAuth
    case signOut
}

public enum CodexHelperProtocol: Sendable {
    public static let currentVersion = 1
}

public struct CodexHelperRequest: Codable, Sendable, Equatable {
    public let protocolVersion: Int
    public let requestID: String
    public let method: CodexHelperRequestMethod
    public let flowID: String?

    public init(
        method: CodexHelperRequestMethod,
        flowID: String? = nil,
        protocolVersion: Int = CodexHelperProtocol.currentVersion,
        requestID: String = UUID().uuidString
    ) {
        self.protocolVersion = protocolVersion
        self.requestID = requestID
        self.method = method
        self.flowID = flowID
    }

    enum CodingKeys: String, CodingKey {
        case protocolVersion
        case requestID = "requestId"
        case method
        case flowID = "flow_id"
    }
}

public enum CodexHelperResponseType: String, Codable, Sendable, Equatable {
    case snapshot
    case deviceAuthStarted
    case deviceAuthPending
    case signedIn
    case signedOut
    case error
}

public enum CodexHelperWireResponse: Sendable, Equatable {
    case snapshot(CodexServiceSnapshotResponse)
    case deviceAuthStarted(CodexDeviceAuthStart)
    case deviceAuthPending(CodexDeviceAuthPollResult)
    case signedIn(CodexDeviceAuthPollResult)
    case signedOut
}

public enum CodexHelperWireError: LocalizedError, Sendable, Equatable {
    case helper(message: String)
    case unexpectedResponse(expected: String, actual: String)
    case missingPayload(String)
    case missingField(String)
    case unsupportedProtocolVersion(expected: Int, actual: Int)
    case requestIDMismatch(expected: String, actual: String)

    public var errorDescription: String? {
        switch self {
        case .helper(let message):
            return message
        case .unexpectedResponse(let expected, let actual):
            return "Expected \(expected) from the helper, but received \(actual)."
        case .missingPayload(let payload):
            return "Helper returned no \(payload) payload."
        case .missingField(let field):
            return "Helper response was missing \(field)."
        case .unsupportedProtocolVersion(let expected, let actual):
            return "Helper protocol version \(actual) is unsupported. Expected \(expected)."
        case .requestIDMismatch(let expected, let actual):
            return "Helper response requestId \(actual) did not match requestId \(expected)."
        }
    }
}

public struct CodexHelperResponseEnvelope: Codable, Sendable, Equatable {
    public let protocolVersion: Int?
    public let requestID: String?
    public let type: CodexHelperResponseType
    public let payloadJSON: String?
    public let message: String?
    public let flowID: String?
    public let verificationURL: URL?
    public let userCode: String?

    public init(
        protocolVersion: Int? = CodexHelperProtocol.currentVersion,
        requestID: String? = nil,
        type: CodexHelperResponseType,
        payloadJSON: String? = nil,
        message: String? = nil,
        flowID: String? = nil,
        verificationURL: URL? = nil,
        userCode: String? = nil
    ) {
        self.protocolVersion = protocolVersion
        self.requestID = requestID
        self.type = type
        self.payloadJSON = payloadJSON
        self.message = message
        self.flowID = flowID
        self.verificationURL = verificationURL
        self.userCode = userCode
    }

    enum CodingKeys: String, CodingKey {
        case protocolVersion
        case requestID = "requestId"
        case type
        case payloadJSON = "payloadJson"
        case message
        case flowID = "flowId"
        case verificationURL = "verificationUri"
        case userCode
    }

    public func validated(against request: CodexHelperRequest) throws -> Self {
        guard let protocolVersion else {
            throw CodexHelperWireError.missingField("protocolVersion")
        }
        guard protocolVersion == request.protocolVersion else {
            throw CodexHelperWireError.unsupportedProtocolVersion(
                expected: request.protocolVersion,
                actual: protocolVersion
            )
        }
        guard let requestID else {
            throw CodexHelperWireError.missingField("requestId")
        }
        guard requestID == request.requestID else {
            throw CodexHelperWireError.requestIDMismatch(
                expected: request.requestID,
                actual: requestID
            )
        }
        return self
    }

    public func decodedSnapshotResponse() throws -> CodexServiceSnapshotResponse {
        guard case .snapshot(let response) = try typedResponse() else {
            throw CodexHelperWireError.unexpectedResponse(expected: CodexHelperResponseType.snapshot.rawValue, actual: type.rawValue)
        }
        return response
    }

    public func decodedDeviceAuthStart() throws -> CodexDeviceAuthStart {
        guard case .deviceAuthStarted(let auth) = try typedResponse() else {
            throw CodexHelperWireError.unexpectedResponse(expected: CodexHelperResponseType.deviceAuthStarted.rawValue, actual: type.rawValue)
        }
        return auth
    }

    public func decodedDeviceAuthPollResult() throws -> CodexDeviceAuthPollResult {
        switch try typedResponse() {
        case .signedIn(let result), .deviceAuthPending(let result):
            return result
        case .snapshot, .deviceAuthStarted, .signedOut:
            throw CodexHelperWireError.unexpectedResponse(
                expected: "\(CodexHelperResponseType.deviceAuthPending.rawValue) or \(CodexHelperResponseType.signedIn.rawValue)",
                actual: type.rawValue
            )
        }
    }

    public func typedResponse() throws -> CodexHelperWireResponse {
        switch type {
        case .snapshot:
            guard let payloadJSON else {
                throw CodexHelperWireError.missingPayload("snapshot")
            }
            return .snapshot(try Self.decoder.decode(CodexServiceSnapshotResponse.self, from: Data(payloadJSON.utf8)))
        case .deviceAuthStarted:
            guard let flowID else { throw CodexHelperWireError.missingField("flowId") }
            guard let verificationURL else { throw CodexHelperWireError.missingField("verificationUri") }
            guard let userCode else { throw CodexHelperWireError.missingField("userCode") }
            return .deviceAuthStarted(
                CodexDeviceAuthStart(flowID: flowID, verificationURL: verificationURL, userCode: userCode)
            )
        case .signedIn:
            return .signedIn(CodexDeviceAuthPollResult(status: .signedIn, message: message))
        case .deviceAuthPending:
            return .deviceAuthPending(CodexDeviceAuthPollResult(status: .pending, message: message))
        case .signedOut:
            return .signedOut
        case .error:
            throw CodexHelperWireError.helper(message: message ?? "Helper returned an unknown error.")
        }
    }

    public func requireResponse(_ expected: CodexHelperResponseType) throws {
        if type == .error {
            throw CodexHelperWireError.helper(message: message ?? "Helper returned an unknown error.")
        }
        guard type == expected else {
            throw CodexHelperWireError.unexpectedResponse(expected: expected.rawValue, actual: type.rawValue)
        }
    }

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }()
}
