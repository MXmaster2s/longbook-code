import DesignSystem
import LongbookCore
import SwiftUI

/// The ledger in four screens. Commitments looks ahead: each commitment once at its next
/// charge, then those with no date. Charges, Earnings and Transfers look behind, newest
/// first. A list on the phone, cards with an inspector on the Mac.
struct CommitmentsView: View {
    /// What the form sheet is editing — its own type so add and edit share one sheet.
    private enum FormTarget: Identifiable {
        case add
        case edit(String)
        /// A commitment named at setup, getting its details.
        case fill(CommitmentPlaceholder)
        var id: String {
            switch self {
            case .add: return "add"
            case .edit(let id): return id
            case .fill(let placeholder): return "fill:" + placeholder.id
            }
        }
    }

    /// A commitment by id and name, so a sheet or an alert can be driven by it.
    private struct CommitmentRef: Identifiable {
        let id: String
        let name: String
    }

    /// The two fields Bulk Edit sets by picking a value.
    private enum BulkField: String, Identifiable {
        case category, person
        var id: String { rawValue }
    }

    /// One narrowing the Filter control offers: its name, glyph, choice and options.
    private struct FilterSpec: Identifiable {
        let title: String
        let symbol: String
        let selection: Binding<String?>
        let options: [(String, String)]
        var id: String { title }
        var chosen: String? { selection.wrappedValue.flatMap { value in options.first { $0.0 == value }?.1 } }
    }

    let model: DashboardModel
    /// Which of the landed rows this screen lists: money out, money in, or transfers. Nil
    /// lists them all, as a day or a month door does.
    private let kind: ListFilter.Kind?

    @State private var search = ""
    @State private var pickedCategory: String?
    @State private var day: String?
    /// Narrowed to the months a dashboard panel was showing, each held as any day inside
    /// it. Empty when no month narrows the list.
    @State private var months: [String]
    /// The Date window, a first day and a last; either end may be open. Set, it replaces a
    /// door's day or months.
    @State private var from: Date?
    @State private var to: Date?
    @State private var pickingRange = false
    /// The Date sheet opened from inside the phone's Filter sheet, which holds it.
    @State private var pickingRangeInFilters = false
    @State private var showingFilters = false
    @State private var when: ListScope = .upcoming
    @State private var formTarget: FormTarget?
    @State private var onlyBookmarked = false
    /// Narrowed to one account or person — the door the entity rows open.
    @State private var methodId: String?
    @State private var memberId: String?
    /// Narrowed to one commitment's rows — the door a Preview's See All opens.
    @State private var commitmentId: String?
    /// The filter's own narrowings, each held as the vault's raw value.
    @State private var pickedCycle: String?
    @State private var pickedStatus: String?
    @State private var pickedCurrency: String?
    /// The commitment whose delete is awaiting confirmation — the whole plan, every row.
    @State private var deletingItem: CommitmentRef?
    @State private var deletingCharge: DashboardModel.ChargeItem?
    #if os(iOS)
    /// The phone's swipe Edit opens one charge's own form; the Mac edits through the commitment.
    @State private var editingCharge: Charge?
    #endif
    /// The to-fill-in name whose Remove is awaiting confirmation.
    @State private var removingPlaceholder: CommitmentPlaceholder?
    /// The Mac list's chosen cards.
    @State private var selection: Set<String> = []
    #if os(macOS)
    /// The card whose Edit form stands in the panel, in its Preview's place, and how many
    /// times that form has been asked to close.
    @State private var formCard: CardRef?
    @State private var formCloseAsked = 0
    /// The field a Preview's row opened the form on; nil for the whole form.
    @State private var formFocus: EditFocus?
    /// The row the screen just landed on, for the list to bring into view.
    @State private var landing: String?
    #endif
    /// A card opened from inside the inspector, read there in place of the chosen one.
    @State private var inspected: CardRef?
    /// The last card clicked and when, for telling a second click from a first.
    @State private var lastClick: (id: String, at: Date) = ("", .distantPast)
    /// Select, and what it asks before a bulk change writes.
    @State private var picking = ListSelection()
    @State private var prompt = BulkPrompt()
    /// The field a bulk change is picking a value for, and the question that pick then asks.
    @State private var bulkField: BulkField?
    @State private var afterPick: BulkAsk?

    /// The filter's word for rows that wear no category, as the panels and reports say it.
    static let noCategory = "No category"

    private static let cycleOptions: [(String, String)] = [
        ("monthly", "Monthly"), ("yearly", "Yearly"), ("custom", "Custom"), ("once", "One-time"),
    ]
    private static let statusOptions: [(String, String)] = [
        ("active", "Active"), ("paused", "Paused"), ("cancelled", "Cancelled"),
    ]

