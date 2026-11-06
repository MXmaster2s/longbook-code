import DesignSystem
import LongbookCore
import SwiftUI

/// What a Proposal does to a row, as its card and its detail both say it.
enum ProposalVerb {
    case added, changed, removed

    var word: String {
        switch self {
        case .added: "New"
        case .changed: "Edited"
        case .removed: "Removed"
        }
    }

    var tone: LBBadgeTone {
        switch self {
        case .added: .positive
        case .changed: .brand
        case .removed: .urgent
        }
    }

    var pill: (text: String, tone: LBBadgeTone) { (word, tone) }
    var state: LBCardState { self == .removed ? .removed : .plain }
}

/// One line of a Proposal, named well enough to draw: its section's kind, the rows it stands
/// for, and what the diff itself said in case the row can no longer be read.
struct ProposalRow {
    let kind: String
    let verb: ProposalVerb
    let id: String
    /// Every row the card stands for: "commitment@day" for charges, else the row's id.
    let ids: [String]
    let name: String
    let count: Int
    /// The days a folded plan covers.
    let span: String?
    let amount: Double?
    let currency: String?
}

/// What a Proposal's cards read, held once per review so no row reads the vault: the file as
/// it stands for what is new or edited, the last accepted version for what is removed. From
/// and To follow from that: the file's People already hold anyone this Proposal adds.
@MainActor
final class ProposalBook {
    private struct Read {
        let vault: Vault
        let subs: [String: Subscription]
        let book: MoneySides.Book
        /// By "commitment@day", as the diff keys them.
        let charges: [String: ChargeRow]
        /// A one-time commitment shown as its charge is keyed by the commitment alone.
        let firstCharge: [String: ChargeRow]
        let tagKinds: [String: String]

        init(_ vault: Vault) {
            self.vault = vault
            subs = Dictionary(vault.subscriptions.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            book = MoneySides.Book(vault)
            charges = Dictionary(vault.charges.map { ("\($0.commitmentId)@\($0.date)", $0) }, uniquingKeysWith: { first, _ in first })
            firstCharge = Dictionary(vault.charges.map { ($0.commitmentId, $0) }, uniquingKeysWith: { first, _ in first })
            tagKinds = Dictionary((vault.tags ?? []).map { ($0.id, $0.kind) }, uniquingKeysWith: { first, _ in first })
        }
    }

