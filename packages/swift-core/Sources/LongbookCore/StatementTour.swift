// What an import saved, read back from the two vaults: every card the tour shows, and the
// steps that show them. Pure, so the words, counts and skipping are proved without a screen.
import Foundation

public enum StatementTour {
    /// The six kinds, in the order the reading names them and the steps show them.
    public enum Kind: String, CaseIterable, Sendable {
        case charge, people, account, commitment, transfer, earning
    }

    /// Which symbol a detail wears; the app names the SF Symbol.
    public enum Fact: Sendable, Equatable {
        case date, category, person, account, cycle, charges, commitments
    }

    public struct Detail: Equatable, Sendable {
        public let fact: Fact
        public let text: String
    }

    /// One card, in words already.
    public struct Card: Identifiable, Equatable, Sendable {
        public let id: String
        public let kind: Kind
        public let title: String
        /// Self or a relationship; only a person has one.
        public let pill: String?
        public let amount: String?
        public let details: [Detail]
        /// A file name inside the longbook folder, when the row has a picture.
        public let photo: String?
    }

    /// Every card of an import, kind by kind.
    public struct Findings: Equatable, Sendable {
        public var charges: [Card] = []
        public var people: [Card] = []
        public var accounts: [Card] = []
        public var commitments: [Card] = []
        public var transfers: [Card] = []
        public var earnings: [Card] = []

        public init() {}

        public func cards(_ kind: Kind) -> [Card] {
            switch kind {
            case .charge: charges
            case .people: people
            case .account: accounts
            case .commitment: commitments
            case .transfer: transfers
            case .earning: earnings
            }
        }

        /// A step for each kind with something to show, in order.
        public var steps: [Step] {
            Kind.allCases.compactMap { kind in
                let count = cards(kind).count
                return count > 0 ? Step(kind: kind, count: count) : nil
            }
        }

        public var isEmpty: Bool { steps.isEmpty }
    }

    /// The cards a step opens with; the rest wait behind See All.
    public static let cardsOnAStep = 4

    /// One step's words. Only the count varies them.
    public struct Step: Identifiable, Equatable, Sendable {
        public let kind: Kind
        public let count: Int
        public var id: Kind { kind }

        public init(kind: Kind, count: Int) {
            self.kind = kind
            self.count = count
        }

        public var heading: String {
            let many = count != 1
            switch kind {
            case .charge: return "Imported \(count) Past \(many ? "Expenses" : "Expense")"
            case .people: return "Found \(count) \(many ? "People" : "Person")"
            case .account: return "Found \(count) \(many ? "Accounts" : "Account")"
            case .commitment: return "Found \(count) \(many ? "Commitments" : "Commitment")"
            case .transfer: return "Found \(count) \(many ? "Transfers" : "Transfer")"
            case .earning: return "Found \(count) \(many ? "Earnings" : "Earning")"
            }
        }

        public var line: String {
            switch kind {
            case .charge: "Charges cards are saved"
            case .people: "People cards are saved"
            case .account: "Account cards are saved"
            case .commitment: "Commitment cards are saved"
            case .transfer: "Transfer cards are saved"
            case .earning: "Earning cards are saved"
            }
        }

        /// See All, when there is more than the step shows. People always has it: a person is
        /// removed only there.
        public var seeAll: String? {
            guard count > StatementTour.cardsOnAStep || kind == .people else { return nil }
            return "See All \(count) \(listName(count))"
        }

        /// The See All screen's heading.
        public var listTitle: String {
            switch kind {
            case .charge: "\(count) Past \(count == 1 ? "Expense" : "Expenses")"
            case .people: "People"
            default: "\(count) \(listName(count))"
            }
        }

        private func listName(_ count: Int) -> String {
            let many = count != 1
            switch kind {
            case .charge: return many ? "Charges" : "Charge"
            case .people: return many ? "People" : "Person"
            case .account: return many ? "Accounts" : "Account"
            case .commitment: return many ? "Commitments" : "Commitment"
            case .transfer: return many ? "Transfers" : "Transfer"
            case .earning: return many ? "Earnings" : "Earning"
            }
        }
    }

