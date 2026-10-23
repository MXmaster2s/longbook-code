import DesignSystem
import LongbookCore
import SwiftUI

/// One report as a document: its name and days, the cards the dashboard draws, every charge
/// the way the charges screen lists it, what was taken out, and sharing. What this screen
/// draws is what a shared link draws; a module's comment shows quietly beneath it.
struct ReportDetailView: View {
    let model: DashboardModel
    let id: String
    var auth: AuthViewModel?
    /// Prose modules the reader has opened past their first lines, by position.
    @State private var openProse: Set<Int> = []
    /// Bumped when the card below makes or ends a link, so the top button follows it.
    @State private var shareRevision = 0
    /// The charge list's narrowing; a tap on a ring or a tile sets it too.
    @State private var narrowing = ChargeNarrowing()

    private static let sharingAnchor = "sharing"

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: LBSpacing.s6) {
                    if let report = model.report(id: id) {
                        header(report) { jumpToSharing(proxy) }
                        ForEach(Array(report.modules.enumerated()), id: \.offset) { index, module in
                            moduleView(module, at: index, report: report)
                        }
                        if let auth {
                            section("Sharing") {
                                ReportSharingCard(model: model, auth: auth, reportId: id, revision: $shareRevision)
                            }
                            .id(Self.sharingAnchor)
                        }
                    } else {
                        LBCard {
                            Text("This report is no longer in the folder.")
                                .lbText(.footnote)
                                .foregroundStyle(LBColor.textTertiary.color)
                        }
                    }
                }
                .padding(LBSpacing.s4)
                #if os(macOS)
                .padding(.top, LBSpacing.s6)
                .frame(maxWidth: 760)
                #else
                .frame(maxWidth: 700)
                #endif
                .frame(maxWidth: .infinity)
            }
            // The report's heading is in the page; the bar holds the way back and Share.
            .lbScreenTitle("", large: false) {
                if let auth, model.report(id: id) != nil {
                    ReportShareJump(model: model, auth: auth, reportId: id, revision: shareRevision) {
                        jumpToSharing(proxy)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LBColor.canvas.color)
    }

    private func jumpToSharing(_ proxy: ScrollViewProxy) {
        withAnimation(.snappy(duration: 0.25)) {
            proxy.scrollTo(Self.sharingAnchor, anchor: .top)
        }
    }

    // MARK: header

    /// The report's name, the days it covers, and what it was narrowed to. A file that
    /// settles no days says when it was written instead, named as that.
    private func header(_ report: Report, jump: @escaping () -> Void) -> some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: LBSpacing.s1) {
                if report.id == model.openTripId {
                    LBBadge("Trip mode is on", tone: .brand)
                }
                Text(report.title)
                    .lbText(.displayLG)
                    .foregroundStyle(LBColor.textPrimary.color)
                    .fixedSize(horizontal: false, vertical: true)
                if let days = report.rangeName {
                    // A whole calendar month is already in the title; only other spans need their days.
                    if !titleNamesMonth(report) {
                        Text(days)
                            .lbText(.bodySM)
                            .foregroundStyle(LBColor.textSecondary.color)
                    }
                } else if let written = report.writtenNote {
                    Text(written)
                        .lbText(.bodySM)
                        .foregroundStyle(LBColor.textSecondary.color)
                }
                if let scope = report.scopeLine {
                    Text(scope)
                        .lbText(.footnote)
                        .foregroundStyle(LBColor.textTertiary.color)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            #if os(macOS)
            // No navigation bar on the Mac: Share sits at the heading's trailing edge.
            Spacer(minLength: LBSpacing.s3)
            if let auth {
                ReportShareJump(model: model, auth: auth, reportId: id, revision: shareRevision, jump: jump)
            }
            #endif
        }
    }

    /// Whether the title is the month the report covers, first day to last.
    private func titleNamesMonth(_ report: Report) -> Bool {
        guard let range = report.range, report.periodName == report.title else { return false }
        let first = LB.firstOfMonth(range.start)
        let last = LB.addDays(LB.addMonths(first, 1), -1)
        return range.start == first && range.end == last
    }

    // MARK: sections

    /// A heading over its card, the way a document names its parts; a note sits at the end
    /// of the line. The heading is the report author's own words, never re-cased.
    private func section<Content: View>(_ title: String?, note: String? = nil, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: LBSpacing.s2) {
            if title != nil || note != nil {
                HStack(alignment: .firstTextBaseline) {
                    if let title {
                        Text(title)
                            .lbText(.screenTitle)
                            .foregroundStyle(LBColor.textPrimary.color)
                    }
                    Spacer(minLength: LBSpacing.s2)
                    if let note {
                        Text(note)
                            .lbText(.footnote)
                            .foregroundStyle(LBColor.textTertiary.color)
                    }
                }
            }
            content()
        }
    }

    @ViewBuilder
    private func moduleView(_ module: ReportModule, at index: Int, report: Report) -> some View {
        switch module {
        case .stats(let stats):
            section(stats.title) { annotated(stats.comment) { LBPanel { statsView(stats) } } }
        case .prose(let prose):
            section(prose.title) { annotated(prose.comment) { LBPanel { proseView(prose, at: index) } } }
        case .donut(let donut):
            section(donut.title) {
                annotated(donut.comment) {
                    LBPanel {
                        if donut.title == MonthlyReport.Titles.categories {
                            categoryTiles(donut, report: report)
                        } else {
                            donutView(donut, report: report)
                        }
                    }
                }
            }
        case .bars(let bars):
            section(bars.title) { annotated(bars.comment) { LBPanel { barsView(bars) } } }
        case .transactions(let list):
            if list.title == MonthlyReport.Titles.charges {
                chargesSections(list, report: report)
            } else {
                section(list.title) {
                    annotated(list.comment) {
                        VStack(spacing: LBSpacing.s2) {
                            ForEach(Array(list.rows.enumerated()), id: \.offset) { _, row in
                                chargeRow(row, ink: LBColor.neutralFold, report: report, removed: false)
                            }
                        }
                    }
                }
            }
        case .unknown(let type, let fields):
            let heading = stringField(fields, "title") ?? type.replacingOccurrences(of: "_", with: " ")
            section(heading) { annotated(stringField(fields, "comment")) { LBPanel { genericView(fields) } } }
        }
    }

    private func stringField(_ fields: [String: ReportValue], _ key: String) -> String? {
        if case .string(let text)? = fields[key] { return text }
        return nil
    }

    /// The owner's annotation and a viewer's lines, worn under the card they belong to.
    private func annotated<Content: View>(_ comment: String?, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: LBSpacing.s2) {
            content()
            if let comment, !comment.isEmpty {
                HStack(alignment: .firstTextBaseline, spacing: LBSpacing.s2) {
                    Image(systemName: "bubble.left")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(LBColor.brandText.color)
                        .accessibilityLabel("Comment")
                    Text(comment)
                        .lbText(.footnote)
                        .foregroundStyle(LBColor.textSecondary.color)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, LBSpacing.s2)
            }
        }
    }

    // MARK: total expenses

    /// The first money stat is the figure, drawn as the dashboard draws a month's total, with
    /// any other currency's sum under the same label beside it; the change follows, and
    /// every other stat reads as one line under it.
    private func statsView(_ module: StatsModule) -> some View {
        let lead = module.stats.firstIndex { $0.amount != nil && $0.currency != nil }
        let leadLabel = lead.map { module.stats[$0].label }
        let isCompanion = { (index: Int, stat: ReportStat) in index != lead && stat.amount != nil && stat.currency != nil && stat.label == leadLabel }
        let companions = module.stats.enumerated().filter { isCompanion($0.offset, $0.element) }.map(\.element)
        let rest = module.stats.enumerated().filter { $0.offset != lead && !isCompanion($0.offset, $0.element) }.map(\.element)
        return VStack(alignment: .leading, spacing: LBSpacing.s2) {
            if let lead {
                let stat = module.stats[lead]
                HStack(alignment: .firstTextBaseline, spacing: LBSpacing.s2) {
                    Text(fmtMoney(stat.amount ?? 0, stat.currency ?? ""))
                        .lbText(.statNumber)
                        .foregroundStyle(LBColor.textPrimary.color)
                        .lineLimit(1)
                        .minimumScaleFactor(0.55)
                }
                if let delta = stat.deltaPct {
                    Text(deltaWords(delta, against: stat.deltaLabel))
                        .lbText(.footnote)
                        .foregroundStyle(LBColor.textSecondary.color)
                }
                // Another currency's sum is its own fact on its own line, never added in.
                ForEach(Array(companions.enumerated()), id: \.offset) { _, other in
                    Text("+ \(fmtMoney(other.amount ?? 0, other.currency ?? "")) in \(other.currency ?? "")")
                        .lbText(.footnote)
                        .foregroundStyle(LBColor.textSecondary.color)
                }
            }
            let line = rest.map(statWords).joined(separator: " · ")
            if !line.isEmpty {
                Text(line)
                    .lbText(.footnote)
                    .foregroundStyle(LBColor.textTertiary.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// "0.1% more than June": the change in words, under the figure. The file words what it is
    /// against ("vs June"), and the words follow it; a direction is stated, never drawn as an alarm.
    private func deltaWords(_ percent: Double, against label: String?) -> String {
        let size = String(format: "%.1f%%", abs(percent))
        let flat = abs(percent) < 1
        let direction = flat ? "About the same" : "\(size) \(percent >= 0 ? "more" : "less")"
        guard let label, !label.isEmpty else { return direction }
        if label.hasPrefix("vs ") { return "\(direction) \(flat ? "as" : "than") \(label.dropFirst(3))" }
        return "\(direction) \(label)"
    }

    /// "20 charges", "4 not yet confirmed", "Money in ₹1,50,000": a count wears its label
    /// after it, money keeps its label first.
    private func statWords(_ stat: ReportStat) -> String {
        if let amount = stat.amount, let currency = stat.currency { return "\(stat.label) \(fmtMoney(amount, currency))" }
        guard let value = stat.value else { return stat.label }
        return "\(value) \(stat.label.prefix(1).lowercased() + stat.label.dropFirst())"
    }

    // MARK: rings and tiles

    /// A ring is one currency; a slice in any other is listed with its own sum and no share.
    private func rows(of module: DonutModule, report: Report) -> (scope: String, scoped: [ReportSlice], foreign: [ReportSlice], total: Double) {
        let scope = module.currency ?? report.currency ?? module.slices.first?.currency ?? ""
        let scoped = module.slices.filter { $0.currency == scope }
        let total = scoped.filter { $0.amount > 0 && $0.amount.isFinite }.reduce(0) { $0 + $1.amount }
        return (scope, scoped, module.slices.filter { $0.currency != scope }, total)
    }

    private func donutView(_ module: DonutModule, report: Report) -> some View {
        let ring = rows(of: module, report: report)
        let narrowsAccounts = module.title == MonthlyReport.Titles.accounts
        return VStack(alignment: .leading, spacing: LBSpacing.s3) {
            LBDonut(
                slices: ring.scoped.enumerated().map { .init(value: max($0.element.amount, 0), ink: LBColor.dataInk(rank: $0.offset)) },
                // The legend names each share; the centre holds the ring's whole.
                centerTitle: ring.total > 0 ? fmtMoney(ring.total, ring.scope) : "—",
                centerNote: ring.total > 0 ? "Total" : "Nothing yet"
            )
            .frame(maxWidth: 190)
            .frame(maxWidth: .infinity)
            VStack(spacing: 0) {
                ForEach(Array(ring.scoped.enumerated()), id: \.offset) { rank, slice in
                    legendRow(
                        name: shown(slice.label, in: module.title), ink: rank, amountText: fmtMoney(slice.amount, slice.currency),
                        share: ring.total > 0 && slice.amount > 0 ? slice.amount / ring.total : nil,
                        picked: narrowsAccounts && narrowing.account == slice.label
                    ) {
                        guard narrowsAccounts else { return }
                        narrowing.account = narrowing.account == slice.label ? nil : slice.label
                    }
                }
                ForEach(Array(ring.foreign.enumerated()), id: \.offset) { _, slice in
                    legendRow(name: shown(slice.label, in: module.title), ink: nil, amountText: fmtMoney(slice.amount, slice.currency), share: nil, picked: false) {}
                }
            }
        }
    }

    /// The dashboard's legend row: swatch, name, share, amount. A tap narrows the charge
    /// list below to this account, and a second tap widens it again.
    private func legendRow(
        name: String, ink: Int?, amountText: String, share: Double?, picked: Bool, tap: @escaping () -> Void
    ) -> some View {
        Button(action: tap) {
            HStack(spacing: LBSpacing.s2) {
                Group {
                    if let ink {
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(LBColor.dataInk(rank: ink).color)
                    } else {
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .strokeBorder(LBColor.textQuaternary.color, lineWidth: 1)
                    }
                }
                .frame(width: 8, height: 8)
                Text(name)
                    .lbText(.footnote)
                    .foregroundStyle(picked ? LBColor.brandText.color : LBColor.textSecondary.color)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: LBSpacing.s1)
                Text(share.map(sharePct) ?? "—")
                    .lbText(.footnote)
                    .foregroundStyle(LBColor.textPrimary.color)
                    .layoutPriority(1)
                Text(amountText)
                    .lbText(.footnote)
                    .foregroundStyle(LBColor.textTertiary.color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .layoutPriority(1)
            }
            .frame(minHeight: 30)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Narrows the charges below to this account")
    }

    /// The dashboard's category tiles, in a strip: glyph, name, amount, share. A tap narrows
    /// the charge list below to that category.
    private func categoryTiles(_ module: DonutModule, report: Report) -> some View {
        let ring = rows(of: module, report: report)
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: LBSpacing.s2) {
                ForEach(Array(ring.scoped.enumerated()), id: \.offset) { rank, slice in
                    Button {
                        narrowing.category = narrowing.category == slice.label ? nil : slice.label
                    } label: {
                        categoryTile(
                            name: slice.label, ink: LBColor.dataInk(rank: rank), amountText: fmtMoney(slice.amount, slice.currency),
                            share: ring.total > 0 && slice.amount > 0 ? slice.amount / ring.total : nil,
                            picked: narrowing.category == slice.label
                        )
                    }
                    .buttonStyle(.plain)
                    .lbTapHaptic()
                }
                ForEach(Array(ring.foreign.enumerated()), id: \.offset) { _, slice in
                    categoryTile(name: slice.label, ink: LBColor.neutralFold, amountText: fmtMoney(slice.amount, slice.currency), share: nil, picked: false)
                }
            }
        }
    }

    private func categoryTile(name: String, ink: LBColorValue, amountText: String, share: Double?, picked: Bool) -> some View {
        VStack(alignment: .leading, spacing: LBSpacing.s2) {
            Image(systemName: CategoryGlyph.symbol(name))
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(ink.color)
                .frame(width: 30, height: 30)
                .background(LBColor.chrome.color, in: RoundedRectangle(cornerRadius: LBRadius.xs, style: .continuous))
            Text(categoryWord(name))
                .lbText(.footnote)
                .foregroundStyle(LBColor.textSecondary.color)
                .lineLimit(1)
            LBAmount(amountText, prominence: .inline)
                .foregroundStyle(LBColor.textPrimary.color)
            Text(share.map(sharePct) ?? "—")
                .lbText(.footnote)
                .foregroundStyle(LBColor.textTertiary.color)
        }
        .padding(LBSpacing.s3)
        // minWidth, not width: money never clips, so a long amount stretches its tile.
        .frame(minWidth: 124, alignment: .topLeading)
        .background(LBColor.sunken.color, in: RoundedRectangle(cornerRadius: LBRadius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: LBRadius.md, style: .continuous)
                .strokeBorder(picked ? LBColor.brand.color : LBColor.hairline.color, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Narrows the charges below to this category")
    }

    private func sharePct(_ share: Double) -> String {
        let percent = share * 100
        return percent >= 10 ? "\(Int(percent.rounded()))%" : String(format: "%.1f%%", (percent * 10).rounded() / 10)
    }

    // MARK: other kinds

    /// Three lines to read, the rest behind one word. A text that plainly fits is never
    /// clamped; a long one opens in place and closes again.
    private func proseView(_ module: ProseModule, at index: Int) -> some View {
        let long = module.text.count > 240 || module.text.filter { $0 == "\n" }.count >= 3
        let open = openProse.contains(index)
        return VStack(alignment: .leading, spacing: LBSpacing.s2) {
            Text(module.text)
                .lbText(.body)
                .foregroundStyle(LBColor.textSecondary.color)
                .lineLimit(long && !open ? 3 : nil)
                .fixedSize(horizontal: false, vertical: true)
            if long {
                Button {
                    if open { openProse.remove(index) } else { openProse.insert(index) }
                } label: {
                    Text(open ? "Less" : "More")
                        .lbText(.footnote)
                        .foregroundStyle(LBColor.brandText.color)
                        .frame(minHeight: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .lbTapHaptic()
            }
        }
    }

    /// A chart's label as the reader sees it: a category in its proper case, as the month
    /// reports write it, whatever the title an AI gave the chart.
    private func shown(_ label: String, in title: String?) -> String {
        title?.localizedCaseInsensitiveContains("categor") == true ? categoryWord(label) : label
    }

    private func barsView(_ module: BarsModule) -> some View {
        let top = module.bars.map(\.amount).max() ?? 0
        return HStack(alignment: .bottom, spacing: LBSpacing.s2) {
            ForEach(Array(module.bars.enumerated()), id: \.offset) { _, bar in
                VStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(LBColor.chartBar.color)
                        .frame(height: top > 0 ? max(3, 72 * bar.amount / top) : 3)
                        .frame(maxWidth: .infinity)
                    Text(shown(bar.label, in: module.title))
                        .lbText(.footnote)
                        .foregroundStyle(LBColor.textTertiary.color)
                        .lineLimit(1)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(shown(bar.label, in: module.title)), \(module.currency.map { fmtMoney(bar.amount, $0) } ?? String(bar.amount))")
            }
        }
    }

    /// A module this version doesn't know still shows its data — generically, in the
    /// house style. The AI is limited to our design, never to our module list.
    private func genericView(_ fields: [String: ReportValue]) -> some View {
        let claimed = ["title", "comment"].filter { stringField(fields, $0) != nil }
        return VStack(alignment: .leading, spacing: LBSpacing.s2) {
            ForEach(fields.keys.sorted().filter { !claimed.contains($0) }, id: \.self) { key in
                genericField(key, fields[key] ?? .null)
            }
        }
    }

    @ViewBuilder
    private func genericField(_ key: String, _ value: ReportValue) -> some View {
        switch value {
        case .array(let items):
            VStack(alignment: .leading, spacing: LBSpacing.s1) {
                Text(key.replacingOccurrences(of: "_", with: " "))
                    .lbText(.footnote)
                    .foregroundStyle(LBColor.textTertiary.color)
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    Text(genericWord(item))
                        .lbText(.bodySM)
                        .foregroundStyle(LBColor.textSecondary.color)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        default:
            HStack(alignment: .firstTextBaseline, spacing: LBSpacing.s2) {
                Text(key.replacingOccurrences(of: "_", with: " "))
                    .lbText(.footnote)
                    .foregroundStyle(LBColor.textTertiary.color)
                Spacer(minLength: LBSpacing.s2)
                Text(genericWord(value))
                    .lbText(.bodySM)
                    .foregroundStyle(LBColor.textPrimary.color)
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// One JSON value as reading text. Objects join as "key value" pairs; money can't
    /// be assumed, so numbers stay plain.
    private func genericWord(_ value: ReportValue) -> String {
        switch value {
        case .string(let text): return text
        case .integer(let number): return String(number)
        case .number(let number):
            // Int(Double) traps outside Int64's range — a huge figure prints as it is.
            let wholeAndSafe = number == number.rounded() && number.magnitude < 9_007_199_254_740_992
            return wholeAndSafe ? String(Int(number)) : String(number)
        case .bool(let flag): return flag ? "Yes" : "No"
        case .null: return "—"
        case .array(let items): return items.map(genericWord).joined(separator: ", ")
        case .object(let object):
            return object.keys.sorted()
                .map { "\($0.replacingOccurrences(of: "_", with: " ")) \(genericWord(object[$0] ?? .null))" }
                .joined(separator: " · ")
        }
    }

    // MARK: charges

    /// The drawn charge list, the way the charges screen lists a month: searched, narrowed,
    /// each row with its date, category, member and account and the category's ink. What
    /// was taken out follows under its own heading.
    @ViewBuilder
    private func chargesSections(_ list: TransactionsModule, report: Report) -> some View {
        let kept = list.rows.filter { $0.removed != true }
        let removed = list.rows.filter { $0.removed == true }
        let shown = narrowing.apply(to: kept)
        let inks = categoryInks(report)
        section(list.title, note: shown.count == kept.count ? "\(kept.count)" : "\(shown.count) of \(kept.count)") {
            annotated(list.comment) {
                VStack(alignment: .leading, spacing: LBSpacing.s2) {
                    searchField
                    filters(kept)
                    if shown.isEmpty {
                        LBCard {
                            Text(kept.isEmpty ? "Every charge was removed from this report." : "No charges match. Clear the search or a filter.")
                                .lbText(.footnote)
                                .foregroundStyle(LBColor.textTertiary.color)
                        }
                    }
                    // Eager, not lazy: the button above scrolls to the sharing card that follows
                    // this list, and a lazy row has no height until it is built.
                    ForEach(Array(shown.enumerated()), id: \.offset) { _, row in
                        chargeRow(row, ink: inks(row), report: report, removed: false)
                    }
                }
            }
        }
        if !removed.isEmpty {
            section("Removed from this report", note: "\(removed.count)") {
                VStack(spacing: LBSpacing.s2) {
                    ForEach(Array(removed.enumerated()), id: \.offset) { _, row in
                        chargeRow(row, ink: inks(row), report: report, removed: true)
                    }
                }
            }
        }
    }

    /// The category ring's order gives every category its ink, so the list and the tiles
    /// agree; a row outside the ring wears the neutral fold.
    private func categoryInks(_ report: Report) -> (ReportRow) -> LBColorValue {
        var rank: [String: Int] = [:]
        for module in report.modules {
            guard case .donut(let donut) = module, donut.title == MonthlyReport.Titles.categories else { continue }
            for (index, slice) in donut.slices.enumerated() where rank[slice.label] == nil { rank[slice.label] = index }
        }
        return { row in
            let category = ChargeNarrowing.category(row)
            return rank[category.isEmpty ? "No category" : category].map { LBColor.dataInk(rank: $0) } ?? LBColor.neutralFold
        }
    }

    /// One charge as the charges screen lists it, from the fields the file carries. A row
    /// that names its charge can be taken out, put back, or dropped for good.
    private func chargeRow(_ row: ReportRow, ink: LBColorValue, report: Report, removed: Bool) -> some View {
        let category = ChargeNarrowing.category(row)
        let facts: [LBMetaFact] = [
            row.date.flatMap { LB.parseDate($0) }.map { LBMetaFact(symbol: LBGlyph.date, text: LB.shortDate($0)) },
            LBMetaFact(symbol: LBGlyph.category, text: category.isEmpty ? CommitmentsView.noCategory : categoryWord(category)),
            row.member.map { LBMetaFact(symbol: LBGlyph.member, text: $0) },
            row.account.map { LBMetaFact(symbol: LBGlyph.account, text: $0) },
        ].compactMap { $0 }
        return LBCommitmentRow(name: row.name, facts: facts, amount: fmtMoney(row.amount, row.currency), ink: removed ? LBColor.neutralFold : ink)
            .opacity(removed ? 0.6 : 1)
            .contextMenu {
                if let rowId = row.id {
                    if removed {
                        Button {
                            model.setReportRow(rowId, in: report.id, to: .kept)
                        } label: {
                            Label("Put back", systemImage: "arrow.uturn.backward")
                        }
                        Button(role: .destructive) {
                            model.setReportRow(rowId, in: report.id, to: .hidden)
                        } label: {
                            Label("Remove for good", systemImage: "trash")
                        }
                    } else {
                        Button(role: .destructive) {
                            model.setReportRow(rowId, in: report.id, to: .removed)
                        } label: {
                            Label("Remove from report", systemImage: "minus.circle")
                        }
                    }
                }
            }
    }

    // MARK: narrowing

    private var searchField: some View {
        HStack(spacing: LBSpacing.s2) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(LBColor.textTertiary.color)
            TextField("", text: $narrowing.search, prompt: Text("Search").foregroundStyle(LBColor.textTertiary.color))
                .textFieldStyle(.plain)
                .lbText(.bodySM)
                .foregroundStyle(LBColor.textPrimary.color)
        }
        .padding(.horizontal, LBSpacing.s3)
        .padding(.vertical, LBSpacing.s2)
        .background(LBColor.card.color, in: RoundedRectangle(cornerRadius: LBRadius.sm, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: LBRadius.sm, style: .continuous)
                .strokeBorder(LBColor.hairline.color, lineWidth: 1)
        )
    }

    /// The narrowings the rows can answer, each on offer only when it has a choice to make.
    @ViewBuilder
    private func filters(_ rows: [ReportRow]) -> some View {
        let categories = narrowing.categoryOptions(rows)
        let accounts = ChargeNarrowing.names(rows.map(\.account))
        let members = ChargeNarrowing.names(rows.map(\.member))
        let currencies = Array(Set(rows.map(\.currency))).sorted()
        if categories.count > 1 || accounts.count > 1 || members.count > 1 || currencies.count > 1 {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: LBSpacing.s2) {
                    if categories.count > 1 {
                        filterMenu("Category", symbol: LBGlyph.category, selection: $narrowing.category, options: categories)
                    }
                    if accounts.count > 1 {
                        filterMenu("Account", symbol: LBGlyph.account, selection: $narrowing.account, options: accounts.map { ($0, $0) })
                    }
                    if members.count > 1 {
                        filterMenu("Person", symbol: LBGlyph.member, selection: $narrowing.member, options: members.map { ($0, $0) })
                    }
                    if currencies.count > 1 {
                        filterMenu("Currency", symbol: LBGlyph.currency, selection: $narrowing.currency, options: currencies.map { ($0, $0) })
                    }
                    if narrowing.isNarrowed {
                        chip("Clear", symbol: "xmark") { narrowing.clear() }
                    }
                }
            }
        }
    }

    /// A chip that opens a menu, wearing its choice — the same shape the charges screen's
    /// filter row uses.
    private func filterMenu(
        _ title: String, symbol: String, selection: Binding<String?>, options: [(String, String)]
    ) -> some View {
        let chosen = selection.wrappedValue.flatMap { value in options.first { $0.0 == value }?.1 }
        return Menu {
            Picker(title, selection: selection) {
                Text("Any").tag(String?.none)
                ForEach(options, id: \.0) { option in
                    Text(option.1).tag(String?.some(option.0))
                }
            }
            .pickerStyle(.inline)
        } label: {
            HStack(spacing: LBSpacing.s1) {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .medium))
                Text(chosen ?? title).lbText(.bodySM)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
            }
            .foregroundStyle(chosen != nil ? LBColor.onBrand.color : LBColor.textSecondary.color)
            .padding(.horizontal, LBSpacing.s3)
            .padding(.vertical, LBSpacing.s2)
            .background(chosen != nil ? LBColor.brand.color : LBColor.chrome.color, in: Capsule())
            .contentShape(Capsule())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel(chosen.map { "\(title): \($0)" } ?? title)
    }

    private func chip(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: LBSpacing.s1) {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .medium))
                Text(title).lbText(.bodySM)
            }
            .foregroundStyle(LBColor.textSecondary.color)
            .padding(.horizontal, LBSpacing.s3)
            .padding(.vertical, LBSpacing.s2)
            .background(LBColor.chrome.color, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// How the charge list is narrowed: a search and one choice per fact. The file's own rows
/// answer every narrowing, so a shared link lists the same charges.
private struct ChargeNarrowing {
    var search = ""
    var category: String?
    var account: String?
    var member: String?
    var currency: String?

    var isNarrowed: Bool { category != nil || account != nil || member != nil || currency != nil }

    mutating func clear() {
        category = nil
        account = nil
        member = nil
        currency = nil
    }

    static func category(_ row: ReportRow) -> String {
        row.category?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    /// Every name the rows carry, in the order they appear.
    static func names(_ values: [String?]) -> [String] {
        var out: [String] = []
        for value in values {
            guard let value, !value.isEmpty, !out.contains(value) else { continue }
            out.append(value)
        }
        return out
    }

    /// Every category the rows wear, in the order they appear, the no-category word last
    /// when a row carries none.
    func categoryOptions(_ rows: [ReportRow]) -> [(String, String)] {
        var named: [String] = []
        var bare = false
        for row in rows {
            let name = Self.category(row)
            if name.isEmpty { bare = true } else if !named.contains(name) { named.append(name) }
        }
        var out = named.map { ($0, categoryWord($0)) }
        if bare { out.append((CommitmentsView.noCategory, CommitmentsView.noCategory)) }
        return out
    }

    /// The order the file wrote is the order shown — biggest first, as it was drawn.
    func apply(to rows: [ReportRow]) -> [ReportRow] {
        let needle = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return rows.filter { row in
            let rowCategory = Self.category(row)
            if let category {
                let wanted = category == CommitmentsView.noCategory ? "" : category
                if rowCategory != wanted { return false }
            }
            if let account, row.account != account { return false }
            if let member, row.member != member { return false }
            if let currency, row.currency != currency { return false }
            guard !needle.isEmpty else { return true }
            return "\(row.name) \(rowCategory) \(row.account ?? "") \(row.member ?? "")".lowercased().contains(needle)
        }
    }
}

/// Share, in the bar on the phone and at the heading's edge on the Mac: it moves the screen
/// to the sharing card, which asks for sign-in only if it is needed. Sharing itself stays
/// in one place.
private struct ReportShareJump: View {
    let model: DashboardModel
    @ObservedObject var auth: AuthViewModel
    let reportId: String
    /// Changes when a link is made or ended, so the label is drawn again.
    let revision: Int
    let jump: () -> Void

    var body: some View {
        Button(action: jump) {
            #if os(macOS)
            Label(live ? "Sharing" : "Share", systemImage: live ? "link" : "square.and.arrow.up")
            #else
            Image(systemName: live ? "link" : "square.and.arrow.up")
            #endif
        }
        #if os(macOS)
        .buttonStyle(.bordered)
        .controlSize(.small)
        #endif
        .lbTapHaptic()
        .accessibilityLabel(live ? "Sharing" : "Share")
        .accessibilityHint("Moves to sharing, at the end of the report.")
    }

    /// A link that has expired or ended reads as no link, as the card below reads it.
    private var live: Bool {
        guard auth.isSignedIn, let share = model.shareDetails(forReport: reportId) else { return false }
        return share.expiresAt.map { $0 > Date() } ?? true
    }
}
