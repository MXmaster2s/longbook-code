// Who and which account each side of a row names: where the money leaves, where it lands.
// Derived from what the file already holds, so nothing new is written for it.
import Foundation

public struct MoneySides: Equatable, Sendable {
    /// One side of the money. A person is always someone in People; an account with no id is
    /// the name a statement gave. Nil where the book names nothing.
    public struct Side: Equatable, Sendable {
        public var accountId: String?
        public var account: String?
        public var personId: String?
        public var person: String?

        public init(accountId: String? = nil, account: String? = nil, personId: String? = nil, person: String? = nil) {
            self.accountId = accountId
            self.account = account
            self.personId = personId
            self.person = person
        }
    }

    public var from: Side
    public var to: Side

    public init(from: Side, to: Side) {
        self.from = from
        self.to = to
    }

    /// The real people on either side, From first, each once.
    public var personIds: [String] {
        let ids = [from.personId, to.personId].compactMap { $0 }
        return ids.first == ids.last ? Array(ids.prefix(1)) : ids
    }

    /// The real accounts on either side, From first, each once.
    public var accountIds: [String] {
        let ids = [from.accountId, to.accountId].compactMap { $0 }
        return ids.first == ids.last ? Array(ids.prefix(1)) : ids
    }

    /// The accounts and people sides are read against, held once for a whole list of rows.
    public struct Book: Sendable {
        let accounts: [String: Account]
        let ordered: [Account]
        let people: [String: String]

        struct Account: Sendable {
            let id: String
            let name: String
            let holderId: String?
        }

        public init(_ vault: Vault) {
            let list = vault.paymentMethods.map { Account(id: $0.id, name: $0.name, holderId: $0.familyMemberId) }
            ordered = list
            accounts = Dictionary(list.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            people = Dictionary(vault.familyMembers.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        }

        /// An account's side: the account and whoever holds it.
        func side(of account: Account?) -> Side {
            let holder = account?.holderId.flatMap { id in people[id].map { (id, $0) } }
            return Side(accountId: account?.id, account: account?.name, personId: holder?.0, person: holder?.1)
        }

        /// The account a row names on its other side: by id first, else by a name that reads
        /// as the same account, else that name alone.
        func counterpart(of sub: Subscription) -> Side {
            let named = CounterpartAccounts.counterpart(of: sub)
            if let id = named.id, let account = accounts[id] { return side(of: account) }
            if let name = named.name {
                if let account = ordered.first(where: { StatementCounterparts.sameAccount(name, $0.name) }) {
                    return side(of: account)
                }
                return Side(account: name)
            }
            return Side()
        }
    }

    /// Each kind's rule. Out: the account and its holder pay the commitment's person. In: the
    /// person pays the account's holder, whose statement it is. A transfer: account to account,
    /// each with its holder.
    public static func of(_ sub: Subscription, in book: Book) -> MoneySides {
        let own = book.side(of: sub.paymentMethodId.flatMap { book.accounts[$0] })
        var other = book.counterpart(of: sub)
        if sub.isTransfer { return MoneySides(from: own, to: other) }
        let member = sub.familyMemberId.flatMap { id in book.people[id].map { (id, $0) } }
        other.personId = member?.0
        other.person = member?.1
        return sub.isIncome ? MoneySides(from: other, to: own) : MoneySides(from: own, to: other)
    }
}