    /// The line over People's See All, counting those still kept.
    public static func peopleLine(kept: Int) -> String {
        kept == 1 ? "1 Person is saved. Tap one to remove it." : "\(kept) People are saved. Tap one to remove it."
    }

    /// Under Import Another Statement on the end screen.
    public static let nextMonthLine = "Next month, import your new statement and everything stays in one place."

    /// A kind's name in the end screen's list.
    public static func listLabel(_ kind: Kind) -> String {
        switch kind {
        case .charge: "Charges"
        case .people: "People"
        case .account: "Accounts"
        case .commitment: "Commitments"
        case .transfer: "Transfers"
        case .earning: "Earnings"
        }
    }

    /// Where the reader stands: a step, or the end past the last one. Fixed to the steps it
    /// started with, so taking the last person out never moves a step from under them.
    public struct Walk: Equatable, Sendable {
        public let steps: [Step]
        public private(set) var index = 0

        public init(steps: [Step]) { self.steps = steps }

        public var current: Step? { steps.indices.contains(index) ? steps[index] : nil }
        public var isEnd: Bool { current == nil }
        public var isFirst: Bool { index == 0 }

        /// Continue, also on the last step, which leads to the end.
        public mutating func forward() { if !isEnd { index += 1 } }
        public mutating func back() { if index > 0 { index -= 1 } }
        public mutating func skip() { index = steps.count }
        public mutating func jump(to kind: Kind) {
            if let at = steps.firstIndex(where: { $0.kind == kind }) { index = at }
        }
    }

    // MARK: reading the vaults

