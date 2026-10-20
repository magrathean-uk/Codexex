import Foundation
import Security

public struct OpenAIAPICredential: Codable, Sendable {
    public let key: String
    public let kind: OpenAIAPIKeyKind
    public let organizationID: String?
    public init(key: String, kind: OpenAIAPIKeyKind, organizationID: String? = nil) {
        self.key = key; self.kind = kind; self.organizationID = organizationID
    }
}

/// This product's API credential is separate from ChatGPT subscription authentication.
public struct OpenAIAPICredentialStore: Sendable {
    private let service: String
    public init(service: String = "uk.magrathean.codexex.openai-api") { self.service = service }
    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
         kSecAttrAccount as String: "api-monitor", kSecAttrSynchronizable as String: false]
    }
    public func load() throws -> OpenAIAPICredential? {
        var query = query
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data,
              let credential = try? JSONDecoder().decode(OpenAIAPICredential.self, from: data) else { throw CredentialError.unavailable }
        return credential
    }
    public func save(_ credential: OpenAIAPICredential) throws {
        try OpenAIAPIClient.validateCredential(credential.key, kind: credential.kind)
        try OpenAIAPIClient.validateOrganizationID(credential.organizationID)
        let data = try JSONEncoder().encode(credential)
        let attributes: [String: Any] = [kSecValueData as String: data, kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var addition = query
            addition.merge(attributes) { _, new in new }
            guard SecItemAdd(addition as CFDictionary, nil) == errSecSuccess else { throw CredentialError.unavailable }
        } else if status != errSecSuccess { throw CredentialError.unavailable }
    }
    public func delete() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw CredentialError.unavailable }
    }
    public enum CredentialError: Error, LocalizedError {
        case unavailable
        public var errorDescription: String? { "The API credential could not be accessed in Keychain. Unlock the device and try again." }
    }
}
