import DesignSystem
import LongbookCore
import SwiftUI

/// What a search result opens: a card on its own screen, the Proposals screen, or an article.
enum SearchTarget: Hashable {
    case card(CardRef)
    case proposals
    case help(slug: String)
}

/// One result as the results draw it: what it is, a line of its facts, its amount and where it goes.
struct SearchItem {
    enum Source {
        case commitment(DashboardData.CommitmentItem)
        case charge(DashboardModel.ChargeItem)
        case entity(DashboardModel.EntityCard)
        case plain(symbol: String)
    }

    let entry: SearchEntry
    let facts: String
    let amount: String?
    let target: SearchTarget
    let source: Source

    /// The tile's glyph and colour: the kind's own, as its card's band wears it.
    var tile: (symbol: String, ink: Color) {
        switch source {
        case .commitment: (LBCardKind.commitment.symbol, LBCardKind.commitment.ink.color)
        case .charge(let charge): (charge.cardKind.symbol, charge.cardKind.ink.color)
        case .entity(let card):
            card.kind == .paymentMethod
                ? (LBCardKind.account.symbol, LBCardKind.account.ink.color)
                : (LBCardKind.people.symbol, LBCardKind.people.ink.color)
        case .plain(let symbol): (symbol, entry.kind == .proposals ? LBColor.attention.color : LBColor.textSecondary.color)
        }
    }
}

/// The search across the whole longbook, on this device only: the words typed, the row the
/// keyboard has reached, the recent searches, and the index the results are read from.
@MainActor
@Observable
final class SearchCenter {
    static let shared = SearchCenter()

    /// Words handed to a list screen by Show all. The token tells a second ask from the first.
    struct HandedWords: Equatable {
        let screen: String
        let query: String
        let token = UUID()
    }

    var query = "" {
        didSet { if query != oldValue { highlighted = 0 } }
    }
    /// The row Return opens, counted down the results.
    var highlighted = 0
    /// Whether the Mac's results stand under the sidebar's field.
    var showsPanel = false
    /// How many times ⌘K has asked for the field; each ask focuses it.
    private(set) var focusAsks = 0
    private(set) var handed: HandedWords?
    /// The last searches on this device, newest first.
    private(set) var recent: [String]

    private static let recentKey = "longbook.search.recent"
    @ObservationIgnored private var cache: (key: String, entries: [SearchEntry], items: [String: SearchItem])?

    private init() {
        recent = UserDefaults.standard.stringArray(forKey: Self.recentKey) ?? []
        #if DEBUG
        if let typed = ProcessInfo.processInfo.environment["LONGBOOK_SNAPSHOT_SEARCH"] {
            query = typed
            showsPanel = !typed.isEmpty
        }
        #endif
    }

    func askFocus() {
        focusAsks += 1
        if !query.isEmpty { showsPanel = true }
    }

    func close() {
        showsPanel = false
    }

    func hand(_ words: String, to screen: String) {
        handed = HandedWords(screen: screen, query: words)
    }

    /// The words handed to `screen`, taken once.
    func take(for screen: String) -> String? {
        guard let handed, handed.screen == screen else { return nil }
        self.handed = nil
        return handed.query
    }

    func remember(_ words: String) {
        recent = GlobalSearch.remembering(words, in: recent)
        #if DEBUG
        if ProcessInfo.processInfo.environment["LONGBOOK_SNAPSHOT"] != nil { return }
        #endif
        UserDefaults.standard.set(recent, forKey: Self.recentKey)
    }

    /// The results for what is typed: each kind's groups, the rows top to bottom, and what each draws.
    func results(_ model: DashboardModel) -> (groups: [SearchGroup], rows: [SearchRow], items: [String: SearchItem]) {
        let index = index(model)
        let groups = GlobalSearch.search(query, in: index.entries)
        return (groups, GlobalSearch.rows(groups), index.items)
    }

    /// Read once per version of the file and per day, then searched as each letter is typed.
    private func index(_ model: DashboardModel) -> (entries: [SearchEntry], items: [String: SearchItem]) {
        let key = "\(ObjectIdentifier(model).hashValue)|\(model.loadedHash ?? "-")|\(model.reviewKey)|\(LB.toISO(LB.todayMid()))"
        if let cache, cache.key == key { return (cache.entries, cache.items) }
        let built = SearchIndex.items(model)
        let items = Dictionary(built.map { ($0.entry.key, $0) }, uniquingKeysWith: { first, _ in first })
        cache = (key, built.map(\.entry), items)
        return (built.map(\.entry), items)
    }
}

