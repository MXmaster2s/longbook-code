import Foundation
import Security

/// The trial's start as this device remembers it. The server stamps a start per account;
/// this stamp is per device and never later than the earliest start it has seen, so a
/// reinstall or a second address does not begin the three days again.
public enum TrialClock {
    /// The earlier of the two starts wins. No device stamp yet means the server's word.
    public static func effectiveStart(server: Date, device: Date?) -> Date {
        guard let device else { return server }
        return min(server, device)
    }

    /// Reads the device stamp, folds the server's start in, and keeps whichever is earlier.
    /// The keychain is the app's own data-protection store — no prompt, nothing typed.
    static func reconcile(serverStart: Date) -> Date {
        let start = effectiveStart(server: serverStart, device: TrialStamp.read())
        TrialStamp.write(start)
        return start
    }
}

/// One keychain item, one date. Written by the app in the background; same store and
/// accessibility as the signed-in session, so it needs nothing from the person.
enum TrialStamp {
    private static let service = "app.longbook.trial"
    private static let account = "started"

    private static var query: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecUseDataProtectionKeychain as String: true,
        ]
    }

    static func read() -> Date? {
        var find = query
        find[kSecReturnData as String] = true
        find[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(find as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data, let text = String(data: data, encoding: .utf8),
              let seconds = Double(text)
        else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }

    static func write(_ date: Date) {
        let data = Data(String(date.timeIntervalSince1970).utf8)
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }
}
