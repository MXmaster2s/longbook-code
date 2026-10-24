import DesignSystem
import LongbookCore
import SwiftUI

/// The reports in the vault, newest month first: the app's own monthly report for every
/// past month holding a confirmed charge, this one included, and any an AI wrote.
/// Importing a statement from here draws the months it confirms.
struct ReportsView: View {
    let model: DashboardModel
    @ObservedObject var auth: AuthViewModel
    @State private var copied = false
    @State private var importing = false
    /// The report open beside the list on the Mac; the newest until one is clicked.
    @State private var picked: String?
    /// The report a Delete asked about, until the owner answers.
    @State private var deleting: Report?

    var body: some View {
        page
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(LBColor.canvas.color)
            .screenTutorial(.reports)
            .onAppear {
                model.applyLocalRequests()
                model.drawMonthlyReports()
            }
            .measured("reports_importing", .sheet, when: importing)
            .sheet(isPresented: $importing) {
                StatementImportView(model: model, auth: auth, context: .reports) { importing = false }
            }
            .measured("reports_deleting", .dialog, when: deleting != nil)
            .confirmationDialog("Delete \(deleting?.title ?? "this report")?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
                Button("Delete Report", role: .destructive) {
                    Measure.used("delete_report")
                    if let report = deleting, model.deleteReport(id: report.id), picked == report.id { picked = nil }
                    deleting = nil
                }
                Button("Keep", role: .cancel) { Measure.used("keep"); deleting = nil }
            } message: {
                Text("The report’s file goes from your longbook folder and it is not drawn again. Your charges are not touched.")
            }
            // Reading a file in is an import; it sits in the bar, a tap away, without
            // leading a page that is for browsing.
            .lbScreenTitle("Reports") {
                Button("Import Statement") { Measure.used("import_statement"); importing = true }
                    .accessibilityLabel("Import a statement")
            }
    }

