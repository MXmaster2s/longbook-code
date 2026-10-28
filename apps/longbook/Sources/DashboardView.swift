import DesignSystem
import LongbookCore
import SwiftUI

#if os(macOS)
import AppKit
#endif

/// The dashboard — what longbook answers before you ask. The model is owned above it,
/// so the Mac sidebar and this pane read one load of the same vault.
struct DashboardView: View {
    @Environment(\.scenePhase) private var scenePhase
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #else
    @Environment(\.openSettings) private var openSettings
    #endif
    let model: DashboardModel
    /// The statement importer, opened from a month with nothing in it, signs its call.
    @ObservedObject var auth: AuthViewModel
    /// The stack above, for the one door a link cannot be: a bar of the chart.
    @Binding var path: [Destination]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The month card turned to its list of expenses.
    @State private var monthFlipped = false
    /// Each flip card's front height: the back takes it, so turning a card never resizes it.
    @State private var monthFrontHeight: CGFloat = 0
    @State private var accountsFrontHeight: CGFloat = 0
    /// True while a swipe is turning the month card. Its rows disable for that beat, so
    /// the same motion can never both flip the card and open a commitment.
    @State private var monthCardSwiping = false
    /// The accounts card turned to its account browser.
    @State private var accountsFlipped = false
    /// The same beat for the accounts card, for the same reason.
    @State private var accountsCardSwiping = false
    /// Which account the browser reads. Nil until one is touched: the first chip, the
    /// most used account in the months shown, answers until then.
    @State private var pickedAccountId: String?
    /// True while a strip or chip inside a card is taking a sideways drag of its own.
    /// The card's flip stands down for it, so one motion never means two things.
    @State private var innerDrag = false
    /// When the claim was last renewed. Every frame of a drag renews it, so a watchdog
    /// that wakes to a newer instant sleeps again rather than freeing a live drag.
    @State private var innerDragAt = Date.distantPast
    /// Bumped by every claim, so a release timed by an earlier drag frees nothing.
    @State private var innerDragMark = 0
    /// Whether a watchdog is already running for the claim: one per drag, not one a frame.
    @State private var innerDragArmed = false
    /// The pointer's hold on the account chips, so a mouse can pull them as a finger does.
    @State private var chipPointer = LBPointerScroll()
    /// The chip rail and the chips inside it. A rail with nothing to scroll claims no
    /// drag, so the card it sits on can still be turned from the row it sits in.
    @State private var chipRailWidth: CGFloat = 0
    @State private var chipRowWidth: CGFloat = 0
    /// The month grid, opened by any panel's month control.
    @State private var pickingMonth = false
    /// A month with nothing in it, asked for: a statement to read, or a commitment to add.
    @State private var importingMonth: MonthAsk?
    @State private var addingForMonth: MonthAsk?
    /// The pointer's hold on the category strip, so a mouse can pull it as a finger does.
    @State private var tilePointer = LBPointerScroll()

    /// How many rows a turned card's list shows, so it is the same height whichever
    /// month or account the reader opens.
    private static let expenseRows = 5
    /// Legend rows on the accounts card when it sits beside the expenses card.
    private static let legendRows = 4
    /// The widest a day's bar is drawn while few days share the chart.
    private static let monthBarWidth: CGFloat = 18
    /// Up to this many bars stay bar-shaped; more share the width out.
    private static let barShapedDays = 12


    /// Phones stack the month and donut panels full-width — half of a compact screen
    /// truncates the one number the panel exists to show.
    private var stacksPanels: Bool {
        #if os(iOS)
        return sizeClass == .compact
        #else
        return false
        #endif
    }

