#if os(macOS)
import Foundation
import Security

/// The access key's safe place on this Mac. Saved as a generic password under one fixed
/// service name, so an unattended run reads it back with the system's own tool instead of
/// a file — `security find-generic-password -s "longbook access key" -w` — and the key
/// never touches disk in the clear.
enum KeyKeychain {
    static let service = "longbook access key"

    /// Saves (or replaces) the key, and answers the sentence the screen shows —
    /// including the exact command an agent uses, because that is the point of saving it.
    static func save(_ key: String, named account: String) -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = Data(key.utf8)
        add[kSecAttrLabel as String] = service
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else {
            return "The keychain refused to store it (error \(status)). Copy the key instead."
        }
        return """
        Saved. An agent on this Mac reads it with:
        security find-generic-password -s "longbook access key" -w
        The first read asks once — choose Always Allow.
        """
    }
}
#endif
