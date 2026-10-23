import DesignSystem
import LongbookCore
import SwiftUI

/// The words the account and people screens share, so the list, the editor and the
/// delete question never drift apart.
enum EntityCopy {
    static func word(_ kind: VaultPatch.EntityKind) -> String {
        kind == .paymentMethod ? "account" : "person"
    }

    /// The vault's own word for the kind, which insight keys are filed under.
    static func insightWord(_ kind: VaultPatch.EntityKind) -> String {
        kind == .paymentMethod ? "account" : "member"
    }

    /// A card's name as it reads: the bucket of commitments naming nobody is Unassigned.
    static func name(_ card: DashboardModel.EntityCard) -> String {
        card.isReal ? card.name : "Unassigned"
    }

    /// The counts first: the numbers are the whole reason to hesitate. Commitments are
    /// counted as the card counts them; settled one-time charges and, for a person, their
    /// accounts are named beside them, since deleting unhooks those too.
    static func removalNote(
        _ kind: VaultPatch.EntityKind, use: (commitments: Int, oneTime: Int, accounts: Int)
    ) -> String {
        let isAccount = kind == .paymentMethod
        let parts = [
            use.commitments > 0 ? counted(use.commitments, "commitment") : nil,
            use.oneTime > 0 ? counted(use.oneTime, "one-time charge") : nil,
            use.accounts > 0 ? counted(use.accounts, "account") : nil,
        ].compactMap { $0 }
        guard let last = parts.last else {
            return isAccount
                ? "No commitment uses this account. Deleting it changes nothing else."
                : "Nothing names this person. Deleting them changes nothing else."
        }
        let list = parts.count > 1 ? parts.dropLast().joined(separator: ", ") + " and " + last : last
        let single = use.commitments + use.oneTime + use.accounts == 1
        let verb = isAccount ? (single ? "uses this account" : "use this account")
            : (single ? "names this person" : "name this person")
        return "\(list) \(verb). \(single ? "It stays" : "They stay"), without \(isAccount ? "an account" : "a person")."
    }

    static func counted(_ count: Int, _ noun: String) -> String {
        "\(count) \(noun)\(count == 1 ? "" : "s")"
    }

    /// A tag as it reads: its first letter raised, and the few that are initials in full.
    static func tagWord(_ tag: String) -> String { categoryWord(tag) }
}

/// The add form as an account or a person opens it, with that account or person already
/// chosen. The one place the cards and the editor open it from.
@MainActor
func entityAddForm(
    model: DashboardModel, kind: VaultPatch.EntityKind, id: String, onDone: @escaping () -> Void
) -> some View {
    RenewalFormView(
        model: model, editingId: nil,
        seedMethodId: kind == .paymentMethod ? id : nil,
        seedMemberId: kind == .familyMember ? id : nil,
        onDone: onDone
    )
}

/// The initial in a tinted circle: the colour an account or a person wears everywhere. A
/// person with a picture in the folder shows it instead, in the same circle.
struct EntityAvatar: View {
    let name: String
    let ink: Int?
    var size: CGFloat = 36
    var photo: URL? = nil
    var photoData: Data? = nil
    @ScaledMetric(relativeTo: .body) private var scale: CGFloat = 1

    var body: some View {
        Circle()
            .fill(LBColor.dataInk(rank: ink).color.opacity(0.22))
            .frame(width: size * scale, height: size * scale)
            .overlay {
                if let image = picture {
                    image.resizable().scaledToFill()
                        .frame(width: size * scale, height: size * scale)
                        .clipShape(Circle())
                } else {
                    Text(name.trimmingCharacters(in: .whitespaces).prefix(1).uppercased())
                        .lbText(size >= 30 ? .body : .tabLabel)
                        .foregroundStyle(LBColor.textPrimary.color)
                }
            }
            .accessibilityHidden(true)
    }

    /// The picked bytes first, then the file in the folder; a file that will not open draws the initial.
    private var picture: Image? {
        let data = photoData ?? photo.flatMap { try? Data(contentsOf: $0) }
        #if os(macOS)
        return data.flatMap(NSImage.init(data:)).map(Image.init(nsImage:))
        #else
        return data.flatMap(UIImage.init(data:)).map(Image.init(uiImage:))
        #endif
    }
}

/// An account's type or a person's tag, as the quiet pill beside their name.
struct EntityTagPill: View {
    let tag: String

