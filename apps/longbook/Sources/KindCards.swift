import DesignSystem
import LongbookCore
import SwiftUI

/// What a card opens: its own Preview. A charge, an earning and a transfer are each a row of
/// a commitment; the row knows which it is.
enum CardRef: Hashable {
    case charge(subId: String, id: String)
    case commitment(id: String)
    case entity(VaultPatch.EntityKind, id: String)

    /// The screen a stack pushes for it.
    var destination: Destination {
        if case .commitment(let id) = self { return .commitment(id: id) }
        return .card(self)
    }

    /// The same charge on another day; a charge's card is named by its commitment and its day.
    func moved(to day: String) -> CardRef? {
        guard case .charge(let subId, _) = self else { return nil }
        return .charge(subId: subId, id: "\(subId)-\(day)")
    }
}

/// The decided card for each thing a list holds, so every list says it in one format.
enum KindCards {
    /// Money cards say From before To: the account, then who it went to; money in the other
    /// way round; a transfer names both accounts. An account not known says None; a person not in People is left off.
    static func links(_ sides: MoneySides, income: Bool, transfer: Bool) -> [LBMetaFact] {
        func account(_ word: String, _ name: String?) -> LBMetaFact {
            LBMetaFact(symbol: LBGlyph.account, text: "\(word) \(name ?? "None")")
        }
        func person(_ word: String, _ name: String?) -> [LBMetaFact] {
            name.map { [LBMetaFact(symbol: LBGlyph.member, text: "\(word) \($0)")] } ?? []
        }
        if transfer { return [account("From", sides.from.account), account("To", sides.to.account)] }
        if income { return person("From", sides.from.person) + [account("To", sides.to.account)] }
        return [account("From", sides.from.account)] + person("To", sides.to.person)
    }

    static func badge(_ badge: DashboardData.CommitmentItem.Badge?) -> (text: String, tone: LBBadgeTone)? {
        switch badge {
        case .trial: (text: "Free trial", tone: .brand)
        case .cancelling: (text: "Cancelling", tone: .urgent)
        case .paused: (text: "Paused", tone: .muted)
        case .cancelled: (text: "Cancelled", tone: .muted)
        case nil: nil
        }
    }

    /// A charge, an earning or a transfer: its day and a spend's category, then From and To.
    /// Ahead of its day it wears its commitment's badge, and a tick once marked paid, unless an
    /// `accessory` such as the calendar's Mark Paid says so. A landed row wears neither.
    static func card(_ charge: DashboardModel.ChargeItem, photo: URL?, selected: Bool = false, marked: Bool = false,
                     accessory: AnyView? = nil) -> LBKindCard {
        let mark = charge.isPast ? nil : badge(charge.badge)
        return money(
            kind: charge.cardKind, title: charge.name, pill: mark, amount: charge.amountText, day: charge.dateWord,
            category: charge.category, sides: charge.sides, income: charge.isIncome, transfer: charge.isTransfer,
            photo: photo, state: accessory == nil && !charge.isPast && charge.isPaid ? .paid : .plain, selected: selected, marked: marked,
            accessory: accessory
        )
    }

    /// Money that moved, wherever a list shows it: its day, then a spend's category, asking for
    /// one it lacks while it can still be filled in, then From and To. An earning and a transfer
    /// carry no category.
    static func money(
        kind: LBCardKind, title: String, pill: (text: String, tone: LBBadgeTone)?, holdsPill: Bool = false, amount: String?,
        day: String?, category: String?, sides: MoneySides, income: Bool, transfer: Bool, photo: URL?, state: LBCardState,
        selected: Bool = false, marked: Bool = false, accessory: AnyView? = nil
    ) -> LBKindCard {
        let spend = !income && !transfer
        let filed = spend
            ? category.map { LBMetaFact(symbol: LBGlyph.category, text: categoryWord($0)) } ?? (state != .removed ? DashboardModel.addCategoryFact : nil)
            : nil
        let first = (day.map { [LBMetaFact(symbol: LBGlyph.date, text: $0)] } ?? []) + (filed.map { [$0] } ?? [])
        return LBKindCard(
            kind: kind, title: title, pill: pill?.text, pillTone: pill?.tone ?? .muted, holdsPill: holdsPill, amount: amount,
            details: first + links(sides, income: income, transfer: transfer),
            lead: first.count, image: photo, state: state, selected: selected, marked: marked, accessory: accessory
        )
    }

