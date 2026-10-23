// A report drawn from the book itself: the total, the accounts, the categories, every
// confirmed charge. Every month the ledger holds as fact draws one; any span of days narrowed
// to accounts, members or categories draws the same way. No projection and no transfer anywhere.
import Foundation

public enum MonthlyReport {
    /// What marks a report as the app's own, so a later draw may replace it and an
    /// AI's never is.
    public static let subtitle = "Drawn by longbook"

    /// The modules a drawn report holds, in order. Public because a screen matches
    /// on one: this charge list carries search and filters, another file's does not.
    public enum Titles {
        public static let total = "Total expenses"
        public static let accounts = "Accounts"
        public static let categories = "Categories"
        public static let charges = "All charges"
    }

    /// The stat labels a draw writes. A screen reads each figure by its label, so these are
    /// part of the format.
    public enum Labels {
        public static let total = "Total expenses"
        public static let charges = "Charges"
        public static let unconfirmed = "Not yet confirmed"
        public static let income = "Money in"
    }

    /// The basis written ahead at the commitment's price, confirmed by nobody. A row
    /// carrying it, or carrying none at all, is a projection: every other reader treats
    /// a missing basis the same way.
    public static let projectedBasis = "plan"

    /// What a report may state: a charge dated today or earlier that something real backs —
    /// a statement, a mail, the owner's word, a paid-tap. A row longbook wrote ahead itself
    /// is nobody's word yet, so no figure here counts one.
    public static func confirmed(_ charges: [Charge], _ today: Date = LB.todayMid()) -> [Charge] {
        charges.filter { $0.date <= today && ($0.row.basis ?? projectedBasis) != projectedBasis }
    }

    /// The first day of every month holding a confirmed charge or credit. A month of
    /// projection alone is no month to report on, the month ahead never draws, and a
    /// transfer fills nothing.
    public static func months(in vault: Vault, today: Date = LB.todayMid()) -> [Date] {
        let firsts = confirmed(allCharges(vault, today) + incomeCharges(vault, today), today)
            .map { LB.firstOfMonth($0.date) }
        return Array(Set(firsts)).sorted()
    }

    /// The months holding confirmed spending: the ones a report is drawn for. A month of
    /// money in alone would read as a ₹0 report, so it draws none.
    public static func spendingMonths(in vault: Vault, today: Date = LB.todayMid()) -> Set<Date> {
        Set(confirmed(allCharges(vault, today), today).map { LB.firstOfMonth($0.date) })
    }

    /// The filename the guide asks for: the month and the year, `july-2026`.
    public static func id(for month: Date) -> String {
        LB.monthYear(month).lowercased().replacingOccurrences(of: " ", with: "-")
    }

    /// Id prefixes for a span: a trip made in the app, and one an AI asked for. Neither can
    /// equal a month's id, which starts with the month's name.
    public static let tripPrefix = "trip"
    public static let requestPrefix = "report"

    /// Whether an id can name a file in reports/: one path part, no dot in front, no slash.
    /// A file's id comes from the file, so a hand-made one must never reach another file.
    public static func isSafeId(_ id: String) -> Bool {
        !id.isEmpty && id.count <= 160 && !id.hasPrefix(".") && !id.contains("/") && !id.contains("\\")
            && !id.contains("..") && id.unicodeScalars.allSatisfy { !CharacterSet.controlCharacters.contains($0) }
    }

    /// Whether longbook redraws this span on its own: one it made, under a span prefix, with
    /// a safe id. A hand-made file wearing the subtitle is left as it is.
    public static func redrawsItself(_ report: Report) -> Bool {
        report.isDrawnSpan && isSafeId(report.id)
            && (report.id.hasPrefix(tripPrefix + "-") || report.id.hasPrefix(requestPrefix + "-"))
    }