    /// The dashed needs-details cards side by side, scrolling sideways, each its own Edit
    /// and Remove: the same rail the dashboard shows.
    private func placeholderRail(_ toFill: [CommitmentPlaceholder]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: LBSpacing.s2) {
                ForEach(toFill) { placeholder in
                    PlaceholderCard(placeholder, onEdit: { formTarget = .fill(placeholder) },
                                    onRemove: { removingPlaceholder = placeholder })
                }
            }
        }
    }

    /// The commitment the Mac's inspector opens on, when a door named one.
    private let focus: String?
    /// The charge the Mac's inspector opens on, when a door named one.
    private let focusCharge: String?
    #if os(macOS)
    /// The name this list's memory of its last row goes under, when it has one.
    private let memoryKey: String?
    #endif

    init(model: DashboardModel, filter: ListFilter, focus: String? = nil, focusCharge: String? = nil) {
        self.model = model
        self.focus = focus
        self.focusCharge = focusCharge
        #if os(macOS)
        self.memoryKey = filter.memoryKey
        #endif
        self.kind = filter.kind
        _day = State(initialValue: filter.day)
        _months = State(initialValue: filter.months)
        _from = State(initialValue: LB.parseDate(filter.from))
        _to = State(initialValue: LB.parseDate(filter.to))
        _methodId = State(initialValue: filter.methodId)
        _memberId = State(initialValue: filter.memberId)
        _commitmentId = State(initialValue: filter.commitmentId)
        _pickedCategory = State(initialValue: filter.category)
        _onlyBookmarked = State(initialValue: filter.bookmarked)
        // A door may name its side; otherwise the window decides, so this month and today
        // open on what is still coming, and a day or month gone on what landed.
        var opens: ListScope = switch filter.scope {
        case .past: .past
        case .upcoming: .upcoming
        case nil: filter.kind != nil ? .past : listScope(day: filter.day, months: filter.months, from: filter.from, to: filter.to)
        }
        // A named commitment with nothing ahead — a paid one-time, a stopped one — is only
        // on the Past side, so that is where the door opens.
        if let focus, filter.scope == nil {
            let items = model.chargeItems().filter { $0.subId == focus }
            if !items.isEmpty, items.allSatisfy(\.isPast) { opens = .past }
        }
        // A door naming a month or an account whose rows all landed already — this month's
        // "No account", say — opens on them rather than on an empty Upcoming.
        if filter.scope == nil, focus == nil, opens == .upcoming, !filter.months.isEmpty || filter.methodId != nil {
            let keys = Set(filter.months.map { $0.prefix(7) })
            let items = model.chargeItems().filter { charge in
                guard keys.isEmpty || keys.contains(charge.dateISO.prefix(7)) else { return false }
                guard let wanted = filter.methodId else { return true }
                return wanted == DashboardModel.unassignedMethodId ? charge.methodId == nil : charge.methodId == wanted
            }
            if !items.isEmpty, items.allSatisfy(\.isPast) { opens = .past }
        }
        _when = State(initialValue: opens)
    }

    /// The months' words, the dashboard's own: "September 2026", "Jul – Sep 2026",
    /// "5 chosen months".
    private var monthsWords: String? {
        let anchor = LB.firstOfMonth(LB.todayMid())
        return MonthSelection(days: months.compactMap(LB.parseDate), anchor: anchor)?.label(anchor: anchor)
    }

    private var fromISO: String? { from.map(LB.toISO) }
    private var toISO: String? { to.map(LB.toISO) }
    private var hasRange: Bool { from != nil || to != nil }

    /// The Date window's words, nil while it narrows nothing.
    private var rangeWords: String? { dayRangeLabel(from: from, to: to) }

    /// The category a filter word asks for: the word itself, or no category at all.
    private func matchesCategory(_ category: String?) -> Bool {
        guard let pickedCategory else { return true }
        return category == (pickedCategory == Self.noCategory ? nil : pickedCategory)
    }

    var body: some View {
        content
            .screenTutorial(.commitments)
            // A window set by hand replaces the one a door passed; its pills step aside.
            .onChange(of: from) { _, from in if from != nil { day = nil; months = [] } }
            .onChange(of: to) { _, to in if to != nil { day = nil; months = [] } }
            .onChange(of: when) { _, _ in selection = []; picking.finish() }
            .onChange(of: selection) { _, _ in inspected = nil }
            .onChange(of: selectableIds) { _, shown in
                // While the file reloads the list shows nothing; that narrows nothing.
                if case .loaded = model.state { picking.keep(shown) }
            }
            .onDisappear { picking.finish() }
            // Show all in a search lands here with its words typed in this list's field.
            .onAppear(perform: takeHandedSearch)
            .onChange(of: SearchCenter.shared.handed) { _, _ in takeHandedSearch() }
            .measured("commitments_bulk_field", .sheet, when: bulkField != nil)
            .sheet(item: $bulkField, onDismiss: {
                if let afterPick { prompt.start(afterPick) }
                afterPick = nil
            }) { field in
                bulkPicker(field)
                    .lbKeyboardFocusEffects()
            }
            .measured("commitments_picking_range", .sheet, when: pickingRange)
            .sheet(isPresented: $pickingRange, onDismiss: settleSide) {
                DateRangePickerView(from: $from, to: $to) { pickingRange = false }
                    .lbKeyboardFocusEffects()
            }
            .onAppear {
                #if DEBUG
                // The snapshot harness can open the Date sheet or the Filter sheet over the list.
                switch ProcessInfo.processInfo.environment["LONGBOOK_SNAPSHOT_SHEET"] {
                case "daterange": pickingRange = true
                case "filters": showingFilters = true
                default: break
                }
                #endif
            }
            .measured("commitments_form_target", .sheet, when: formTarget != nil)
            .sheet(item: $formTarget) { target in
                switch target {
                case .add:
                    RenewalFormView(model: model, editingId: nil, seedDirection: addDirection) { formTarget = nil }
                        .lbKeyboardFocusEffects()
                case .edit(let id):
                    RenewalFormView(model: model, editingId: id) { formTarget = nil }
                        .lbThreeQuarterSheet()
                        .lbKeyboardFocusEffects()
                case .fill(let placeholder):
                    RenewalFormView(model: model, editingId: nil, seedCategory: placeholder.tag, seedName: placeholder.name) {
                        // Saved under its name, the placeholder has become the real thing.
                        if model.hasCommitment(named: placeholder.name) { model.removePlaceholder(placeholder.id) }
                        formTarget = nil
                    }
                    .lbKeyboardFocusEffects()
                }
            }
            #if os(iOS)
            .measured("commitments_editing_charge", .sheet, when: editingCharge != nil)
            .sheet(item: $editingCharge) { charge in
                RenewalFormView(model: model, editingId: charge.sub.id, chargeISO: charge.row.date) { editingCharge = nil }
                    .lbThreeQuarterSheet()
                    .lbKeyboardFocusEffects()
            }
            #endif
            .measured("commitments_deleting_item", .alert, when: deletingItem != nil)
            .alert("Delete \(deletingItem?.name ?? "this commitment")?",
                   isPresented: Binding(get: { deletingItem != nil }, set: { if !$0 { deletingItem = nil } }),
                   presenting: deletingItem) { item in
                Button("Delete", role: .destructive) {
                    Measure.used("delete")
                    model.deleteCommitment(id: item.id)
                    selection = []
                }
                Button("Cancel", role: .cancel) { Measure.used("cancel") }
            } message: { _ in
                Text("Its charges are removed with it. The version before stays in Proposals.")
            }
            .measured("commitments_deleting_charge", .alert, when: deletingCharge != nil)
            .alert("Delete this charge?",
                   isPresented: Binding(get: { deletingCharge != nil }, set: { if !$0 { deletingCharge = nil } }),
                   presenting: deletingCharge) { charge in
                // A planned charge of a recurring commitment can take the plan after it too.
                if model.offersLaterRemoval(subscriptionId: charge.subId, dateISO: charge.dateISO) {
                    Button("Only This Charge", role: .destructive) {
                        Measure.used("only_this_charge")
                        _ = model.removeCharge(subscriptionId: charge.subId, dateISO: charge.dateISO)
                        selection = []
                    }
                    Button("This and Every One After", role: .destructive) {
                        Measure.used("this_and_every_one_after")
                        _ = model.removeChargeAndLater(subscriptionId: charge.subId, dateISO: charge.dateISO)
                        selection = []
                    }
                } else {
                    Button("Delete", role: .destructive) {
                        Measure.used("delete")
                        _ = model.removeCharge(subscriptionId: charge.subId, dateISO: charge.dateISO)
                        selection = []
                    }
                }
                Button("Cancel", role: .cancel) { Measure.used("cancel") }
            } message: { charge in
                Text(model.offersLaterRemoval(subscriptionId: charge.subId, dateISO: charge.dateISO)
                     ? "\(charge.name), \(charge.amountText). \(model.laterRemovalWords(subscriptionId: charge.subId, dateISO: charge.dateISO))"
                     : "\(charge.name), \(charge.amountText). Only this charge is removed.")
            }
            .measured("commitments_removing_placeholder", .alert, when: removingPlaceholder != nil)
            .alert("Remove \(removingPlaceholder?.name ?? "this commitment")?",
                   isPresented: Binding(get: { removingPlaceholder != nil }, set: { if !$0 { removingPlaceholder = nil } }),
                   presenting: removingPlaceholder) { placeholder in
                Button("Remove", role: .destructive) {
                    Measure.used("remove")
                    model.removePlaceholder(placeholder.id)
                    selection = []
                }
                Button("Cancel", role: .cancel) { Measure.used("cancel") }
            } message: { _ in
                Text("Only the name is removed. Nothing has been written for it yet.")
            }
    }

    /// The name a search hands its words to this list under: the screen its kind names.
    private var searchScreen: String {
        switch kind {
        case .charges: "charges"
        case .earnings: "earnings"
        case .transfers: "transfers"
        case nil: "commitments"
        }
    }

    private func takeHandedSearch() {
        if let words = SearchCenter.shared.take(for: searchScreen) { search = words }
    }

    @ViewBuilder
    private var content: some View {
        #if os(macOS)
        macBody
        #else
        phoneBody
        #endif
    }

    // MARK: narrowing

    /// The rows one side holds under the current narrowing: a day, months, the Date window,
    /// the filters, a bookmark, the search. Ahead reads soonest first; behind, newest first.
    private func rows(in scope: ListScope) -> [DashboardModel.ChargeItem] {
        // Each month as its "YYYY-MM" prefix, the part of a day that names it.
        let monthKeys = Set(months.map { $0.prefix(7) })
        let needle = search.lowercased()
        let rows = model.chargeItems().filter { charge in
            if charge.isPast != (scope == .past) { return false }
            if scope == .past, !matchesKind(charge) { return false }
            if let day, charge.dateISO != day { return false }
            if !monthKeys.isEmpty, !monthKeys.contains(charge.dateISO.prefix(7)) { return false }
            if hasRange, !inDayRange(charge.dateISO, from: fromISO, to: toISO) { return false }
            if !matchesCategory(charge.category) { return false }
            if !matchesMethod(charge) { return false }
            if !matchesMember(charge.memberId, sides: charge.sides) { return false }
            if let commitmentId, charge.subId != commitmentId { return false }
            if let pickedCycle, charge.cycle.rawValue != pickedCycle { return false }
            if let pickedStatus, charge.status.rawValue != pickedStatus { return false }
            if let pickedCurrency, charge.currency != pickedCurrency { return false }
            if onlyBookmarked, !model.bookmarks.contains(charge.subId) { return false }
            return needle.isEmpty || charge.searchText.contains(needle)
        }
        return scope == .past ? Array(rows.reversed()) : rows
    }

    /// Money out, money in or a transfer, as the screen lists; every kind when none is named.
    private func matchesKind(_ charge: DashboardModel.ChargeItem) -> Bool {
        switch kind {
        case .charges: !charge.isIncome && !charge.isTransfer
        case .earnings: charge.isIncome
        case .transfers: charge.isTransfer
        case nil: true
        }
    }

    private func visibleRows() -> [DashboardModel.ChargeItem] {
        rows(in: when)
    }

    /// Ahead with no day, months or Date window, the list is each commitment once rather
    /// than every charge its plan has written.
    private func listsCommitments(_ scope: ListScope) -> Bool {
        scope == .upcoming && day == nil && months.isEmpty && !hasRange
    }

    /// The commitments with a next charge, soonest first, or those with none, narrowed as the
    /// rows are — by what each is.
    private func visibleCommitments(_ data: DashboardData, scheduled: Bool) -> [DashboardData.CommitmentItem] {
        let needle = search.lowercased()
        return data.commitments.filter { item in
            guard (item.monthLabel != nil) == scheduled else { return false }
            if !matchesCategory(item.category) { return false }
            if !matchesMethod(item.methodId) { return false }
            if !matchesMember(item.memberId, sides: item.sides) { return false }
            if let commitmentId, item.id != commitmentId { return false }
            if let pickedCycle, item.cycle.rawValue != pickedCycle { return false }
            if let pickedStatus, item.status.rawValue != pickedStatus { return false }
            if let pickedCurrency, item.currency != pickedCurrency { return false }
            if onlyBookmarked, !model.bookmarks.contains(item.id) { return false }
            return needle.isEmpty || item.searchText.contains(needle)
        }
    }

    /// Named at setup, not yet filled in: shown only when no filter narrows the list,
    /// because a placeholder has no account, cycle or amount to be narrowed by.
    private func visiblePlaceholders() -> [CommitmentPlaceholder] {
        guard !anyFilter, day == nil, months.isEmpty, !hasRange else { return [] }
        // The section's own name finds them too: "needs details" lists every one.
        let needle = search.lowercased()
        return model.placeholders.filter {
            needle.isEmpty || $0.name.lowercased().contains(needle) || "needs details".contains(needle)
        }
    }

    /// The unassigned bucket is an id no account carries, so it asks for the absence
    /// rather than for a match — otherwise its door lands on an empty list.
    private func matchesMethod(_ id: String?) -> Bool {
        guard let methodId else { return true }
        if methodId == DashboardModel.unassignedMethodId { return id == nil }
        return id == methodId
    }

    /// A transfer stands on the account it moved money to as well as the one it left.
    private func matchesMethod(_ charge: DashboardModel.ChargeItem) -> Bool {
        matchesMethod(charge.methodId) || (charge.isTransfer && methodId != nil && charge.sides.to.accountId == methodId)
    }

    /// A person is on every row where they are From or To Person, on either side. The bucket
    /// naming nobody asks what the row writes down.
    private func matchesMember(_ id: String?, sides: MoneySides) -> Bool {
        guard let memberId else { return true }
        if memberId == DashboardModel.unassignedMemberId { return id == nil }
        return sides.personIds.contains(memberId)
    }

    /// The parts of the list as the narrowing leaves them, both platforms' one source: the
    /// charges, or ahead each commitment once; then what has no date, and what needs details.
    private func parts(_ data: DashboardData) -> (
        rows: [DashboardModel.ChargeItem], upcoming: [DashboardData.CommitmentItem],
        unscheduled: [DashboardData.CommitmentItem], toFill: [CommitmentPlaceholder]
    ) {
        let commitments = listsCommitments(when)
        let rows = commitments ? [] : visibleRows()
        let upcoming = commitments ? visibleCommitments(data, scheduled: true) : []
        // Under a day, months or a Date window the unscheduled have nothing to be inside of.
        let unscheduled = commitments ? visibleCommitments(data, scheduled: false) : []
        let toFill = when == .upcoming ? visiblePlaceholders() : []
        return (rows, upcoming, unscheduled, toFill)
    }

    // MARK: filters

    private func filterSpecs(_ data: DashboardData) -> [FilterSpec] {
        let currencies = Array(Set(data.commitments.map(\.currency))).sorted()
        var specs = [
            FilterSpec(title: "Category", symbol: LBGlyph.category, selection: $pickedCategory,
                       options: data.commitmentCategories.map { ($0, categoryWord($0)) } + [(Self.noCategory, Self.noCategory)]),
            FilterSpec(title: "Account", symbol: LBGlyph.account, selection: $methodId,
                       options: model.editChoices.methods.map { ($0.id, $0.name) }
                           + [(DashboardModel.unassignedMethodId, "No account")]),
            FilterSpec(title: "Person", symbol: LBGlyph.member, selection: $memberId,
                       options: model.editChoices.members.map { ($0.id, $0.name) }
                           + [(DashboardModel.unassignedMemberId, "No person")]),
            FilterSpec(title: "Type", symbol: LBGlyph.cycle, selection: $pickedCycle, options: Self.cycleOptions),
            FilterSpec(title: "Status", symbol: LBGlyph.status, selection: $pickedStatus, options: Self.statusOptions),
        ]
        if currencies.count > 1 {
            specs.append(FilterSpec(title: "Currency", symbol: LBGlyph.currency, selection: $pickedCurrency,
                                    options: currencies.map { ($0, $0) }))
        }
        return specs
    }

    /// What the filters narrow to, in their own words — a short list must always say why.
    private func filterWords(_ data: DashboardData) -> [String] {
        var words = filterSpecs(data).compactMap(\.chosen)
        if let name = commitmentId.flatMap({ model.subscription(id: $0)?.name }) { words.insert(name, at: 0) }
        if let rangeWords { words.insert(rangeWords, at: 0) }
        if onlyBookmarked { words.append("Bookmarked") }
        return words
    }

    private var anyFilter: Bool {
        pickedCategory != nil || methodId != nil || memberId != nil || commitmentId != nil || pickedCycle != nil
            || pickedStatus != nil || pickedCurrency != nil || onlyBookmarked || hasRange
    }

    private func clearFilters() {
        pickedCategory = nil
        methodId = nil
        memberId = nil
        commitmentId = nil
        pickedCycle = nil
        pickedStatus = nil
        pickedCurrency = nil
        onlyBookmarked = false
        from = nil
        to = nil
    }

    /// The Date sheet, prefilled from a door's window so the reader narrows from it rather
    /// than from blank: a day is both ends; months run first day to last.
    private func prefillRange() {
        guard !hasRange else { return }
        if let day, let date = LB.parseDate(day) {
            from = date
            to = date
        } else if let span = monthsSpan {
            from = span.first
            to = span.last
        }
    }

    private func openRange() {
        prefillRange()
        pickingRange = true
    }

    private var monthsSpan: (first: Date, last: Date)? {
        let anchor = LB.firstOfMonth(LB.todayMid())
        return MonthSelection(days: months.compactMap(LB.parseDate), anchor: anchor)?.span(anchor: anchor)
    }

    /// Done on the Date sheet: a window wholly on one side of today opens that side, as a
    /// door's would; one crossing today, or open towards it, keeps the side the reader is on.
    private func settleSide() {
        let today = LB.toISO(LB.todayMid())
        let behind = toISO.map { $0 < today } ?? false
        let ahead = fromISO.map { $0 > today } ?? false
        guard behind || ahead else { return }
        when = listScope(day: nil, months: [], from: fromISO, to: toISO)
    }

    /// The narrowings a door brought and the filters chosen here, each clearable, so a short
    /// list always says why it is short.
    @ViewBuilder
    private func narrowedLine(_ data: DashboardData) -> some View {
        let words = filterWords(data)
        if day != nil || monthsWords != nil || !words.isEmpty {
            LBFlow(spacing: LBSpacing.s2, lineSpacing: LBSpacing.s2) {
                if let day, let date = LB.parseDate(day) {
                    pill("On \(LB.shortDate(date))") { self.day = nil }
                }
                if let words = monthsWords {
                    pill(words) { months = [] }
                }
                if !words.isEmpty {
                    pill(words.joined(separator: " · ")) { clearFilters() }
                        .accessibilityLabel("Filtered by \(words.joined(separator: ", ")). Tap to clear.")
                }
            }
        }
    }

    /// Under the search on Earnings: what the list adds up to.
    @ViewBuilder
    private func earningsTotal(_ rows: [DashboardModel.ChargeItem]) -> some View {
        if when == .past, kind == .earnings, !rows.isEmpty {
            Text("Total money in · \(fmtMoneyTotals(totals(of: rows)))")
                .lbText(.footnote)
                .foregroundStyle(LBColor.textSecondary.color)
        }
    }

    /// The kind of card this list holds.
    private var listKind: LBCardKind {
        if when == .upcoming { return .commitment }
        return switch kind {
        case .earnings: .earning
        case .transfers: .transfer
        case .charges, nil: .charge
        }
    }

    /// One amount per currency, biggest first: never blended.
    private func totals(of rows: [DashboardModel.ChargeItem]) -> [CurrencyAmount] {
        var sums: [String: Double] = [:]
        for row in rows { sums[row.currency, default: 0] += row.amount }
        return sums.map { CurrencyAmount(currency: $0.key, amount: $0.value) }.sorted { $0.amount > $1.amount }
    }

    private func pill(_ words: String, clear: @escaping () -> Void) -> some View {
        Button(action: { Measure.used("clear_filter_chip"); clear() }) {
            HStack(spacing: LBSpacing.s1) {
                Text(words).lbText(.label).lineLimit(1)
                Image(systemName: "xmark").font(.system(size: 8, weight: .bold))
            }
            .foregroundStyle(LBColor.onBrand.color)
            .padding(.horizontal, LBSpacing.s3)
            .padding(.vertical, 6)
            .background(LBColor.brand.color, in: Capsule())
        }
        .lbButtonStyle()
        .accessibilityLabel("Filtered to \(words). Tap to clear.")
    }

    // MARK: words

    private var screenTitle: String {
        if when == .upcoming { return "Commitments" }
        return switch kind {
        case .earnings: "Earnings"
        case .transfers: "Transfers"
        case .charges, nil: "Charges"
        }
    }

    /// The one Add the list's first line holds, named for what the list lists.
    private var addTitle: String {
        switch listKind {
        case .earning: "Add Earning"
        case .transfer: "Add Transfer"
        case .charge: "Add Charge"
        default: "Add Commitment"
        }
    }

    /// A new row starts on the list's side of the money: in, a transfer, or out.
    private var addDirection: String? {
        switch listKind {
        case .earning: "in"
        case .transfer: "transfer"
        default: nil
        }
    }

    /// What the Filter narrows, for its tooltip.
    private var filterHelp: String {
        "Filter \(screenTitle.lowercased()) by date, category, account, person, type and status"
    }

    /// The landed rows' noun, for the sentences that count them.
    private var landedNoun: (one: String, many: String) {
        switch kind {
        case .earnings: ("earning", "earnings")
        case .transfers: ("transfer", "transfers")
        case .charges, nil: ("charge", "charges")
        }
    }

    /// A month heading as a sentence: "October 2026".
    private func monthHeading(_ label: String) -> String {
        label.prefix(1).uppercased() + label.dropFirst()
    }

    private var unscheduledHeading: String { "No upcoming date" }

    /// Why the list is empty, in the side's own words.
    private var emptyWords: String {
        if when == .past {
            let noun = landedNoun.many
            return hasRange ? "No \(noun) between these dates."
                : !search.isEmpty || anyFilter ? "No past \(noun) match. Clear the search or a filter."
                : day != nil ? "No \(noun) on this day."
                : months.count > 1 ? "No \(noun) in these months."
                : !months.isEmpty ? "No \(noun) in this month."
                : kind == .earnings ? "No money in yet. longbook lists each deposit here once it lands."
                : kind == .transfers ? "No transfers yet. Moves between your own accounts are listed here."
                : "Nothing has charged yet. longbook remembers each payment the day it lands. This fills in as your commitments come due."
        }
        if onlyBookmarked, model.bookmarks.isEmpty {
            return "Nothing is bookmarked yet. The bookmark on any commitment saves it here."
        }
        return hasRange ? "Nothing is due between these dates."
            : !search.isEmpty || anyFilter ? "Nothing matches. Clear the search or a filter."
            : day != nil ? "Nothing is due on this day."
            : months.count == 1 ? "Nothing is due in this month."
            : months.count > 1 ? "Nothing is due in these months."
            : "Nothing is coming up. Add a commitment, or plan more charges from one you have."
    }

    /// The other side holds rows under the same narrowing: the empty list points there.
    private var elsewhere: ListScope? {
        let other: ListScope = when == .past ? .upcoming : .past
        return rows(in: other).isEmpty ? nil : other
    }

    /// A search or a narrowing answers from both sides: when this side shows matches, the other
    /// side's count is offered too, so a charge already behind today is never missed.
    private func alsoMatching(_ data: DashboardData) -> (scope: ListScope, count: Int, commitments: Bool)? {
        guard !search.isEmpty || day != nil || !months.isEmpty || anyFilter else { return nil }
        let other: ListScope = when == .past ? .upcoming : .past
        let commitments = listsCommitments(other)
        let count = commitments ? visibleCommitments(data, scheduled: true).count : rows(in: other).count
        return count > 0 ? (other, count, commitments) : nil
    }

    private func alsoMatchingWords(_ also: (scope: ListScope, count: Int, commitments: Bool)) -> String {
        let noun = also.commitments ? (also.count == 1 ? "commitment" : "commitments")
            : (also.count == 1 ? landedNoun.one : landedNoun.many)
        return "\(also.count) \(also.scope == .past ? "past" : "upcoming") \(noun) also match"
    }

    // MARK: the card both platforms list

    private func chargeCard(_ charge: DashboardModel.ChargeItem, selected: Bool = false, marked: Bool = false) -> LBKindCard {
        KindCards.card(charge, photo: model.commitmentPhotoURL(id: charge.subId), selected: selected, marked: marked)
    }

    private func commitmentCard(_ item: DashboardData.CommitmentItem, selected: Bool = false, marked: Bool = false) -> LBKindCard {
        KindCards.card(item, photo: model.commitmentPhotoURL(id: item.id), selected: selected, marked: marked)
    }

    // MARK: Select and Bulk Edit

    /// Every card the list shows that Select can reach. Read only while selecting, so the list
    /// does not compute it otherwise.
    private var selectableIds: [String] {
        guard picking.isOn, case .loaded(let data) = model.state else { return [] }
        let parts = parts(data)
        return parts.rows.map { "c:" + $0.id } + (parts.upcoming + parts.unscheduled).map { "s:" + $0.id }
    }

    /// Person is not offered on Transfers: a transfer's people come from its accounts' owners.
    private var offersPerson: Bool { !(when == .past && kind == .transfers) }

    /// The chosen cards as the list holds them.
    private func chosenCards() -> (charges: [DashboardModel.ChargeItem], commitments: [DashboardData.CommitmentItem]) {
        guard case .loaded(let data) = model.state else { return ([], []) }
        let parts = parts(data)
        return (parts.rows.filter { picking.ids.contains("c:" + $0.id) },
                (parts.upcoming + parts.unscheduled).filter { picking.ids.contains("s:" + $0.id) })
    }

    /// One id per chosen card: several charges of a commitment name it several times.
    private func chosenCommitmentIds() -> [String] {
        let cards = chosenCards()
        return cards.charges.map(\.subId) + cards.commitments.map(\.id)
    }

    /// The list's noun for what is chosen.
    private var chosenNoun: (one: String, many: String) {
        selectableIds.first?.hasPrefix("s:") == true ? BulkWords.commitment : landedNoun
    }

    @ViewBuilder
    private func bulkActions(_ count: Int) -> some View {
        SelectionBarButton(title: "Category", measure: "bulk_category", enabled: count > 0) { bulkField = .category }
        if offersPerson {
            SelectionBarButton(title: "Person", measure: "bulk_person", enabled: count > 0) { bulkField = .person }
        }
        SelectionBarButton(title: "Delete \(count.formatted())", measure: "bulk_delete", destructive: true, enabled: count > 0) { askDelete() }
    }

    private var bulkBar: some View {
        SelectionBar(selection: picking, problem: model.saveError) { bulkActions($0) }
            .bulkPopups(prompt)
    }

    /// The list to pick one value from, with None first. The pick asks before it writes.
    private func bulkPicker(_ field: BulkField) -> some View {
        let isCategory = field == .category
        let none = ChoicePickerView.Choice(id: "", name: isCategory ? Self.noCategory : "No person", symbol: nil)
        let choices = isCategory
            ? model.tagChoices(kind: "commitment").map { ChoicePickerView.Choice(id: $0.name, name: categoryWord($0.name), symbol: nil) }
            : model.editChoices.members.map { ChoicePickerView.Choice(id: $0.id, name: $0.name, symbol: nil) }
        return ChoicePickerView(
            title: isCategory ? "Category" : "Person",
            glyph: isCategory ? LBGlyph.category : LBGlyph.member,
            choices: [none] + choices,
            selected: nil,
            onPick: { id in
                let word = choices.first { $0.id == id }?.name
                afterPick = isCategory ? categoryAsk(id.isEmpty ? nil : id, word: word) : personAsk(id.isEmpty ? nil : id, word: word)
            },
            onDone: { bulkField = nil }
        )
    }

    private func categoryAsk(_ tag: String?, word: String?) -> BulkAsk? {
        let ids = chosenCommitmentIds()
        guard let reach = model.bulkReach(cardsOf: ids) else { return nil }
        let words = BulkWords.change(field: "category", value: word, noun: chosenNoun, reach: reach, cardsAreCommitments: chosenCards().charges.isEmpty)
        return BulkAsk(title: words.title, message: words.message, confirm: "Change") {
            if model.setCategory(tag, onCommitments: Array(Set(ids))) { picking.finish() }
        }
    }

    private func personAsk(_ memberId: String?, word: String?) -> BulkAsk? {
        let ids = chosenCommitmentIds()
        guard let reach = model.bulkReach(cardsOf: ids) else { return nil }
        guard reach.commitments > reach.transfers else {
            return BulkAsk(title: "No person to set", message: "A transfer's people come from its accounts' owners.", confirm: nil)
        }
        let words = BulkWords.change(field: "person", value: word, noun: chosenNoun, reach: reach, cardsAreCommitments: chosenCards().charges.isEmpty,
                                     skipping: reach.transfers)
        return BulkAsk(title: words.title, message: words.message, confirm: "Change") {
            if model.setPerson(memberId, onCommitments: Array(Set(ids))) { picking.finish() }
        }
    }

    /// Deleting many says what deleting one says, made plural: charges go alone, a commitment
    /// goes with its charges.
    private func askDelete() {
        let cards = chosenCards()
        if !cards.commitments.isEmpty {
            let ids = cards.commitments.map(\.id)
            let whole = BulkWords.counted(ids.count, BulkWords.commitment)
            prompt.start(BulkAsk(title: "Delete \(whole)?", message: "Their charges are removed with them. \(BulkWords.wayBack)",
                                 confirm: "Delete \(whole.capitalized)", destructive: true) {
                if model.deleteCommitments(ids: ids) { picking.finish() }
            })
        } else if !cards.charges.isEmpty {
            let rows = cards.charges.map { (commitmentId: $0.subId, date: $0.dateISO) }
            let whole = BulkWords.counted(rows.count, landedNoun)
            prompt.start(BulkAsk(title: "Delete \(whole)?", message: "Only \(rows.count == 1 ? "this" : "these") \(rows.count == 1 ? landedNoun.one : landedNoun.many) \(rows.count == 1 ? "is" : "are") removed. \(BulkWords.wayBack)",
                                 confirm: "Delete \(whole.capitalized)", destructive: true) {
                if model.removeCharges(rows) { picking.finish() }
            })
        }
    }

    // MARK: actions shared by both platforms

    #if os(iOS)
    private func editCharge(_ charge: DashboardModel.ChargeItem) {
        editingCharge = model.charges(of: charge.subId).first { $0.id == charge.id }
    }
    #endif

    private func togglePaid(_ charge: DashboardModel.ChargeItem) {
        LBHaptics.tap()
        model.setPaid(subscriptionId: charge.subId, dateISO: charge.dateISO, paid: !charge.isPaid)
    }

    /// A commitment's Mark Paid acts on its next charge.
    private func togglePaid(_ item: DashboardData.CommitmentItem) {
        guard let due = item.dueISO else { return }
        LBHaptics.tap()
        model.setPaid(subscriptionId: item.id, dateISO: due, paid: !item.isPaid)
    }

    /// A per-machine preference in the sidecar, so an outside AI editing the vault can never
    /// appear to have removed a bookmark. It belongs to the commitment.
    private func toggleBookmark(_ id: String) {
        LBHaptics.tap()
        model.toggleBookmark(id)
    }

    private func bookmarkWord(_ id: String) -> (title: String, symbol: String) {
        model.bookmarks.contains(id) ? ("Remove Bookmark", "bookmark.slash") : ("Bookmark", "bookmark")
    }

    /// A commitment's next charge can be marked, while it has one; the bookmark is the commitment's.
    private func leadingActions(_ item: DashboardData.CommitmentItem) -> [LBRowAction] {
        let bookmark = bookmarkWord(item.id)
        let paid = item.dueISO == nil ? [] : [
            LBRowAction(item.isPaid ? "Mark Unpaid" : "Mark Paid",
                        systemImage: item.isPaid ? LBGlyph.unpaid : LBGlyph.paid) { togglePaid(item) },
        ]
        return paid + [LBRowAction(bookmark.title, systemImage: bookmark.symbol, tint: LBColor.textSecondary) { toggleBookmark(item.id) }]
    }

    /// A charge ahead can be marked; one behind is paid already. Both keep the bookmark.
    private func leadingActions(_ charge: DashboardModel.ChargeItem) -> [LBRowAction] {
        let bookmark = bookmarkWord(charge.subId)
        var actions: [LBRowAction] = []
        if !charge.isPast {
            actions.append(LBRowAction(charge.isPaid ? "Mark Unpaid" : "Mark Paid",
                                       systemImage: charge.isPaid ? LBGlyph.unpaid : LBGlyph.paid) { togglePaid(charge) })
        }
        actions.append(LBRowAction(bookmark.title, systemImage: bookmark.symbol, tint: LBColor.textSecondary) {
            toggleBookmark(charge.subId)
        })
        return actions
    }

