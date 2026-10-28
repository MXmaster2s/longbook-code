import DesignSystem
import LongbookCore
import SwiftUI

/// The month as real charges, both directions — what already landed and what's coming.
/// Cells stay uniform: a day wears a dot per charge, or their count past three, never
/// amount text that warps the grid. Tapping a day lays its details below; the full list
/// stays one more tap away.
struct CalendarView: View {
    let model: DashboardModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    /// The month at the top of the stream — the one the header names and the steps move.
    #if os(iOS)
    /// The phone reads the position through the binding but moves with the reader, which
    /// lands a month under the title bar rather than behind it.
    @State private var visibleOffset: Int? = 0
    @State private var wanted: Int?
    #else
    @State private var visibleOffset: Int? = 0
    #endif
    @State private var selected: String?

    /// Four years of months, two either side of this one; the stream draws only what shows.
    private static let reach = 24
    private var offsets: [Int] { Array(-Self.reach...Self.reach) }
    private var offset: Int { visibleOffset ?? 0 }
    private var shownMonth: DashboardModel.CalendarMonth? { model.calendarMonth(offset: offset) }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(LBColor.canvas.color)
            .screenTutorial(.calendar)
            .onAppear { if selected == nil, offset == 0 { selected = Self.todayId } }
            .lbScreenTitle("Calendar") {
                if let month = shownMonth {
                    Button("Today") { Measure.used("today"); goToday() }
                        .disabled(atToday)
                        .help("Today")
                    Button { Measure.used("previous_month"); step(-1, in: month) } label: { Label("Previous month", systemImage: "chevron.left") }
                        .disabled(month.atStart)
                        .help("Previous month")
                        .accessibilityLabel("Previous month")
                    Button { Measure.used("next_month"); step(1, in: month) } label: { Label("Next month", systemImage: "chevron.right") }
                        .disabled(month.atEnd)
                        .help("Next month")
                        .accessibilityLabel("Next month")
                }
            }
            #if os(macOS)
            // The month beside the title, and the Go menu's doors to the same steps.
            .navigationSubtitle(shownMonth?.title ?? "")
            .onMacCommand(.today) { if !atToday { goToday() } }
            .onMacCommand(.previousMonth) { if let month = shownMonth, !month.atStart { step(-1, in: month) } }
            .onMacCommand(.nextMonth) { if let month = shownMonth, !month.atEnd { step(1, in: month) } }
            #endif
    }

    @ViewBuilder
    private var content: some View {
        #if os(macOS)
        VStack(alignment: .leading, spacing: LBSpacing.s3) {
            // The months scroll on the left; the picked day's details stand beside them.
            HStack(alignment: .top, spacing: LBSpacing.s4) {
                VStack(alignment: .leading, spacing: LBSpacing.s2) {
                    weekdayRow
                    monthStream
                }
                .frame(minWidth: 420, maxWidth: .infinity)
                .tutorialTarget(.calendarMonth)
                detailsPanel.frame(width: 300)
                    .tutorialTarget(.calendarDay)
            }
        }
        .lbPageColumn(.wide)
        #else
        // The phone turns one month at a time, the way a wall calendar does: the stream of
        // months is the Mac's, where the details stand beside it rather than between months.
        ScrollView {
            VStack(alignment: .leading, spacing: LBSpacing.s3) {
                if let month = shownMonth {
                    Text(month.title)
                        .lbText(.headline)
                        .foregroundStyle(LBColor.textPrimary.color)
                        .accessibilityAddTraits(.isHeader)
                    weekdayRow
                    grid(month)
                        .tutorialTarget(.calendarMonth)
                    dayContent(month)
                        .tutorialTarget(.calendarDay)
                }
            }
            .lbPageColumn(.wide)
        }
        .onChange(of: offset) { _, now in selected = now == 0 ? Self.todayId : nil }
        #endif
    }

    /// The months one under the other, scrolled like Calendar's: the next month's days come
    /// up from below as this one's go. The month at the top is the one the header names.
    private var monthStream: some View {
        ScrollViewReader { proxy in
        ScrollView {
            LazyVStack(alignment: .leading, spacing: LBSpacing.s4) {
                ForEach(offsets, id: \.self) { off in
                    if let month = model.calendarMonth(offset: off) {
                        VStack(alignment: .leading, spacing: LBSpacing.s2) {
                            Text(month.title)
                                .lbText(.headline)
                                .foregroundStyle(LBColor.textPrimary.color)
                                .accessibilityAddTraits(.isHeader)
                            #if os(iOS)
                            weekdayRow
                            #endif
                            grid(month)
                            #if os(iOS)
                            // The picked day's details sit under its own month, in the stream.
                            if selectedMonthOffset == off { dayContent(month) }
                            #endif
                        }
                        .id(off)
                    }
                }
            }
            .scrollTargetLayout()
            #if os(iOS)
            .lbPageColumn(.wide)
            #endif
        }
        .scrollPosition(id: $visibleOffset, anchor: .top)
        #if os(iOS)
        .onAppear { DispatchQueue.main.async { proxy.scrollTo(0, anchor: .top) } }
        .onChange(of: wanted) { _, target in
            guard let target else { return }
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) { proxy.scrollTo(target, anchor: .top) }
            wanted = nil
        }
        #endif
        }
    }

    /// A programmatic move: the Mac sets the position, the phone asks the reader.
    private func show(_ target: Int) {
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) { visibleOffset = target }
    }

    /// The month the picked day falls in, as an offset from this one.
    private var selectedMonthOffset: Int? {
        guard let selected, let date = LB.parseDate(selected) else { return nil }
        return LB.calendar.dateComponents([.month], from: LB.firstOfMonth(LB.todayMid()), to: LB.firstOfMonth(date)).month
    }

    private static var todayId: String { LB.toISO(LB.todayMid()) }

    /// This month on show with today picked: nothing for Today to do.
    private var atToday: Bool { offset == 0 && selected == Self.todayId }

    private func goToday() {
        LBHaptics.tap()
        show(0)
        selected = Self.todayId
    }

    private var weekdayRow: some View {
        HStack(spacing: LBSpacing.s1) {
            ForEach(0..<7, id: \.self) { i in
                Text(LB.weekdayInitials[i])
                    .lbText(.eyebrow)
                    .foregroundStyle(LBColor.textTertiary.color)
                    #if os(macOS)
                    // Over the day numbers, which sit at each cell's leading edge.
                    .padding(.leading, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    #else
                    .frame(maxWidth: .infinity)
                    #endif
            }
        }
    }

    private func grid(_ month: DashboardModel.CalendarMonth) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: LBSpacing.s1), count: 7), spacing: LBSpacing.s1) {
            ForEach(month.days) { day in
                cell(day)
            }
        }
        // Seven columns hold a two-digit day only so large: past the largest standard size the
        // numbers clipped, so the grid stops growing there, as Calendar's own month does.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        // Without a shape the grid is only hit-testable where its days are, so a swipe
        // that begins in the space between them never begins at all.
        .contentShape(Rectangle())
        // The page turns under the thumb, the way a wall calendar does: left-to-right goes
        // back, right-to-left goes forward. Simultaneous, not exclusive — inside a vertical
        // ScrollView an exclusive drag loses the race and never fires.
        .simultaneousGesture(
            DragGesture(minimumDistance: 24).onEnded { drag in
                guard abs(drag.translation.width) > abs(drag.translation.height) else { return }
                step(drag.translation.width > 0 ? -1 : 1, in: month)
            }
        )
        .accessibilityHint("Swipe sideways to change month")
    }

    /// Stepping stops at the ends of the range rather than pretending to move and
    /// answering with the same month.
    private func step(_ delta: Int, in month: DashboardModel.CalendarMonth) {
        guard delta < 0 ? !month.atStart : !month.atEnd else { return }
        LBHaptics.tap()
        show(offset + delta)
    }

    @ViewBuilder
    private func cell(_ day: DashboardModel.CalendarDay) -> some View {
        if day.inMonth {
            Button {
                Measure.used("pick_day")
                selected = selected == day.id ? nil : day.id
            } label: {
                cellBody(day)
            }
            .lbButtonStyle()
            .accessibilityLabel(cellWord(day))
            .accessibilityHint("Shows the day’s details.")
            .accessibilityAddTraits(selected == day.id ? .isSelected : [])
        } else {
            // Padding cells belong to the neighbouring month — visible, never a door.
            cellBody(day).opacity(0.25).accessibilityHidden(true)
        }
    }

    /// The spoken cell: a real date instead of raw ISO, today named, the count
    /// pluralised, and the all-paid mark said out loud — everything the eye gets. A past
    /// day carries no mark: its charges are paid by the calendar, not by hand.
    private func cellWord(_ day: DashboardModel.CalendarDay) -> String {
        let date = LB.parseDate(day.id).map(LB.shortDate) ?? day.id
        var word = "\(date)\(day.isToday ? ", today" : "")"
        word += ", \(day.charges.count) payment\(day.charges.count == 1 ? "" : "s")"
        if !day.transfers.isEmpty { word += ", " + transferWord(day.transfers.count) }
        if allPaid(day) { word += ", all paid" }
        return word
    }

    /// Transfers are counted in their own words, beside the payments and never among them.
    private func transferWord(_ count: Int) -> String {
        "\(count) transfer\(count == 1 ? "" : "s")"
    }

    /// Everything owed that day carries its mark, a transfer included. Never said of a past day.
    private func allPaid(_ day: DashboardModel.CalendarDay) -> Bool {
        let owed = day.charges + day.transfers
        return !day.isPast && !owed.isEmpty && owed.allSatisfy(\.paid)
    }

    @ViewBuilder
    private func cellBody(_ day: DashboardModel.CalendarDay) -> some View {
        #if os(macOS)
        macCellBody(day)
        #else
        phoneCellBody(day)
        #endif
    }

    /// Every Mac day is one height, whatever it holds: three payments named on a line each,
    /// the rest counted. A day never grows and never shrinks the week.
    private let macCellHeight: CGFloat = 100

    /// How many payments a Mac cell names before it counts the rest.
    private static let namedPerCell = 3

    /// A Mac day: its number at the top, then up to three payments by name with their
    /// amounts, transfers flagged, the rest counted. Today's number sits in a filled circle.
    private func macCellBody(_ day: DashboardModel.CalendarDay) -> some View {
        let faded = day.isPast && day.inMonth && !day.isToday
        let entries = day.charges.map { ($0, false) } + day.transfers.map { ($0, true) }
        return VStack(alignment: .leading, spacing: 3) {
            Text("\(day.dayNumber)")
                .lbText(.label)
                .foregroundStyle(day.isToday ? LBColor.onBrand.color
                                 : faded ? LBColor.textTertiary.color : LBColor.textPrimary.color)
                .frame(minWidth: 22, minHeight: 22)
                .background(Circle().fill(day.isToday ? LBColor.brand.color : Color.clear))
            ForEach(Array(entries.prefix(Self.namedPerCell).enumerated()), id: \.offset) { _, entry in
                HStack(alignment: .center, spacing: 4) {
                    if entry.1 {
                        Image(systemName: LBGlyph.transfer)
                            .font(.system(size: 7, weight: .bold))
                            .foregroundStyle(LBColor.textSecondary.color)
                    } else {
                        Circle()
                            .fill(LBColor.dataInk(rank: entry.0.ink).color)
                            .frame(width: 5, height: 5)
                    }
                    // The name keeps the line. The amount follows whole when the cell has
                    // room for both, and waits for the Preview when it has not.
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 4) {
                            Text(entry.0.name)
                                .lbText(.footnote)
                                .foregroundStyle(faded ? LBColor.textTertiary.color : LBColor.textSecondary.color)
                                .fixedSize()
                            Spacer(minLength: 2)
                            Text(entry.0.amountText)
                                .lbText(.footnote)
                                .foregroundStyle(LBColor.textTertiary.color)
                                .fixedSize()
                        }
                        Text(entry.0.name)
                            .lbText(.footnote)
                            .foregroundStyle(faded ? LBColor.textTertiary.color : LBColor.textSecondary.color)
                            .truncationMode(.tail)
                    }
                }
                .lineLimit(1)
            }
            if entries.count > Self.namedPerCell {
                Text("\(entries.count - Self.namedPerCell) more")
                    .lbText(.footnote)
                    .foregroundStyle(LBColor.textTertiary.color)
            }
            Spacer(minLength: 0)
        }
        .padding(6)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: macCellHeight)
        .clipped()
        .background(LBColor.card.color.opacity(day.inMonth ? 1 : 0), in: RoundedRectangle(cornerRadius: LBRadius.sm, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: LBRadius.sm, style: .continuous)
                .strokeBorder(selected == day.id ? LBColor.brandText.color : Color.clear, lineWidth: 1.5)
        )
        .contentShape(Rectangle())
    }

    private func phoneCellBody(_ day: DashboardModel.CalendarDay) -> some View {
        let faded = day.isPast && day.inMonth && !day.isToday
        return VStack(spacing: 4) {
            // The date outranks its marks — body over the marks' tabLabel — so the day is what a
            // scanning eye reads first. Today wears a filled circle; the picked day a ring
            // around its number, so picking today still shows.
            Text("\(day.dayNumber)")
                .lbText(.body)
                .foregroundStyle(day.isToday ? LBColor.onBrand.color
                                 : faded ? LBColor.textTertiary.color : LBColor.textPrimary.color)
                .frame(width: 30, height: 30)
                .background(Circle().fill(day.isToday ? LBColor.brand.color : Color.clear))
                .frame(height: 38)
            if day.charges.isEmpty, day.transfers.isEmpty {
                Color.clear.frame(height: 10)
            } else {
                marks(day)
            }
        }
        .padding(.vertical, 2)
        .frame(minHeight: 56)
        .frame(maxWidth: .infinity)
        // Each day in its own box: the border is what says a day can be tapped, and the
        // picked day's box wears the brand, as the Mac's does.
        .background(LBColor.sunken.color.opacity(day.inMonth ? 1 : 0), in: RoundedRectangle(cornerRadius: LBRadius.sm, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: LBRadius.sm, style: .continuous)
                .strokeBorder(selected == day.id ? LBColor.brandText.color : LBColor.hairline.color.opacity(day.inMonth ? 1 : 0),
                              lineWidth: selected == day.id ? 1.5 : 1)
        )
        .contentShape(Rectangle())
    }

    /// One dot per charge up to three, in the category colours; past three, the count. A ✓
    /// follows once every charge that day carries its mark, never on a past day. A transfer
    /// wears its glyph, outside the count.
    private func marks(_ day: DashboardModel.CalendarDay) -> some View {
        let allPaid = self.allPaid(day)
        // Two dots at most, in the category colours, a transfer as a grey one; past two, a
        // small plus. The day's list says the rest.
        let inks: [LBColorValue] = day.charges.map { LBColor.dataInk(rank: $0.ink) }
            + day.transfers.map { _ in LBColor.textTertiary }
        return HStack(spacing: 3) {
            ForEach(Array(inks.prefix(2).enumerated()), id: \.offset) { _, ink in
                Circle()
                    .fill(ink.color)
                    .frame(width: 5, height: 5)
            }
            if inks.count > 2 {
                Image(systemName: "plus")
                    .font(.system(size: 6, weight: .heavy))
                    .foregroundStyle(LBColor.textSecondary.color)
            }
            if allPaid {
                Image(systemName: "checkmark")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(LBColor.textTertiary.color)
            }
        }
        .frame(height: 10)
    }

    private typealias Entry = (subId: String, name: String, amountText: String, paid: Bool, ink: Int?)

    /// The same details as a standing side panel — the Mac's wide-layout seat.
    private var detailsPanel: some View {
        VStack(alignment: .leading, spacing: LBSpacing.s2) {
            if let month = selectedMonthOffset.flatMap({ model.calendarMonth(offset: $0) }) ?? shownMonth {
                dayContent(month)
            }
            Spacer(minLength: 0)
        }
        .padding(LBSpacing.s3)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(LBColor.sunken.color, in: RoundedRectangle(cornerRadius: LBRadius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: LBRadius.md, style: .continuous)
                .strokeBorder(LBColor.hairline.color, lineWidth: 1)
        )
    }

    /// The picked day's charges, laid below the grid — the door to the filtered list stays,
    /// one tap deeper. A day with nothing in it says so and shows what comes next in the
    /// month, so the space under the grid is never left bare.
    @ViewBuilder
    private func dayContent(_ month: DashboardModel.CalendarMonth) -> some View {
        if let selected, let day = month.days.first(where: { $0.id == selected && $0.inMonth }) {
            detailsHeadline(day)
            ForEach(Array(day.charges.enumerated()), id: \.offset) { _, charge in
                chargeRow(charge, day: day)
            }
            ForEach(Array(day.transfers.enumerated()), id: \.offset) { _, charge in
                chargeRow(charge, day: day, transfer: true)
            }
            if day.charges.isEmpty, day.transfers.isEmpty {
                nextPayments(after: day, in: month)
            }
        } else {
            // The Mac panel says this; without it the phone never revealed that a
            // details section exists at all.
            Text("A day’s payments appear here.")
                .lbText(.footnote)
                .foregroundStyle(LBColor.textTertiary.color)
        }
    }

    /// The first three payments after the picked day, from today on, within the month shown.
    @ViewBuilder
    private func nextPayments(after day: DashboardModel.CalendarDay, in month: DashboardModel.CalendarMonth) -> some View {
        let coming = month.days
            .filter { $0.inMonth && !$0.isPast && $0.date > day.date }
            .flatMap { later in later.charges.map { (day: later, charge: $0) } }
            .prefix(3)
        if !coming.isEmpty {
            Text("Next payments")
                .lbText(.footnote)
                .foregroundStyle(LBColor.textTertiary.color)
                .padding(.top, LBSpacing.s3)
            ForEach(Array(coming.enumerated()), id: \.offset) { _, entry in
                chargeRow(entry.charge, day: entry.day, dated: true)
            }
        }
    }

    private static let dayTitleFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = LB.calendar
        formatter.locale = .current
        formatter.setLocalizedDateFormatFromTemplate("d MMMM")
        return formatter
    }()

    @ViewBuilder
    private func detailsHeadline(_ day: DashboardModel.CalendarDay) -> some View {
        let count = day.charges.count
        // The payments are counted alone; a transfer is named after them, in its own words.
        let words = [
            count > 0 ? "\(count) payment\(count == 1 ? "" : "s")" : nil,
            day.transfers.isEmpty ? nil : transferWord(day.transfers.count),
        ].compactMap { $0 }
        VStack(alignment: .leading, spacing: 2) {
            LBReflowStack(alignment: .firstTextBaseline) {
                Text(Self.dayTitleFormatter.string(from: day.date))
                    .lbText(.body)
                    .foregroundStyle(LBColor.textPrimary.color)
                if !typeSize.isAccessibilitySize { Spacer() }
                if !words.isEmpty {
                    NavigationLink(value: Destination.commitments(ListFilter(day: day.id))) {
                        Text("Show in Commitments")
                            .lbText(.label)
                            .foregroundStyle(LBColor.brandText.color)
                    }
                    .lbButtonStyle()
                }
            }
            Text(words.isEmpty ? "No payments" : words.joined(separator: ", "))
                .lbText(.footnote)
                .foregroundStyle(LBColor.textTertiary.color)
        }
        .padding(.top, LBSpacing.s2)
    }

    /// A day's charge as the card every list wears: its day, what it is filed under, who it
    /// is for, the amount — and the mark, a toggle offered for today or later; a past date
    /// is paid by the calendar and offers nothing. A tap opens the commitment.
    private func chargeRow(
        _ charge: Entry, day: DashboardModel.CalendarDay, transfer: Bool = false, dated: Bool = false
    ) -> some View {
        let links = model.subscription(id: charge.subId).map(model.linkFacts) ?? []
        let facts = [LBMetaFact(symbol: LBGlyph.date, text: LB.shortDate(day.date))]
            + (transfer ? [DashboardModel.transferFact] : [])
            + links
        return NavigationLink(value: Destination.commitment(id: charge.subId)) {
            LBCommitmentRow(name: charge.name, facts: facts, amount: charge.amountText,
                            ink: LBColor.dataInk(rank: charge.ink),
                            image: model.commitmentPhotoURL(id: charge.subId)) {
                if !day.isPast {
                    Button {
                        Measure.used("paid")
                        model.setPaid(subscriptionId: charge.subId, dateISO: day.id, paid: !charge.paid)
                    } label: {
                        Text(charge.paid ? "Paid" : "Mark Paid")
                            .lbText(.tabLabel)
                            .fixedSize()
                            .foregroundStyle(charge.paid ? LBColor.textTertiary.color : LBColor.brandText.color)
                            .padding(.horizontal, LBSpacing.s2)
                            .padding(.vertical, 4)
                            .background(LBColor.chrome.color, in: Capsule())
                            .contentShape(Capsule())
                    }
                    .lbButtonStyle()
                }
            }
        }
        .lbButtonStyle()
        .lbTapHaptic()
    }
}
