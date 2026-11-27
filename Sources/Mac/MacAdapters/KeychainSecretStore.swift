import BugeyeCore
import Foundation
import Security

/// Secrets in the login Keychain, as generic passwords: service `dev.msenechal.bugeye`, account = the key's
/// name. Never UserDefaults, never a file (spec §5.3).
public struct KeychainSecretStore: SecretStore {
    public struct KeychainError: Error, Equatable {
        public let status: OSStatus
    }

    public let service: String

    /// Tests pass a unique service so they never touch the real key.
    public init(service: String = "dev.msenechal.bugeye") {
        self.service = service
    }

    public func secret(for key: SecretKey) throws -> String? {
        var query = baseQuery(key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainError(status: status) }
        guard let data = item as? Data else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    public func setSecret(_ value: String, for key: SecretKey) throws {
        let data = Data(value.utf8)
        let update = [kSecValueData as String: data] as CFDictionary
        let status = SecItemUpdate(baseQuery(key) as CFDictionary, update)
        if status == errSecItemNotFound {
            var add = baseQuery(key)
            add[kSecValueData as String] = data
            let added = SecItemAdd(add as CFDictionary, nil)
            guard added == errSecSuccess else { throw KeychainError(status: added) }
        } else if status != errSecSuccess {
            throw KeychainError(status: status)
        }
    }

    public func removeSecret(for key: SecretKey) throws {
        let status = SecItemDelete(baseQuery(key) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError(status: status) }
    }

    private func baseQuery(_ key: SecretKey) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
        ]
    }
}
