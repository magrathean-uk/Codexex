#if os(macOS)
import Foundation
import Security

enum CodexSecretStore {
    private static let service = "com.bolyki.Codexex.api-key"
    private static let account = "default"

    static func saveAPIKey(_ key: String) throws {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            throw NSError(
                domain: "CodexSecretStore",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "API key is empty."]
            )
        }

        let data = Data(trimmed.utf8)
        var query = baseQuery
        query[kSecValueData as String] = data

        SecItemDelete(baseQuery as CFDictionary)

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }

    static func loadAPIKey() throws -> String? {
        var query = baseQuery
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecReturnData as String] = true

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            guard let data = result as? Data,
                  let key = String(data: data, encoding: .utf8)
            else {
                throw NSError(
                    domain: "CodexSecretStore",
                    code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "Stored API key is unreadable."]
                )
            }
            return key
        case errSecItemNotFound:
            return nil
        default:
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }

    static func hasAPIKey() -> Bool {
        (try? loadAPIKey())?.isEmpty == false
    }

    static func removeAPIKey() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}
#endif