/// Everything a search can find, read from the model: the six kinds, the Proposals waiting
/// and the help articles the app ships.
@MainActor
enum SearchIndex {
    static func items(_ model: DashboardModel) -> [SearchItem] {
        var items: [SearchItem] = []
        for card in model.entityCards(.paymentMethod) where card.isReal {
            items.append(entity(card))
        }
        if case .loaded(let data) = model.state {
            for item in data.commitments {
                items.append(SearchItem(
                    entry: SearchEntry(kind: .commitments, id: item.id, name: item.name,
                                       words: [item.searchText, item.amountText, item.amountExact, item.dueWord]),
                    facts: facts([item.cycleWord], item.sides, income: item.isIncome, transfer: item.isTransfer),
                    amount: item.amountText, target: .card(.commitment(id: item.id)), source: .commitment(item)
                ))
            }
        }
        // Landed rows, newest first, as their screens list them.
        for charge in model.chargeItems().reversed() where charge.isPast {
            let kind: SearchKind = charge.isIncome ? .earnings : (charge.isTransfer ? .transfers : .charges)
            items.append(SearchItem(
                entry: SearchEntry(kind: kind, id: charge.id, name: charge.name, words: [charge.searchText, charge.dateWord]),
                facts: facts([charge.dateWord], charge.sides, income: charge.isIncome, transfer: charge.isTransfer),
                amount: charge.amountText, target: .card(charge.ref), source: .charge(charge)
            ))
        }
        for card in model.entityCards(.familyMember) where card.isReal {
            items.append(entity(card))
        }
        if model.outsideChangeFrom != nil {
            items += proposals(model.reviewDiff())
        }
        for article in HelpArticle.all {
            items.append(SearchItem(
                entry: SearchEntry(kind: .help, id: article.slug, name: article.title, words: [article.body]),
                facts: "Help article", amount: nil, target: .help(slug: article.slug), source: .plain(symbol: "questionmark.circle")
            ))
        }
        return items
    }

    /// The day or the cycle, then From and To as the card says them, leaving out an account not known.
    private static func facts(_ first: [String], _ sides: MoneySides, income: Bool, transfer: Bool) -> String {
        let links = KindCards.links(sides, income: income, transfer: transfer).map(\.text).filter { !$0.hasSuffix(" None") }
        return (first + links).joined(separator: " · ")
    }

    /// An account says its type and owner; a person their relationship and accounts.
    private static func entity(_ card: DashboardModel.EntityCard) -> SearchItem {
        let tag = card.tag.flatMap { $0.isEmpty ? nil : EntityCopy.tagWord($0) }
        let isAccount = card.kind == .paymentMethod
        let facts = isAccount
            ? [tag, card.owner?.name].compactMap { $0 }
            : [tag, KindCards.counted(card.accountCount, "Account", none: "No accounts")].compactMap { $0 }
        let amount = isAccount
            ? card.balance.map { fmtMoney($0, card.balanceCurrency) }
            : (card.sent.isEmpty ? nil : fmtMoneyTotals(card.sent))
        return SearchItem(
            entry: SearchEntry(kind: isAccount ? .accounts : .people, id: card.id, name: EntityCopy.name(card),
                               words: [card.name, card.tag, tag, card.owner?.name, card.linked?.name, amount]),
            facts: facts.joined(separator: " · "), amount: amount, target: .card(card.ref), source: .entity(card)
        )
    }

    /// Each row the outside edit added, changed or removed, named by what it did.
    private static func proposals(_ diff: [EntityDiff]) -> [SearchItem] {
        func noun(_ kind: String) -> String {
            switch kind {
            case "commitments": "Commitment"
            case "charges": "Charge"
            case "accounts": "Account"
            case "members": "Person"
            case "tags": "Category"
            default: "Row"
            }
        }
        func item(_ kind: String, _ verb: String, id: String, name: String, words: [String?], amount: String?) -> SearchItem {
            SearchItem(
                entry: SearchEntry(kind: .proposals, id: "\(kind)/\(verb)/\(id)", name: name, words: words + [verb, noun(kind)]),
                facts: "\(verb) · \(noun(kind))", amount: amount, target: .proposals, source: .plain(symbol: LBGlyph.change)
            )
        }
        func money(_ row: RowRef) -> String? {
            guard let amount = row.amount, let currency = row.currency else { return nil }
            return fmtMoney(amount, currency)
        }
        return diff.flatMap { section in
            section.added.map { item(section.kind, "Added", id: $0.id, name: $0.name, words: [$0.note, $0.tag, $0.cycle, money($0)], amount: money($0)) }
                + section.changed.map { item(section.kind, "Changed", id: $0.id, name: $0.name, words: $0.fields.map(\.after), amount: nil) }
                + section.removed.map { item(section.kind, "Removed", id: $0.id, name: $0.name, words: [$0.note, $0.tag, $0.cycle, money($0)], amount: money($0)) }
        }
    }