    private let model: DashboardModel
    private let commitmentIds: [String]
    private lazy var now: Read? = model.currentVault.map(Read.init)
    private lazy var before: Read? = model.reviewBaseVault().map(Read.init)
    private lazy var commitments: [String: DashboardData.CommitmentItem] = {
        let subs = commitmentIds.compactMap { now?.subs[$0] }
        return Dictionary(model.commitmentItems(of: subs).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }()
    private lazy var accounts = cards(.paymentMethod)
    private lazy var people = cards(.familyMember)
    private lazy var removedCounts = RemovedCounts(before?.vault, today: LB.todayMid())

    /// `commitmentIds`: the commitments the review shows, drawn together on the first card.
    init(model: DashboardModel, commitmentIds: [String]) {
        self.model = model
        self.commitmentIds = commitmentIds
    }

    private func cards(_ kind: VaultPatch.EntityKind) -> [String: DashboardModel.EntityCard] {
        Dictionary(model.entityCards(kind).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private func read(_ row: ProposalRow) -> Read? { row.verb == .removed ? before : now }

    private static func commitmentKey(_ id: String) -> String {
        guard let at = id.lastIndex(of: "@") else { return id }
        return String(id[..<at])
    }

    // MARK: the card

    func card(_ row: ProposalRow, selected: Bool) -> LBKindCard {
        switch row.kind {
        case "charges": moneyCard(row, selected: selected)
        case "commitments": commitmentCard(row, selected: selected)
        case "accounts": entityCard(row, kind: .paymentMethod, band: .account, selected: selected)
        case "members": entityCard(row, kind: .familyMember, band: .people, selected: selected)
        default: otherCard(row, selected: selected)
        }
    }

    private func moneyCard(_ row: ProposalRow, selected: Bool) -> LBKindCard {
        let read = read(row)
        let key = Self.commitmentKey(row.id)
        let sub = read?.subs[key]
        let rows = chargeRows(row, in: read)
        let day = row.count > 1
            ? ["\(row.count) charges", row.span].compactMap { $0 }.joined(separator: " · ")
            : rows.first.flatMap { LB.parseDate($0.date) }.map { model.chargeDayWord($0) }
        let ahead = rows.first.flatMap { LB.parseDate($0.date) }.map { !($0 < LB.todayMid()) } ?? false
        let paid = row.count == 1 && ahead && rows.first?.paid == true
        return KindCards.money(
            kind: sub.map(Self.band) ?? .charge, title: sub?.name ?? Self.namePart(row.name), pill: row.verb.pill, holdsPill: true,
            amount: amount(row), day: day, category: sub.flatMap(model.trimmedCategory),
            sides: sides(sub, in: read), income: sub?.isIncome ?? false, transfer: sub?.isTransfer ?? false,
            photo: model.photoURL(sub?.photo), state: row.verb == .removed ? .removed : (paid ? .paid : .plain), selected: selected
        )
    }

    private func commitmentCard(_ row: ProposalRow, selected: Bool) -> LBKindCard {
        if row.verb != .removed, let item = commitments[row.id] {
            return KindCards.card(item, photo: model.commitmentPhotoURL(id: row.id), pill: row.verb.pill, amount: amount(row), selected: selected)
        }
        let read = read(row)
        let sub = read?.subs[row.id]
        let first = sub.map { [LBMetaFact(symbol: LBGlyph.cycle, text: DashboardModel.cycleWord($0))] } ?? []
        return LBKindCard(
            kind: .commitment, title: sub?.name ?? row.name, pill: row.verb.word, pillTone: row.verb.tone, holdsPill: true,
            amount: amount(row), details: first + links(row),
            lead: first.count, image: model.photoURL(sub?.photo), state: row.verb.state, selected: selected
        )
    }

    private func entityCard(_ row: ProposalRow, kind: VaultPatch.EntityKind, band: LBCardKind, selected: Bool) -> LBKindCard {
        let held = row.verb == .removed
            ? removedEntity(row, kind: kind)
            : (kind == .paymentMethod ? accounts : people)[row.id]
        if let held {
            return KindCards.card(held, pill: row.verb.pill, state: row.verb.state, selected: selected, exactBalance: true)
        }
        return LBKindCard(kind: band, title: row.name, pill: row.verb.word, pillTone: row.verb.tone, holdsPill: true,
                          state: row.verb.state, selected: selected)
    }

    /// An account or a person read from the version it is leaving: what hung on it then.
    private func removedEntity(_ row: ProposalRow, kind: VaultPatch.EntityKind) -> DashboardModel.EntityCard? {
        guard let read = before else { return nil }
        let isAccount = kind == .paymentMethod
        let method = isAccount ? read.vault.paymentMethods.first { $0.id == row.id } : nil
        let member = isAccount ? nil : read.vault.familyMembers.first { $0.id == row.id }
        guard method != nil || member != nil else { return nil }
        let holder = method?.familyMemberId.flatMap { id in read.vault.familyMembers.first { $0.id == id } }
        let counts = removedCounts.of(row.id)
        return DashboardModel.EntityCard(
            id: row.id, kind: kind, name: method?.name ?? member?.name ?? row.name, tag: method?.tag ?? member?.tag,
            photo: model.photoURL(method?.photo ?? member?.photo), ink: nil, isReal: true, isIncomplete: false,
            starred: false, commitments: counts.commitments, charges: counts.charges, activity: counts.charges, sent: [],
            addedOn: nil, balance: method?.balance, balanceDate: LB.parseDate(method?.balanceDate), balanceCurrency: model.figureCurrency(read.vault),
            owner: holder.map { ($0.id, $0.name, nil) }, linked: nil,
            accountCount: read.vault.paymentMethods.filter { $0.familyMemberId == row.id }.count, next: nil, window: []
        )
    }

    /// A category, an account type or a relationship: none of the kinds, so the shape with no
    /// band, in plain words. What changed stands under it and in its detail.
    private func otherCard(_ row: ProposalRow, selected: Bool) -> LBKindCard {
        LBKindCard(
            kind: nil, symbol: LBGlyph.category, title: categoryWord(row.name), pill: row.verb.word, pillTone: row.verb.tone,
            holdsPill: true, details: [LBMetaFact(symbol: LBGlyph.category, text: noun(row))], lead: 1,
            state: row.verb.state, selected: selected
        )
    }

    // MARK: what a card and the detail share

    /// The money the card shows: the rows' own figure when they agree, proposed or as last
    /// kept; a commitment's own. A row's own currency wins over its commitment's.
    func amount(_ row: ProposalRow) -> String? {
        switch row.kind {
        case "charges":
            let read = read(row)
            let sub = read?.subs[Self.commitmentKey(row.id)]
            let rows = chargeRows(row, in: read)
            let agreed = Set(rows.map(\.amount)).count == 1 ? rows.first?.amount : nil
            guard let figure = rows.isEmpty ? row.amount : agreed else { return nil }
            let currency = rows.first?.currency ?? sub?.currency ?? row.currency ?? ""
            return (sub?.isIncome == true ? "+" : "") + fmtMoneyCents(figure, currency)
        case "commitments":
            // New: as its list will say it. Edited or removed: the figure the row itself holds, so
            // an edited amount shows though the next charge still says the old one.
            if row.verb == .added, let item = commitments[row.id] { return item.amountExact }
            guard let sub = read(row)?.subs[row.id] else { return row.amount.map { fmtMoneyCents($0, row.currency ?? "") } }
            return fmtMoneyCents(sub.amount, sub.currency)
        default:
            return nil
        }
    }

    /// From and To, the same words as every money card. Empty where the row is not money.
    func links(_ row: ProposalRow) -> [LBMetaFact] {
        guard row.kind == "charges" || row.kind == "commitments" else { return [] }
        let read = read(row)
        guard let sub = read?.subs[Self.commitmentKey(row.id)] else { return [] }
        return KindCards.links(sides(sub, in: read), income: sub.isIncome, transfer: sub.isTransfer)
    }

    /// The row's category, as the file holds it or last held it.
    func category(_ row: ProposalRow) -> String? {
        read(row)?.subs[Self.commitmentKey(row.id)].flatMap(model.trimmedCategory)
    }

    /// What the row is, in a sentence: "charge", "earning", "category".
    func noun(_ row: ProposalRow) -> String {
        switch row.kind {
        case "charges":
            switch read(row)?.subs[Self.commitmentKey(row.id)].map(Self.band) {
            case .earning: "Earning"
            case .transfer: "Transfer"
            default: "Charge"
            }
        case "commitments": "Commitment"
        case "accounts": "Account"
        case "members": "Person"
        default:
            // A tag's id is its own, or "kind/key" when an outside hand wrote none.
            switch read(row)?.tagKinds[row.id] ?? row.id.split(separator: "/").first.map(String.init) {
            case "account": "Account type"
            case "member": "Relationship"
            default: "Category"
            }
        }
    }

    private func chargeRows(_ row: ProposalRow, in read: Read?) -> [ChargeRow] {
        row.ids.compactMap { id in id.contains("@") ? read?.charges[id] : read?.firstCharge[id] }
    }

    private func sides(_ sub: Subscription?, in read: Read?) -> MoneySides {
        guard let sub, let read else { return MoneySides(from: .init(), to: .init()) }
        return MoneySides.of(sub, in: read.book)
    }

    private static func band(_ sub: Subscription) -> LBCardKind {
        sub.isIncome ? .earning : (sub.isTransfer ? .transfer : .charge)
    }

    private static func namePart(_ name: String) -> String {
        name.components(separatedBy: " — ").first ?? name
    }
}

/// How much hung on each account and person in the version a removal leaves, counted once:
/// the commitments naming it and the landed charges of those.
private struct RemovedCounts {
    private var commitments: [String: Int] = [:]
    private var charges: [String: Int] = [:]

    init(_ vault: Vault?, today: Date) {
        guard let vault else { return }
        let book = MoneySides.Book(vault)
        var landed: [String: Int] = [:]
        for row in vault.charges {
            if let date = LB.parseDate(row.date), date < today { landed[row.commitmentId, default: 0] += 1 }
        }
        for sub in vault.subscriptions {
            let sides = MoneySides.of(sub, in: book)
            for id in sides.personIds + (sub.paymentMethodId.map { [$0] } ?? []) {
                commitments[id, default: 0] += 1
                if !sub.isIncome, !sub.isTransfer { charges[id, default: 0] += landed[sub.id] ?? 0 }
            }
        }
    }

    func of(_ id: String) -> (commitments: Int, charges: Int) {
        (commitments[id] ?? 0, charges[id] ?? 0)
    }
}