#if os(iOS)
    /// Edit opens this charge, with the way on to its commitment; Delete removes this charge.
    private func trailingActions(_ charge: DashboardModel.ChargeItem) -> [LBRowAction] {
        [
            LBRowAction("Edit", systemImage: "pencil", tint: LBColor.textSecondary) { editCharge(charge) },
            .destructive("Delete") { deletingCharge = charge },
        ]
    }
#endif

    // MARK: - iPhone

    #if os(iOS)
    private var phoneBody: some View {
        // A list, so each card takes the system's own swipe actions; it draws only the rows in view.
        List {
            if case .loaded(let data) = model.state {
                phoneTop(data)
                phoneSections(data)
            }
        }
        .lbCardList()
        .scrollDismissesKeyboard(.immediately)
        .measured("commitments_showing_filters", .sheet, when: showingFilters)
        .sheet(isPresented: $showingFilters) {
            if case .loaded(let data) = model.state { filterSheet(data).lbKeyboardFocusEffects() }
        }
        .lbScreenTitle(screenTitle) {
            if picking.isOn {
                Button("Done") { Measure.used("select_done"); picking.finish() }
            } else {
                Button("Select") { Measure.used("select"); picking.begin() }
                Button {
                    Measure.used("add_commitment")
                    formTarget = .add
                } label: {
                    Image(systemName: "plus")
                }
                .tutorialTarget(.commitmentsAdd)
                .accessibilityLabel(addTitle)
            }
        }
        .toolbar {
            if picking.isOn {
                ToolbarItem(placement: .topBarLeading) {
                    SelectAllButton(selection: picking) { selectableIds }
                }
            }
        }
        .navigationBarBackButtonHidden(picking.isOn)
        .preference(key: HidesTabBarKey.self, value: picking.isOn)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if picking.isOn { bulkBar }
        }
    }

    /// What the list holds, the search and the Filter beside it, and what narrows the list,
    /// above the rows.
    private func phoneTop(_ data: DashboardData) -> some View {
        VStack(alignment: .leading, spacing: LBSpacing.s3) {
            ListDefinition(kind: listKind)
            HStack(spacing: LBSpacing.s2) {
                ListSearchField(text: $search, prompt: "Search")
                    .tutorialTarget(.commitmentsSearch)
                Button {
                    Measure.used("line_3_horizontal_decrease_circle_fill")
                    showingFilters = true
                } label: {
                    Image(systemName: anyFilter ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                        .font(.system(size: 20, weight: .regular))
                        .foregroundStyle(LBColor.brandText.color)
                        .frame(width: 40, height: 40)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(anyFilter ? "Filter, some chosen" : "Filter")
                .accessibilityHint(filterHelp + ".")
            }
            earningsTotal(parts(data).rows)
            narrowedLine(data)
        }
        .lbCardRow()
    }

    private func phoneHeading(_ words: String) -> some View {
        LBSectionHeader(words)
            .padding(.top, LBSpacing.s3)
            .lbCardRow()
    }

    @ViewBuilder
    private func phoneSections(_ data: DashboardData) -> some View {
        let parts = parts(data)
        if parts.rows.isEmpty, parts.upcoming.isEmpty, parts.unscheduled.isEmpty, parts.toFill.isEmpty {
            LBCard {
                VStack(alignment: .leading, spacing: LBSpacing.s3) {
                    Text(emptyWords)
                        .lbText(.footnote)
                        .foregroundStyle(LBColor.textSecondary.color)
                        .fixedSize(horizontal: false, vertical: true)
                    if let elsewhere {
                        Button(elsewhere == .past ? "Show Past Charges" : "Show Upcoming Charges") { Measure.used("show_past_charges"); when = elsewhere }
                            .foregroundStyle(LBColor.brandText.color)
                            .buttonStyle(.borderless)
                    }
                }
            }
            .lbCardRow()
        }
        if !parts.toFill.isEmpty, !picking.isOn {
            phoneHeading("Needs details")
            placeholderRail(parts.toFill)
                .lbCardRow()
        }
        let first = parts.rows.first?.id ?? parts.upcoming.first?.id
        ForEach(grouped(parts.rows, by: \.monthLabel), id: \.label) { group in
            phoneHeading(monthHeading(group.label))
            ForEach(group.items) { phoneRow($0, spot: $0.id == first ? .commitmentsFirst : nil) }
        }
        ForEach(grouped(parts.upcoming, by: \.monthLabel), id: \.label) { group in
            phoneHeading(monthHeading(group.label))
            ForEach(group.items) { phoneRow($0, spot: $0.id == first ? .commitmentsFirst : nil) }
        }
        if !parts.unscheduled.isEmpty {
            phoneHeading(unscheduledHeading)
            ForEach(parts.unscheduled) { phoneRow($0) }
        }
        if !picking.isOn, !parts.rows.isEmpty || !parts.upcoming.isEmpty || !parts.unscheduled.isEmpty, let also = alsoMatching(data) {
            Button(alsoMatchingWords(also)) { Measure.used("show_also_matching"); when = also.scope }
                .lbText(.body)
                .foregroundStyle(LBColor.brandText.color)
                .buttonStyle(.borderless)
                .padding(.top, LBSpacing.s2)
                .lbCardRow()
        }
    }

    /// One charge as the card every list wears. A tap opens its Preview; Mark Paid and
    /// Bookmark on the leading swipe, Edit and Delete trailing. While selecting, a tap toggles it.
    @ViewBuilder
    private func phoneRow(_ charge: DashboardModel.ChargeItem, spot: TutorialTarget? = nil) -> some View {
        if picking.isOn {
            SelectableCard(selection: picking, id: "c:" + charge.id) { chargeCard(charge, selected: $0, marked: true) }
                .tutorialTarget(spot)
                .lbCardRow()
        } else {
            CardListLink(destination: charge.ref.destination) { chargeCard(charge) }
                .tutorialTarget(spot)
                .lbCardRow()
                .lbRowActions(leading: leadingActions(charge), trailing: trailingActions(charge))
        }
    }

    /// One commitment, opening on itself. Mark Paid, while it has a next charge, and Bookmark
    /// lead; Edit and Delete act on the whole commitment. While selecting, a tap toggles it.
    @ViewBuilder
    private func phoneRow(_ item: DashboardData.CommitmentItem, spot: TutorialTarget? = nil) -> some View {
        if picking.isOn {
            SelectableCard(selection: picking, id: "s:" + item.id) { commitmentCard(item, selected: $0, marked: true) }
                .tutorialTarget(spot)
                .lbCardRow()
        } else {
            CardListLink(destination: .commitment(id: item.id)) { commitmentCard(item) }
                .tutorialTarget(spot)
                .lbCardRow()
                .lbRowActions(
                    leading: leadingActions(item),
                    trailing: [
                        LBRowAction("Edit", systemImage: "pencil", tint: LBColor.textSecondary) { formTarget = .edit(item.id) },
                        .destructive("Delete") { deletingItem = CommitmentRef(id: item.id, name: item.name) },
                    ]
                )
        }
    }

    /// Every narrowing in one sheet, behind the one Filter button.
    private func filterSheet(_ data: DashboardData) -> some View {
        NavigationStack {
            Form {
                Section {
                    Button {
                        Measure.used("pick_date_range")
                        prefillRange()
                        pickingRangeInFilters = true
                    } label: {
                        HStack {
                            Label("Date", systemImage: LBGlyph.date)
                                .foregroundStyle(LBColor.textPrimary.color)
                            Spacer()
                            Text(rangeWords ?? "Any")
                                .foregroundStyle(LBColor.textSecondary.color)
                        }
                    }
                    .lbListRowBackground()
                    ForEach(filterSpecs(data)) { spec in
                        Picker(selection: spec.selection) {
                            Text("Any").tag(String?.none)
                            ForEach(spec.options, id: \.0) { option in
                                Text(option.1).tag(String?.some(option.0))
                            }
                        } label: {
                            Label(spec.title, systemImage: spec.symbol)
                        }
                        .lbListRowBackground()
                    }
                    Toggle(isOn: $onlyBookmarked.measured("bookmarked_only")) {
                        Label("Bookmarked Only", systemImage: "bookmark")
                    }
                    .lbListRowBackground()
                }
                if anyFilter {
                    Section {
                        Button("Clear Filters", role: .destructive) { Measure.used("clear_filters"); clearFilters() }
                            .lbListRowBackground()
                    }
                }
            }
            .lbText(.body)
            .tint(LBColor.brand.color)
            .scrollContentBackground(.hidden)
            .background(LBColor.canvas.color)
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { Measure.used("done"); showingFilters = false }
                }
            }
            .measured("commitments_picking_range_in_filters", .sheet, when: pickingRangeInFilters)
            .sheet(isPresented: $pickingRangeInFilters, onDismiss: settleSide) {
                DateRangePickerView(from: $from, to: $to) { pickingRangeInFilters = false }
                    .lbKeyboardFocusEffects()
            }
        }
        .presentationDetents([.medium, .large])
    }
    #endif

    // MARK: - Mac

    /// One row of the Mac list: a charge, a commitment, or a name still to fill in.
    struct LedgerRow: Identifiable {
        enum Kind {
            case charge(DashboardModel.ChargeItem)
            case commitment(DashboardData.CommitmentItem)
            case placeholder(CommitmentPlaceholder)
        }

        let id: String
        let kind: Kind

        var subId: String? {
            switch kind {
            case .charge(let charge): charge.subId
            case .commitment(let item): item.id
            case .placeholder: nil
            }
        }
    }

    #if os(macOS)
    private typealias Parts = (
        rows: [DashboardModel.ChargeItem], upcoming: [DashboardData.CommitmentItem],
        unscheduled: [DashboardData.CommitmentItem], toFill: [CommitmentPlaceholder]
    )

    private func ledgerRows(_ parts: Parts) -> [LedgerRow] {
        parts.toFill.map { LedgerRow(id: "p:" + $0.id, kind: .placeholder($0)) }
            + parts.rows.map { LedgerRow(id: "c:" + $0.id, kind: .charge($0)) }
            + (parts.upcoming + parts.unscheduled).map { LedgerRow(id: "s:" + $0.id, kind: .commitment($0)) }
    }

    private var macBody: some View {
        VStack(spacing: 0) {
            if case .loaded(let data) = model.state {
                // Read once per pass: the header, the cards and the lookup all take these.
                let parts = parts(data)
                let rows = ledgerRows(parts)
                let byId = Dictionary(rows.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
                macHeader(data, parts: parts, rows: rows)
                VStack(spacing: 0) {
                    macNotes(data, parts: parts)
                    macCards(data, parts: parts, rows: rows, byId: byId)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background { SelectAllKey { macSelectAll() } }
                }
                .lbSidePanel(isPresented: inspectorShown) {
                    if let formCard {
                        CardEditForm(model: model, card: formCard, inPanel: true, closeAsked: formCloseAsked, focus: formFocus,
                                     onDeleted: { selection = []; inspected = nil },
                                     onMoved: { followMovedCharge(to: $0) }) { self.formCard = nil }
                            .id(formCard)
                    } else {
                        inspector(rows)
                    }
                }
                // A chosen row that has left the list, narrowed away or moved, closes the panel,
                // once no form stands in it.
                .onChange(of: model.isLoaded && formCard == nil && !selection.isEmpty && selected(rows).isEmpty) { _, gone in
                    if gone { selection = [] }
                }
                // Another card chosen under the form closes it, asking first if it holds changes.
                .onChange(of: selection) { old, _ in
                    if let formCard, selected(rows).first.flatMap(card(of:)) != formCard {
                        PanelForm.shared.onKeep = { selection = old }
                        formCloseAsked += 1
                    }
                }
                // A door that named a commitment opens the inspector on it; the picture
                // harness opens it on the first.
                .onAppear {
                    guard selection.isEmpty else { return }
                    if let focusCharge, rows.contains(where: { $0.id == "c:" + focusCharge }) {
                        selection = ["c:" + focusCharge]
                        return
                    }
                    if let focus, let row = rows.first(where: { $0.subId == focus }) {
                        selection = [row.id]
                        return
                    }
                    #if DEBUG
                    if ProcessInfo.processInfo.environment["LONGBOOK_SNAPSHOT"] != nil || ProcessInfo.processInfo.environment["LONGBOOK_WINDOW_SNAPSHOT"] != nil,
                       ProcessInfo.processInfo.environment["LONGBOOK_SNAPSHOT_OPEN"] != "remembered",
                       let first = rows.first(where: { $0.subId != nil }) ?? rows.first {
                        // The picture harness can open the list in Select with the first card chosen.
                        if ProcessInfo.processInfo.environment["LONGBOOK_SNAPSHOT_OPEN"] == "select", first.subId != nil {
                            picking.begin(with: [first.id])
                            return
                        }
                        selection = [first.id]
                        // The picture harness opens its Edit form in the panel.
                        if ProcessInfo.processInfo.environment["LONGBOOK_SNAPSHOT_OPEN"] == "edit" { formCard = card(of: first) }
                    }
                    #endif
                }
                .lbRemembersRow(
                    on: memoryKey, row: openRow, ready: focus == nil && focusCharge == nil,
                    holds: { byId[$0] != nil },
                    // The list's rows go by their charge's or commitment's own id, without the kind's prefix.
                    landed: { landing = String($0.dropFirst(2)) }
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LBColor.canvas.color)
        .bulkPopups(prompt)
    }

    /// The one row open in the panel, as the memory reads and sets it.
    private var openRow: Binding<String?> {
        Binding(get: { selection.count == 1 ? selection.first : nil }, set: { selection = $0.map { [$0] } ?? [] })
    }

    /// The panel's ×: the row stays closed on the next visit too.
    private func closePanel() {
        selection = []
        ScreenMemory.shared.forget(on: memoryKey)
    }

    private func selected(_ rows: [LedgerRow]) -> [LedgerRow] {
        rows.filter { selection.contains($0.id) }
    }

    /// ⌘A: Select comes on, with everything the list shows.
    private func macSelectAll() {
        beginPicking()
        picking.choose(all: selectableIds)
    }

    /// Select comes on, holding the card that was chosen, and the Preview goes.
    private func beginPicking() {
        guard !picking.isOn else { return }
        picking.begin(with: selection.filter { !$0.hasPrefix("p:") })
        selection = []
    }

    /// Beside the filter: Select, then Select All while selecting, as Done stands in the first line.
    @ViewBuilder
    private var selectButton: some View {
        if picking.isOn {
            SelectAllButton(selection: picking) { selectableIds }
                .help("Select All (⌘A)")
        } else {
            Button("Select") {
                Measure.used("select")
                beginPicking()
            }
            .help("Select \(screenTitle) · ⌘A selects all · ⌘-click or ⇧-click adds")
        }
    }

    /// The page's title and the one Add on one line — the window's toolbar, drawn in the page —
    /// or, while selecting, the count and what works on every chosen card. Then what the list
    /// holds, and the search, the one Filter menu and Select beside the panel.
    private func macHeader(_ data: DashboardData, parts: Parts, rows: [LedgerRow]) -> some View {
        VStack(alignment: .leading, spacing: LBSpacing.s3) {
            if picking.isOn {
                HeaderSelectionBar(selection: picking) { macBulkActions($0) }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: LBSpacing.s2) {
                    LBPageTitle(screenTitle)
                    Spacer()
                    Button {
                        Measure.used("add")
                        formTarget = .add
                    } label: {
                        Label(addTitle, systemImage: "plus")
                    }
                    .tutorialTarget(.commitmentsAdd)
                }
                .controlSize(.large)
            }
            ListDefinition(kind: listKind)
            HStack(spacing: LBSpacing.s2) {
                ListSearchField(text: $search, prompt: "Search")
                    .tutorialTarget(.commitmentsSearch)
                filterMenu(data)
                selectButton
            }
            .lbBesidePanel(inspectorShown.wrappedValue)
        }
        .padding(.horizontal, LBSpacing.s4)
        .padding(.top, LBSpacing.s6)
        .frame(height: SidePanel.line, alignment: .top)
    }

    /// What works on every chosen card, in the selection's first line: Mark Paid on the cards
    /// ahead, Bookmark, the two fields Bulk Edit sets, and Delete.
    @ViewBuilder
    private func macBulkActions(_ count: Int) -> some View {
        let cards = chosenCards()
        let marks = cards.charges.filter { !$0.isPast }.map { (subId: $0.subId, dateISO: $0.dateISO, isPaid: $0.isPaid) }
            + cards.commitments.compactMap { item in item.dueISO.map { (subId: item.id, dateISO: $0, isPaid: item.isPaid) } }
        let allPaid = !marks.isEmpty && marks.allSatisfy(\.isPaid)
        let ids = Array(Set(chosenCommitmentIds()))
        let allSaved = !ids.isEmpty && ids.allSatisfy { model.bookmarks.contains($0) }
        if when == .upcoming {
            SelectionBarButton(title: allPaid ? "Mark Unpaid" : "Mark Paid", measure: "bulk_mark_paid", enabled: !marks.isEmpty, opensMore: false) {
                LBHaptics.tap()
                for mark in marks { model.setPaid(subscriptionId: mark.subId, dateISO: mark.dateISO, paid: !allPaid) }
            }
        }
        SelectionBarButton(title: allSaved ? "Remove Bookmark" : "Bookmark", measure: "bulk_bookmark", enabled: !ids.isEmpty, opensMore: false) {
            LBHaptics.tap()
            for id in ids where model.bookmarks.contains(id) == allSaved { model.toggleBookmark(id) }
        }
        bulkActions(count)
    }

    /// What narrows the list, and what the list adds up to: above the cards, beside the panel.    /// What narrows the list, and what the list adds up to: above the cards, beside the panel.
    private func macNotes(_ data: DashboardData, parts: Parts) -> some View {
        VStack(alignment: .leading, spacing: LBSpacing.s3) {
            // A bulk change the file refused says why here, under the selection's first line.
            if picking.isOn, let problem = model.saveError {
                Text(problem)
                    .lbText(.footnote)
                    .foregroundStyle(LBColor.urgent.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
            earningsTotal(parts.rows)
            narrowedLine(data)
        }
        .padding(.horizontal, LBSpacing.s4)
        .padding(.bottom, LBSpacing.s2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Every narrowing in one menu; each is a submenu that ticks its choice.
    private func filterMenu(_ data: DashboardData) -> some View {
        Menu {
            Button(rangeWords.map { "Date: \($0)…" } ?? "Date…", action: { Measure.used("pick_date_range", .menuItem); openRange() })
            ForEach(filterSpecs(data)) { spec in
                Picker(selection: spec.selection) {
                    Text("Any").tag(String?.none)
                    ForEach(spec.options, id: \.0) { option in
                        Text(option.1).tag(String?.some(option.0))
                    }
                } label: {
                    Label(spec.chosen.map { "\(spec.title): \($0)" } ?? spec.title, systemImage: spec.symbol)
                }
                .pickerStyle(.menu)
            }
            Toggle("Bookmarked Only", isOn: $onlyBookmarked.measured("bookmarked_only"))
            if anyFilter {
                Divider()
                Button("Clear Filters", action: { Measure.used("clear_filters", .menuItem); clearFilters() })
            }
        } label: {
            Image(systemName: anyFilter ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
        }
        .fixedSize()
        .help(filterHelp)
        .lbLinkPointer()
        .accessibilityLabel(anyFilter ? "Filter, some chosen" : "Filter")
    }

    /// The same cards the phone lists, under their months, beside the inspector: a click
    /// picks one, a double click edits it, and a right click offers what the card can do.
    private func macCards(_ data: DashboardData, parts: Parts, rows: [LedgerRow], byId: [String: LedgerRow]) -> some View {
        let first = parts.rows.first.map { "c:" + $0.id } ?? parts.upcoming.first.map { "s:" + $0.id }
        return VStack(spacing: 0) {
            if rows.isEmpty {
                VStack(alignment: .leading, spacing: LBSpacing.s3) {
                    Text(emptyWords)
                        .lbText(.body)
                        .foregroundStyle(LBColor.textSecondary.color)
                        .fixedSize(horizontal: false, vertical: true)
                    if let elsewhere {
                        Button(elsewhere == .past ? "Show Past Charges" : "Show Upcoming Charges") { Measure.used("show_past_charges"); when = elsewhere }
                    }
                }
                .padding(LBSpacing.s4)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                List {
                    if !parts.toFill.isEmpty, !picking.isOn {
                        Section {
                            placeholderRail(parts.toFill)
                                .lbCardRow()
                        } header: {
                            LBSectionHeader("Needs details")
                        }
                    }
                    ForEach(grouped(parts.rows, by: \.monthLabel), id: \.label) { group in
                        Section {
                            ForEach(group.items) { charge in
                                macCard("c:" + charge.id, byId: byId) { chargeCard(charge, selected: $0, marked: $1) }
                                    .tutorialTarget("c:" + charge.id == first ? .commitmentsFirst : nil)
                                    .lbCardRow()
                            }
                        } header: {
                            LBSectionHeader(monthHeading(group.label))
                        }
                    }
                    ForEach(grouped(parts.upcoming, by: \.monthLabel), id: \.label) { group in
                        Section {
                            ForEach(group.items) { item in
                                macCard("s:" + item.id, byId: byId) { commitmentCard(item, selected: $0, marked: $1) }
                                    .tutorialTarget("s:" + item.id == first ? .commitmentsFirst : nil)
                                    .lbCardRow()
                            }
                        } header: {
                            LBSectionHeader(monthHeading(group.label))
                        }
                    }
                    if !parts.unscheduled.isEmpty {
                        Section {
                            ForEach(parts.unscheduled) { item in
                                macCard("s:" + item.id, byId: byId) { commitmentCard(item, selected: $0, marked: $1) }
                                    .lbCardRow()
                            }
                        } header: {
                            LBSectionHeader(unscheduledHeading)
                        }
                    }
                    if !picking.isOn, let also = alsoMatching(data) {
                        Section {
                            Button(alsoMatchingWords(also)) { Measure.used("show_also_matching"); when = also.scope }
                                .lbCardRow()
                        }
                    }
                }
                .lbGroupedList()
                // A right click focuses the row; its ring shows only while the keyboard drives,
                // so a click never leaves one. The card's own tint already says chosen.
                .lbKeyboardFocusEffects()
                .lbLandsOnRow($landing)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var inspectorShown: Binding<Bool> {
        Binding(get: { formCard != nil || (!selection.isEmpty && !picking.isOn) }, set: { if !$0 { selection = []; formCard = nil } })
    }

    /// One card of the list: a door while nothing is selecting, a toggle while Select is on.
    @ViewBuilder
    private func macCard(_ id: String, byId: [String: LedgerRow], _ card: @escaping (Bool, Bool) -> LBKindCard) -> some View {
        if picking.isOn {
            SelectableCard(selection: picking, id: id, order: { selectableIds }) { card($0, true) }
        } else {
            pickable(id, byId: byId, card(selection.contains(id), false))
                .lbSwipeActions(leading: byId[id].map(leadingActions) ?? [], trailing: byId[id].map(trailingActions) ?? [])
        }
    }

    /// A trackpad swipe offers what the phone's does: Mark Paid and Bookmark leading.
    private func leadingActions(_ row: LedgerRow) -> [LBRowAction] {
        switch row.kind {
        case .charge(let charge): leadingActions(charge)
        case .commitment(let item): leadingActions(item)
        case .placeholder: []
        }
    }

    /// Edit opens the panel's form; Delete asks first, a charge alone or the whole commitment.
    private func trailingActions(_ row: LedgerRow) -> [LBRowAction] {
        let delete: LBRowAction
        switch row.kind {
        case .charge(let charge): delete = .destructive("Delete") { deletingCharge = charge }
        case .commitment(let item): delete = .destructive("Delete") { deletingItem = CommitmentRef(id: item.id, name: item.name) }
        case .placeholder: return []
        }
        return [LBRowAction("Edit", systemImage: "pencil", tint: LBColor.textSecondary) { edit(row) }, delete]
    }

    /// A click chooses the card at once, a second click within a moment opens it, a right
    /// click shows its menu. Timed by hand: a double-click recognizer would hold every
    /// single click back while it waited for the second.
    private func pickable<V: View>(_ id: String, byId: [String: LedgerRow], _ content: V) -> some View {
        let row = byId[id]
        // A click only chooses, so the card hovers but has no pressed look. Tab reaches it;
        // Return or Space chooses it as a click does.
        return content
            .lbHoverWash()
            .lbKeyboardFocusable(radius: LBRadius.md) { selection = [id]; inspected = nil }
            .contentShape(Rectangle())
            .onTapGesture {
                // ⌘ or ⇧ on a card that can be chosen turns Select on with it.
                if !NSEvent.modifierFlags.isDisjoint(with: [.command, .shift]), !id.hasPrefix("p:") {
                    beginPicking()
                    picking.click(id, order: { selectableIds })
                    return
                }
                let now = Date()
                if lastClick.id == id, now.timeIntervalSince(lastClick.at) < 0.35, let row {
                    lastClick = ("", .distantPast)
                    edit(row)
                } else {
                    lastClick = (id, now)
                    selection = [id]
                    inspected = nil
                }
            }
            .contextMenu { if let row { menu([row]) } }
    }

    /// What Mark Paid acts on for a row: a charge ahead, or a commitment's next charge.
    private func markable(_ row: LedgerRow) -> (subId: String, dateISO: String, isPaid: Bool)? {
        switch row.kind {
        case .charge(let charge): charge.isPast ? nil : (charge.subId, charge.dateISO, charge.isPaid)
        case .commitment(let item): item.dueISO.map { (item.id, $0, item.isPaid) }
        case .placeholder: nil
        }
    }

    /// A charge Save moved to another day is another row: the Preview follows it there.
    private func followMovedCharge(to day: String) {
        guard case .charge(let subId, _)? = formCard, let moved = formCard?.moved(to: day) else { return }
        // A charge opened inside another card's Preview stays there, under that card.
        if formCard == inspected {
            inspected = moved
        } else {
            selection = ["c:\(subId)-\(day)"]
        }
        formCard = nil
    }

    /// What a row's Preview reads and its form edits; a name to fill in has neither.
    private func card(of row: LedgerRow) -> CardRef? {
        switch row.kind {
        case .charge(let charge): charge.ref
        case .commitment(let item): .commitment(id: item.id)
        case .placeholder: nil
        }
    }

    /// Double click, Edit and the menu's Edit open one form: the one the Preview's Edit opens,
    /// in the Preview's place, on what the Preview reads. A name to fill in is something new,
    /// so it opens the fill-in form as a sheet.
    private func edit(_ row: LedgerRow) {
        if case .placeholder(let placeholder) = row.kind {
            formTarget = .fill(placeholder)
            return
        }
        guard let opened = card(of: row) else { return }
        let shown = selection == [row.id] ? inspected ?? opened : opened
        PanelForm.shared.ask {
            selection = [row.id]
            inspected = shown == opened ? nil : shown
            formFocus = nil
            formCard = shown
        }
    }

    @ViewBuilder
    private func menu(_ rows: [LedgerRow]) -> some View {
        if rows.count == 1, let row = rows.first {
            switch row.kind {
            case .charge(let charge):
                if !charge.isPast {
                    Button(charge.isPaid ? "Mark Unpaid" : "Mark Paid") { Measure.used("mark_unpaid"); togglePaid(charge) }
                }
                Button(bookmarkWord(charge.subId).title) { Measure.used("toggle_bookmark"); toggleBookmark(charge.subId) }
                Divider()
                Button("Edit") { Measure.used("edit"); edit(row) }
                Divider()
                Button("Delete Charge", role: .destructive) { Measure.used("delete_charge"); deletingCharge = charge }
                Button("Delete Commitment", role: .destructive) {
                    Measure.used("delete_commitment")
                    deletingItem = CommitmentRef(id: charge.subId, name: charge.name)
                }
            case .commitment(let item):
                if item.dueISO != nil {
                    Button(item.isPaid ? "Mark Unpaid" : "Mark Paid") { Measure.used("mark_unpaid"); togglePaid(item) }
                }
                Button(bookmarkWord(item.id).title) { Measure.used("toggle_bookmark"); toggleBookmark(item.id) }
                Button("Edit") { Measure.used("edit"); edit(row) }
                Divider()
                Button("Delete Commitment", role: .destructive) {
                    Measure.used("delete_commitment")
                    deletingItem = CommitmentRef(id: item.id, name: item.name)
                }
            case .placeholder(let placeholder):
                Button("Fill In") { Measure.used("fill_in"); formTarget = .fill(placeholder) }
                Divider()
                Button("Remove", role: .destructive) { Measure.used("remove"); removingPlaceholder = placeholder }
            }
        } else if !rows.isEmpty {
            let charges = rows.compactMap(markable)
            if !charges.isEmpty {
                Button("Mark \(charges.count) Paid") {
                    Measure.used("mark_paid")
                    for charge in charges { model.setPaid(subscriptionId: charge.subId, dateISO: charge.dateISO, paid: true) }
                }
            }
        }
    }

    /// A card's Preview in the pane; a card inside it opens here too, in its place.
    private func preview(_ card: CardRef) -> some View {
        CardPreviewView(model: model, card: card, onClose: closePanel, open: { inspected = $0 },
                        onEdit: { field in
                            formFocus = field
                            formCard = card
                        })
            .id(card)
    }

    /// The selected record, read whole beside the table.
    @ViewBuilder
    private func inspector(_ rows: [LedgerRow]) -> some View {
        let chosen = selected(rows)
        if chosen.count == 1, let row = chosen.first {
            switch row.kind {
            case .charge(let charge):
                preview(inspected ?? charge.ref)
            case .commitment(let item):
                preview(inspected ?? .commitment(id: item.id))
            case .placeholder(let placeholder):
                VStack(alignment: .leading, spacing: LBSpacing.s3) {
                    PanelCloseButton(measure: "close_placeholder", action: closePanel)
                    Text(placeholder.name)
                        .lbText(.screenTitle)
                        .foregroundStyle(LBColor.textPrimary.color)
                    Text("Named at setup. It needs an amount and a day before it is planned.")
                        .lbText(.body)
                        .foregroundStyle(LBColor.textSecondary.color)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Button("Fill In") { Measure.used("fill_in"); formTarget = .fill(placeholder) }
                            .buttonStyle(.borderedProminent)
                            .tint(LBColor.brand.color)
                        Button("Remove", role: .destructive) { Measure.used("remove"); removingPlaceholder = placeholder }
                    }
                }
                .padding(LBSpacing.s4)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        } else {
            VStack(alignment: .leading, spacing: LBSpacing.s3) {
                PanelCloseButton(measure: "close_no_selection", action: closePanel)
                Text(chosen.isEmpty ? "No selection" : "\(chosen.count) selected")
                    .lbText(.body)
                    .foregroundStyle(LBColor.textTertiary.color)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(LBSpacing.s4)
        }
    }
    #endif

    // MARK: grouping

    /// Buckets an already-ordered list under its labels, encounter order — pure
    /// presentation; the model owns the sort.
    private func grouped<T>(_ items: [T], by label: (T) -> String?) -> [(label: String, items: [T])] {
        var out: [(label: String, items: [T])] = []
        var index: [String: Int] = [:]
        for item in items {
            guard let key = label(item) else { continue }
            if let at = index[key] {
                out[at].items.append(item)
            } else {
                index[key] = out.count
                out.append((label: key, items: [item]))
            }
        }
        return out
    }
}