    /// A commitment: when it is next due and how often, then From and To; its badge by the
    /// name. A Proposal gives its own `pill`, and the `amount` it proposes.
    static func card(_ item: DashboardData.CommitmentItem, photo: URL?, pill: (text: String, tone: LBBadgeTone)? = nil, amount: String? = nil,
                     selected: Bool = false, marked: Bool = false) -> LBKindCard {
        let first = (item.dueWord.map { [LBMetaFact(symbol: LBGlyph.date, text: $0)] } ?? [])
            + [LBMetaFact(symbol: LBGlyph.cycle, text: item.cycleWord)]
        let mark = pill ?? badge(item.badge)
        return LBKindCard(
            kind: .commitment, title: item.name, pill: mark?.text, pillTone: mark?.tone ?? .muted, holdsPill: pill != nil,
            amount: amount ?? item.amountText,
            details: first + links(item.sides, income: item.isIncome, transfer: item.isTransfer),
            lead: first.count, image: photo, state: item.dueISO != nil && item.isPaid ? .paid : .plain, selected: selected, marked: marked
        )
    }

    /// What each list holds, said under its search field in the same words on iPhone and Mac.
    static func definition(of kind: LBCardKind) -> String {
        switch kind {
        case .commitment: "Money that comes round on a schedule: subscriptions, rent, premiums and EMIs. longbook works out the next date for each."
        case .charge: "Money that has left your accounts, one line per payment. A charge can stand alone or belong to a commitment."
        case .earning: "Money that has come in: salary, refunds and payments from others. Kept beside your spending, never added to it."
        case .transfer: "Money moved between accounts owned by someone marked Self. Left out of spending and earnings."
        case .account: "Where your money sits and moves: bank accounts, cards and wallets, each with an owner."
        case .people: "Who your money goes to and comes from: family, landlords and anyone a charge names."
        case .report: ""
        }
    }

    /// An account: its balance, whose it is and how much hangs on it. A person: what they
    /// sent, their relationship and how much hangs on them. A star stands in the corner when set.
    /// A Proposal's `pill` and `state` say what it does to the row.
    static func card(_ entity: DashboardModel.EntityCard, pill: (text: String, tone: LBBadgeTone)? = nil, state: LBCardState = .plain,
                     selected: Bool = false, marked: Bool = false, exactBalance: Bool = false) -> LBKindCard {
        let star = entity.starred
            ? AnyView(Image(systemName: "star.fill")
                .lbText(.cardDetail)
                .foregroundStyle(LBColor.brand.color)
                .accessibilityLabel("Starred"))
            : nil
        let tag = entity.tag.flatMap { $0.isEmpty ? nil : EntityCopy.tagWord($0) }
        if entity.kind == .paymentMethod {
            let first = (entity.isReal ? [LBMetaFact(symbol: LBGlyph.member, text: entity.owner?.name ?? "None")] : [])
                + [LBMetaFact(symbol: LBGlyph.charge, text: counted(entity.charges, "Charge", none: "No charges"))]
            let second = [LBMetaFact(symbol: LBGlyph.commitment, text: counted(entity.commitments, "Commitment", none: "No commitments"))]
            return LBKindCard(kind: .account, title: EntityCopy.name(entity), pill: pill?.text, pillTone: pill?.tone ?? .muted, holdsPill: pill != nil,
                              amount: entity.balance.map { exactBalance ? fmtMoneyCents($0, entity.balanceCurrency) : fmtMoney($0, entity.balanceCurrency) },
                              details: first + second, lead: first.count, image: entity.photo, state: state, selected: selected, marked: marked, accessory: star)
        }
        let first = (entity.isReal ? [LBMetaFact(symbol: LBGlyph.account, text: counted(entity.accountCount, "Account", none: "No accounts"))] : [])
            + [LBMetaFact(symbol: LBGlyph.charge, text: counted(entity.charges, "Charge", none: "No charges"))]
        return LBKindCard(kind: .people, title: EntityCopy.name(entity), pill: pill?.text ?? tag, pillTone: pill?.tone ?? .muted, holdsPill: pill != nil,
                          amount: entity.sent.isEmpty ? nil : fmtMoneyTotals(entity.sent),
                          details: first + [LBMetaFact(symbol: LBGlyph.commitment, text: counted(entity.commitments, "Commitment", none: "No commitments"))],
                          lead: first.count, image: entity.photo, state: state, selected: selected, marked: marked, accessory: star)
    }