    /// The screen a kind's Show all opens, and the name its list takes the words under.
    static func screen(for kind: SearchKind) -> (destination: Destination, name: String?) {
        switch kind {
        case .accounts: (.accounts, "accounts")
        case .commitments: (.commitments(ListFilter()), "commitments")
        case .charges: (.commitments(ListFilter(scope: .past, kind: .charges)), "charges")
        case .earnings: (.commitments(ListFilter(scope: .past, kind: .earnings)), "earnings")
        case .transfers: (.commitments(ListFilter(scope: .past, kind: .transfers)), "transfers")
        case .people: (.members, "members")
        case .proposals: (.changes, nil)
        case .help: (.helpAbout, nil)
        }
    }
}

/// A result's own card where its kind has one; Proposals and articles wear the card's shape
/// with their glyph.
@MainActor
func searchCard(_ item: SearchItem, model: DashboardModel, selected: Bool = false) -> LBKindCard {
    switch item.source {
    case .commitment(let commitment):
        KindCards.card(commitment, photo: model.commitmentPhotoURL(id: commitment.id), selected: selected)
    case .charge(let charge):
        KindCards.card(charge, photo: model.commitmentPhotoURL(id: charge.subId), selected: selected)
    case .entity(let card):
        KindCards.card(card, selected: selected)
    case .plain(let symbol):
        LBKindCard(kind: nil, symbol: symbol, title: item.entry.name, amount: item.amount,
                   details: [LBMetaFact(symbol: symbol, text: item.facts)], lead: 1, selected: selected)
    }
}

#if os(macOS)
/// The Mac's search field at the top of the sidebar: the magnifier, the words and the ⌘K hint.
/// ⌘K focuses it from anywhere; typing opens the results under it.
struct SidebarSearchField: View {
    @State private var center = SearchCenter.shared
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: LBSpacing.s2) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(LBColor.textTertiary.color)
                .accessibilityHidden(true)
            TextField("", text: $center.query, prompt: Text("Search").foregroundStyle(LBColor.textTertiary.color))
                .textFieldStyle(.plain)
                .lbText(.bodySM)
                .foregroundStyle(LBColor.textPrimary.color)
                .autocorrectionDisabled()
                .focused($focused)
                .accessibilityLabel("Search longbook")
            Text(KeyShortcut.search.symbols)
                .lbText(.footnote)
                .foregroundStyle(LBColor.textTertiary.color)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, LBSpacing.s2)
        .frame(height: 28)
        .background(LBColor.card.color, in: RoundedRectangle(cornerRadius: LBRadius.xs, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: LBRadius.xs, style: .continuous)
                .strokeBorder(focused ? LBColor.brand.color : LBColor.hairline.color, lineWidth: 1)
        )
        .anchorPreference(key: SearchFieldAnchor.self, value: .bounds) { $0 }
        .onChange(of: center.query) { _, typed in center.showsPanel = !typed.isEmpty }
        .onChange(of: focused) { _, now in if now, !center.query.isEmpty { center.showsPanel = true } }
        // The window may not be key yet when ⌘K asks from another one.
        .onChange(of: center.focusAsks) { _, _ in DispatchQueue.main.async { focused = true } }
        .onChange(of: center.showsPanel) { _, shown in if !shown, center.query.isEmpty { focused = false } }
        #if DEBUG
        .onAppear { if ProcessInfo.processInfo.environment["LONGBOOK_SNAPSHOT_SEARCH"] != nil { focused = true } }
        #endif
    }
}

/// Where the sidebar's field stands, so the results drop from it over the content.
struct SearchFieldAnchor: PreferenceKey {
    static let defaultValue: Anchor<CGRect>? = nil
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = value ?? nextValue()
    }
}

/// The results under the sidebar's field: grouped by kind in the sidebar's order, at most five
/// a kind with a Show all, the first highlighted. ↑ and ↓ move, Return opens, Escape closes.
struct SearchResultsPanel: View {
    let model: DashboardModel
    let open: (SearchRow, [String: SearchItem]) -> Void
    @State private var center = SearchCenter.shared

    static let width: CGFloat = 560