    var body: some View {
        Text(EntityCopy.tagWord(tag))
            .lbText(.label)
            .foregroundStyle(LBColor.textSecondary.color)
            .lineLimit(1)
            .padding(.horizontal, LBSpacing.s2)
            .padding(.vertical, 4)
            .background(LBColor.chrome.color, in: Capsule())
    }
}

/// A commitment's glyph on its tile, tinted with its category's ink.
struct EntityGlyphTile: View {
    let symbol: String
    var ink: Int?
    var size: CGFloat = 32

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.44, weight: .medium))
            .foregroundStyle(LBColor.dataInk(rank: ink).color)
            .frame(width: size, height: size)
            .background(LBColor.chrome.color, in: RoundedRectangle(cornerRadius: LBRadius.xs, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// One charge a card or the editor names: its glyph, its name, then the day and amount.
struct EntityMomentRow: View {
    let moment: DashboardModel.EntityMoment
    var showsChevron = true

    var body: some View {
        HStack(spacing: LBSpacing.s3) {
            EntityGlyphTile(symbol: moment.symbol, ink: moment.ink)
            VStack(alignment: .leading, spacing: 2) {
                Text(moment.name)
                    .lbText(.bodySM)
                    .foregroundStyle(LBColor.textPrimary.color)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(LB.longDate(moment.date)) · \(moment.amountText)")
                    .lbText(.footnote)
                    .foregroundStyle(LBColor.textSecondary.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: LBSpacing.s2)
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(LBColor.textQuaternary.color)
                    .accessibilityHidden(true)
            }
        }
        .frame(minHeight: 36)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// One labelled fact: the word above, the glyph and what it says below.
private struct EntityFact<Value: View>: View {
    let label: String
    @ViewBuilder let value: () -> Value

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .lbText(.footnote)
                .foregroundStyle(LBColor.textTertiary.color)
                .lineLimit(1)
            value()
        }
        .accessibilityElement(children: .combine)
    }
}

/// Columns by share of the width, where a column that needs more than its share keeps
/// what it needs and the rest give way. The ideal width is every column's words on one
/// line, so ViewThatFits takes the row only when nothing in it would be cut.
private struct EntityColumns: Layout {
    var shares: [CGFloat] = []
    var spacing: CGFloat = LBSpacing.s3

    private func needs(_ subviews: Subviews) -> [CGFloat] {
        subviews.map { $0.sizeThatFits(.unspecified).width.rounded(.up) }
    }

    private func gaps(_ count: Int) -> CGFloat {
        spacing * CGFloat(max(count - 1, 0))
    }

    private func widths(_ total: CGFloat, needs: [CGFloat]) -> [CGFloat] {
        let all = Array(needs.indices)
        let parts = shares.count == needs.count ? shares : all.map { _ in 1 }
        let room = max(0, total - gaps(needs.count))
        var held = Set<Int>()
        while held.count < needs.count {
            let open = all.filter { !held.contains($0) }
            let free = room - held.reduce(0) { $0 + needs[$1] }
            let share = max(open.reduce(0) { $0 + parts[$1] }, 0.0001)
            let short = open.filter { free * parts[$0] / share < needs[$0] }
            if short.isEmpty {
                return all.map { held.contains($0) ? needs[$0] : free * parts[$0] / share }
            }
            held.formUnion(short)
        }
        // Narrower than the words: every column gives way alike.
        let wanted = max(needs.reduce(0, +), 0.0001)
        return needs.map { $0 * min(1, room / wanted) }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard !subviews.isEmpty else { return .zero }
        let needs = needs(subviews)
        let ideal = needs.reduce(0, +) + gaps(needs.count)
        let width = proposal.width.map { $0.isFinite ? $0 : ideal } ?? ideal
        let height = zip(subviews, widths(width, needs: needs))
            .map { $0.sizeThatFits(ProposedViewSize(width: $1, height: nil)).height }
            .max() ?? 0
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        for (subview, width) in zip(subviews, widths(bounds.width, needs: needs(subviews))) {
            subview.place(
                at: CGPoint(x: x, y: bounds.minY), anchor: .topLeading,
                proposal: ProposedViewSize(width: width, height: bounds.height)
            )
            x += width + spacing
        }
    }
}

/// An account or a person as a card: who, how much hangs on them, what comes next, and
/// the three things to do about it. The editor draws the same card as its live preview.
struct EntityCardView: View {
    enum Style {
        /// The list's card: every fact and the actions; delete is in its menu.
        case list
        /// The editor's preview: every fact, nothing to press.
        case preview
    }

    struct Actions {
        let delete: () -> Void
        let addCommitment: () -> Void
        let edit: () -> Void
        /// Opens one commitment the card names; without it the row is a navigation link.
        var open: ((String) -> Void)? = nil
    }

    let card: DashboardModel.EntityCard
    var style: Style = .list
    var insight: Insight?
    var actions: Actions?

    private var isAccount: Bool { card.kind == .paymentMethod }

    /// Named, and nothing said about it yet.
    private var isBare: Bool {
        guard card.isReal, card.isIncomplete, card.tag == nil else { return false }
        return !isAccount || (card.balance == nil && card.owner == nil && card.linked == nil)
    }

    /// The actions a list card offers from its menu; the editor's preview offers none.
    private var menuActions: Actions? {
        style == .list && card.isReal ? actions : nil
    }

    var body: some View {
        if let menuActions {
            cardBody
                .contextMenu { menu(menuActions) }
                // A press and hold is the only way to the menu, and VoiceOver has none to give.
                .accessibilityActions { menu(menuActions) }
        } else {
            cardBody
        }
    }

    @ViewBuilder
    private func menu(_ actions: Actions) -> some View {
        Button(action: actions.edit) { Label("Edit", systemImage: "pencil") }
        Button(action: actions.addCommitment) { Label("Add Commitment", systemImage: "plus") }
        Button(role: .destructive, action: actions.delete) { Label("Delete", systemImage: "trash") }
    }

    private var cardBody: some View {
        VStack(alignment: .leading, spacing: LBSpacing.s3) {
            header
            if isBare, style == .list {
                Text("Only its name is written. Edit adds the rest.")
                    .lbText(.footnote)
                    .foregroundStyle(LBColor.textSecondary.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
            counts
            if isAccount, card.isReal {
                rule
                money
            } else if card.accountCount > 0 {
                rule
                EntityFact(label: "Accounts") {
                    glyphValue(LBGlyph.account, EntityCopy.counted(card.accountCount, "account"))
                }
            }
            rule
            nextCommitment
            if style == .list { buttons }
        }
        .padding(LBSpacing.s4)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        // The wide preview sits inside a panel, so it takes the surface under the card's.
        .background(
            (style == .preview ? LBColor.sunken : LBColor.card).color,
            in: RoundedRectangle(cornerRadius: LBRadius.md, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: LBRadius.md, style: .continuous)
                .strokeBorder(LBColor.hairline.color, lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel(EntityCopy.name(card))
    }

    private var rule: some View {
        Rectangle()
            .fill(LBColor.hairline.color)
            .frame(height: 1)
            .accessibilityHidden(true)
    }

    // MARK: who

    private var header: some View {
        HStack(alignment: .center, spacing: LBSpacing.s3) {
            EntityAvatar(name: EntityCopy.name(card), ink: card.ink, photo: card.photo)
            // Beside the name while both fit; under it once the name runs long.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: LBSpacing.s2) {
                    nameText.lineLimit(1)
                    pill
                }
                VStack(alignment: .leading, spacing: LBSpacing.s1) {
                    nameText
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    pill
                }
            }
            .accessibilityElement(children: .combine)
            InsightMark(insight: insight, labelled: true)
            Spacer(minLength: 0)
        }
    }

    private var nameText: some View {
        Text(EntityCopy.name(card).isEmpty ? " " : EntityCopy.name(card))
            .lbText(.body)
            .foregroundStyle(LBColor.textPrimary.color)
    }

    @ViewBuilder
    private var pill: some View {
        if let tag = card.tag, !tag.isEmpty { EntityTagPill(tag: tag) }
    }

    // MARK: facts

    private func glyphValue(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: LBSpacing.s1) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(LBColor.textTertiary.color)
                .accessibilityHidden(true)
            Text(text)
                .lbText(.bodySM)
                .foregroundStyle(LBColor.textPrimary.color)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Side by side while every word fits on its line, stacked once one would be cut.
    private func row<A: View, B: View, C: View>(shares: [CGFloat], _ a: A, _ b: B, _ c: C) -> some View {
        ViewThatFits(in: .horizontal) {
            EntityColumns(shares: shares) {
                a
                divided(b)
                if C.self != EmptyView.self { divided(c) }
            }
            VStack(alignment: .leading, spacing: LBSpacing.s2) {
                a
                b
                c
            }
        }
    }

    /// A column after the first wears the hairline that parts it from the one before.
    private func divided<Content: View>(_ content: Content) -> some View {
        content
            .padding(.leading, LBSpacing.s3)
            // The row's full height, so every hairline in it is the same length.
            .frame(maxHeight: .infinity, alignment: .topLeading)
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(LBColor.hairline.color)
                    .frame(width: 1)
                    .accessibilityHidden(true)
            }
    }

    /// How many commitments and charges name it.
    private var counts: some View {
        row(
            shares: [1, 1],
            EntityFact(label: "Commitments") { glyphValue(LBGlyph.commitment, "\(card.commitments)") },
            EntityFact(label: "Charges") { glyphValue(LBGlyph.charge, "\(card.charges)") },
            EmptyView()
        )
    }

    private var balanceFact: some View {
        EntityFact(label: "Balance") {
            if let balance = card.balance {
                // The amount and its day part ways only when one line cannot hold both.
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: LBSpacing.s1) {
                        balanceAmount(balance)
                        balanceDay(leading: "· ")
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        balanceAmount(balance)
                        balanceDay(leading: "")
                    }
                }
            } else {
                Text("—")
                    .lbText(.bodySM)
                    .foregroundStyle(LBColor.textTertiary.color)
                    .accessibilityLabel("Not written")
            }
        }
    }

    private func balanceAmount(_ balance: Double) -> some View {
        LBAmount(fmtMoney(balance, card.balanceCurrency), prominence: .inline)
            .foregroundStyle(LBColor.textPrimary.color)
    }

    @ViewBuilder
    private func balanceDay(leading: String) -> some View {
        if let day = card.balanceDate {
            Text(leading + LB.longDate(day))
                .lbText(.footnote)
                .foregroundStyle(LBColor.textSecondary.color)
                .lineLimit(1)
        }
    }

    private var ownerFact: some View {
        EntityFact(label: "Owner") {
            if let owner = card.owner {
                HStack(spacing: LBSpacing.s1) {
                    EntityAvatar(name: owner.name, ink: owner.ink, size: 18)
                    Text(owner.name)
                        .lbText(.bodySM)
                        .foregroundStyle(LBColor.textPrimary.color)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text("—")
                    .lbText(.bodySM)
                    .foregroundStyle(LBColor.textTertiary.color)
                    .accessibilityLabel("No owner")
            }
        }
    }

    private var linkedFact: some View {
        EntityFact(label: "Linked to") {
            if let linked = card.linked {
                glyphValue("link", linked.name)
            } else {
                Text("—")
                    .lbText(.bodySM)
                    .foregroundStyle(LBColor.textTertiary.color)
                    .accessibilityLabel("Not linked")
            }
        }
    }

    /// Three across where the card is wide; on a phone the balance takes its own line.
    private var money: some View {
        ViewThatFits(in: .horizontal) {
            // Floors, so the three go across on a wide card and never on a phone.
            EntityColumns(shares: [1.4, 1, 1]) {
                balanceFact.frame(minWidth: 150, alignment: .leading)
                divided(ownerFact).frame(minWidth: 124, alignment: .leading)
                divided(linkedFact).frame(minWidth: 124, alignment: .leading)
            }
            VStack(alignment: .leading, spacing: LBSpacing.s2) {
                balanceFact
                row(shares: [1, 1], ownerFact, linkedFact, EmptyView())
            }
        }
    }

    // MARK: what comes next

    /// The twelve-month figure shares the label's line while both fit. Once they do not,
    /// it closes the block instead, so it never reads as the next commitment's amount.
    private var nextCommitment: some View {
        VStack(alignment: .leading, spacing: 0) {
            ViewThatFits(in: .horizontal) {
                labelLine
                nextLabel
            }
            nextRow.padding(.top, LBSpacing.s2)
            ViewThatFits(in: .horizontal) {
                labelLine
                    .hidden()
                    .frame(height: 0)
                    .accessibilityHidden(true)
                windowNote.padding(.top, LBSpacing.s1)
            }
        }
    }

    private var labelLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: LBSpacing.s2) {
            nextLabel
            Spacer(minLength: LBSpacing.s2)
            windowNote
        }
    }

    @ViewBuilder
    private var nextRow: some View {
        if let next = card.next {
            if style == .list, let open = actions?.open {
                // The phone's card is reached by a pushed page, where a value link would
                // reopen the page itself; the commitment opens as a sheet instead.
                Button { open(next.commitmentId) } label: {
                    EntityMomentRow(moment: next)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens this commitment.")
            } else if style == .list {
                NavigationLink(value: Destination.commitment(id: next.commitmentId)) {
                    EntityMomentRow(moment: next)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens this commitment.")
            } else {
                EntityMomentRow(moment: next, showsChevron: false)
            }
        } else {
            Text("No upcoming commitment.")
                .lbText(.bodySM)
                .foregroundStyle(LBColor.textSecondary.color)
                .frame(minHeight: 36, alignment: .leading)
        }
    }

    private var nextLabel: some View {
        Text("Next commitment")
            .lbText(.footnote)
            .foregroundStyle(LBColor.textTertiary.color)
            .lineLimit(1)
    }

    /// Real charges in the months they fall, per currency; silent when there are none. An
    /// account holds a total; a person is not a budget, so a member's card does not carry one.
    @ViewBuilder
    private var windowNote: some View {
        if isAccount, !card.window.isEmpty {
            Text("\(fmtMoneyTotals(card.window)) in the next 12 months")
                .lbText(.footnote)
                .foregroundStyle(LBColor.textTertiary.color)
                .lineLimit(1)
        }
    }

    // MARK: what to do

    @ViewBuilder
    private var buttons: some View {
        if let actions {
            if card.isReal {
                // One row where the card has the room, two once a label would be squeezed,
                // and one under another at the largest text sizes.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: LBSpacing.s2) {
                        addButton(actions, fills: true)
                        editButton(actions, fills: false)
                        showAllLink(fills: false)
                    }
                    VStack(spacing: LBSpacing.s2) {
                        addButton(actions, fills: true)
                        HStack(spacing: LBSpacing.s2) {
                            editButton(actions, fills: true)
                            showAllLink(fills: true)
                        }
                    }
                    VStack(spacing: LBSpacing.s2) {
                        addButton(actions, fills: true)
                        editButton(actions, fills: true)
                        showAllLink(fills: true)
                    }
                }
            } else if isAccount {
                // Nobody's bucket has nothing to edit; its list is still a door.
                showAllLink(fills: true)
            }
        }
    }

    private func addButton(_ actions: Actions, fills: Bool) -> some View {
        Button(action: actions.addCommitment) {
            EntityActionLabel(title: "Add Commitment", symbol: "plus", prominent: true, fills: fills)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add a commitment for \(card.name)")
    }

    private func editButton(_ actions: Actions, fills: Bool) -> some View {
        Button(action: actions.edit) {
            EntityActionLabel(title: "Edit", symbol: "pencil", prominent: false, fills: fills)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Edit \(card.name)")
    }

    private func showAllLink(fills: Bool) -> some View {
        NavigationLink(value: isAccount
            ? Destination.commitments(ListFilter(methodId: card.id))
            : Destination.commitments(ListFilter(memberId: card.id))) {
            EntityActionLabel(title: "Show All", symbol: "list.bullet", prominent: false, fills: fills)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isAccount ? "Commitments paid from \(card.name)" : "Commitments for \(card.name)")
    }
}

/// A card's action, drawn one way whether a button or a link carries it.
struct EntityActionLabel: View {
    let title: String
    let symbol: String
    let prominent: Bool
    var fills = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .accessibilityHidden(true)
            Text(title)
                .lbText(.bodySM)
                .lineLimit(1)
        }
        .foregroundStyle((prominent ? LBColor.onBrandTint : LBColor.textPrimary).color)
        .padding(.horizontal, LBSpacing.s4)
        .frame(maxWidth: fills ? .infinity : nil, minHeight: Self.height)
        .background(
            prominent ? LBColor.brand.color.opacity(0.12) : LBColor.chrome.color,
            in: RoundedRectangle(cornerRadius: LBRadius.xs, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: LBRadius.xs, style: .continuous)
                .strokeBorder(prominent ? LBColor.brand.color.opacity(0.45) : LBColor.hairline.color, lineWidth: 1)
        )
        .contentShape(Rectangle())
    }

    /// A finger's target on the phone; the pointer needs less.
    static var height: CGFloat {
        #if os(iOS)
        44
        #else
        36
        #endif
    }
}