    static func counted(_ count: Int, _ noun: String, none: String) -> String {
        count == 0 ? none : "\(count) \(noun)\(count == 1 ? "" : "s")"
    }
}

/// A list's definition above its search field: two lines at most, its type giving a little on a
/// narrow phone; an accessibility size takes what room it needs.
struct ListDefinition: View {
    private let words: String
    @Environment(\.dynamicTypeSize) private var typeSize

    init(kind: LBCardKind) { words = KindCards.definition(of: kind) }

    /// A screen whose list is no kind of card says what it holds in its own words.
    init(_ words: String) { self.words = words }

    var body: some View {
        Text(words)
            .lbText(.footnote)
            .foregroundStyle(LBColor.textTertiary.color)
            .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
            .minimumScaleFactor(typeSize.isAccessibilitySize ? 1 : 0.8)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension DashboardModel.ChargeItem {
    var cardKind: LBCardKind { isIncome ? .earning : (isTransfer ? .transfer : .charge) }
    var ref: CardRef { .charge(subId: subId, id: id) }
}

extension DashboardModel.EntityCard {
    var ref: CardRef { .entity(kind, id: id) }
}

/// A list's search field, under the list's definition: the magnifier, the words, and on the
/// phone a clear button once something is typed.
struct ListSearchField: View {
    @Binding var text: String
    let prompt: String

    var body: some View {
        HStack(spacing: LBSpacing.s2) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(LBColor.textTertiary.color)
                .accessibilityHidden(true)
            TextField("", text: $text, prompt: Text(prompt).foregroundStyle(LBColor.textTertiary.color))
                .textFieldStyle(.plain)
                .lbText(.body)
                .foregroundStyle(LBColor.textPrimary.color)
                .autocorrectionDisabled()
                #if os(iOS)
                .submitLabel(.search)
                #endif
                .accessibilityLabel(prompt)
            #if os(iOS)
            if !text.isEmpty {
                Button {
                    Measure.used("clear_search")
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(LBColor.textTertiary.color)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Clear search")
            }
            #endif
        }
        .padding(.horizontal, LBSpacing.s3)
        #if os(iOS)
        .frame(minHeight: 40)
        #else
        .padding(.vertical, 6)
        #endif
        .background(LBColor.card.color, in: RoundedRectangle(cornerRadius: LBRadius.sm, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: LBRadius.sm, style: .continuous)
                .strokeBorder(LBColor.hairline.color, lineWidth: 1)
        )
    }
}

#if os(iOS)
/// A card in a list row that opens its screen. The row's own tap follows the hidden link, so the
/// list draws no chevron over the card and the swipe actions stay the row's.
struct CardListLink<Card: View>: View {
    let destination: Destination
    @ViewBuilder let card: () -> Card

    var body: some View {
        ZStack {
            NavigationLink(value: destination) { EmptyView() }
                .opacity(0)
            card()
        }
    }
}
#endif
