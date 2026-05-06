import Foundation
import Security

struct CodexiOSPendingAuthRegistry: Sendable {
    struct PendingFlow: Sendable, Equatable {
        let verificationURL: URL
        let userCode: String
        let deviceAuthID: String
        let interval: Int
        let createdAt: Date
        let expiresAt: Date
    }

    private var flows: [String: PendingFlow] = [:]
    private let ttl: TimeInterval

    init(ttl: TimeInterval = 10 * 60) {
        self.ttl = ttl
    }

    mutating func insert(
        verificationURL: URL,
        userCode: String,
        deviceAuthID: String,
        interval: Int,
        now: Date = Date()
    ) throws -> String {
        prune(now: now)
        let flowID = try Self.randomFlowID()
        flows[flowID] = PendingFlow(
            verificationURL: verificationURL,
            userCode: userCode,
            deviceAuthID: deviceAuthID,
            interval: interval,
            createdAt: now,
            expiresAt: now.addingTimeInterval(ttl)
        )
        return flowID
    }

    mutating func resolve(_ flowID: String, now: Date = Date()) throws -> PendingFlow {
        prune(now: now)
        guard let flow = flows[flowID], flow.expiresAt > now else {
            flows.removeValue(forKey: flowID)
            throw CodexiOSError.badResponse("Sign-in code expired. Start again.")
        }
        return flow
    }

    mutating func remove(_ flowID: String) {
        flows.removeValue(forKey: flowID)
    }

    mutating func removeAll() {
        flows.removeAll(keepingCapacity: false)
    }

    mutating func prune(now: Date = Date()) {
        flows = flows.filter { _, flow in flow.expiresAt > now }
    }

    private static func randomFlowID() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else {
            throw CodexiOSError.badResponse("Could not start sign-in securely.")
        }
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