    var body: some View {
        Group {
            switch model.state {
            case .loading:
                canvas { EmptyView() }
            case .provisioning, .firstRun, .unavailable, .failed:
                VaultChoiceView(model: model, auth: auth)
            case .loaded(let data):
                loaded(data)
            }
        }
        .onAppear { model.loadIfNeeded() }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
            model.load()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { model.load() }
        }
    }

    private func canvas<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        // Built once, out here: the reader's closure escapes, and the builder does not.
        let built = content()
        return ScrollView {
            VStack(alignment: .leading, spacing: LBSpacing.s4) { built }
                .lbPageColumn(.wide)
        }
        .refreshable {
            await model.load()
            await model.applyPendingWrites()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LBColor.canvas.color)
        .lbScreenTitle("Dashboard")
        .onAppear {
            #if DEBUG
            if ProcessInfo.processInfo.environment["LONGBOOK_SNAPSHOT_SCREEN"] == "monthpicker" { pickingMonth = true }
            if ProcessInfo.processInfo.environment["LONGBOOK_SNAPSHOT_RAIL"] == "back" { model.railLooksBack = true }
            // The months the cards start on, as offsets from this one: "-2,-1,0" is the last three.
            // Only offsets the panels can browse to are kept.
            if let raw = ProcessInfo.processInfo.environment["LONGBOOK_SNAPSHOT_MONTHS"],
               let months = MonthSelection(offsets: raw.split(separator: ",").compactMap {
                   Int($0.trimmingCharacters(in: .whitespaces))
               }.filter(DashboardModel.monthRange.contains)),
               months != model.selectedMonths {
                model.selectedMonths = months
            }
            // Which card starts turned, so the back of one can be photographed.
            switch ProcessInfo.processInfo.environment["LONGBOOK_SNAPSHOT_CARD"] {
            case "accounts": accountsFlipped = true
            case "month": monthFlipped = true
            default: break
            }
            #endif
        }
        .measured("dashboard_picking_month", .sheet, when: pickingMonth)
        .sheet(isPresented: $pickingMonth) {
            // Read through a binding, so the grid redraws with each month the cards take on.
            MonthPickerView(
                selection: Binding(get: { model.selectedMonths }, set: { setMonths($0) }),
                range: DashboardModel.monthRange,
                filled: model.monthsWithCharges,
                gatesEmpty: true,
                onImport: { importingMonth = MonthAsk(offset: $0, prompt: "Selected month’s data not available. Import bank statement?", namesMonth: true) },
                onAdd: { addingForMonth = MonthAsk(offset: $0) },
                onDone: { pickingMonth = false }
            )
            .lbMonthSheet()
        }
        .measured("dashboard_importing_month", .sheet, when: importingMonth != nil)
        .sheet(item: $importingMonth) { asked in
            StatementImportView(model: model, auth: auth, prompt: asked.prompt,
                                context: asked.namesMonth ? .month(PromptCatalog.monthName(of: asked.firstDay)) : nil,
                                picksOnOpen: asked.picks, dropped: asked.dropped) {
                importingMonth = nil
            }
        }
        .measured("dashboard_adding_for_month", .sheet, when: addingForMonth != nil)
        .sheet(item: $addingForMonth) { asked in
            RenewalFormView(model: model, editingId: nil, seedDate: asked.firstDay) { addingForMonth = nil }
        }
    }

    /// A month named by its offset from this one, as a sheet's item, with why it opened.
    private struct MonthAsk: Identifiable {
        let offset: Int
        var prompt: String? = nil
        /// Opened for that one month, so the own-AI prompt asks for its report by name.
        var namesMonth = false
        var picks = false
        /// The statements dropped on the dashboard, read without the picker.
        var dropped: [URL] = []
        var id: Int { offset }
        var firstDay: Date { LB.addMonths(LB.firstOfMonth(LB.todayMid()), offset) }
    }

    private func loaded(_ data: DashboardData) -> some View {
        // One canvas for both, so a sheet opened from the empty book stays up as it fills.
        canvas {
            header(data)
            if isEmptyBook {
                DashboardStart(
                    waiting: model.placeholders.map(\.name),
                    onImport: { importingMonth = MonthAsk(offset: 0, prompt: "No past charges yet. Import a bank statement to add them.") },
                    onDrop: { importingMonth = MonthAsk(offset: 0, dropped: $0) },
                    onAdd: { addingForMonth = MonthAsk(offset: 0) },
                    onOwnAI: openOwnAI
                )
            } else {
                filled(data).screenTutorial(.dashboard)
            }
        }
    }

    /// No commitment and no charge anywhere: the dashboard is one way in, not empty cards.
    private var isEmptyBook: Bool {
        model.commitmentCount == 0 && model.chargeCount == 0
    }

    /// Settings › AI: the Settings window's AI pane on the Mac, the AI screen on the phone.
    private func openOwnAI() {
        #if os(macOS)
        UserDefaults.standard.set(SettingsPane.ai.rawValue, forKey: SettingsPane.pickedKey)
        openSettings()
        #else
        path.append(.mcpServer)
        #endif
    }

    /// Today's dashboard: what is due, the 30-day rail, and the month's cards.
    private func filled(_ data: DashboardData) -> some View {
        VStack(alignment: .leading, spacing: LBSpacing.s4) {
            heroRow(data)
            // The rail stays whatever the book holds: it carries the Needs details card.
            DashboardRail(model: model, rail: data.rail) {
                importingMonth = MonthAsk(offset: 0, prompt: "No past charges yet. Import a bank statement to add them.")
            }
            .tutorialTarget(.dashboardComingUp)
            if isBare(data) {
                // Until a charge exists anywhere, one card says what to do next, and the
                // month card keeps the dashboard's shape with the way to its statement.
                welcomeCard
                monthPanel(data)
            } else {
                if stacksPanels {
                    monthPanel(data)
                    donutPanel(data)
                } else {
                    // Side by side, the two read as one row: the taller sets both heights.
                    HStack(alignment: .top, spacing: LBSpacing.s3) {
                        monthPanel(data)
                        donutPanel(data)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
                categoryPanel(data)
            }
        }
    }

    /// Nothing due ahead and no month in the range holding a charge: a book with no money in it yet.
    private func isBare(_ data: DashboardData) -> Bool {
        data.nextDay == nil && model.monthsWithCharges.isEmpty && data.rail.charges.isEmpty
    }

    /// The one card a bare book shows: the two ways money gets in, and what setup named
    /// that still waits for its details.
    private var welcomeCard: some View {
        LBPanel(eyebrow: "Get started") {
            VStack(alignment: .leading, spacing: LBSpacing.s3) {
                Text("No charges yet")
                    .lbText(.headline)
                    .foregroundStyle(LBColor.textPrimary.color)
                Text("Import a statement to see what you spent, or add a commitment to see what is due.")
                    .lbText(.footnote)
                    .foregroundStyle(LBColor.textSecondary.color)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: LBSpacing.s2) {
                    pillButton("Import a Statement", filled: true) {
                        importingMonth = MonthAsk(offset: 0, prompt: "No past charges yet. Import a bank statement to add them.")
                    }
                    pillButton("Add Commitment", filled: false) { addingForMonth = MonthAsk(offset: 0) }
                }
                if !model.placeholders.isEmpty {
                    Rectangle().fill(LBColor.hairline.color).frame(height: 1)
                    NavigationLink(value: Destination.commitments(ListFilter())) {
                        HStack(alignment: .firstTextBaseline, spacing: LBSpacing.s2) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(model.placeholders.count) needs details")
                                    .lbText(.body)
                                    .foregroundStyle(LBColor.textPrimary.color)
                                Text(DashboardRail.waitingNames(model.placeholders.map(\.name)))
                                    .lbText(.footnote)
                                    .foregroundStyle(LBColor.textSecondary.color)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: LBSpacing.s2)
                            Text("Finish")
                                .lbText(.label)
                                .foregroundStyle(LBColor.brandText.color)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(LBColor.textQuaternary.color)
                        }
                        .contentShape(Rectangle())
                    }
                    .lbButtonStyle()
                    .lbTapHaptic()
                }
            }
        }
    }

    private func pillButton(_ title: String, filled: Bool, run: @escaping () -> Void) -> some View {
        Button {
            Measure.used("dashboard_shortcut")
            LBHaptics.tap()
            run()
        } label: {
            Text(title)
                .lbText(.label)
                .lineLimit(1)
                .foregroundStyle(filled ? LBColor.onBrand.color : LBColor.brandText.color)
                .padding(.horizontal, LBSpacing.s3)
                .frame(minHeight: 34)
                .background(filled ? LBColor.brand.color : LBColor.chrome.color, in: Capsule())
                .contentShape(Capsule())
        }
        .lbButtonStyle()
    }

    private func note(_ title: String, _ body: String) -> some View {
        LBPanel {
            VStack(alignment: .leading, spacing: LBSpacing.s2) {
                Text(title).lbText(.body).foregroundStyle(LBColor.textPrimary.color)
                Text(body).lbText(.footnote).foregroundStyle(LBColor.textTertiary.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: header

    /// The Mac's title row; the phone's title sits in the navigation bar. The currency the
    /// cards show is a setting, chosen in Display & currency.
    @ViewBuilder
    private func header(_ data: DashboardData) -> some View {
        #if os(macOS)
        LBPageTitle("Dashboard")
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, LBSpacing.s2)
        #endif
    }

    // MARK: hero row

    /// Side by side, or one above the other at the accessibility sizes, where half the
    /// width broke "Commitments" in two.
    private func heroRow(_ data: DashboardData) -> some View {
        LBReflowStack(alignment: .top, spacing: LBSpacing.s3) {
            heroCard(data).tutorialTarget(.dashboardNextPayment)
            statCard(data)
        }
        .frame(maxWidth: .infinity)
    }

    /// The hero is the door to what it names: one thing due opens that commitment, a
    /// shared day opens the day's list. A transfer due that day counts as a thing due.
    private func heroCard(_ data: DashboardData) -> some View {
        Group {
            if let day = data.nextDay {
                let due = day.charges + day.transfers
                NavigationLink(value: due.count == 1
                    ? Destination.commitment(id: due[0].sub.id)
                    : Destination.commitments(ListFilter(day: LB.toISO(day.date)))) {
                    heroFace(data)
                }
                .lbButtonStyle()
                .lbTapHaptic()
            } else {
                heroFace(data)
            }
        }
    }

    private func heroFace(_ data: DashboardData) -> some View {
        VStack(alignment: .leading, spacing: LBSpacing.s2) {
            HStack(alignment: .firstTextBaseline, spacing: LBSpacing.s1) {
                Text("Next payment")
                    .lbText(.eyebrow)
                    .foregroundStyle(LBColor.onBrand.color.opacity(0.75))
                InsightMark(insight: model.insight("dashboard.next_payment"), ink: LBColor.onBrand)
            }
            if let day = data.nextDay {
                // The day leads: several commitments can share it, and a name would run to
                // two lines. The money and the name follow under it.
                Text(LB.dayWord(day.days))
                    .lbText(.heroSans)
                    .foregroundStyle(LBColor.onBrand.color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if day.charges.isEmpty {
                    // A day of transfers alone: the names and what moves, flagged by the glyph.
                    heroTransferLine(heroTransferNames(day) + " · " + fmtMoneyTotals(sumByCurrency(day.transfers)), lines: 1)
                } else {
                    // With a transfer line beneath it, this one keeps to a single line, so the
                    // card stays the height of the stat beside it.
                    Text(heroLine(day))
                        .lbText(.bodySM)
                        .foregroundStyle(LBColor.onBrand.color.opacity(0.9))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .truncationMode(.tail)
                    if !day.transfers.isEmpty {
                        heroTransferLine(heroTransfers(day), lines: 1)
                    }
                }
            } else {
                Text("Nothing due")
                    .lbText(.heroSans)
                    .foregroundStyle(LBColor.onBrand.color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .padding(LBSpacing.s4)
        .frame(maxWidth: .infinity, minHeight: 128, alignment: .topLeading)
        .background(
            LinearGradient(
                colors: [LBColor.heroTop.color, LBColor.heroBottom.color],
                startPoint: .topLeading, endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: LBRadius.lg, style: .continuous)
        )
        // The decorative glyph stays on the desktop, where the card is wide enough for
        // it. On a phone the card is half a screen and the glyph lands on the words.
        #if os(macOS)
        .overlay(alignment: .topTrailing) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 26, weight: .regular))
                .foregroundStyle(LBColor.onBrand.color.opacity(0.35))
                .padding(LBSpacing.s4)
                .accessibilityHidden(true)
        }
        #endif
        .accessibilityElement(children: .combine)
    }

    /// The day's one payment by name, two by both names, more by their count.
    private func heroName(_ day: PaymentDay) -> String {
        day.charges.count <= 2
            ? day.charges.map(\.sub.name).joined(separator: ", ")
            : "\(day.charges.count) payments"
    }

    /// Per-currency sums joined with " + ", then when — never one blended number. The sum
    /// is spending only; transfers are named and summed on their own line.
    private func heroLine(_ day: PaymentDay) -> String {
        fmtMoneyTotals(sumByCurrency(day.charges)) + " · " + heroName(day)
    }

    /// "in 2 days", "today": the day word, lowered to sit mid-sentence.
    private func whenWord(_ days: Int) -> String {
        let word = LB.dayWord(days)
        return word.prefix(1).lowercased() + word.dropFirst()
    }

    /// A transfer line on the hero, led by the transfer glyph so it is never read as spending.
    private func heroTransferLine(_ words: String, lines: Int) -> some View {
        HStack(spacing: LBSpacing.s1) {
            Image(systemName: LBGlyph.transfer)
                .font(.system(size: 10, weight: .medium))
                .accessibilityHidden(true)
            Text(words)
                .lbText(.bodySM)
                .lineLimit(lines)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(LBColor.onBrand.color.opacity(0.9))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Transfer, \(words)")
    }

    /// The names of a day's transfers: both when there are two, else how many.
    private func heroTransferNames(_ day: PaymentDay) -> String {
        day.transfers.count <= 2
            ? day.transfers.map(\.sub.name).joined(separator: ", ")
            : "\(day.transfers.count) transfers"
    }

    /// The day's transfers on their own line, "1 transfer, ₹12,450": beside the spending,
    /// never inside it.
    private func heroTransfers(_ day: PaymentDay) -> String {
        "\(day.transfers.count) transfer\(day.transfers.count == 1 ? "" : "s"), "
            + fmtMoneyTotals(sumByCurrency(day.transfers))
    }

    /// The stat is also the door to the full list.
    private func statCard(_ data: DashboardData) -> some View {
        NavigationLink(value: Destination.commitments(ListFilter())) {
            LBPanel(padding: LBSpacing.s4) {
                VStack(alignment: .leading, spacing: LBSpacing.s2) {
                    // Trailing room for the overlaid glyph, which reserves no layout space.
                    HStack(alignment: .firstTextBaseline, spacing: LBSpacing.s1) {
                        Text("Commitments")
                            .lbText(.eyebrow)
                            .foregroundStyle(LBColor.textTertiary.color)
                        InsightMark(insight: model.insight("dashboard.active_commitments"))
                    }
                    #if os(macOS)
                    .padding(.trailing, 36)
                    #endif
                    Text("\(data.activeCount + model.placeholders.count)")
                        .lbText(.statNumber)
                        .foregroundStyle(LBColor.textPrimary.color)
                    Text(statWords(data))
                        .lbText(.footnote)
                        .foregroundStyle(LBColor.textTertiary.color)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(minHeight: 96, alignment: .topLeading)
            }
            #if os(macOS)
            .overlay(alignment: .topTrailing) {
                Image(systemName: "square.stack.3d.up")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(LBColor.textQuaternary.color)
                    .padding(LBSpacing.s4)
                    .accessibilityHidden(true)
            }
            #endif
        }
        .lbButtonStyle()
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(data.activeCount + model.placeholders.count) commitments, \(statWords(data)), opens the list")
    }

    /// What the count is: active, with the ones named at setup and still to finish said
    /// apart, and how many currencies the totals are kept in.
    private func statWords(_ data: DashboardData) -> String {
        let waiting = model.placeholders.count
        return waiting == 0 ? "All active" : "\(data.activeCount) active · \(waiting) needs details"
    }

    // MARK: this month

    private func monthPanel(_ data: DashboardData) -> some View {
        // The card turns, not the words on it: the surface, its border and its heading
        // are all inside the rotation, so what the hand sees is one object turning over.
        // Both faces stay in the layout, the hidden one invisible, so the card keeps one
        // height whichever face is up.
        ZStack(alignment: .top) {
            LBPanel(eyebrow: "Spending", mark: { monthMark }, accessory: { monthMenu(data.month.name) }) {
                monthFront(data)
                    .frame(maxHeight: rowHeight, alignment: .top)
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { monthFrontHeight = $0 }
            .opacity(monthFlipped ? 0 : 1)
            .accessibilityHidden(monthFlipped)
            .allowsHitTesting(!monthFlipped)
            LBPanel(eyebrow: "Spending", mark: { monthMark }, accessory: { monthMenu(data.month.name) }) {
                monthExpenses(data)
                    .frame(maxHeight: .infinity, alignment: .top)
            }
            .frame(height: monthFrontHeight > 0 ? monthFrontHeight : nil, alignment: .top)
            .clipped()
            .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
            .opacity(monthFlipped ? 1 : 0)
            .accessibilityHidden(!monthFlipped)
            .allowsHitTesting(monthFlipped)
        }
        // One face at a time, so the card is only ever as tall as what it shows.
        .rotation3DEffect(.degrees(monthFlipped ? 180 : 0), axis: (x: 0, y: 1, z: 0),
                          perspective: 0.45)
        .animation(reduceMotion ? nil : .spring(duration: 0.45), value: monthFlipped)
        // Both faces go quiet while a swipe is turning the card — the front's own
        // controls could otherwise fire from the same motion.
        .disabled(monthCardSwiping)
        // Without a shape the card is only hit-testable where its words are, so a
        // swipe that starts in the space between them never begins at all.
        .contentShape(Rectangle())
        .simultaneousGesture(flipGesture($monthFlipped, swiping: $monthCardSwiping))
        .tutorialTarget(.dashboardSpending)
    }

    private var monthMark: some View {
        InsightMark(insight: model.insight("dashboard.this_month"))
    }

    /// Side by side with its neighbour, a panel fills the row so the two match; stacked,
    /// it is as tall as what it holds.
    private var rowHeight: CGFloat? {
        stacksPanels ? nil : .infinity
    }

    /// A month with nothing in it draws no ₹0 and no empty chart: it names the next step.
    @ViewBuilder
    private func monthFront(_ data: DashboardData) -> some View {
        let month = data.month
        if month.chargeCount == 0, month.income <= 0, month.otherTotals.isEmpty {
            monthEmpty(data)
        } else {
            monthStats(data)
        }
    }

    /// Past or this month asks for a statement, as the month grid does; a month ahead asks
    /// for a commitment, since no statement can hold it yet.
    private func monthEmpty(_ data: DashboardData) -> some View {
        let offset = model.selectedMonths.months.last ?? 0
        let ahead = offset > 0
        return DashboardEmpty(
            title: "No charges in \(data.month.name)",
            message: ahead ? "Add a commitment to see what is due." : "Import a statement to see your spending.",
            action: (ahead ? "Add commitment" : "Import a statement", {
                if ahead { addingForMonth = MonthAsk(offset: offset) } else { importingMonth = MonthAsk(offset: offset, namesMonth: true) }
            }),
            minHeight: 150
        )
    }

    private func monthStats(_ data: DashboardData) -> some View {
        let month = data.month
        return VStack(alignment: .leading, spacing: LBSpacing.s2) {
                HStack(alignment: .firstTextBaseline, spacing: LBSpacing.s2) {
                    Text(fmtMoney(month.total, data.scope))
                        .lbText(.statNumber)
                        .foregroundStyle(LBColor.textPrimary.color)
                        .lineLimit(1)
                        .minimumScaleFactor(0.55)
                    if !month.otherTotals.isEmpty {
                        Text("+" + fmtMoneyTotals(month.otherTotals))
                            .lbText(.label)
                            .foregroundStyle(LBColor.brandText.color)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
                // The total and one line under it; money in and what remains are on the back.
                Text("\(month.chargeCount) charge\(month.chargeCount == 1 ? "" : "s")")
                    .lbText(.footnote)
                    .foregroundStyle(LBColor.textTertiary.color)
                // Stacked, one height so the card ends on the first screen; beside Accounts
                // the bars grow a little, never into a column. A few days stay bar-shaped
                // rather than stretching across their share.
                LBDayBars(dayBars(month, scope: data.scope),
                          widest: month.bars.count <= Self.barShapedDays ? Self.monthBarWidth : nil,
                          onOpen: { openDay(month, at: $0) })
                    .frame(minHeight: stacksPanels ? 72 : 88, maxHeight: stacksPanels ? 72 : 132)
                    .padding(.top, LBSpacing.s2)
                    .accessibilityHint("Bar heights are compressed so small days stay visible.")
                    .accessibilityValue("Lighter bars are paid, darker bars planned.")
                // One month names its two ends; several name each month under its first bar.
                if month.firstDays.count == 1 {
                    HStack {
                        Text(month.edges.first).lbText(.footnote).foregroundStyle(LBColor.textTertiary.color)
                        Spacer()
                        Text(month.edges.last).lbText(.footnote).foregroundStyle(LBColor.textTertiary.color)
                    }
                }
            // The way to the other face sits at the card's foot, level with its neighbour's.
            Spacer(minLength: 0)
            HStack {
                Spacer()
                flipControl($monthFlipped, mac: "Show List")
            }
        }
        .accessibilityElement(children: .contain)
    }

    /// A bar opens its day's charges — a day behind today on Past, today or ahead on
    /// Upcoming, the list deciding. A day with nothing charged is no door.
    private func openDay(_ month: DashboardData.Month, at index: Int) {
        guard month.bars.indices.contains(index), !month.bars[index].chargeIds.isEmpty else { return }
        // A double-click reports two clicks; the second finds its list already on top.
        let door = Destination.commitments(ListFilter(day: LB.toISO(month.bars[index].day)))
        guard path.last != door else { return }
        LBHaptics.tap()
        path.append(door)
    }

    /// Each bar's words: the day, the scope currency's sum with any other currency's
    /// beside it, and the count. A month's name goes under its first bar when several
    /// months share the chart.
    private func dayBars(_ month: DashboardData.Month, scope: String) -> [LBDayBarValue] {
        let several = month.firstDays.count > 1
        return month.bars.map { bar in
            LBDayBarValue(scoped: bar.scoped, foreignOnly: bar.foreignOnly, isPast: bar.isPast,
                          title: LB.shortDate(bar.day), detail: Self.barDetail(bar, scope: scope),
                          axisLabel: several && bar.startsMonth ? LB.shortMonth(bar.day) : nil)
        }
    }

    /// One bar's caption: the money, then the count. A day with charges but nothing due in
    /// any currency says the count alone; an empty day says so.
    private static func barDetail(_ bar: ExpenseBar, scope: String) -> String {
        let count = bar.chargeIds.count
        guard count > 0 else { return "No charges" }
        var sums: [String] = []
        if bar.scoped > 0 { sums.append(fmtMoney(bar.scoped, scope)) }
        if !bar.others.isEmpty { sums.append(fmtMoneyTotals(bar.others)) }
        let charges = "\(count) charge\(count == 1 ? "" : "s")"
        return sums.isEmpty ? charges : "\(sums.joined(separator: " + ")) · \(charges)"
    }

    /// The card's other face. Five charges, never more: a card that grows with the month
    /// resizes the whole screen every time it turns, and the rest is one tap away.
    private func monthExpenses(_ data: DashboardData) -> some View {
        let month = data.month
        let shown = expenseWindow(month)
        return VStack(alignment: .leading, spacing: LBSpacing.s2) {
            // The month's name is the way to the whole list, in the colour of a link.
            if month.expenses.isEmpty {
                Text("Nothing in \(month.name).")
                    .lbText(.footnote)
                    .foregroundStyle(LBColor.textTertiary.color)
                    .padding(.bottom, LBSpacing.s1)
            } else {
                monthCountLine("\(month.expenses.count) expense\(month.expenses.count == 1 ? "" : "s") in",
                               month: month.name, to: listing(data))
            }
            if let line = moneyLine(data) {
                Text(line)
                    .lbText(.footnote)
                    .foregroundStyle(LBColor.textSecondary.color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .padding(.bottom, LBSpacing.s1)
            }
            VStack(alignment: .leading, spacing: LBSpacing.s2) {
            ForEach(shown) { charge in
                NavigationLink(value: Destination.commitment(id: charge.sub.id)) {
                    HStack(spacing: LBSpacing.s2) {
                        Text(LB.shortDate(charge.date))
                            .lbText(.footnote)
                            .foregroundStyle(LBColor.textTertiary.color)
                            .frame(width: 52, alignment: .leading)
                        Text(charge.sub.name)
                            .lbText(.bodySM)
                            .foregroundStyle(LBColor.textPrimary.color)
                            .lineLimit(1)
                        Spacer(minLength: LBSpacing.s2)
                        Text(fmtMoney(charge.amount, charge.currency))
                            .lbText(.bodySM)
                            .foregroundStyle(LBColor.textPrimary.color)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(LBColor.textQuaternary.color)
                    }
                    .frame(minHeight: 30)
                    .contentShape(Rectangle())
                }
                .lbButtonStyle()
                .lbTapHaptic()
            }
            }
            .frame(minHeight: 0, maxHeight: .infinity, alignment: .top)
            .clipped()
            #if os(macOS)
            // The Mac turns the card back with a word; the phone with the swipe it turned on.
            HStack {
                Spacer()
                flipControl($monthFlipped, mac: "Show Chart")
            }
            #endif
        }
        .accessibilityElement(children: .contain)
    }

    /// Money in, and what is still to go out: the latter only when the months hold this
    /// one, since a selection wholly ahead would repeat its own total.
    private func moneyLine(_ data: DashboardData) -> String? {
        let month = data.month
        let parts = [
            month.income > 0 ? "Money in \(fmtMoney(month.income, data.scope))" : nil,
        ].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// Which five. Months that include this one show what is left of them; once there is
    /// less than a card's worth ahead, the days just gone fill the rest rather than the
    /// card shrinking. Months wholly past or ahead read from their first day.
    private func expenseWindow(_ month: DashboardData.Month) -> [Charge] {
        let all = month.expenses
        let rows = backRows
        guard month.holdsThisMonth else { return Array(all.prefix(rows)) }
        let today = LB.todayMid()
        let ahead = all.filter { $0.date >= today }
        guard ahead.count < rows else { return Array(ahead.prefix(rows)) }
        return Array(all.filter { $0.date < today }.suffix(rows - ahead.count)) + ahead
    }

    /// Charges on a card's back: four on the phone, so the card keeps its front's height.
    private var backRows: Int { stacksPanels ? 4 : Self.expenseRows }

    /// A long legend makes the Accounts front tall, so its back lists as many charges as that
    /// height holds rather than four rows over blank card.
    private var accountRowsThatFit: Int {
        max(backRows, Int((accountsFrontHeight - 170) / 44))
    }

    /// "25 expenses in October 2026", the month a link to the whole list.
    private func monthCountLine(_ lead: String, month: String, to destination: Destination) -> some View {
        HStack(spacing: 4) {
            Text(lead)
                .foregroundStyle(LBColor.textTertiary.color)
            NavigationLink(value: destination) {
                Text(month)
                    .foregroundStyle(LBColor.brandText.color)
                    .contentShape(Rectangle())
            }
            .lbButtonStyle()
            .lbTapHaptic()
        }
        .lbText(.footnote)
        .lineLimit(1)
        .padding(.bottom, LBSpacing.s1)
    }

    /// The list, narrowed to the months the cards answer for and to whatever was tapped. No
    /// side is named: this month opens on what is still coming, a month gone on what landed.
    private func listing(_ data: DashboardData, methodId: String? = nil, category: String? = nil) -> Destination {
        .commitments(ListFilter(months: data.month.firstDays.map(LB.toISO), methodId: methodId, category: category))
    }

    /// The way to everything a shortened list left out.
    private func showAllLink(_ destination: Destination) -> some View {
        NavigationLink(value: destination) {
            Text("Show All")
                .lbText(.footnote)
                .foregroundStyle(LBColor.brandText.color)
                .frame(minHeight: 32)
                .contentShape(Rectangle())
        }
        .lbButtonStyle()
        .lbTapHaptic()
    }

    /// A sideways swipe turns a card. Simultaneous, not exclusive: inside a vertical
    /// ScrollView an exclusive drag loses the race and never fires. Anything inside the
    /// card that took the drag first keeps it, so stepping a month or scrolling a strip
    /// never also turns the card.
    private func flipGesture(_ flipped: Binding<Bool>, swiping: Binding<Bool>) -> some Gesture {
        DragGesture(minimumDistance: 24)
            .onChanged { drag in
                guard !innerDrag, abs(drag.translation.width) > abs(drag.translation.height) else { return }
                if !swiping.wrappedValue {
                    swiping.wrappedValue = true
                    // A cancelled drag skips onEnded; the flag frees itself.
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(1500))
                        swiping.wrappedValue = false
                    }
                }
            }
            .onEnded { drag in
                defer {
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(180))
                        swiping.wrappedValue = false
                    }
                }
                guard !innerDrag, abs(drag.translation.width) > abs(drag.translation.height) else { return }
                LBHaptics.tap()
                flipped.wrappedValue.toggle()
            }
    }

    /// How long a claim outlives its last frame. Only a cancelled drag gets this far: one
    /// that ends says so, and one still under a finger keeps renewing.
    private static let innerDragIdle: TimeInterval = 0.5

    /// A sideways drag inside a card, claimed for what it is on: the strip it scrolls or
    /// the chip it steps. Renewed every frame, so the claim outlasts a drag of any length,
    /// and marked, so a release timed by an earlier drag cannot free this one.
    private func claimInnerDrag() {
        innerDragAt = Date()
        innerDragMark &+= 1
        innerDrag = true
        guard !innerDragArmed else { return }
        innerDragArmed = true
        Task { @MainActor in
            // A cancelled drag never ends, so the claim frees itself once the frames stop
            // arriving — never on a timer set when the drag began, which would fire under
            // a finger still holding it.
            while Date().timeIntervalSince(innerDragAt) < Self.innerDragIdle {
                try? await Task.sleep(for: .milliseconds(120))
            }
            innerDragArmed = false
            innerDrag = false
        }
    }

    /// The finger lifted. The claim is held one beat longer, so the card's flip — which
    /// ends in the same instant — still reads it, then freed only if no newer drag has
    /// claimed it in the meantime.
    private func releaseInnerDrag() {
        innerDragMark &+= 1
        let mark = innerDragMark
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(180))
            guard innerDragMark == mark else { return }
            innerDrag = false
            innerDragAt = .distantPast
        }
    }

    /// The accounts the legend leaves out, as one row that turns the card to all of them.
    private func moreAccountsRow(_ count: Int) -> some View {
        Button {
            Measure.used("show_more_accounts")
            LBHaptics.tap()
            withAnimation(reduceMotion ? nil : .spring(duration: 0.45)) { accountsFlipped = true }
        } label: {
            HStack(spacing: LBSpacing.s2) {
                Text(count == 1 ? "1 more account" : "\(count) more accounts")
                    .lbText(.footnote)
                    .foregroundStyle(LBColor.brandText.color)
                Spacer(minLength: LBSpacing.s1)
            }
            .frame(minHeight: 30)
            .contentShape(Rectangle())
        }
        .lbButtonStyle()
    }

    /// The turn, as a control as well as a gesture — a swipe nobody guesses is no door.
    /// The phone says the motion; a pointer clicks, so the Mac names what the other face shows.
    private func flipControl(_ flipped: Binding<Bool>, mac: String) -> some View {
        Button {
            Measure.used("arrow_left_arrow_right")
            LBHaptics.tap()
            withAnimation(reduceMotion ? nil : .spring(duration: 0.45)) { flipped.wrappedValue.toggle() }
        } label: {
            HStack(spacing: LBSpacing.s1) {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.system(size: 9, weight: .semibold))
                #if os(macOS)
                Text(mac).lbText(.footnote)
                #else
                Text("Swipe").lbText(.footnote)
                #endif
            }
            .foregroundStyle(LBColor.brandText.color)
            .frame(minHeight: 36)
            .contentShape(Rectangle())
        }
        .lbButtonStyle()
    }

    /// One control, on every panel that answers for months, wearing their words. It opens a
    /// year of tiles rather than a menu, so the year is visible and a month is one reach away.
    private func monthMenu(_ label: String) -> some View {
        Button {
            Measure.used("pick_month")
            LBHaptics.tap()
            pickingMonth = true
        } label: {
            HStack(spacing: LBSpacing.s1) {
                Text(label)
                    .lbText(.footnote)
                // Chevrons lie flat because the motion does: this control is stepped
                // sideways, and an up-down pair would promise a gesture that does nothing.
                HStack(spacing: 0) {
                    Image(systemName: "chevron.left")
                    Image(systemName: "chevron.right")
                }
                .font(.system(size: 7, weight: .semibold))
            }
            .foregroundStyle(LBColor.textSecondary.color)
            .padding(.horizontal, LBSpacing.s2)
            .padding(.vertical, 4)
            .background(LBColor.chrome.color, in: Capsule())
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .lbButtonStyle()
        // Swiping steps every chosen month together, the way a calendar page turns:
        // left-to-right goes back, right-to-left goes forward. The card below keeps its
        // own swipe for the flip, so the two never collide.
        .simultaneousGesture(
            DragGesture(minimumDistance: 18)
                .onChanged { drag in
                    guard abs(drag.translation.width) > abs(drag.translation.height) else { return }
                    claimInnerDrag()
                }
                .onEnded { drag in
                    defer { releaseInnerDrag() }
                    guard abs(drag.translation.width) > abs(drag.translation.height) else { return }
                    LBHaptics.tap()
                    let step = drag.translation.width > 0 ? -1 : 1
                    if let next = model.selectedMonths.shifted(by: step, within: DashboardModel.monthRange) { setMonths(next) }
                }
        )
        .accessibilityLabel("Showing \(label)")
        .accessibilityHint("Choose months, or swipe to step by one month")
    }

    /// Stepping stops at the ends of the range, where a shift is refused, rather than
    /// pretending to move; the same months again reload nothing.
    private func setMonths(_ months: MonthSelection) {
        guard months != model.selectedMonths else { return }
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { model.selectedMonths = months }
    }

    // MARK: donut

    /// The months' spend by account on one face, the accounts themselves on the other —
    /// one card, turned the same way as the expenses card beside it.
    private func donutPanel(_ data: DashboardData) -> some View {
        ZStack {
            LBPanel(eyebrow: "Accounts", mark: { accountsMark }, accessory: { monthMenu(data.accountsMonthName) }) {
                donutFront(data)
                    .frame(maxHeight: rowHeight, alignment: .top)
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { accountsFrontHeight = $0 }
            .opacity(accountsFlipped ? 0 : 1)
            .accessibilityHidden(accountsFlipped)
            .allowsHitTesting(!accountsFlipped)
            LBPanel(eyebrow: "Accounts", mark: { accountsMark }, accessory: { monthMenu(data.accountsMonthName) }) {
                accountBrowser(data)
                    .frame(maxHeight: .infinity, alignment: .top)
            }
            .frame(height: accountsFrontHeight > 0 ? accountsFrontHeight : nil, alignment: .top)
            .clipped()
            .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
            .opacity(accountsFlipped ? 1 : 0)
            .accessibilityHidden(!accountsFlipped)
            .allowsHitTesting(accountsFlipped)
        }
        // One face at a time, so the card is only ever as tall as what it shows.
        .rotation3DEffect(.degrees(accountsFlipped ? 180 : 0), axis: (x: 0, y: 1, z: 0),
                          perspective: 0.45)
        .animation(reduceMotion ? nil : .spring(duration: 0.45), value: accountsFlipped)
        .disabled(accountsCardSwiping)
        .contentShape(Rectangle())
        .simultaneousGesture(flipGesture($accountsFlipped, swiping: $accountsCardSwiping))
    }

    private var accountsMark: some View {
        InsightMark(insight: model.insight("dashboard.by_account"))
    }

    @ViewBuilder
    private func donutFront(_ data: DashboardData) -> some View {
        if data.methods.isEmpty {
            DashboardEmpty(title: "No charges in \(data.accountsMonthName)", quiet: true, minHeight: 150)
        } else {
            donutStats(data)
        }
    }

    private func donutStats(_ data: DashboardData) -> some View {
        let scoped = data.methods.filter { $0.scoped > 0 }
        let top = scoped.first
        // Every panel answers for the months the chip names, so an account's door opens
        // the list on the same months the expenses card shows.
        return VStack(alignment: .leading, spacing: LBSpacing.s3) {
            LBDonut(
                slices: scoped.map { .init(value: $0.scoped, ink: LBColor.dataInk(rank: $0.ink)) },
                centerTitle: top.flatMap { $0.share.map { s in sharePct(s) } } ?? "—",
                centerNote: top.map { "From \($0.name)" } ?? "Nothing yet"
            )
            // Beside the Spending card the ring stays small enough that the two cards end
            // together; stacked on the phone it has the width to itself.
            .frame(maxWidth: stacksPanels ? 190 : 150)
            .frame(maxWidth: .infinity)
            // Beside the expenses card, the legend is at most four rows, the last one standing
            // for the rest, so this card never makes that one taller.
            let legend = stacksPanels || data.methods.count <= Self.legendRows
                ? data.methods : Array(data.methods.prefix(Self.legendRows - 1))
            // A legend is a list to read down, not a stack of buttons: the rows sit
            // close enough to be compared at a glance, and stay wide enough to hit.
            // Each row is a door: the list, narrowed to this account and these months.
            VStack(spacing: 0) {
                ForEach(legend) { slice in
                    NavigationLink(value: listing(data, methodId: slice.id)) {
                        legendRow(slice, scope: data.scope)
                            .frame(minHeight: 30)
                            .contentShape(Rectangle())
                    }
                    .lbButtonStyle()
                    .lbTapHaptic()
                }
                if data.methods.count > legend.count {
                    moreAccountsRow(data.methods.count - legend.count)
                }
            }
            Spacer(minLength: 0)
            HStack {
                Spacer()
                flipControl($accountsFlipped, mac: "Show Charges")
            }
        }
    }

    // MARK: accounts, turned over

    /// Most used, over the months shown: how often the account was charged, largest first.
    /// Money breaks a tie, then the name, so the row is the same every time the months are
    /// opened. The legend on the front keeps its own order — spend.
    private func accountsByUse(_ methods: [DashboardData.Slice]) -> [DashboardData.Slice] {
        methods.sorted { a, b in
            if a.charges.count != b.charges.count { return a.charges.count > b.charges.count }
            if a.scoped != b.scoped { return a.scoped > b.scoped }
            return a.name < b.name
        }
    }

    /// The chip the rows answer for. Months the picked account has nothing in fall back to
    /// the first chip rather than reading as an account that stopped existing.
    private func pickedAccount(_ accounts: [DashboardData.Slice]) -> DashboardData.Slice? {
        accounts.first { $0.id == pickedAccountId && !$0.charges.isEmpty } ?? accounts.first
    }

    /// The card's other face: the accounts of the months shown across the top, and what the
    /// touched one was charged, earliest first.
    private func accountBrowser(_ data: DashboardData) -> some View {
        let accounts = accountsByUse(data.methods)
        let picked = pickedAccount(accounts)
        let shown = picked.map { account in
            Array(account.charges.sorted {
                $0.date != $1.date ? $0.date < $1.date : $0.sub.name < $1.sub.name
            }.prefix(accountRowsThatFit))
        } ?? []
        return VStack(alignment: .leading, spacing: LBSpacing.s3) {
            if !accounts.isEmpty {
                accountChips(accounts, picked: picked?.id)
            }
            if let picked, !shown.isEmpty {
                // The month's name opens this account's charges for it, as the Spending card's does.
                monthCountLine("\(picked.charges.count) charge\(picked.charges.count == 1 ? "" : "s") in",
                               month: data.accountsMonthName, to: listing(data, methodId: picked.id))
            }
            if shown.isEmpty {
                Text("No charges in \(data.accountsMonthName)")
                    .lbText(.footnote)
                    .foregroundStyle(LBColor.textTertiary.color)
            } else {
                VStack(spacing: 0) {
                    ForEach(shown) { charge in
                        NavigationLink(value: Destination.commitment(id: charge.sub.id)) {
                            accountChargeRow(charge)
                        }
                        .lbButtonStyle()
                        .lbTapHaptic()
                    }
                }
                .frame(minHeight: 0, maxHeight: .infinity, alignment: .top)
                .clipped()
            }
            #if os(macOS)
            HStack {
                Spacer()
                flipControl($accountsFlipped, mac: "Show Chart")
            }
            #endif
        }
        .accessibilityElement(children: .contain)
    }

    /// Whether the chips are wider than the rail holding them. A rail with room for all of
    /// them scrolls nowhere, and a drag across it is the card's to turn on.
    private var chipsOverflow: Bool {
        chipRowWidth > chipRailWidth + 1
    }

    /// The accounts in a row that scrolls, the touched one brought back into view when the
    /// months change under it. On the Mac the chips wrap instead: the card is wide enough for
    /// a second row, and a scroll view under the card's turn did not take the pointer's clicks.
    private func accountChips(_ accounts: [DashboardData.Slice], picked: String?) -> some View {
        // One row on every device: as many accounts as the card holds, the rest behind a
        // "more" chip that lists them. Nothing to scroll, so nothing to miss with a finger.
        // The last try lets one long name shorten rather than widen the page.
        ViewThatFits(in: .horizontal) {
            ForEach(Array(stride(from: accounts.count, through: 2, by: -1)), id: \.self) { shown in
                chipRow(accounts, shown: shown, picked: picked).fixedSize()
            }
            chipRow(accounts, shown: 1, picked: picked)
        }
    }

    /// The first `shown` accounts as chips; a picked account the row would hide takes the
    /// last visible place, so the "more" chip never has to carry a name.
    private func chipRow(_ accounts: [DashboardData.Slice], shown: Int, picked: String?) -> some View {
        var visible = Array(accounts.prefix(shown))
        if let picked, !visible.contains(where: { $0.id == picked }),
           let hidden = accounts.first(where: { $0.id == picked }), !visible.isEmpty {
            visible[visible.count - 1] = hidden
        }
        let rest = accounts.filter { slice in !visible.contains { $0.id == slice.id } }
        return HStack(spacing: LBSpacing.s2) {
            ForEach(visible) { slice in
                accountChip(slice, selected: slice.id == picked)
            }
            if !rest.isEmpty {
                moreAccountsChip(rest)
            }
        }
    }

    private func accountChip(_ slice: DashboardData.Slice, selected: Bool) -> some View {
        Button {
            Measure.used("pick_account_slice")
            LBHaptics.tap()
            pickedAccountId = slice.id
        } label: {
            Text(slice.name)
                .lbText(.bodySM)
                .lineLimit(1)
                .foregroundStyle(selected ? LBColor.onBrand.color : LBColor.textSecondary.color)
                .padding(.horizontal, LBSpacing.s3)
                .frame(minHeight: 36)
                .background(selected ? LBColor.brand.color : LBColor.chrome.color, in: Capsule())
                .contentShape(Capsule())
        }
        .lbButtonStyle()
        .accessibilityLabel("\(slice.name), \(slice.charges.count) charge\(slice.charges.count == 1 ? "" : "s")")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// The accounts the row has no room for, one menu away.
    private func moreAccountsChip(_ rest: [DashboardData.Slice]) -> some View {
        Menu {
            ForEach(rest) { slice in
                Button(slice.name) { Measure.used("picked_account_id", .menuItem); pickedAccountId = slice.id }
            }
        } label: {
            HStack(spacing: LBSpacing.s1) {
                Text("\(rest.count) more")
                    .lbText(.bodySM)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
            }
            .foregroundStyle(LBColor.textSecondary.color)
            .padding(.horizontal, LBSpacing.s3)
            .frame(minHeight: 36)
            .background(LBColor.chrome.color, in: Capsule())
            .contentShape(Capsule())
        }
        .menuStyle(.button)
        .lbButtonStyle()
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("\(rest.count) more accounts")
    }

    /// One charge under the chips: when, what, which category, how much.
    private func accountChargeRow(_ charge: Charge) -> some View {
        HStack(spacing: LBSpacing.s2) {
            Text(LB.shortDate(charge.date))
                .lbText(.footnote)
                .foregroundStyle(LBColor.textTertiary.color)
                .frame(width: 52, alignment: .leading)
            VStack(alignment: .leading, spacing: 1) {
                Text(charge.sub.name)
                    .lbText(.bodySM)
                    .foregroundStyle(LBColor.textPrimary.color)
                    .lineLimit(1)
                if let category = chargeCategory(charge) {
                    Text(categoryWord(category))
                        .lbText(.footnote)
                        .foregroundStyle(LBColor.textTertiary.color)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: LBSpacing.s2)
            Text(fmtMoney(charge.amount, charge.currency))
                .lbText(.bodySM)
                .foregroundStyle(LBColor.textPrimary.color)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Image(systemName: "chevron.right")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(LBColor.textQuaternary.color)
        }
        .frame(minHeight: 38)
        .contentShape(Rectangle())
    }

    /// The category as it was typed on the commitment; the row shows it as the tiles do. A
    /// row with none says nothing rather than inventing a name for it.
    private func chargeCategory(_ charge: Charge) -> String? {
        let name = charge.sub.tag?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? nil : name
    }

    /// The two ways out of a shortened list, each named by what it widens to.
    private func accountLink(_ title: String, symbol: String, to destination: Destination, fills: Bool = true) -> some View {
        NavigationLink(value: destination) {
            HStack(spacing: LBSpacing.s1) {
                Image(systemName: symbol)
                    .font(.system(size: 10, weight: .semibold))
                    .accessibilityHidden(true)
                Text(title)
                    .lbText(.footnote)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .foregroundStyle(LBColor.brandText.color)
            .frame(maxWidth: fills ? .infinity : nil, minHeight: 32, alignment: .leading)
            .contentShape(Rectangle())
        }
        .lbButtonStyle()
        .lbTapHaptic()
    }

    private func legendRow(_ slice: DashboardData.Slice, scope: String) -> some View {
        HStack(spacing: LBSpacing.s2) {
            // A method whose money is all in another currency is present with a hollow
            // swatch — never blended into the shares.
            Group {
                if slice.scoped > 0 {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(LBColor.dataInk(rank: slice.ink).color)
                } else {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .strokeBorder(LBColor.textQuaternary.color, lineWidth: 1)
                }
            }
            .frame(width: 8, height: 8)
            // Footnote, not tabLabel: that role is the 10pt floor of the scale, meant for
            // a tab caption, and it was carrying a table of money.
            Text(slice.name)
                .lbText(.footnote)
                .foregroundStyle(LBColor.textSecondary.color)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: LBSpacing.s1)
            Text(slice.share.map(sharePct) ?? "—")
                .lbText(.footnote)
                .foregroundStyle(LBColor.textPrimary.color)
                .layoutPriority(1)
            Text(slice.scoped > 0 ? fmtMoney(slice.scoped, scope) : fmtMoneyTotals(slice.others))
                .lbText(.footnote)
                .foregroundStyle(LBColor.textTertiary.color)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .layoutPriority(1)
            Image(systemName: "chevron.right")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(LBColor.textQuaternary.color)
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the commitments this account pays for")
    }

    private func sharePct(_ share: Double) -> String {
        share >= 10 ? "\(Int(share.rounded()))%" : String(format: "%.1f%%", (share * 10).rounded() / 10)
    }

    // MARK: categories

    /// The months by category — the same months the two panels above answer for, under the
    /// same control, so every card on the dashboard reads the same way. A tile is a door:
    /// the list, narrowed to that category and these months.
    private func categoryPanel(_ data: DashboardData) -> some View {
        LBPanel(
            eyebrow: "Categories",
            mark: { InsightMark(insight: model.insight("dashboard.by_category")) },
            accessory: { monthMenu(data.accountsMonthName) }
        ) {
            VStack(alignment: .leading, spacing: LBSpacing.s3) {
                if data.categories.isEmpty {
                    DashboardEmpty(title: "No charges in \(data.accountsMonthName)", quiet: true, minHeight: 48)
                }
                #if os(macOS)
                // The window is wide enough for every tile: they wrap into rows rather than
                // running off the card's edge.
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 132), spacing: LBSpacing.s2)],
                          alignment: .leading, spacing: LBSpacing.s2) {
                    ForEach(data.categories) { slice in
                        NavigationLink(value: listing(data, category: slice.name)) {
                            categoryTile(slice, scope: data.scope)
                        }
                        .lbButtonStyle()
                    }
                }
                #else
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: LBSpacing.s2) {
                        ForEach(data.categories) { slice in
                            NavigationLink(value: listing(data, category: slice.name)) {
                                categoryTile(slice, scope: data.scope)
                            }
                            .lbButtonStyle()
                            .lbTapHaptic()
                        }
                    }
                    .lbPointerScrollTarget(tilePointer)
                }
                .lbPointerDrag(tilePointer)
                #endif
            }
        }
    }

    private func categoryTile(_ slice: DashboardData.Slice, scope: String) -> some View {
        let ink = LBColor.dataInk(rank: slice.ink)
        return VStack(alignment: .leading, spacing: LBSpacing.s2) {
            // The owner's picture of the category when there is one; the library's glyph otherwise.
            if let picture = tagPicture(slice.name) {
                picture.resizable().scaledToFill()
                    .frame(width: 30, height: 30)
                    .clipShape(RoundedRectangle(cornerRadius: LBRadius.xs, style: .continuous))
                    .accessibilityHidden(true)
            } else {
                Image(systemName: model.tagIcon(kind: "commitment", name: slice.name) ?? CategoryGlyph.symbol(slice.name))
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(ink.color)
                    .frame(width: 30, height: 30)
                    .background(LBColor.chrome.color, in: RoundedRectangle(cornerRadius: LBRadius.xs, style: .continuous))
            }
            Text(categoryWord(slice.name))
                .lbText(.footnote)
                .foregroundStyle(LBColor.textSecondary.color)
                .lineLimit(1)
            LBAmount(slice.scoped > 0 ? fmtMoney(slice.scoped, scope) : fmtMoneyTotals(slice.others), prominence: .inline)
                .foregroundStyle(LBColor.textPrimary.color)
            Text(slice.share.map(sharePct) ?? "—")
                .lbText(.footnote)
                .foregroundStyle(LBColor.textTertiary.color)
        }
        .padding(LBSpacing.s3)
        // minWidth, not width: money never clips, so a long amount stretches its tile
        // instead of losing digits mid-figure.
        .frame(minWidth: 124, maxWidth: Self.tileMaxWidth, alignment: .topLeading)
        .background(LBColor.sunken.color, in: RoundedRectangle(cornerRadius: LBRadius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: LBRadius.md, style: .continuous)
                .strokeBorder(LBColor.hairline.color, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens this category’s commitments")
    }

    private func tagPicture(_ name: String) -> Image? {
        guard let url = model.tagPhotoURL(kind: "commitment", name: name), let data = try? Data(contentsOf: url) else { return nil }
        #if os(macOS)
        return NSImage(data: data).map(Image.init(nsImage:))
        #else
        return UIImage(data: data).map(Image.init(uiImage:))
        #endif
    }

    /// A tile fills its grid cell on the Mac; in the phone's strip it is as wide as it needs.
    private static var tileMaxWidth: CGFloat? {
        #if os(macOS)
        .infinity
        #else
        nil
        #endif
    }
}

/// The width the rail has to fill, carried up from the scroll view that owns it.
private struct RailWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// The account chips and the rail they sit in, measured apart: the two widths say whether
/// the rail has anywhere to scroll, and so whether a drag across it is its own.
private struct ChipRowWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct ChipRailWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// A book with nothing in it: one way in instead of empty cards. A statement first, then
/// a commitment by hand or the reader's own AI. On the Mac a statement dropped on it opens the import.
private struct DashboardStart: View {
    /// Names setup picked that still wait for their details.
    let waiting: [String]
    let onImport: () -> Void
    let onDrop: ([URL]) -> Void
    let onAdd: () -> Void
    let onOwnAI: () -> Void
    #if os(macOS)
    @State private var dropping = false
    #endif

    private static let title = "Start with a statement"
    private static let tail = "PDF or CSV. longbook reads it and fills in what you pay, when, and from which account."

    var body: some View {
        VStack(spacing: 0) {
            #if os(macOS)
            dropZone
            HStack(spacing: LBSpacing.s3) {
                secondary("Add a commitment by hand") { Measure.used("dashboard_add_by_hand"); onAdd() }
                secondary("Use your own AI") { Measure.used("dashboard_use_own_ai"); onOwnAI() }
            }
            .padding(.top, LBSpacing.s6)
            #else
            icon(box: 72, glyph: 30, radius: 18)
            words(line: "Import a bank or card statement, \(Self.tail)")
            VStack(spacing: LBSpacing.s3) {
                primary { Measure.used("dashboard_import_statement"); onImport() }
                secondary("Add a commitment by hand") { Measure.used("dashboard_add_by_hand"); onAdd() }
                secondary("Use your own AI") { Measure.used("dashboard_use_own_ai"); onOwnAI() }
            }
            .padding(.top, LBSpacing.s6)
            .padding(.horizontal, LBSpacing.s4)
            #endif
            if !waiting.isEmpty { waitingLink.padding(.top, LBSpacing.s6) }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Self.lead)
    }

    /// The block sits a little above the middle of a new window, as it does on the phone.
    #if os(macOS)
    private static let lead: CGFloat = 76
    #else
    private static let lead: CGFloat = 88
    #endif

    private func icon(box: CGFloat, glyph: CGFloat, radius: CGFloat) -> some View {
        Image(systemName: "arrow.down.doc")
            .font(.system(size: glyph, weight: .regular))
            .foregroundStyle(LBColor.brandText.color)
            .frame(width: box, height: box)
            .background(LBColor.chrome.color, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .accessibilityHidden(true)
    }

    private func words(line: String) -> some View {
        VStack(spacing: LBSpacing.s2) {
            Text(Self.title)
                .lbText(.screenTitle)
                .foregroundStyle(LBColor.textPrimary.color)
            Text(line)
                #if os(macOS)
                .lbText(.body)
                #else
                .lbText(.bodySM)
                #endif
                .foregroundStyle(LBColor.textSecondary.color)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 420)
                #if os(iOS)
                .padding(.horizontal, LBSpacing.s6)
                #endif
        }
        .multilineTextAlignment(.center)
        .padding(.top, LBSpacing.s6)
    }

    private func primary(run: @escaping () -> Void) -> some View {
        button("Import a statement", fill: LBColor.brand.color, ink: LBColor.onBrand.color, macHeight: 32, run: run)
    }

    private func secondary(_ title: String, run: @escaping () -> Void) -> some View {
        button(title, fill: LBColor.chrome.color, ink: LBColor.textPrimary.color, macHeight: 28, run: run)
    }

    /// Full width and tall on the phone; a small pill on the Mac.
    private func button(_ title: String, fill: Color, ink: Color, macHeight: CGFloat, run: @escaping () -> Void) -> some View {
        Button {
            Measure.used("dashboard_start")
            LBHaptics.tap()
            run()
        } label: {
            Text(title)
                #if os(macOS)
                .lbText(.label)
                .padding(.horizontal, LBSpacing.s4)
                .frame(minHeight: macHeight)
                #else
                .lbText(.headline)
                .frame(maxWidth: 400, minHeight: 50)
                #endif
                .lineLimit(1)
                .foregroundStyle(ink)
                .background(fill, in: Capsule())
                .contentShape(Capsule())
        }
        .lbButtonStyle()
    }

    #if os(macOS)
    /// A statement dragged from Finder opens the import, as the button does.
    private var dropZone: some View {
        VStack(spacing: 0) {
            icon(box: 64, glyph: 26, radius: 16)
            words(line: "Drop a bank or card statement here, \(Self.tail)")
            primary { Measure.used("dashboard_import_statement"); onImport() }
                .padding(.top, LBSpacing.s6)
        }
        .padding(LBSpacing.s8)
        .frame(maxWidth: 600, minHeight: 360)
        .background(dropping ? LBColor.brand.color.opacity(0.10) : Color.clear,
                    in: RoundedRectangle(cornerRadius: LBRadius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: LBRadius.lg, style: .continuous)
                .strokeBorder(dropping ? LBColor.brand.color : LBColor.hairline.color,
                              style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
        )
        .dropDestination(for: URL.self) { urls, _ in
            guard urls.contains(where: Self.readable) else { return false }
            Measure.used("dashboard_statement_drop")
            onDrop(urls.filter(Self.readable))
            return true
        } isTargeted: { dropping = $0 }
    }

    /// The shapes the import reads: PDF, CSV, text and Excel.
    private static func readable(_ url: URL) -> Bool {
        ["pdf", "csv", "txt", "xls", "xlsx"].contains(url.pathExtension.lowercased())
    }
    #endif

    private var waitingLink: some View {
        NavigationLink(value: Destination.commitments(ListFilter())) {
            HStack(spacing: LBSpacing.s2) {
                Text("\(waiting.count) needs details: \(DashboardRail.waitingNames(waiting))")
                    .lbText(.footnote)
                    .foregroundStyle(LBColor.textSecondary.color)
                    .lineLimit(1)
                Text("Finish")
                    .lbText(.label)
                    .foregroundStyle(LBColor.brandText.color)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(LBColor.textQuaternary.color)
            }
            .frame(minHeight: 32)
            .contentShape(Rectangle())
        }
        .lbButtonStyle()
        .lbTapHaptic()
    }
}

/// What a card says when it has nothing to draw: a title, a line under it, and the one
/// next step when there is one. A quiet title only states the fact.
private struct DashboardEmpty: View {
    let title: String
    var message: String?
    var action: (label: String, run: () -> Void)?
    var quiet = false
    var minHeight: CGFloat = 0

    var body: some View {
        VStack(spacing: LBSpacing.s2) {
            Text(title)
                .lbText(quiet ? .footnote : .body)
                .foregroundStyle((quiet ? LBColor.textTertiary : LBColor.textPrimary).color)
                .multilineTextAlignment(.center)
            if let message {
                Text(message)
                    .lbText(.footnote)
                    .foregroundStyle(LBColor.textTertiary.color)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let action {
                Button {
                    Measure.used("dashboard_action")
                    LBHaptics.tap()
                    action.run()
                } label: {
                    Text(action.label)
                        .lbText(.label)
                        .foregroundStyle(LBColor.onBrand.color)
                        .padding(.horizontal, LBSpacing.s3)
                        .frame(minHeight: 34)
                        .background(LBColor.brand.color, in: Capsule())
                        .contentShape(Capsule())
                }
                .lbButtonStyle()
                .padding(.top, LBSpacing.s1)
            }
        }
        .frame(maxWidth: .infinity, minHeight: minHeight)
    }
}

/// The 30-day rail, a view of its own on purpose: the pull updates state on every frame
/// of the finger, and owning that state here keeps the rest of the dashboard still.
private struct DashboardRail: View {
    let model: DashboardModel
    let rail: DashboardData.Rail
    /// Opens the statement importer — the past is filled from a statement, never typed in.
    let onImport: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var railPull: CGFloat = 0
    @State private var railPullStep = 0
    @State private var railEdge: String?
    /// Whether this drag began with nothing left to scroll — the only start that can
    /// mean a pull. A drag that reaches the edge mid-flight stays a scroll.
    @State private var pullArmed: Bool?
    /// How wide the rail is allowed to be, so a row of cards too short to fill it can
    /// still put its far edge where the reader looks for one. Zero until first measured.
    @State private var railWidth: CGFloat = 0
    /// The pointer's hold on the strip: a mouse pulls the cards as a finger does.
    @State private var pointer = LBPointerScroll()

    var body: some View {
        LBPanel(
            eyebrow: rail.looksBack ? "Recent charges" : "Coming up",
            note: rail.looksBack && rail.charges.isEmpty ? nil : railNote,
            mark: { InsightMark(insight: model.insight("dashboard.next_30_days")) }
        ) {
            VStack(alignment: .leading, spacing: LBSpacing.s3) {
                // The day cards are a fixed width so a week reads across; past the largest
                // standard size their words were cut to "In 2…", so they stop growing there.
                railStrip(rail)
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                railFooter(rail)
            }
        }
    }

    /// The cards, counted in their own words: commitments ahead, charges behind, and a
    /// transfer on the timeline is never called either.
    private var railNote: String {
        let noun = rail.looksBack ? "charge" : "commitment"
        let counted = "\(rail.upcomingCount) \(noun)\(rail.upcomingCount == 1 ? "" : "s")"
        guard rail.transferCount > 0 else { return counted }
        return counted + " · \(rail.transferCount) transfer\(rail.transferCount == 1 ? "" : "s")"
    }

    /// A finger needs a dozen points to mean a scroll; a pointer, pressed on purpose,
    /// needs fewer before the strip should follow it.
    #if os(macOS)
    private static let grab: CGFloat = 6
    #else
    private static let grab: CGFloat = 12
    #endif

    /// The cards, plus the control that asks for the days behind today. Two ways in,
    /// deliberately: the pull the owner designed, and a button that cannot be missed.
    private func railStrip(_ rail: DashboardData.Rail) -> some View {
        ScrollViewReader { proxy in
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: LBSpacing.s2) {
                if !rail.looksBack {
                    edgeChip(back: true).id(Self.edgeChipID)
                }
                // What setup was told and nobody has filled in yet stands first, ahead of
                // the days: one card that opens the list where each is filled in.
                if !rail.looksBack, !model.placeholders.isEmpty {
                    NavigationLink(value: Destination.commitments(ListFilter())) {
                        toFillCard
                    }
                    .lbButtonStyle()
                    .lbTapHaptic()
                }
                if rail.charges.isEmpty {
                    if rail.looksBack {
                        // Centred in the room the way back to today leaves, with its one button.
                        DashboardEmpty(
                            title: "No past payments yet",
                            message: "Import a statement to see your past charges.",
                            action: ("Import a statement", onImport),
                            minHeight: Self.cardHeight
                        )
                        .frame(width: max(railWidth - Self.edgeChipSpace - LBSpacing.s2 * 2, 200))
                    } else if model.placeholders.isEmpty {
                        // The card's own height, so the section stays the size it is with one.
                        Text("No upcoming payments.")
                            .lbText(.footnote)
                            .foregroundStyle(LBColor.textTertiary.color)
                            .frame(minHeight: Self.cardHeight)
                    }
                }
                ForEach(rail.charges) { charge in
                    NavigationLink(value: Destination.commitment(id: charge.sub.id)) {
                        railCard(charge, looksBack: rail.looksBack)
                    }
                    .lbButtonStyle()
                    .lbTapHaptic()
                }
                if rail.looksBack {
                    // The way out belongs at the edge it leads to. A wide window and a
                    // short month leave the row ending well before the panel does, and
                    // the chip stranded mid-air reads as something dropped there.
                    Spacer(minLength: 0)
                    edgeChip(back: false).id(Self.edgeChipID)
                }
            }
            .scrollTargetLayout()
            // Only room the cards leave unused: a row that overflows ignores this.
            .frame(minWidth: railWidth, alignment: .leading)
            .lbPointerScrollTarget(pointer)
        }
        .background(
            GeometryReader { geo in
                Color.clear.preference(key: RailWidthKey.self, value: geo.size.width)
            }
        )
        .onPreferenceChange(RailWidthKey.self) { railWidth = $0 }
        // Looking back, the scroll parks at the far end, so the edge that matters is
        // the trailing one — the anchor follows the direction for that reason.
        .scrollPosition(id: $railEdge, anchor: rail.looksBack ? .trailing : .leading)
        // The turn lands on the chip at the far end, the day just gone beside it. Stated
        // twice because the cards change with the turn: set once, it lands mid-list.
        .onChange(of: rail.looksBack) { _, back in
            railEdge = Self.edgeChipID
            pullArmed = nil
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(80))
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) {
                    proxy.scrollTo(Self.edgeChipID, anchor: back ? .trailing : .leading)
                }
            }
        }
        // Looking back, the chip that widens under the pull is the last thing in the row:
        // the strip follows its trailing edge, or the chip grew out of sight past the panel.
        .onChange(of: railPull) { _, pull in
            guard rail.looksBack, pull > 0 else { return }
            proxy.scrollTo(Self.edgeChipID, anchor: .trailing)
        }
        // The pull is read from the finger, not from the scroll view's bounce: the bounce
        // never reached the layout system, so the first cut of this never fired. Both
        // ends work the same way — forward out of the past, back out of the future.
        .modifier(RailDrag(gesture: railDrag(rail)))
        #if os(macOS)
        // A pointer has no bounce and no sideways wheel, so the cursor says the strip
        // can be held. Under a press it scrolls with the pointer, as a finger would.
        .onContinuousHover { phase in
            switch phase {
            case .active: pointer.hover(true)
            case .ended: pointer.hover(false)
            }
        }
        .onDisappear { pointer.hover(false) }
        #endif
        }
    }

    /// One drag, two meanings: a scroll while there is somewhere to go, a pull toward the
    /// other thirty days once there is not. On a Mac the scroll is the pointer's own.
    private func railDrag(_ rail: DashboardData.Rail) -> some Gesture {
        DragGesture(minimumDistance: Self.grab)
            .onChanged { value in
                if pullArmed == nil { pullArmed = atOutwardEdge(rail) }
                let pulled = pullDistance(value.translation, rail: rail)
                guard pulled > 0 else {
                    // An ordinary scroll must not touch state: a write per frame
                    // here was what made the whole screen stutter under the thumb.
                    if railPull != 0 { railPull = 0; railPullStep = 0 }
                    pointer.drag(value.translation.width)
                    return
                }
                // Quantized so layout moves in a few calm steps, not 120 of them.
                let next = min((pulled / 8).rounded(.down) * 8, Self.pullThreshold * 1.3)
                if next != railPull { railPull = next }
                answerPull()
            }
            .onEnded { value in
                let pulled = pullDistance(value.translation, rail: rail)
                railPull = 0
                railPullStep = 0
                let armed = pullArmed == true
                pullArmed = nil
                pointer.end(translation: value.translation.width, predicted: value.predictedEndTranslation.width)
                guard armed, pulled > Self.pullThreshold else { return }
                LBHaptics.commit()
                setLooksBack(!rail.looksBack)
            }
    }

    /// On iOS the drag rides beside the scroll view's own pan; on a Mac, where the pan
    /// belongs to the pointer, the drag outranks the cards so a hold never ends as a click.
    private struct RailDrag<G: Gesture>: ViewModifier {
        let gesture: G

        func body(content: Content) -> some View {
            #if os(macOS)
            content.highPriorityGesture(gesture)
            #else
            content.simultaneousGesture(gesture)
            #endif
        }
    }

    /// How far this drag counts as a pull toward the other thirty days: rightward with
    /// nothing left to scroll toward today's side, and only while it stays a sideways
    /// motion. An ordinary scroll measures zero, whichever way the rail is facing.
    private func pullDistance(_ translation: CGSize, rail: DashboardData.Rail) -> CGFloat {
        guard pullArmed == true else { return 0 }
        guard abs(translation.width) > abs(translation.height) * 2.2 else { return 0 }
        if rail.looksBack {
            guard translation.width < 0 else { return 0 }
            return -translation.width
        }
        guard translation.width > 0 else { return 0 }
        return translation.width
    }

    /// Nothing left to scroll toward the way out — today's side ahead, or the far end
    /// behind. Only a drag that starts here can be a pull.
    private func atOutwardEdge(_ rail: DashboardData.Rail) -> Bool {
        rail.looksBack ? atTrailingEdge(rail) : atLeadingEdge(rail)
    }

    /// The hand hears the effort as it is spent: a quiet knock at each quarter of the
    /// way, firmer as the turn comes within reach, so the threshold is felt before it
    /// is crossed rather than discovered by trying.
    private func answerPull() {
        let step = Int(railPull / Self.pullThreshold * 4)
        guard step > railPullStep else { return }
        railPullStep = step
        LBHaptics.pull(Double(railPull / Self.pullThreshold))
    }

    /// Far enough to be a decision, short enough to be one motion.
    private static let pullThreshold: CGFloat = 110
    private static let edgeChipID = "rail-edge-chip"
    private static let cardWidth: CGFloat = 136
    /// The edge chip at rest — its circle and the finger's padding around it.
    private static let edgeChipSpace: CGFloat = 42
    /// A charge card's height — eyebrow, date, name, amount and padding — so the row
    /// keeps that height when a summary card stands alone.
    private static let cardHeight: CGFloat = 96

    /// Nothing left to scroll toward the older end — the only moment a rightward pull
    /// can mean "show me what came before". A pointer knows the offset itself; a finger
    /// is read from the card at the edge.
    private func atLeadingEdge(_ rail: DashboardData.Rail) -> Bool {
        if pointer.overflows { return pointer.atStart }
        return railEdge == nil || railEdge == Self.edgeChipID || railEdge == rail.charges.first?.id
    }

    /// The mirror of it, for the days behind: nothing left to scroll toward today, so a
    /// leftward pull can only mean "take me back to what's coming".
    private func atTrailingEdge(_ rail: DashboardData.Rail) -> Bool {
        if pointer.overflows { return pointer.atEnd }
        return rail.charges.isEmpty || railEdge == Self.edgeChipID || railEdge == rail.charges.last?.id
    }

    /// The way out of the 30 on screen, at whichever end leads out of them.
    private func edgeChip(back: Bool) -> some View {
        let spent = min(railPull / Self.pullThreshold, 1)
        // The words are the reward for the motion, not an instruction before it.
        let named = min(max((spent - 0.15) / 0.5, 0), 1)
        return Button {
            Measure.used("change_period")
            LBHaptics.tap()
            setLooksBack(back)
        } label: {
            VStack(spacing: LBSpacing.s1) {
                Image(systemName: back ? "chevron.left" : "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                // Out of the layout at rest, so the chevron sits in the circle's centre.
                if named > 0 {
                    Text(back ? "Last\n30 payments" : "Next\n30 payments")
                        .lbText(.footnote)
                        .multilineTextAlignment(.center)
                        .fixedSize()
                        .opacity(named)
                }
            }
            .foregroundStyle(LBColor.brandText.color)
            // A tall sliver at rest, the cards' height, wide enough only to say that
            // something is here. The pull widens it under the finger into a card.
            .frame(width: 22 + spent * 88)
            .frame(maxHeight: .infinity)
            .animation(.interactiveSpring(response: 0.22, dampingFraction: 0.86), value: railPull)
            .background(
                RoundedRectangle(cornerRadius: LBRadius.sm, style: .continuous)
                    .fill(LBColor.brand.color.opacity(0.14))
            )
            .overlay(
                RoundedRectangle(cornerRadius: LBRadius.sm, style: .continuous)
                    .strokeBorder(LBColor.brand.color, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: LBRadius.sm, style: .continuous))
            // The finger gets a wider target than the paint, taken out of the gap.
            .padding(.horizontal, 6)
            .contentShape(Rectangle())
        }
        .lbButtonStyle()
        .accessibilityLabel(back ? "Show the last 30 payments" : "Back to the next 30 payments")
    }

    /// The span the cards cover, said once under them; the chip at the edge is the way
    /// to the other span.
    private func railFooter(_ rail: DashboardData.Rail) -> some View {
        Text(rail.looksBack ? "Last 30 payments" : "Next 30 payments")
            .lbText(.footnote)
            .foregroundStyle(LBColor.textTertiary.color)
            .frame(maxWidth: .infinity, alignment: rail.looksBack ? .leading : .trailing)
    }

    private func setLooksBack(_ back: Bool) {
        guard model.railLooksBack != back else { return }
        railPull = 0
        withAnimation(reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.85)) {
            model.railLooksBack = back
        }
    }

    private func railCard(_ charge: Charge, looksBack: Bool) -> some View {
        let days = LB.daysBetween(LB.todayMid(), charge.date)
        let isToday = days == 0
        // The archived rule: the urgency colour appears from today out to three days.
        // A charge already behind us is never urgent, whatever its distance.
        let eyebrowInk: LBColorValue = isToday
            ? LBColor.brandText
            : (looksBack ? LBColor.textTertiary : (days <= 3 ? LBColor.urgent : LBColor.textTertiary))
        return VStack(alignment: .leading, spacing: 3) {
            Text(looksBack ? LB.agoWord(days) : LB.dayWord(days))
                .lbText(.eyebrow)
                .foregroundStyle(eyebrowInk.color)
            HStack(spacing: LBSpacing.s1) {
                Text(LB.shortDate(charge.date))
                    .lbText(.footnote)
                    .foregroundStyle(LBColor.textTertiary.color)
                // Flagged beside its day, as a list row's fact is, so the card keeps its
                // height: on the timeline, in no total.
                if charge.sub.isTransfer {
                    Image(systemName: LBGlyph.transfer)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(LBColor.textSecondary.color)
                        .accessibilityHidden(true)
                    Text("Transfer")
                        .lbText(.footnote)
                        .foregroundStyle(LBColor.textSecondary.color)
                }
            }
            .lineLimit(1)
            Text(charge.sub.name)
                .lbText(.bodySM)
                .foregroundStyle(LBColor.textPrimary.color)
                .lineLimit(1)
                .truncationMode(.tail)
            HStack(spacing: LBSpacing.s1) {
                LBAmount(fmtMoney(charge.amount, charge.currency), prominence: .inline)
                    .foregroundStyle(LBColor.textPrimary.color)
                // Behind today every charge is paid; the badge means a hand marked it.
                if charge.paid, !looksBack || isToday {
                    LBBadge("Paid", tone: .brand)
                }
            }
        }
        .padding(LBSpacing.s3)
        // One width for every card, so the row reads as a row: a long name ends in an
        // ellipsis and an amount tightens rather than widening its card.
        .frame(minWidth: Self.cardWidth, maxWidth: Self.cardWidth, minHeight: Self.cardHeight, maxHeight: .infinity, alignment: .topLeading)
        .background(
            LBColor.sunken.color,
            in: RoundedRectangle(cornerRadius: LBRadius.md, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: LBRadius.md, style: .continuous)
                .strokeBorder(isToday ? LBColor.brand.color : LBColor.hairline.color, lineWidth: 1)
        )
        // A past charge is a record, not a plan — it reads a step quieter.
        .opacity(looksBack && !isToday ? 0.85 : 1)
        .accessibilityElement(children: .combine)
    }

    /// The chrome of a needs-details card in the rail — canvas fill, dashed brand edge —
    /// carrying the count rather than one name.
    private var toFillCard: some View {
        dashedCard(eyebrow: "Needs details", body: "Details waiting to be filled in.")
            .accessibilityLabel("\(model.placeholders.count) needs details. \(waitingNames)")
            .accessibilityHint("Opens Commitments.")
    }

    private var waitingNames: String {
        Self.waitingNames(model.placeholders.map(\.name))
    }

    /// The first three names waiting, then how many more.
    static func waitingNames(_ names: [String]) -> String {
        let shown = names.prefix(3).joined(separator: ", ")
        return names.count > 3 ? "\(shown) and \(names.count - 3) more" : shown
    }

    /// A summary card in the rail: an eyebrow and a sentence, at a charge card's size.
    private func dashedCard(eyebrow: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(eyebrow)
                .lbText(.eyebrow)
                .foregroundStyle(LBColor.brandText.color)
            Text(body)
                .lbText(.footnote)
                .foregroundStyle(LBColor.textPrimary.color)
                .lineLimit(3)
                .minimumScaleFactor(0.85)
        }
        .padding(LBSpacing.s3)
        // The same height as the charge cards beside it: the strip's rows stretch together.
        .frame(minWidth: Self.cardWidth, maxWidth: Self.cardWidth, minHeight: Self.cardHeight, maxHeight: .infinity, alignment: .topLeading)
        .background(LBColor.canvas.color, in: RoundedRectangle(cornerRadius: LBRadius.md, style: .continuous))
        .lbDashedOutline(cornerRadius: LBRadius.md)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

}