    /// A name as a filename part: lowercase letters and digits, other runs become "-".
    public static func slug(_ title: String) -> String {
        let folded = title.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX")).lowercased()
        var out = ""
        for scalar in folded.unicodeScalars {
            if ("a"..."z").contains(Character(scalar)) || ("0"..."9").contains(Character(scalar)) {
                out.unicodeScalars.append(scalar)
            } else if !out.hasSuffix("-") {
                out.append("-")
            }
        }
        let trimmed = out.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return String(trimmed.prefix(40)).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    /// The id a new span gets: `<prefix>-<slug>-<first day>`. The same name, days and scope
    /// asked again keep the id, so a retry redraws one file; anything else already holding
    /// the id moves the new one to "-2", "-3".
    public static func spanId(
        prefix: String, title: String, start: Date, end: Date, scope: ReportScope?, existing: [Report]
    ) -> String {
        let name = slug(title)
        let base = [prefix, name.isEmpty ? nil : name, LB.toISO(start)].compactMap { $0 }.joined(separator: "-")
        let wanted = normalized(scope)
        var candidate = base
        var twin = 2
        while let held = existing.first(where: { $0.id == candidate }) {
            let same = held.isDrawnSpan && held.title == title && held.startDate == LB.toISO(start)
                && held.endDate == LB.toISO(end) && normalized(held.scope) == wanted
            if same { return candidate }
            candidate = "\(base)-\(twin)"
            twin += 1
        }
        return candidate
    }

    /// A scope compared as sets: the same names in another order are the same scope.
    private static func normalized(_ scope: ReportScope?) -> ReportScope? {
        guard let scope, !scope.isEmpty else { return nil }
        return ReportScope(accounts: Set(scope.accounts).sorted(), members: Set(scope.members).sorted(),
                           categories: Set(scope.categories.map(nameKey)).sorted())
    }

    /// The currency a span is about: the one most of its kept confirmed charges are in, so a
    /// trip abroad reads in the money it was spent in. The home currency wins a tie and an empty span.
    public static func spanCurrency(
        vault: Vault, from start: Date, to end: Date, scope: ReportScope?, fallback: String,
        excluding: Set<String> = [], today: Date = LB.todayMid()
    ) -> String {
        let names = Names(vault)
        let charges = confirmed(chargesInRange(vault, from: start, to: end, today).filter { names.inScope($0, scope) }, today)
            .filter { !excluding.contains($0.id) }
        var counts: [String: Int] = [:]
        for charge in charges { counts[charge.currency, default: 0] += 1 }
        guard let most = counts.values.max() else { return fallback }
        if counts[fallback] == most { return fallback }
        return counts.filter { $0.value == most }.keys.sorted().first ?? fallback
    }

    /// A drawn span drawn again from its own name, days, scope and what the owner took out,
    /// carrying its comments. `through` moves the last day (an open trip follows today).
    /// Nil for any report that is not a drawn span.
    public static func redraw(
        _ stored: Report, vault: Vault, through last: Date? = nil, fallbackCurrency: String, today: Date = LB.todayMid()
    ) -> Report? {
        guard stored.isDrawnSpan, let range = stored.range else { return nil }
        // A scope naming an account, person or category the book no longer has would draw an
        // empty report over the owner's; the file is kept until the name is back or fixed.
        guard namesExist(stored.scope, in: vault) else { return nil }
        let end = max(last ?? range.end, range.start)
        let hidden = Set(stored.hiddenIds ?? [])
        let currency = spanCurrency(vault: vault, from: range.start, to: end, scope: stored.scope, fallback: fallbackCurrency,
                                    excluding: stored.removedIds.union(hidden), today: today)
        return draw(
            vault: vault, id: stored.id, title: stored.title, from: range.start, to: end, scope: stored.scope,
            currency: currency, removed: stored.removedIds, hidden: hidden, today: today
        ).carryingComments(from: stored)
    }

    /// Whether every name a scope holds is still one the book wears.
    public static func namesExist(_ scope: ReportScope?, in vault: Vault) -> Bool {
        guard let scope, !scope.isEmpty else { return true }
        let accounts = Set(vault.paymentMethods.map(\.name)).union(["No account"])
        let members = Set(vault.familyMembers.map(\.name))
        let tags = Set((vault.subscriptions.compactMap(\.tag) + (vault.tags ?? []).map(\.name)).map(nameKey)).union([nameKey("No category")])
        return scope.accounts.allSatisfy(accounts.contains) && scope.members.allSatisfy(members.contains)
            && scope.categories.allSatisfy { tags.contains(nameKey($0)) }
    }

    /// One calendar month as a document, named for the month and compared against the month
    /// before. Rows the owner took out of an earlier draw stay out.
    public static func build(
        vault: Vault, month first: Date, currency scope: String, removed: Set<String> = [], hidden: Set<String> = [],
        today: Date = LB.todayMid()
    ) -> Report {
        let last = LB.addDays(LB.addMonths(first, 1), -1)
        let priorFirst = LB.addMonths(first, -1)
        var report = draw(
            vault: vault, id: id(for: first), title: LB.monthYear(first), from: first, to: last, scope: nil,
            currency: scope, removed: removed, hidden: hidden,
            comparedTo: (priorFirst, LB.addDays(first, -1), "vs \(monthOnly(priorFirst))"), today: today
        )
        report.period = String(LB.toISO(first).prefix(7))
        return report
    }

    /// Any span of days, narrowed to the accounts, members and categories named: confirmed
    /// charges only, one currency's figures, every row listed. A charge `removed` is listed
    /// last and counted nowhere; one `hidden` is not listed. The change is drawn only against
    /// a span the caller names, when both are whole.
    public static func draw(
        vault: Vault, id: String, title: String, from start: Date, to end: Date, scope: ReportScope?,
        currency: String, removed: Set<String> = [], hidden: Set<String> = [],
        comparedTo prior: (start: Date, end: Date, label: String)? = nil, today: Date = LB.todayMid()
    ) -> Report {
        let names = Names(vault)
        let within = { (charge: Charge) in names.inScope(charge, scope) }
        let all = chargesInRange(vault, from: start, to: end, today).filter(within)
        let backed = confirmed(all, today).filter { !hidden.contains($0.id) }
        let kept = backed.filter { !removed.contains($0.id) }
        let taken = backed.filter { removed.contains($0.id) }
        let cover = coverage(all, currency: currency, removed: removed.union(hidden), today: today)
        let scoped = cover.confirmed
        let total = scoped.reduce(0) { $0 + $1.amount }
        let income = confirmed(incomeCharges(vault, today), today)
            .filter { $0.date >= start && $0.date <= end && $0.currency == currency && within($0) }
            .reduce(0) { $0 + $1.amount }

        var totalStat = ReportStat(label: Labels.total, amount: total, currency: currency)
        if let prior {
            let before = chargesInRange(vault, from: prior.start, to: prior.end, today).filter(within)
            let priorCover = coverage(before, currency: currency, removed: [], today: today)
            let priorTotal = priorCover.confirmed.reduce(0) { $0 + $1.amount }
            // A change needs two whole spans in one currency. A span still running is a few of
            // its days, and a part-covered one is some of its evidence; against a whole one
            // either reports a fall that never happened, which `deltaIsGood` would call good news.
            if end < today && priorTotal > 0 && !cover.partCovered && !priorCover.partCovered {
                totalStat.deltaPct = ((total - priorTotal) / priorTotal * 1000).rounded() / 10
                totalStat.deltaIsGood = total <= priorTotal
                totalStat.deltaLabel = prior.label
            }
        }
        var stats = [totalStat]
        // Money in another currency is its own total under the same label, never blended in;
        // the charge count is every row the list holds, whatever its currency.
        var others: [String: Double] = [:]
        for charge in kept where charge.currency != currency { others[charge.currency, default: 0] += charge.amount }
        for (other, sum) in others.sorted(by: { $0.key < $1.key }) {
            stats.append(ReportStat(label: Labels.total, amount: sum, currency: other))
        }
        stats.append(ReportStat(label: Labels.charges, value: "\(kept.count)"))
        // Passed charges nobody has confirmed are named and counted apart, so the total beside
        // them is read for what it is.
        if cover.unconfirmed > 0 {
            stats.append(ReportStat(label: Labels.unconfirmed, value: "\(cover.unconfirmed)"))
        }
        if income > 0 {
            stats.append(ReportStat(label: Labels.income, amount: income, currency: currency))
        }
        var modules: [ReportModule] = [.stats(StatsModule(id: nil, title: Titles.total, comment: nil, stats: stats))]

        // Every account that paid, biggest first, the unassigned bucket among them when it
        // holds money. None is dropped: a share describes a total the reader can see. Only
        // the scoped currency enters a ring.
        var byAccount: [String: Double] = [:]
        for charge in scoped { byAccount[names.account(charge) ?? "No account", default: 0] += charge.amount }
        let accounts = ring(byAccount, currency)
        if !accounts.isEmpty {
            modules.append(.donut(DonutModule(id: nil, title: Titles.accounts, comment: nil, currency: currency, slices: accounts)))
        }
        var byTag: [String: Double] = [:]
        for charge in scoped { byTag[names.category(charge), default: 0] += charge.amount }
        let categories = ring(byTag, currency)
        if !categories.isEmpty {
            modules.append(.donut(DonutModule(id: nil, title: Titles.categories, comment: nil, currency: currency, slices: categories)))
        }

        // The record carries every currency, biggest first; what was taken out follows, marked.
        let rows = kept.sorted { $0.amount > $1.amount }.map { names.row($0, removed: false) }
            + taken.sorted { $0.amount > $1.amount }.map { names.row($0, removed: true) }
        if !rows.isEmpty {
            modules.append(.transactions(TransactionsModule(id: nil, title: Titles.charges, comment: nil, rows: rows)))
        }

        return Report(
            version: 2, id: id, title: title, subtitle: subtitle, createdAt: LB.toISO(today), period: nil,
            startDate: LB.toISO(start), endDate: LB.toISO(end), scope: scope?.isEmpty == false ? scope : nil,
            hiddenIds: hidden.isEmpty ? nil : hidden.sorted(), currency: currency, modules: modules
        )
    }

    /// How much of a span a report can account for, in the currency it is about: that
    /// currency's passed spending charges, and the confirmed part still in the report. They
    /// differ when the span holds money nobody has accounted for, which the report then says.
    static func coverage(_ charges: [Charge], currency scope: String, removed: Set<String>, today: Date)
        -> (past: [Charge], confirmed: [Charge], unconfirmed: Int, partCovered: Bool) {
        let past = charges.filter { $0.date <= today && $0.currency == scope }
        let backed = confirmed(past, today)
        let known = backed.filter { !removed.contains($0.id) }
        let unconfirmed = past.count - backed.count
        return (past, known, unconfirmed, unconfirmed > 0)
    }

    /// One month's coverage, as the month draws it.
    static func coverage(_ vault: Vault, first: Date, currency scope: String, today: Date)
        -> (past: [Charge], confirmed: [Charge], partCovered: Bool) {
        let last = LB.addDays(LB.addMonths(first, 1), -1)
        let cover = coverage(chargesInRange(vault, from: first, to: last, today), currency: scope, removed: [], today: today)
        return (cover.past, cover.confirmed, cover.partCovered)
    }

    /// Slices biggest first; the label breaks a tie, so one span draws one order.
    private static func ring(_ sums: [String: Double], _ currency: String) -> [ReportSlice] {
        sums.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .map { ReportSlice(label: $0.key, amount: $0.value, currency: currency) }
    }

    private static func monthOnly(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = LB.calendar
        formatter.dateFormat = "MMMM"
        return formatter.string(from: date)
    }

    /// The names a charge's ids stand for, and whether a charge is inside a scope.
    private struct Names {
        let accounts: [String: String]
        let members: [String: String]

        init(_ vault: Vault) {
            accounts = Dictionary(vault.paymentMethods.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
            members = Dictionary(vault.familyMembers.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
        }

        func account(_ charge: Charge) -> String? { charge.sub.paymentMethodId.flatMap { accounts[$0] } }
        func member(_ charge: Charge) -> String? { charge.sub.familyMemberId.flatMap { members[$0] } }
        func category(_ charge: Charge) -> String {
            let tag = charge.sub.tag?.trimmingCharacters(in: .whitespaces) ?? ""
            return tag.isEmpty ? "No category" : tag
        }

        /// Names are matched as the owner wrote them; a list left empty narrows nothing. "No
        /// account" stands for charges billed to none, as the ring names them.
        func inScope(_ charge: Charge, _ scope: ReportScope?) -> Bool {
            guard let scope, !scope.isEmpty else { return true }
            if !scope.accounts.isEmpty, !scope.accounts.contains(account(charge) ?? "No account") { return false }
            if !scope.members.isEmpty, !scope.members.contains(member(charge) ?? "") { return false }
            // A category is one name in any casing, as the rest of the app groups it.
            if !scope.categories.isEmpty, !scope.categories.contains(where: { nameKey($0) == nameKey(category(charge)) }) { return false }
            return true
        }

        func row(_ charge: Charge, removed: Bool) -> ReportRow {
            ReportRow(
                id: charge.id, name: charge.sub.name, date: LB.toISO(charge.date), amount: charge.amount,
                currency: charge.currency, category: charge.sub.tag, account: account(charge), member: member(charge),
                removed: removed ? true : nil
            )
        }
    }
}