    var body: some View {
        let results = center.results(model)
        let highlighted = min(center.highlighted, max(results.rows.count - 1, 0))
        VStack(spacing: 0) {
            if results.groups.isEmpty {
                Text("Nothing matches “\(center.query.trimmingCharacters(in: .whitespaces))”.")
                    .lbText(.body)
                    .foregroundStyle(LBColor.textSecondary.color)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(LBSpacing.s4)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(results.groups, id: \.kind) { group in
                                LBSectionHeader(group.kind.title)
                                    .padding(.horizontal, LBSpacing.s3)
                                    .padding(.top, LBSpacing.s3)
                                    .padding(.bottom, LBSpacing.s1)
                                ForEach(group.hits, id: \.key) { entry in
                                    let index = results.rows.firstIndex(of: .hit(entry)) ?? 0
                                    if let item = results.items[entry.key] {
                                        hitRow(item, lit: index == highlighted) { open(.hit(entry), results.items) }
                                            .id(index)
                                            .onHover { if $0 { center.highlighted = index } }
                                    }
                                }
                                if let words = group.showAllWords {
                                    let row = SearchRow.showAll(group.kind, total: group.total)
                                    let index = results.rows.firstIndex(of: row) ?? 0
                                    showAllRow(words, lit: index == highlighted) { open(row, results.items) }
                                        .id(index)
                                        .onHover { if $0 { center.highlighted = index } }
                                }
                            }
                        }
                        .padding(.horizontal, LBSpacing.s2)
                        .padding(.bottom, LBSpacing.s2)
                    }
                    .frame(maxHeight: 460)
                    .fixedSize(horizontal: false, vertical: true)
                    .onChange(of: center.highlighted) { _, index in proxy.scrollTo(index) }
                }
            }
            Rectangle().fill(LBColor.hairline.color).frame(height: 1)
            Text("↑ ↓ to move · Return opens it on its own screen · ⌘K from anywhere")
                .lbText(.footnote)
                .foregroundStyle(LBColor.textTertiary.color)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, LBSpacing.s4)
                .padding(.vertical, LBSpacing.s2)
        }
        .frame(width: Self.width)
        .background(LBColor.chrome.color, in: RoundedRectangle(cornerRadius: LBRadius.md, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: LBRadius.md, style: .continuous).strokeBorder(LBColor.hairline.color, lineWidth: 1))
        .shadow(color: .black.opacity(0.28), radius: 18, y: 8)
        .background {
            SearchKeys(
                move: { step in center.highlighted = GlobalSearch.moved(highlighted, by: step, count: results.rows.count) },
                activate: { if results.rows.indices.contains(highlighted) { open(results.rows[highlighted], results.items) } },
                close: { center.close() }
            )
        }
    }

    private func hitRow(_ item: SearchItem, lit: Bool, action: @escaping () -> Void) -> some View {
        Button {
            Measure.used("search_result")
            action()
        } label: {
            HStack(spacing: LBSpacing.s3) {
                RoundedRectangle(cornerRadius: LBRadius.xs, style: .continuous)
                    .fill(item.tile.ink.opacity(0.18))
                    .frame(width: 30, height: 30)
                    .overlay(
                        Image(systemName: item.tile.symbol)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(item.tile.ink)
                    )
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.entry.name)
                        .lbText(.headline)
                        .foregroundStyle(LBColor.textPrimary.color)
                        .lineLimit(1)
                    if !item.facts.isEmpty {
                        Text(item.facts)
                            .lbText(.footnote)
                            .foregroundStyle(LBColor.textTertiary.color)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: LBSpacing.s2)
                if let amount = item.amount {
                    Text(amount)
                        .lbText(.bodySM)
                        .monospacedDigit()
                        .foregroundStyle(LBColor.textSecondary.color)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, LBSpacing.s2)
            .frame(height: 44)
            .lbSelectionFill(lit, in: RoundedRectangle(cornerRadius: LBRadius.xs, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(lit ? [.isButton, .isSelected] : .isButton)
    }

    private func showAllRow(_ words: String, lit: Bool, action: @escaping () -> Void) -> some View {
        Button {
            Measure.used("search_show_all")
            action()
        } label: {
            HStack(spacing: LBSpacing.s2) {
                Text(words)
                    .lbText(.bodySM)
                    .foregroundStyle(LBColor.brandText.color)
                Spacer(minLength: 0)
                Image(systemName: "arrow.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(LBColor.textTertiary.color)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, LBSpacing.s2)
            .frame(height: 32)
            .lbSelectionFill(lit, in: RoundedRectangle(cornerRadius: LBRadius.xs, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// ↑, ↓, Return and Escape while the results show, heard before the field or the window's
/// own shortcuts take them.
private struct SearchKeys: NSViewRepresentable {
    let move: (Int) -> Void
    let activate: () -> Void
    let close: () -> Void

    func makeNSView(context: Context) -> Catcher { Catcher() }

    func updateNSView(_ view: Catcher, context: Context) {
        view.move = move
        view.activate = activate
        view.close = close
    }

    static func dismantleNSView(_ view: Catcher, coordinator: ()) { view.stop() }

    final class Catcher: NSView {
        var move: (Int) -> Void = { _ in }
        var activate: () -> Void = {}
        var close: () -> Void = {}
        private var monitor: Any?

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stop()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, let window = self.window, event.window === window, window.attachedSheet == nil else { return event }
                switch event.keyCode {
                case 125: self.move(1)
                case 126: self.move(-1)
                case 36, 76: self.activate()
                case 53: self.close()
                default: return event
                }
                return nil
            }
        }

        func stop() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }
    }
}
#endif
