// The account on the other side of a transfer. A statement import writes the account it
// names into the commitment's details, by id when the book holds it and by name always.
import Foundation

public enum CounterpartAccounts {
    public static let idKey = "counterpart_account_id"
    public static let nameKey = "counterpart_account"

    /// The counterpart an outgoing transfer names: its id first, else its name.
    public static func counterpart(of sub: Subscription) -> (id: String?, name: String?) {
        let details = sub.details ?? [:]
        func text(_ key: String) -> String? {
            guard case .string(let value)? = details[key] else { return nil }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        return (text(idKey), text(nameKey))
    }

    /// Whether a commitment moves money to this account: by id, or by a name that reads
    /// as the same account.
    public static func moves(_ sub: Subscription, to account: PaymentMethod) -> Bool {
        let named = counterpart(of: sub)
        if let id = named.id { return id == account.id }
        guard let name = named.name else { return false }
        return StatementCounterparts.sameAccount(name, account.name)
    }

    /// Every commitment moving money to each account, keyed by account id, in the book's order.
    public static func transfers(in vault: Vault) -> [String: [Subscription]] {
        var out: [String: [Subscription]] = [:]
        let byId = Dictionary(vault.paymentMethods.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for sub in vault.subscriptions {
            let named = counterpart(of: sub)
            if let id = named.id {
                if byId[id] != nil { out[id, default: []].append(sub) }
                continue
            }
            guard let name = named.name,
                  let account = vault.paymentMethods.first(where: { StatementCounterparts.sameAccount(name, $0.name) })
            else { continue }
            out[account.id, default: []].append(sub)
        }
        return out
    }
}