    /// The cards for what `after` holds and `before` did not: charges by their commitment and
    /// day, people, accounts and commitments by id. A later import shows only what it added,
    /// so nothing older can be taken out from here.
    public static func findings(before: [String: Any], after: [String: Any], today: Date = LB.todayMid()) -> Findings {
        func rows(_ raw: [String: Any], _ key: String) -> [[String: Any]] { raw[key] as? [[String: Any]] ?? [] }
        func ids(_ raw: [String: Any], _ key: String) -> Set<String> { Set(rows(raw, key).compactMap { $0["id"] as? String }) }
        func chargeId(_ row: [String: Any]) -> String? {
            guard let id = row["commitment_id"] as? String, let date = row["date"] as? String else { return nil }
            return VaultPatch.chargeKey(id, date)
        }

        let peopleKey = VaultPatch.EntityKind.familyMember.rawValue
        let accountsKey = VaultPatch.EntityKind.paymentMethod.rawValue
        let members = rows(after, peopleKey)
        let accounts = rows(after, accountsKey)
        let commitments = rows(after, "commitments")
        let charges = VaultPatch.chargeRows(after)
        let memberName = Dictionary(members.compactMap { row in (row["id"] as? String).map { ($0, row["name"] as? String ?? "") } }, uniquingKeysWith: { first, _ in first })
        let accountById = Dictionary(accounts.compactMap { row in (row["id"] as? String).map { ($0, row) } }, uniquingKeysWith: { first, _ in first })
        let byId = Dictionary(commitments.compactMap { row in (row["id"] as? String).map { ($0, row) } }, uniquingKeysWith: { first, _ in first })

        /// The person a row is for: the one it names, else whoever owns its account.
        func personId(_ commitment: [String: Any]) -> String? {
            if let member = commitment["member_id"] as? String, memberName[member] != nil { return member }
            return (commitment["account_id"] as? String).flatMap { accountById[$0]?["member_id"] as? String }
        }
        /// From before To, as every money card says them: the account and whom it paid, money
        /// in the other way round, a transfer account to account. An account not known says None; a
        /// person not in People is left off.
        func links(_ commitment: [String: Any]) -> [Detail] {
            func text(_ word: String, _ name: String?) -> String { "\(word) \(name.flatMap { $0.isEmpty ? nil : $0 } ?? "None")" }
            let own = (commitment["account_id"] as? String).flatMap { accountById[$0]?["name"] as? String }
            let details = commitment["details"] as? [String: Any]
            let other = (details?[CounterpartAccounts.idKey] as? String).flatMap { accountById[$0]?["name"] as? String }
                ?? details?[CounterpartAccounts.nameKey] as? String
            let person = (commitment["member_id"] as? String).flatMap { memberName[$0] }
            let named = person.map { [$0] } ?? []
            switch direction(commitment) {
            case "in": return named.map { Detail(fact: .person, text: text("From", $0)) } + [Detail(fact: .account, text: text("To", own))]
            case "transfer": return [Detail(fact: .account, text: text("From", own)), Detail(fact: .account, text: text("To", other))]
            default: return [Detail(fact: .account, text: text("From", own))] + named.map { Detail(fact: .person, text: text("To", $0)) }
            }
        }
        func day(_ iso: String?) -> String { iso.flatMap(LB.parseDate).map(LB.longDate) ?? (iso ?? "") }
        func direction(_ commitment: [String: Any]?) -> String? { VaultPatch.storedDirection(commitment?["direction"] as? String) }
        func isLanded(_ row: [String: Any]) -> Bool { (row["basis"] as? String) == "statement" }
        func currency(_ row: [String: Any], _ commitment: [String: Any]) -> String {
            row["currency"] as? String ?? commitment["currency"] as? String ?? "INR"
        }

        var found = Findings()
        let oldCharges = Set(VaultPatch.chargeRows(before).compactMap(chargeId))
        var newCharges: [(row: [String: Any], commitment: [String: Any], id: String)] = []
        for row in charges where isLanded(row) {
            guard let id = chargeId(row), !oldCharges.contains(id),
                  let commitment = (row["commitment_id"] as? String).flatMap({ byId[$0] }) else { continue }
            newCharges.append((row, commitment, id))
        }
        newCharges.sort { ($0.row["date"] as? String ?? "") > ($1.row["date"] as? String ?? "") }
        for charge in newCharges {
            let amount = fmtMoneyExact((charge.row["amount"] as? NSNumber)?.doubleValue ?? 0, currency(charge.row, charge.commitment))
            let title = charge.commitment["name"] as? String ?? ""
            let when = Detail(fact: .date, text: day(charge.row["date"] as? String))
            switch direction(charge.commitment) {
            case "in":
                found.earnings.append(Card(id: charge.id, kind: .earning, title: title, pill: nil, amount: amount,
                                           details: [when] + links(charge.commitment), photo: nil))
            case "transfer":
                found.transfers.append(Card(id: charge.id, kind: .transfer, title: title, pill: nil, amount: amount,
                                            details: [when] + links(charge.commitment), photo: nil))
            default:
                let category = (charge.commitment["tag"] as? String).flatMap { $0.isEmpty ? nil : Detail(fact: .category, text: categoryWord($0)) }
                found.charges.append(Card(id: charge.id, kind: .charge, title: title, pill: nil, amount: amount,
                                          details: [when] + (category.map { [$0] } ?? []) + links(charge.commitment), photo: nil))
            }
        }

        // Charges only: a Transfer is shown and never summed, and money in is nobody's spending.
        var spent: [String: [String: Double]] = [:]
        var chargeCount: [String: Int] = [:]
        var chargesOnAccount: [String: Int] = [:]
        for row in charges where isLanded(row) || row["paid"] as? Bool == true {
            guard let commitment = (row["commitment_id"] as? String).flatMap({ byId[$0] }), direction(commitment) == nil else { continue }
            if let person = personId(commitment) {
                chargeCount[person, default: 0] += 1
                spent[person, default: [:]][currency(row, commitment), default: 0] += (row["amount"] as? NSNumber)?.doubleValue ?? 0
            }
            if let account = commitment["account_id"] as? String { chargesOnAccount[account, default: 0] += 1 }
        }
        let recurring = commitments.filter { ($0["billing_cycle"] as? String) != BillingCycle.once.rawValue }
        var repeatsOfPerson: [String: Int] = [:]
        var repeatsOnAccount: [String: Int] = [:]
        for commitment in recurring {
            if let person = personId(commitment) { repeatsOfPerson[person, default: 0] += 1 }
            if let account = commitment["account_id"] as? String { repeatsOnAccount[account, default: 0] += 1 }
        }
        func count(_ number: Int, _ one: String, _ many: String, none: String) -> String {
            number == 0 ? none : number == 1 ? "1 \(one)" : "\(number) \(many)"
        }

        let oldPeople = ids(before, peopleKey)
        var people: [Card] = []
        for member in members {
            guard let id = member["id"] as? String, !oldPeople.contains(id) else { continue }
            let owned = accounts.filter { $0["member_id"] as? String == id }.count
            // Each currency stands alone; the largest speaks for the card.
            let total = spent[id]?.max { $0.value < $1.value }
            let tag = (member["tag"] as? String)?.trimmingCharacters(in: .whitespaces)
            people.append(Card(id: id, kind: .people, title: member["name"] as? String ?? "",
                               pill: (tag?.isEmpty ?? true) ? nil : pillWord(tag ?? ""),
                               amount: total.map { fmtMoneyExact($0.value, $0.key) },
                               details: [
                                Detail(fact: .account, text: count(owned, "Account", "Accounts", none: "No account named")),
                                Detail(fact: .charges, text: count(chargeCount[id] ?? 0, "Charge", "Charges", none: "No charges")),
                                Detail(fact: .commitments, text: count(repeatsOfPerson[id] ?? 0, "Commitment", "Commitments", none: "No commitments")),
                               ],
                               photo: member["photo"] as? String))
        }
        found.people = people.filter { $0.pill?.lowercased() == StatementTransfers.selfTag } + people.filter { $0.pill?.lowercased() != StatementTransfers.selfTag }

        let oldAccounts = ids(before, accountsKey)
        let money = commitments.first?["currency"] as? String ?? "INR"
        for account in accounts {
            guard let id = account["id"] as? String, !oldAccounts.contains(id) else { continue }
            var details: [Detail] = []
            if let owner = (account["member_id"] as? String).flatMap({ memberName[$0] }), !owner.isEmpty { details.append(Detail(fact: .person, text: owner)) }
            details.append(Detail(fact: .charges, text: count(chargesOnAccount[id] ?? 0, "Charge", "Charges", none: "No charges")))
            if let date = account["balance_date"] as? String { details.append(Detail(fact: .date, text: "On \(day(date))")) }
            details.append(Detail(fact: .commitments, text: count(repeatsOnAccount[id] ?? 0, "Commitment", "Commitments", none: "No commitments")))
            found.accounts.append(Card(id: id, kind: .account, title: account["name"] as? String ?? "", pill: nil,
                                       amount: (account["balance"] as? NSNumber).map { fmtMoneyExact($0.doubleValue, money) },
                                       details: details, photo: account["photo"] as? String))
        }

        let oldCommitments = ids(before, "commitments")
        for commitment in recurring {
            guard let id = commitment["id"] as? String, !oldCommitments.contains(id) else { continue }
            let next = charges.filter { $0["commitment_id"] as? String == id && $0["paid"] as? Bool != true }
                .compactMap { ($0["date"] as? String).flatMap(LB.parseDate) }
                .filter { !($0 < today) }.min()
            var details: [Detail] = []
            if let next { details.append(Detail(fact: .date, text: LB.dueWord(LB.daysBetween(today, next), on: next))) }
            details.append(Detail(fact: .cycle, text: cycleWord(commitment)))
            found.commitments.append(Card(id: id, kind: .commitment, title: commitment["name"] as? String ?? "", pill: nil,
                                          amount: (commitment["amount"] as? NSNumber).map { fmtMoneyExact($0.doubleValue, commitment["currency"] as? String ?? money) },
                                          details: details + links(commitment), photo: commitment["photo"] as? String))
        }
        return found
    }

    /// A relationship as a pill says it: its first letter up.
    private static func pillWord(_ tag: String) -> String { tag.prefix(1).uppercased() + tag.dropFirst() }

    private static func cycleWord(_ commitment: [String: Any]) -> String {
        switch commitment["billing_cycle"] as? String {
        case BillingCycle.monthly.rawValue: return "Monthly"
        case BillingCycle.yearly.rawValue: return "Yearly"
        default: return (commitment["custom_cycle_days"] as? NSNumber).map { "Every \($0.intValue) days" } ?? "Repeats"
        }
    }
}
