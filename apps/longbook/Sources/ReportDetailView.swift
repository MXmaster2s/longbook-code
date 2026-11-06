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
    /// The kind of card Cards Control has chosen.
    @State private var shownKind: LBCardKind = .charge
    /// A comment that could not be deleted: its module's position, and why.
    @State private var commentFailure: (module: Int, words: String)?

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
                    .tutorialTarget(.reportsShare)
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
            section(stats.title) { annotated(stats.comment, at: index) { LBPanel { statsView(stats) } } }
                #if os(macOS)
                // The Reports tutorial lights the report's lead figure beside the list.
                .tutorialTarget(index == report.modules.firstIndex { if case .stats = $0 { true } else { false } } ? .reportsTotal : nil)
                #endif
        case .prose(let prose):
            section(prose.title) { annotated(prose.comment, at: index) { LBPanel { proseView(prose, at: index) } } }
        case .donut(let donut):
            section(donut.title) {
                annotated(donut.comment, at: index) {
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
            section(bars.title) { annotated(bars.comment, at: index) { LBPanel { barsView(bars) } } }
        case .transactions(let list):
            if list.title == MonthlyReport.Titles.charges {
                chargesSections(list, at: index, report: report)
            } else {
                section(list.title) {
                    annotated(list.comment, at: index) {
                        VStack(spacing: LBSpacing.s2) {
                            ForEach(Array(list.rows.enumerated()), id: \.offset) { _, row in
                                chargeRow(row, report: report, removed: false)
                            }
                        }
                    }
                }
            }
        case .unknown(let type, let fields):
            let heading = stringField(fields, "title") ?? type.replacingOccurrences(of: "_", with: " ")
            section(heading) { annotated(stringField(fields, "comment"), at: index) { LBPanel { genericView(fields) } } }
        }
    }

    private func stringField(_ fields: [String: ReportValue], _ key: String) -> String? {
        if case .string(let text)? = fields[key] { return text }
        return nil
    }

    /// The owner's annotation and a viewer's lines, worn under the card they belong to. Each
    /// line deletes on its own from its menu, so a viewer's unwanted comment can go.
    private func annotated<Content: View>(_ comment: String?, at index: Int, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: LBSpacing.s2) {
            content()
            if let comment, !comment.isEmpty {
                HStack(alignment: .firstTextBaseline, spacing: LBSpacing.s2) {
                    Image(systemName: "bubble.left")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(LBColor.brandText.color)
                        .accessibilityLabel("Comment")
                    VStack(alignment: .leading, spacing: LBSpacing.s1) {
                        ForEach(Array(comment.components(separatedBy: "\n").enumerated()), id: \.offset) { _, line in
                            commentLine(line, at: index)
                        }
                    }
                }
                .padding(.horizontal, LBSpacing.s2)
                if let failure = commentFailure, failure.module == index {
                    Text(failure.words)
                        .lbText(.footnote)
                        .foregroundStyle(LBColor.urgent.color)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, LBSpacing.s2)
                }
            }
        }
    }

    private func commentLine(_ line: String, at index: Int) -> some View {
        Text(line)
            .lbText(.footnote)
            .foregroundStyle(LBColor.textSecondary.color)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .contextMenu {
                Button(role: .destructive) {
                    Measure.used("delete_comment")
                    deleteComment(line, at: index)
                } label: {
                    Label("Delete Comment", systemImage: "trash")
                }
            }
            .accessibilityAction(named: "Delete Comment") { deleteComment(line, at: index) }
    }

    private func deleteComment(_ line: String, at index: Int) {
        commentFailure = nil
        Task {
            if let words = await ShareReportClient.deleteLine(line, moduleAt: index, reportId: id, model: model, auth: auth) {
                commentFailure = (index, words)
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
                        shownKind = .charge
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
        Button(action: { Measure.used("pick_slice"); tap() }) {
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
        .lbButtonStyle()
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
                        Measure.used("narrowing")
                        narrowing.category = narrowing.category == slice.label ? nil : slice.label
                        shownKind = .charge
                    } label: {
                        categoryTile(
                            name: slice.label, ink: LBColor.dataInk(rank: rank), amountText: fmtMoney(slice.amount, slice.currency),
                            share: ring.total > 0 && slice.amount > 0 ? slice.amount / ring.total : nil,
                            picked: narrowing.category == slice.label
                        )
                    }
                    .lbButtonStyle()
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
                    Measure.used("less")
                    if open { openProse.remove(index) } else { openProse.insert(index) }
                } label: {
                    Text(open ? "Less" : "More")
                        .lbText(.footnote)
                        .foregroundStyle(LBColor.brandText.color)
                        .frame(minHeight: 28)
                        .contentShape(Rectangle())
                }
                .lbButtonStyle()
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

    /// The kinds of card the report's rows name, each once, as the book holds them now. A
    /// row from a file with no id answers by the names it wrote.
    private func named(by rows: [ReportRow]) -> (people: [DashboardModel.EntityCard], accounts: [DashboardModel.EntityCard], commitments: [DashboardData.CommitmentItem]) {
        var personIds: [String] = []
        var accountIds: [String] = []
        var subIds: [String] = []
        var personNames: [String] = []
        var accountNames: [String] = []
        func add(_ value: String, to list: inout [String]) {
            if !list.contains(value) { list.append(value) }
        }
        for row in rows {
            if let item = row.id.flatMap(model.chargeItem(id:)) {
                item.sides.personIds.forEach { add($0, to: &personIds) }
                item.sides.accountIds.forEach { add($0, to: &accountIds) }
                add(item.subId, to: &subIds)
            } else {
                if let member = row.member { add(member, to: &personNames) }
                if let account = row.account { add(account, to: &accountNames) }
            }
        }
        func cards(_ kind: VaultPatch.EntityKind, ids: [String], names: [String]) -> [DashboardModel.EntityCard] {
            let all = model.entityCards(kind)
            return all.filter { $0.isReal && (ids.contains($0.id) || names.contains($0.name)) }
        }
        return (cards(.familyMember, ids: personIds, names: personNames),
                cards(.paymentMethod, ids: accountIds, names: accountNames),
                model.commitmentItems(of: subIds.compactMap(model.subscription(id:))))
    }

    /// Cards Control where the list's heading would stand, then the search and the chips. They
    /// narrow every kind, since each is read from the rows they leave. What was taken out
    /// follows under its own heading.
    @ViewBuilder
    private func chargesSections(_ list: TransactionsModule, at index: Int, report: Report) -> some View {
        let kept = list.rows.filter { $0.removed != true }
        let removed = list.rows.filter { $0.removed == true }
        let shown = narrowing.apply(to: kept)
        let whole = named(by: kept)
        let left = named(by: shown)
        annotated(list.comment, at: index) {
            VStack(alignment: .leading, spacing: LBSpacing.s3) {
                LBCardsControl(
                    items: [
                        LBCardsControlItem(id: LBCardKind.charge, title: "Charges", symbol: LBCardKind.charge.symbol, count: kept.count),
                        LBCardsControlItem(id: LBCardKind.people, title: "People", symbol: LBCardKind.people.symbol, count: whole.people.count),
                        LBCardsControlItem(id: LBCardKind.account, title: "Accounts", symbol: LBCardKind.account.symbol, count: whole.accounts.count),
                        LBCardsControlItem(id: LBCardKind.commitment, title: "Commitments", symbol: LBCardKind.commitment.symbol, count: whole.commitments.count),
                    ],
                    current: shownKind
                ) { kind in
                    Measure.used("cards_control")
                    shownKind = kind
                }
                searchField
                filters(kept)
                if shown.count != kept.count {
                    Text("\(shown.count) of \(kept.count)")
                        .lbText(.footnote)
                        .foregroundStyle(LBColor.textTertiary.color)
                }
                switch shownKind {
                case .people:
                    ForEach(left.people) { card in entityDoor(card) }
                case .account:
                    ForEach(left.accounts) { card in entityDoor(card) }
                case .commitment:
                    ForEach(left.commitments) { item in
                        NavigationLink(value: Destination.commitment(id: item.id)) {
                            KindCards.card(item, photo: model.commitmentPhotoURL(id: item.id))
                        }
                        .lbCardButtonStyle()
                    }
                default:
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
                        chargeRow(row, report: report, removed: false)
                    }
                }
            }
        }
        if !removed.isEmpty {
            section("Removed from this report", note: "\(removed.count)") {
                VStack(spacing: LBSpacing.s3) {
                    ForEach(Array(removed.enumerated()), id: \.offset) { _, row in
                        chargeRow(row, report: report, removed: true)
                    }
                }
            }
        }
    }

    private func entityDoor(_ card: DashboardModel.EntityCard) -> some View {
        NavigationLink(value: card.ref.destination) { KindCards.card(card) }
            .lbCardButtonStyle()
    }

    /// One charge as the charges screen lists it, in the words the file wrote: a report says
    /// what it said on its day. A row that names its charge opens it, and can be taken out,
    /// put back, or dropped for good.
    @ViewBuilder
    private func chargeRow(_ row: ReportRow, report: Report, removed: Bool) -> some View {
        let item = row.id.flatMap(model.chargeItem(id:))
        let actions = rowCard(row, item: item, removed: removed)
            .contextMenu {
                if let rowId = row.id {
                    if removed {
                        Button {
                            Measure.used("put_back", .contextMenu)
                            model.setReportRow(rowId, in: report.id, to: .kept)
                        } label: {
                            Label("Put back", systemImage: "arrow.uturn.backward")
                        }
                        Button(role: .destructive) {
                            Measure.used("remove_for_good", .contextMenu)
                            model.setReportRow(rowId, in: report.id, to: .hidden)
                        } label: {
                            Label("Remove for good", systemImage: "trash")
                        }
                    } else {
                        Button(role: .destructive) {
                            Measure.used("remove_from_report", .contextMenu)
                            model.setReportRow(rowId, in: report.id, to: .removed)
                        } label: {
                            Label("Remove from report", systemImage: "minus.circle")
                        }
                    }
                }
            }
        if let item, !removed {
            NavigationLink(value: item.ref.destination) { actions }
                .lbCardButtonStyle()
        } else {
            actions
        }
    }

    /// The card every list draws, filled with the words the report kept. A person the report
    /// named who has left People is left off; money in names its account as To.
    private func rowCard(_ row: ReportRow, item: DashboardModel.ChargeItem?, removed: Bool) -> LBKindCard {
        let category = ChargeNarrowing.category(row)
        let income = item?.isIncome ?? false
        let transfer = item?.isTransfer ?? false
        let person = model.statementBook.person(row.member)
        let sides = transfer ? item?.sides ?? MoneySides(from: .init(account: row.account), to: .init())
            : income ? MoneySides(from: .init(person: person), to: .init(account: row.account))
            : MoneySides(from: .init(account: row.account), to: .init(person: person))
        return KindCards.money(
            kind: item?.cardKind ?? .charge, title: row.name, pill: nil, amount: fmtMoney(row.amount, row.currency),
            day: row.date.flatMap { LB.parseDate($0) }.map(LB.shortDate), category: category.isEmpty ? nil : category,
            sides: sides, income: income, transfer: transfer, photo: item.flatMap { model.commitmentPhotoURL(id: $0.subId) },
            state: removed ? .removed : .plain
        )
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
        .lbButtonStyle()
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel(chosen.map { "\(title): \($0)" } ?? title)
    }

    private func chip(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: { Measure.used("report_chip"); action() }) {
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
        .lbButtonStyle()
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
        Button(action: { Measure.used("sharing"); jump() }) {
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