    /// The phone lists the reports and opens one on top; the Mac lists them on the left and
    /// shows the chosen one beside the list, as Mail and Notes do.
    @ViewBuilder
    private var page: some View {
        #if os(macOS)
        let listed = model.reports()
        if let shown = listed.reports.first(where: { $0.id == picked }) ?? listed.reports.first {
            HStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: LBSpacing.s4) {
                        macTitleRow
                        written()
                    }
                    .padding(LBSpacing.s4)
                    .padding(.top, LBSpacing.s6)
                }
                .frame(width: 340)
                Rectangle().fill(LBColor.hairline.color).frame(width: 1)
                ReportDetailView(model: model, id: shown.id, auth: auth)
                    .id(shown.id)
                    .frame(maxWidth: .infinity)
            }
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: LBSpacing.s4) {
                    macTitleRow
                    written()
                }
                .lbPageColumn(.wide)
            }
        }
        #else
        ScrollView {
            VStack(alignment: .leading, spacing: LBSpacing.s4) {
                written()
            }
            .lbPageColumn(.wide)
        }
        #endif
    }

    /// The rule the empty card states in full; every figure a report holds obeys it.
    private let rule = """
    A report is drawn for every month with a confirmed charge in it, up to the current \
    month, and for each trip and each report your AI asks for. A charge is confirmed by a \
    statement, an email, marking it paid, or setting its amount — planned charges are not counted.
    """

    #if os(macOS)
    /// The Mac's title row, where a window toolbar would sit: the name, then Import.
    private var macTitleRow: some View {
        HStack(alignment: .firstTextBaseline) {
            LBPageTitle("Reports")
            Spacer()
            Button("Import Statement…") { Measure.used("import_statement"); importing = true }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityLabel("Import a statement")
        }
    }
    #endif

    /// What the page says with nothing to show — and the way to fix that, since the
    /// analysis longbook can't compute is exactly what an AI can write.
    @ViewBuilder
    private func askYourAI(_ what: String) -> some View {
        LBCard {
            VStack(alignment: .leading, spacing: LBSpacing.s3) {
                Text(what)
                    .lbText(.footnote)
                    .foregroundStyle(LBColor.textTertiary.color)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    Measure.used("copy_prompt")
                    copy(prompt)
                } label: {
                    HStack(spacing: LBSpacing.s2) {
                        Image(systemName: copied ? "checkmark" : "sparkles")
                            .font(.system(size: 11, weight: .semibold))
                        Text(copied ? "Copied to the clipboard." : "Ask your AI to build it")
                            .lbText(.label)
                    }
                    .foregroundStyle(LBColor.onBrand.color)
                    .padding(.horizontal, LBSpacing.s3)
                    .padding(.vertical, LBSpacing.s2)
                    .background(LBColor.brand.color, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func copy(_ prompt: String) {
        #if os(iOS)
        UIPasteboard.general.string = prompt
        #else
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(prompt, forType: .string)
        #endif
        copied = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            copied = false
        }
    }

    // MARK: what the AI wrote

    @ViewBuilder
    private func written() -> some View {
        let listed = model.reports()
        if listed.reports.isEmpty {
            askYourAI("No reports yet. \(rule)")
        } else {
            let years = Self.byYear(listed.reports)
            VStack(alignment: .leading, spacing: LBSpacing.s4) {
                ForEach(years, id: \.year) { group in
                    VStack(alignment: .leading, spacing: LBSpacing.s2) {
                        LBSectionHeader(group.year)
                            .padding(.horizontal, LBSpacing.s3)
                            #if os(iOS)
                            .tutorialTarget(group.year == years.dropFirst().first?.year ? .reportsEarlier : nil)
                            #endif
                        // Cards on their own, as Commitments lists them; each one can be deleted.
                        VStack(spacing: LBSpacing.s2) {
                            ForEach(group.reports, id: \.id) { report in
                                reportRow(report)
                                    .contextMenu {
                                        Button("Delete Report…", role: .destructive) { Measure.used("delete_report", .contextMenu); deleting = report }
                                    }
                                    #if os(iOS)
                                    .tutorialTarget(report.id == listed.reports.first?.id ? .reportsList : nil)
                                    #endif
                            }
                        }
                    }
                }
                #if os(macOS)
                .tutorialTarget(.reportsList)
                #endif
                Text(footer)
                    .lbText(.footnote)
                    .foregroundStyle(LBColor.textTertiary.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        if listed.unreadable > 0 {
            Text("\(listed.unreadable) report\(listed.unreadable == 1 ? "" : "s") in your folder couldn’t be read.")
                .lbText(.footnote)
                .foregroundStyle(LBColor.urgent.color)
        }
    }

    /// The reports in their year, newest first as listed; a report with no days settled
    /// stands under "Other".
    private static func byYear(_ reports: [Report]) -> [(year: String, reports: [Report])] {
        var groups: [(year: String, reports: [Report])] = []
        for report in reports {
            let year = report.range.map { String(LB.calendar.component(.year, from: $0.start)) } ?? "Other"
            if let at = groups.firstIndex(where: { $0.year == year }) {
                groups[at].reports.append(report)
            } else {
                groups.append((year, [report]))
            }
        }
        return groups
    }

    /// One report: its name, how many charges, its total. A month's days are already its
    /// name, so only other spans say their days.
    @ViewBuilder
    private func reportRow(_ report: Report) -> some View {
        let total = report.totalStat.flatMap { stat in stat.amount.flatMap { amount in stat.currency.map { fmtMoney(amount, $0) } } }
        #if os(macOS)
        let isPicked = report.id == (picked ?? model.reports().reports.first?.id)
        Button { Measure.used("picked"); picked = report.id } label: {
            LBCommitmentRow(name: report.title, facts: reportFacts(report), amount: total ?? "", ink: LBColor.brand,
                            selected: isPicked, symbol: reportSymbol(report))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isPicked ? .isSelected : [])
        #else
        NavigationLink(value: Destination.report(id: report.id)) {
            LBCommitmentRow(name: report.title, facts: reportFacts(report), amount: total ?? "", ink: LBColor.brand,
                            symbol: reportSymbol(report))
        }
        .buttonStyle(.plain)
        #endif
    }

    /// A trip wears its plane, every other report its page, so names line up down the list.
    private func reportSymbol(_ report: Report) -> String {
        report.isTrip ? "airplane" : "doc.text"
    }

    /// What the report covers, as the cards everywhere say it: always the same four facts,
    /// its days and how many categories, accounts and people it touches, so every card is
    /// the same height. A report written without a charges list is read from its other parts.
    private func reportFacts(_ report: Report) -> [LBMetaFact] {
        var rows = report.chargeRows.kept
        var categoryNames = Set<String>()
        var accountNames = Set<String>()
        for module in report.modules {
            switch module {
            case .transactions(let list) where rows.isEmpty:
                rows += list.rows.filter { $0.removed != true }
            case .donut(let donut):
                if donut.title == MonthlyReport.Titles.accounts { accountNames.formUnion(donut.slices.map(\.label)) }
                if donut.title == MonthlyReport.Titles.categories { categoryNames.formUnion(donut.slices.map(\.label)) }
            case .bars(let bars):
                if bars.title == MonthlyReport.Titles.categories { categoryNames.formUnion(bars.bars.map(\.label)) }
                if bars.title == MonthlyReport.Titles.accounts { accountNames.formUnion(bars.bars.map(\.label)) }
            default:
                break
            }
        }
        categoryNames.formUnion(rows.compactMap(\.category))
        // A row an AI wrote may not name its account or person; the charge it points at
        // does. Counted by id, so a name and an id for one account count once.
        let charges = Dictionary(model.chargeItems().map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let choices = model.editChoices
        let methodIds = Dictionary(choices.methods.map { ($0.name, $0.id) }, uniquingKeysWith: { a, _ in a })
        let memberIds = Dictionary(choices.members.map { ($0.name, $0.id) }, uniquingKeysWith: { a, _ in a })
        var accounts = Set(accountNames.map { methodIds[$0] ?? $0 })
        var members = Set<String>()
        for row in rows {
            if let id = charges[row.id ?? ""]?.methodId ?? row.account.map({ methodIds[$0] ?? $0 }) { accounts.insert(id) }
            if let id = charges[row.id ?? ""]?.memberId ?? row.member.map({ memberIds[$0] ?? $0 }) { members.insert(id) }
        }
        let days = reportDays(report, rows: rows)
        func word(_ n: Int, _ one: String, _ many: String) -> String { "\(n) \(n == 1 ? one : many)" }
        return [
            LBMetaFact(symbol: LBGlyph.date, text: days.map { word($0, "day", "days") } ?? "Any days"),
            LBMetaFact(symbol: LBGlyph.category, text: word(categoryNames.count, "category", "categories")),
            LBMetaFact(symbol: LBGlyph.account, text: word(accounts.count, "account", "accounts")),
            LBMetaFact(symbol: LBGlyph.member, text: word(members.count, "person", "people")),
        ]
    }

    /// The report's own days; else the month its title names; else the span of its rows.
    private func reportDays(_ report: Report, rows: [ReportRow]) -> Int? {
        if let range = report.range { return LB.daysBetween(range.start, range.end) + 1 }
        let title = DateFormatter()
        title.calendar = LB.calendar
        title.locale = Locale(identifier: "en_US_POSIX")
        title.dateFormat = "MMMM yyyy"
        if let first = title.date(from: report.title) {
            return LB.calendar.range(of: .day, in: .month, for: first)?.count
        }
        let dates = rows.compactMap { $0.date.flatMap(LB.parseDate) }
        guard let first = dates.min(), let last = dates.max() else { return nil }
        return LB.daysBetween(first, last) + 1
    }

    /// The one line under the list: what a report does not count, until it is confirmed.
    private let footer = "Planned charges are not counted until a statement, an email, marking them paid or setting an amount confirms them."

    /// What the button copies: the catalogue's phrase, also listed on the Automations screen, so
    /// the AI reads the guide's chapter, asks for the days, accounts and people, and asks longbook to draw it.
    private var prompt: String { PromptCatalog.phrase(id: "create-a-report-in-my-longbook") }
}
