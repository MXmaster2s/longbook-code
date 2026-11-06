import Foundation
import Security
import Auth

/// Where the signed-in session is kept: the data-protection keychain, which scopes items by
/// entitlement rather than by the binary that wrote them.

/// The file keychain the SDK defaults to asks for the login password whenever the asking
/// build differs from the writing one. `KeyKeychain` still uses it, deliberately — only the
/// file keychain is readable by the `security` command.
struct AuthKeychain: AuthLocalStorage {
    private let service = "app.longbook.session"

    private func query(_ key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            // The whole point: entitlement-scoped, not binary-scoped.
            kSecUseDataProtectionKeychain as String: true,
        ]
    }

    func store(key: String, value: Data) throws {
        SecItemDelete(query(key) as CFDictionary)
        var add = query(key)
        add[kSecValueData as String] = value
        // Readable after the first unlock so a refresh on wake doesn't need the reader.
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else { throw AuthKeychainError(status: status) }
    }

    func retrieve(key: String) throws -> Data? {
        var find = query(key)
        find[kSecReturnData as String] = true
        find[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(find as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw AuthKeychainError(status: status) }
        return item as? Data
    }

    func remove(key: String) throws {
        let status = SecItemDelete(query(key) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw AuthKeychainError(status: status)
        }
    }
}

struct AuthKeychainError: Error {
    let status: OSStatus
}
