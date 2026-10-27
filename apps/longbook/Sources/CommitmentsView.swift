import DesignSystem
import LongbookCore
import SwiftUI

/// Both directions of the ledger, one row per stored charge: ahead, what each commitment
/// will charge, then what has no date ahead; behind, what landed, newest first. A plain
/// list on the phone, a sortable table with an inspector on the Mac; one Filter control.
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
    /// The filter's own narrowings, each held as the vault's raw value.
    @State private var pickedCycle: String?
    @State private var pickedStatus: String?
    @State private var pickedCurrency: String?
    /// The commitment whose delete is awaiting confirmation — the whole plan, every row.
    @State private var deletingItem: CommitmentRef?
    @State private var deletingCharge: DashboardModel.ChargeItem?
    @State private var editingCharge: Charge?
    /// The to-fill-in name whose Remove is awaiting confirmation.
    @State private var removingPlaceholder: CommitmentPlaceholder?
    /// True once the reader asked for the months past the cap.
    @State private var showsLaterMonths = false
    /// The Mac list's chosen cards.
    @State private var selection: Set<String> = []
    /// The last card clicked and when, for telling a second click from a first.
    @State private var lastClick: (id: String, at: Date) = ("", .distantPast)

    /// The filter's word for rows that wear no category, as the panels and reports say it.
    static let noCategory = "No category"

    /// The unfiltered list ahead stops at this many calendar months. A plan written two
    /// years out would otherwise bury what is near under what is far.
    private static let monthsShown = 12

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

    init(model: DashboardModel, filter: ListFilter, focus: String? = nil) {
        self.model = model
        self.focus = focus
        _day = State(initialValue: filter.day)
        _months = State(initialValue: filter.months)
        _from = State(initialValue: LB.parseDate(filter.from))
        _to = State(initialValue: LB.parseDate(filter.to))
        _methodId = State(initialValue: filter.methodId)
        _memberId = State(initialValue: filter.memberId)
        _pickedCategory = State(initialValue: filter.category)
        _onlyBookmarked = State(initialValue: filter.bookmarked)
        // A door may name its side; otherwise the window decides, so this month and today
        // open on what is still coming, and a day or month gone on what landed.
        var opens: ListScope = switch filter.scope {
        case .past: .past
        case .upcoming: .upcoming
        case nil: listScope(day: filter.day, months: filter.months, from: filter.from, to: filter.to)
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
            .onChange(of: when) { _, _ in selection = [] }
            .measured("commitments_picking_range", .sheet, when: pickingRange)
            .sheet(isPresented: $pickingRange, onDismiss: settleSide) {
                DateRangePickerView(from: $from, to: $to) { pickingRange = false }
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
                    RenewalFormView(model: model, editingId: nil) { formTarget = nil }
                case .edit(let id):
                    RenewalFormView(model: model, editingId: id) { formTarget = nil }
                case .fill(let placeholder):
                    RenewalFormView(model: model, editingId: nil, seedCategory: placeholder.tag, seedName: placeholder.name) {
                        // Saved under its name, the placeholder has become the real thing.
                        if model.hasCommitment(named: placeholder.name) { model.removePlaceholder(placeholder.id) }
                        formTarget = nil
                    }
                }
            }
            .measured("commitments_editing_charge", .sheet, when: editingCharge != nil)
            .sheet(item: $editingCharge) { charge in
                RenewalFormView(model: model, editingId: charge.sub.id, chargeISO: charge.row.date) { editingCharge = nil }
                    .lbThreeQuarterSheet()
            }
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
                Button("Delete", role: .destructive) {
                    Measure.used("delete")
                    _ = model.removeCharge(subscriptionId: charge.subId, dateISO: charge.dateISO)
                    selection = []
                }
                Button("Cancel", role: .cancel) { Measure.used("cancel") }
            } message: { charge in
                Text("\(charge.name), \(charge.amountText). Only this charge is removed.")
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
            if let day, charge.dateISO != day { return false }
            if !monthKeys.isEmpty, !monthKeys.contains(charge.dateISO.prefix(7)) { return false }
            if hasRange, !inDayRange(charge.dateISO, from: fromISO, to: toISO) { return false }
            if !matchesCategory(charge.category) { return false }
            if !matchesMethod(charge.methodId) { return false }
            if !matchesMember(charge.memberId) { return false }
            if let pickedCycle, charge.cycle.rawValue != pickedCycle { return false }
            if let pickedStatus, charge.status.rawValue != pickedStatus { return false }
            if let pickedCurrency, charge.currency != pickedCurrency { return false }
            if onlyBookmarked, !model.bookmarks.contains(charge.subId) { return false }
            return needle.isEmpty || charge.searchText.contains(needle)
        }
        return scope == .past ? Array(rows.reversed()) : rows
    }

    private func visibleRows() -> [DashboardModel.ChargeItem] {
        rows(in: when)
    }

    /// What has no date ahead, narrowed as the rows are — by what it is, since it has no day.
    private func visibleUnscheduled(_ data: DashboardData) -> [DashboardData.CommitmentItem] {
        let needle = search.lowercased()
        return data.commitments.filter { item in
            guard item.monthLabel == nil else { return false }
            if !matchesCategory(item.category) { return false }
            if !matchesMethod(item.methodId) { return false }
            if !matchesMember(item.memberId) { return false }
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

    private func matchesMember(_ id: String?) -> Bool {
        guard let memberId else { return true }
        if memberId == DashboardModel.unassignedMemberId { return id == nil }
        return id == memberId
    }

    /// Whether the list ahead stops at the cap: only the whole, unnarrowed list does.
    private var capsMonths: Bool {
        when == .upcoming && !showsLaterMonths && !anyFilter && search.isEmpty && day == nil && months.isEmpty && !hasRange
    }

    /// The three parts of the list as the narrowing leaves them, and whether the cap hid any.
    private func parts(_ data: DashboardData) -> (
        rows: [DashboardModel.ChargeItem], capped: Bool,
        unscheduled: [DashboardData.CommitmentItem], toFill: [CommitmentPlaceholder]
    ) {
        let all = visibleRows()
        let edge = LB.toISO(LB.addMonths(LB.firstOfMonth(LB.todayMid()), Self.monthsShown))
        let rows = underCap(all, before: edge, capped: capsMonths, dateISO: \.dateISO)
        // Under a day, months or a Date window the unscheduled have nothing to be inside of.
        let unscheduled = when == .upcoming && day == nil && months.isEmpty && !hasRange ? visibleUnscheduled(data) : []
        let toFill = when == .upcoming ? visiblePlaceholders() : []
        return (rows, rows.count < all.count, unscheduled, toFill)
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
        if let rangeWords { words.insert(rangeWords, at: 0) }
        if onlyBookmarked { words.append("Bookmarked") }
        return words
    }

    private var anyFilter: Bool {
        pickedCategory != nil || methodId != nil || memberId != nil || pickedCycle != nil
            || pickedStatus != nil || pickedCurrency != nil || onlyBookmarked || hasRange
    }

    private func clearFilters() {
        pickedCategory = nil
        methodId = nil
        memberId = nil
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

    private var screenTitle: String { when == .past ? "Charges" : "Commitments" }

    /// A month heading as a sentence: "October 2026".
    private func monthHeading(_ label: String) -> String {
        label.prefix(1).uppercased() + label.dropFirst()
    }

    private var unscheduledHeading: String { "No upcoming date" }

    /// Why the list is empty, in the side's own words.
    private var emptyWords: String {
        if when == .past {
            return hasRange ? "No charges between these dates."
                : !search.isEmpty || anyFilter ? "No past charges match. Clear the search or a filter."
                : day != nil ? "No charges on this day."
                : months.count > 1 ? "No charges in these months."
                : !months.isEmpty ? "No charges in this month."
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

    /// A search answers from both sides: when this side shows matches, the other side's
    /// count is offered too, so a one-time charge already behind today is never missed.
    private var alsoMatching: (scope: ListScope, count: Int)? {
        guard !search.isEmpty else { return nil }
        let other: ListScope = when == .past ? .upcoming : .past
        let count = rows(in: other).count
        return count > 0 ? (other, count) : nil
    }

    private func alsoMatchingWords(_ also: (scope: ListScope, count: Int)) -> String {
        let noun = also.count == 1 ? "charge" : "charges"
        return "\(also.count) \(also.scope == .past ? "past" : "upcoming") \(noun) also match"
    }

    /// The second line of a charge row: when, its mark and badge, and what it is filed under.
    private func secondary(_ charge: DashboardModel.ChargeItem) -> String {
        var parts: [String?] = [charge.facts.first?.text]
        if !charge.isPast {
            if charge.isPaid { parts.append("Paid") }
            parts.append(badgeSpec(charge.badge)?.text)
        }
        parts.append(kindWord(category: charge.category, income: charge.isIncome, transfer: charge.isTransfer))
        return parts.compactMap { $0 }.joined(separator: " · ")
    }

    private func secondary(_ item: DashboardData.CommitmentItem) -> String {
        var parts: [String?] = [badgeSpec(item.badge)?.text]
        parts += item.facts.filter { !$0.placeholder }.prefix(2).map(\.text)
        return parts.compactMap { $0 }.joined(separator: " · ")
    }

    private func kindWord(category: String?, income: Bool, transfer: Bool) -> String? {
        if income { return "Money in" }
        if transfer { return "Transfer" }
        return category.map(categoryWord)
    }

    private func glyph(category: String?, income: Bool, transfer: Bool) -> String {
        if income { return LBGlyph.income }
        if transfer { return LBGlyph.transfer }
        return category.map(CategoryGlyph.symbol) ?? LBGlyph.commitment
    }

    private func badgeSpec(_ badge: DashboardData.CommitmentItem.Badge?) -> (text: String, tone: LBBadgeTone)? {
        switch badge {
        case .trial: (text: "Free trial", tone: .brand)
        case .cancelling: (text: "Cancelling", tone: .urgent)
        case .paused: (text: "Paused", tone: .muted)
        case .cancelled: (text: "Cancelled", tone: .muted)
        case nil: nil
        }
    }

    // MARK: the card both platforms list

    /// A charge's card: its own facts, and the mark when one was set ahead of its day. A
    /// landed charge wears no badge: what its commitment is now is not what it was then.
    private func chargeCard(_ charge: DashboardModel.ChargeItem, selected: Bool = false) -> some View {
        let paid = !charge.isPast && charge.isPaid ? [LBMetaFact(symbol: LBGlyph.paid, text: "Paid")] : []
        return LBCommitmentRow(name: charge.name, facts: charge.facts + paid, amount: charge.amountText,
                               ink: LBColor.dataInk(rank: charge.ink), badge: charge.isPast ? nil : badgeSpec(charge.badge),
                               selected: selected, image: model.commitmentPhotoURL(id: charge.subId))
    }

    private func commitmentCard(_ item: DashboardData.CommitmentItem, selected: Bool = false) -> some View {
        LBCommitmentRow(name: item.name, facts: item.facts, amount: item.amountText,
                        ink: LBColor.dataInk(rank: item.ink), badge: badgeSpec(item.badge), selected: selected,
                        image: model.commitmentPhotoURL(id: item.id))
    }

    /// A card that is also a door, without the list's own chevron drawn over it.
    private func cardLink<Card: View>(_ destination: Destination, @ViewBuilder card: () -> Card) -> some View {
        ZStack {
            NavigationLink(value: destination) { EmptyView() }
                .opacity(0)
            card()
        }
        .lbTapHaptic()
    }

    // MARK: actions shared by both platforms

    private func editCharge(_ charge: DashboardModel.ChargeItem) {
        editingCharge = model.charges(of: charge.subId).first { $0.id == charge.id }
    }

    private func togglePaid(_ charge: DashboardModel.ChargeItem) {
        LBHaptics.tap()
        model.setPaid(subscriptionId: charge.subId, dateISO: charge.dateISO, paid: !charge.isPaid)
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

    /// Edit opens this charge, with the way on to its commitment; Delete removes this charge.
    private func trailingActions(_ charge: DashboardModel.ChargeItem) -> [LBRowAction] {
        [
            LBRowAction("Edit", systemImage: "pencil", tint: LBColor.textSecondary) { editCharge(charge) },
            .destructive("Delete") { deletingCharge = charge },
        ]
    }

    // MARK: - iPhone

    #if os(iOS)
    private var phoneBody: some View {
        List {
            if case .loaded(let data) = model.state {
                phoneTop(data)
                phoneSections(data)
            }
        }
        .lbGroupedList()
        .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search")
        .measured("commitments_showing_filters", .sheet, when: showingFilters)
        .sheet(isPresented: $showingFilters) {
            if case .loaded(let data) = model.state { filterSheet(data) }
        }
        .lbScreenTitle(screenTitle) {
            Button {
                Measure.used("line_3_horizontal_decrease_circle_fill")
                showingFilters = true
            } label: {
                Image(systemName: anyFilter ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
            }
            .accessibilityLabel(anyFilter ? "Filters, some chosen" : "Filters")
            Button {
                Measure.used("add_commitment")
                formTarget = .add
            } label: {
                Image(systemName: "plus")
            }
            .tutorialTarget(.commitmentsAdd)
            .accessibilityLabel("Add a commitment")
        }
    }

    /// Upcoming or Past, and what narrows the list, above the rows.
    private func phoneTop(_ data: DashboardData) -> some View {
        // A section header, not a row: a grouped row clips to its rounded cell, which cut
        // the left edge of the control and of a filter pill sitting in the cell's corners.
        Section {
        } header: {
            VStack(alignment: .leading, spacing: LBSpacing.s3) {
                LBSegmented(selection: $when, choices: [(ListScope.upcoming, "Upcoming"), (ListScope.past, "Past")])
                    .accessibilityLabel("Show")
                    .tutorialTarget(.commitmentsScope)
                narrowedLine(data)
            }
            .textCase(nil)
            .listRowInsets(EdgeInsets())
        }
        .listSectionSpacing(LBSpacing.s3)
    }

    @ViewBuilder
    private func phoneSections(_ data: DashboardData) -> some View {
        let parts = parts(data)
        if parts.rows.isEmpty, parts.unscheduled.isEmpty, parts.toFill.isEmpty {
            Section {
                Text(emptyWords)
                    .lbText(.footnote)
                    .foregroundStyle(LBColor.textSecondary.color)
                    .fixedSize(horizontal: false, vertical: true)
                    .lbListRowBackground()
                if let elsewhere {
                    Button(elsewhere == .past ? "Show Past Charges" : "Show Upcoming Charges") { Measure.used("show_past_charges"); when = elsewhere }
                        .foregroundStyle(LBColor.brandText.color)
                        .lbListRowBackground()
                }
            }
        }
        if !parts.toFill.isEmpty {
            Section {
                placeholderRail(parts.toFill)
                    .lbCardRow()
            } header: {
                LBSectionHeader("Needs details")
            }
        }
        let first = parts.rows.first?.id
        ForEach(grouped(parts.rows, by: \.monthLabel), id: \.label) { group in
            Section {
                ForEach(group.items) { phoneRow($0).tutorialTarget($0.id == first ? .commitmentsFirst : nil) }
            } header: {
                LBSectionHeader(monthHeading(group.label))
            }
        }
        if parts.capped {
            Section {
                Button("Show Later Months") { Measure.used("show_later_months"); showsLaterMonths = true }
                    .foregroundStyle(LBColor.brandText.color)
                    .lbListRowBackground()
            }
        }
        if !parts.unscheduled.isEmpty {
            Section {
                ForEach(parts.unscheduled) { phoneRow($0) }
            } header: {
                LBSectionHeader(unscheduledHeading)
            }
        }
        if !parts.rows.isEmpty || !parts.unscheduled.isEmpty, let also = alsoMatching {
            Section {
                Button(alsoMatchingWords(also)) { Measure.used("show_also_matching"); when = also.scope }
                    .foregroundStyle(LBColor.brandText.color)
                    .lbListRowBackground()
            }
        }
    }

    /// One charge as the card every list wears. A tap opens its commitment; Mark Paid and
    /// Bookmark on the leading swipe, Edit and Delete trailing.
    private func phoneRow(_ charge: DashboardModel.ChargeItem) -> some View {
        cardLink(.commitment(id: charge.subId)) { chargeCard(charge) }
            .lbCardRow()
            .lbRowActions(leading: leadingActions(charge), trailing: trailingActions(charge))
    }

    private func phoneRow(_ item: DashboardData.CommitmentItem) -> some View {
        let bookmark = bookmarkWord(item.id)
        return cardLink(.commitment(id: item.id)) { commitmentCard(item) }
        .lbCardRow()
        .lbRowActions(
            leading: [LBRowAction(bookmark.title, systemImage: bookmark.symbol, tint: LBColor.textSecondary) { toggleBookmark(item.id) }],
            trailing: [
                LBRowAction("Edit", systemImage: "pencil", tint: LBColor.textSecondary) { formTarget = .edit(item.id) },
                .destructive("Delete") { deletingItem = CommitmentRef(id: item.id, name: item.name) },
            ]
        )
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
            }
        }
        .presentationDetents([.medium, .large])
    }
    #endif

    // MARK: - Mac

    /// One row of the Mac table: a charge, a commitment with no date ahead, or a name still
    /// to fill in, with every column's value read once.
    struct LedgerRow: Identifiable {
        enum Kind {
            case charge(DashboardModel.ChargeItem)
            case commitment(DashboardData.CommitmentItem)
            case placeholder(CommitmentPlaceholder)
        }

        let id: String
        let kind: Kind
        let name: String
        /// The ISO day, or a key that sorts the dateless after every day.
        let dateKey: String
        let dateText: String
        let category: String
        let account: String
        let person: String
        let amountText: String
        /// For sorting only: the figure the amount's words show, read back.
        let amount: Double

        var subId: String? {
            switch kind {
            case .charge(let charge): charge.subId
            case .commitment(let item): item.id
            case .placeholder: nil
            }
        }

        static func figure(_ text: String) -> Double {
            let kept = text.filter { $0.isNumber || $0 == "." }
            return Double(kept) ?? 0
        }
    }

    #if os(macOS)
    private func ledgerRows(_ data: DashboardData) -> [LedgerRow] {
        let parts = parts(data)
        let methods = Dictionary(model.editChoices.methods.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
        let members = Dictionary(model.editChoices.members.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
        let toFill = parts.toFill.map { placeholder in
            LedgerRow(id: "p:" + placeholder.id, kind: .placeholder(placeholder), name: placeholder.name,
                      dateKey: "", dateText: "—",
                      category: placeholder.tag.isEmpty ? placeholder.group : categoryWord(placeholder.tag),
                      account: "—", person: "—", amountText: "", amount: -1)
        }
        let charges = parts.rows.map { charge in
            LedgerRow(id: "c:" + charge.id, kind: .charge(charge), name: charge.name, dateKey: charge.dateISO,
                      dateText: LB.parseDate(charge.dateISO).map(LB.longDate) ?? charge.dateISO,
                      category: kindWord(category: charge.category, income: charge.isIncome, transfer: charge.isTransfer) ?? "—",
                      account: charge.methodId.flatMap { methods[$0] } ?? "—",
                      person: charge.memberId.flatMap { members[$0] } ?? "—",
                      amountText: charge.amountText, amount: LedgerRow.figure(charge.amountText))
        }
        let unscheduled = parts.unscheduled.map { item in
            LedgerRow(id: "s:" + item.id, kind: .commitment(item), name: item.name, dateKey: "9999",
                      dateText: unscheduledHeading,
                      category: item.category.map(categoryWord) ?? "—",
                      account: item.methodId.flatMap { methods[$0] } ?? "—",
                      person: item.memberId.flatMap { members[$0] } ?? "—",
                      amountText: item.amountText, amount: LedgerRow.figure(item.amountText))
        }
        return toFill + charges + unscheduled
    }

    private var macBody: some View {
        VStack(spacing: 0) {
            if case .loaded(let data) = model.state {
                let rows = ledgerRows(data)
                narrowedLine(data)
                    .padding(.horizontal, LBSpacing.s4)
                    .padding(.top, LBSpacing.s3)
                macCards(data, rows: rows)
                    .toolbar { macToolbar(data, rows: rows) }
                    .searchable(text: $search, placement: .toolbar, prompt: "Search")
                    .onMacCommand(.markPaid) { togglePaid(selected(rows)) }
                    .onMacCommand(.bookmark) { toggleBookmarks(selected(rows)) }
                    .onMacCommand(.edit) { if let only = selected(rows).first, selected(rows).count == 1 { edit(only) } }
                    .onMacCommand(.toggleInspector) { if selection.isEmpty { selection = rows.first.map { [$0.id] } ?? [] } else { selection = [] } }
                    // The menu bar's Commitment items follow what is chosen here.
                    .onChange(of: menuKey(rows), initial: true) { _, _ in tellMenu(selected(rows)) }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .lbInspector(isPresented: inspectorShown, width: 360) {
                        inspector(rows)
                            .background(LBColor.canvas.color)
                    }
                // A door that named a commitment opens the inspector on it; the picture
                // harness opens it on the first.
                .onAppear {
                    guard selection.isEmpty else { return }
                    if let focus, let row = rows.first(where: { $0.subId == focus }) {
                        selection = [row.id]
                        return
                    }
                    #if DEBUG
                    if ProcessInfo.processInfo.environment["LONGBOOK_SNAPSHOT"] != nil || ProcessInfo.processInfo.environment["LONGBOOK_WINDOW_SNAPSHOT"] != nil,
                       let first = rows.first(where: { $0.subId != nil }) ?? rows.first {
                        selection = [first.id]
                    }
                    #endif
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LBColor.canvas.color)
    }

    private func selected(_ rows: [LedgerRow]) -> [LedgerRow] {
        rows.filter { selection.contains($0.id) }
    }

    /// The charges ahead among the chosen rows: what Mark Paid acts on.
    private func chosenCharges(_ chosen: [LedgerRow]) -> [DashboardModel.ChargeItem] {
        chosen.compactMap {
            if case .charge(let charge) = $0.kind, !charge.isPast { return charge }
            return nil
        }
    }

    private func chosenIds(_ chosen: [LedgerRow]) -> [String] { Array(Set(chosen.compactMap(\.subId))) }

    private func allPaid(_ chosen: [LedgerRow]) -> Bool {
        let charges = chosenCharges(chosen)
        return !charges.isEmpty && charges.allSatisfy(\.isPaid)
    }

    private func allBookmarked(_ chosen: [LedgerRow]) -> Bool {
        let ids = chosenIds(chosen)
        return !ids.isEmpty && ids.allSatisfy { model.bookmarks.contains($0) }
    }

    private func togglePaid(_ chosen: [LedgerRow]) {
        let paid = allPaid(chosen)
        for charge in chosenCharges(chosen) {
            model.setPaid(subscriptionId: charge.subId, dateISO: charge.dateISO, paid: !paid)
        }
    }

    private func toggleBookmarks(_ chosen: [LedgerRow]) {
        let saved = allBookmarked(chosen)
        for id in chosenIds(chosen) where model.bookmarks.contains(id) == saved { model.toggleBookmark(id) }
    }

    /// Changes whenever the menu's answer would: the choice, its paid marks, its bookmarks.
    private func menuKey(_ rows: [LedgerRow]) -> String {
        let chosen = selected(rows)
        return "\(chosen.map(\.id).sorted()) \(chosenCharges(chosen).count) \(allPaid(chosen)) \(allBookmarked(chosen))"
    }

    private func tellMenu(_ chosen: [LedgerRow]) {
        let menu = MenuState.shared
        menu.chosenRows = chosen.count
        menu.chosenCharges = !chosenCharges(chosen).isEmpty
        menu.chosenAllPaid = allPaid(chosen)
        menu.chosenAllBookmarked = allBookmarked(chosen)
        menu.inspectorShown = !chosen.isEmpty
    }

    /// The window's toolbar for this screen: the side, the one Filter menu, then the chosen
    /// rows' actions as one borderless group. Search and + are placed by the system.
    @ToolbarContentBuilder
    private func macToolbar(_ data: DashboardData, rows: [LedgerRow]) -> some ToolbarContent {
        let chosen = selected(rows)
        let paid = allPaid(chosen)
        let saved = allBookmarked(chosen)
        ToolbarItem(placement: .principal) {
            Picker("Show", selection: $when) {
                Text("Upcoming").tag(ListScope.upcoming)
                Text("Past").tag(ListScope.past)
            }
            .pickerStyle(.segmented)
            .help("Upcoming or past charges")
        }
        ToolbarItemGroup(placement: .primaryAction) {
            filterMenu(data)
            Button {
                Measure.used("mark_paid")
                togglePaid(chosen)
            } label: {
                Label(paid ? "Mark Unpaid" : "Mark Paid", systemImage: paid ? LBGlyph.unpaid : LBGlyph.paid)
            }
            .help(paid ? "Mark Unpaid" : "Mark Paid")
            .disabled(chosenCharges(chosen).isEmpty)
            Button {
                Measure.used("bookmark")
                toggleBookmarks(chosen)
            } label: {
                Label(saved ? "Remove Bookmark" : "Bookmark", systemImage: saved ? "bookmark.slash" : "bookmark")
            }
            .help(saved ? "Remove Bookmark" : "Bookmark")
            .disabled(chosenIds(chosen).isEmpty)
            Button {
                Measure.used("edit")
                if let only = chosen.first { edit(only) }
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            .help("Edit")
            .disabled(chosen.count != 1)
        }
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
            Label("Filter", systemImage: anyFilter ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
        }
        .fixedSize()
        .accessibilityLabel(anyFilter ? "Filter, some chosen" : "Filter")
    }

    /// The same cards the phone lists, under their months, beside the inspector: a click
    /// picks one, a double click edits it, and a right click offers what the card can do.
    private func macCards(_ data: DashboardData, rows: [LedgerRow]) -> some View {
        let parts = parts(data)
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
                    if !parts.toFill.isEmpty {
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
                                pickable("c:" + charge.id, rows: rows, chargeCard(charge, selected: selection.contains("c:" + charge.id)))
                                    .tutorialTarget(charge.id == parts.rows.first?.id ? .commitmentsFirst : nil)
                                    .lbCardRow()
                            }
                        } header: {
                            LBSectionHeader(monthHeading(group.label))
                        }
                    }
                    if parts.capped {
                        Section {
                            Button("Show Later Months") { Measure.used("show_later_months"); showsLaterMonths = true }
                                .lbCardRow()
                        }
                    }
                    if !parts.unscheduled.isEmpty {
                        Section {
                            ForEach(parts.unscheduled) { item in
                                pickable("s:" + item.id, rows: rows, commitmentCard(item, selected: selection.contains("s:" + item.id)))
                                    .lbCardRow()
                            }
                        } header: {
                            LBSectionHeader(unscheduledHeading)
                        }
                    }
                    if let also = alsoMatching {
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
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var inspectorShown: Binding<Bool> {
        Binding(get: { !selection.isEmpty }, set: { if !$0 { selection = [] } })
    }

    /// A click chooses the card at once, a second click within a moment opens it, a right
    /// click shows its menu. Timed by hand: a double-click recognizer would hold every
    /// single click back while it waited for the second.
    private func pickable<V: View>(_ id: String, rows: [LedgerRow], _ content: V) -> some View {
        let row = rows.first { $0.id == id }
        // A click only chooses, so the card hovers but has no pressed look. Tab reaches it;
        // Return or Space chooses it as a click does.
        return content
            .lbHoverWash()
            .lbKeyboardFocusable(radius: LBRadius.md) { selection = [id] }
            .contentShape(Rectangle())
            .onTapGesture {
                let now = Date()
                if lastClick.id == id, now.timeIntervalSince(lastClick.at) < 0.35, let row {
                    lastClick = ("", .distantPast)
                    edit(row)
                } else {
                    lastClick = (id, now)
                    selection = [id]
                }
            }
            .contextMenu { if let row { menu([row]) } }
    }

    /// Double click and Edit: a charge opens on itself, a commitment on itself, a name to
    /// fill in on the form.
    private func edit(_ row: LedgerRow) {
        switch row.kind {
        case .charge(let charge): editCharge(charge)
        case .commitment(let item): formTarget = .edit(item.id)
        case .placeholder(let placeholder): formTarget = .fill(placeholder)
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
                Button("Edit Charge") { Measure.used("edit_charge"); editCharge(charge) }
                Button("Edit Commitment") { Measure.used("edit_commitment"); formTarget = .edit(charge.subId) }
                Divider()
                Button("Delete Charge", role: .destructive) { Measure.used("delete_charge"); deletingCharge = charge }
                Button("Delete Commitment", role: .destructive) {
                    Measure.used("delete_commitment")
                    deletingItem = CommitmentRef(id: charge.subId, name: charge.name)
                }
            case .commitment(let item):
                Button(bookmarkWord(item.id).title) { Measure.used("toggle_bookmark"); toggleBookmark(item.id) }
                Button("Edit") { Measure.used("edit"); formTarget = .edit(item.id) }
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
            let charges: [DashboardModel.ChargeItem] = rows.compactMap {
                if case .charge(let charge) = $0.kind, !charge.isPast { return charge }
                return nil
            }
            if !charges.isEmpty {
                Button("Mark \(charges.count) Paid") {
                    Measure.used("mark_paid")
                    for charge in charges { model.setPaid(subscriptionId: charge.subId, dateISO: charge.dateISO, paid: true) }
                }
            }
        }
    }

    /// The selected record, read whole beside the table.
    @ViewBuilder
    private func inspector(_ rows: [LedgerRow]) -> some View {
        let chosen = selected(rows)
        if chosen.count == 1, let row = chosen.first {
            switch row.kind {
            case .charge(let charge):
                CommitmentDetailView(model: model, id: charge.subId, chargeISO: charge.isPast ? nil : charge.dateISO, embedded: true)
                    .id(row.id)
            case .commitment(let item):
                CommitmentDetailView(model: model, id: item.id, embedded: true)
                    .id(row.id)
            case .placeholder(let placeholder):
                VStack(alignment: .leading, spacing: LBSpacing.s3) {
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
            Text(chosen.isEmpty ? "No selection" : "\(chosen.count) selected")
                .lbText(.body)
                .foregroundStyle(LBColor.textTertiary.color)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
