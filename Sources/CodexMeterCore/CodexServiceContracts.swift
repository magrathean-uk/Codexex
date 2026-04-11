import Foundation

public enum CodexAuthMode: String, Codable, Sendable {
    case chatGPT
    case apiKey
}

public struct CodexServiceSnapshotResponse: Codable, Sendable {
    public let authMode: CodexAuthMode?
    public let snapshot: CodexSnapshot?
    public let errorMessage: String?

    public init(authMode: CodexAuthMode?, snapshot: CodexSnapshot?, errorMessage: String?) {
        self.authMode = authMode
        self.snapshot = snapshot
        self.errorMessage = errorMessage
    }
}

public struct CodexDeviceAuthStart: Codable, Sendable {
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
