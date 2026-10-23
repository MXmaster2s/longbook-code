import DesignSystem
import LongbookCore
import SwiftUI

/// One commitment, read whole: its name large, the amount and rhythm under it, then the
/// form's fields as label and value rows, each showing only what is set, and its history as
/// a row that opens its charges. Edit is a deliberate second step.
struct CommitmentDetailView: View {
    let model: DashboardModel
    let id: String
    /// The charge Mark Paid acts on, when the detail was opened from one; else the
    /// commitment's next.
    var chargeISO: String?
    /// Drawn inside another screen — the Mac table's inspector — with no page of its own.
    var embedded = false
    /// Present when the screen sits in a sheet rather than a push: the way out. A Mac
    /// sheet offers no swipe-down, so without this the reader would be trapped.
    var onClose: (() -> Void)?
    @State private var editing = false
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var showingHistory = false
    /// Notes longer than two lines open on request, so a long note never pushes the
    /// history row off the screen.
    @State private var notesOpen = false

    /// One line of the detail: what it is, and what is set. A long value stands under its label.
    private struct DetailRow {
        let label: String
        let value: String
        var symbol: String?
        var mark: MoneyMark?
        var stacked = false
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LBSpacing.s4) {
                if let sub = model.subscription(id: id) {
                    header(sub)
                    actionsRow
                    detailCard(rows(sub))
                    historyRow(sub)
                    moneyNote(sub)
                } else {
                    // Deleted on another device between the push and this read.
                    Text("That commitment is no longer in your folder.")
                        .lbText(.body)
                        .foregroundStyle(LBColor.textTertiary.color)
                }
            }
            .padding(LBSpacing.s4)
            #if os(macOS)
            .padding(.top, embedded ? 0 : LBSpacing.s6)
            #endif
            .frame(maxWidth: 700)
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        #if os(macOS)
        .frame(minWidth: onClose != nil ? 520 : 0, minHeight: onClose != nil ? 480 : 0)
        #endif
        .background(LBColor.canvas.color)
        .sheet(isPresented: $editing) {
            RenewalFormView(model: model, editingId: id) { editing = false }
        }
        .sheet(isPresented: $showingHistory) {
            CommitmentHistoryView(model: model, id: id) { showingHistory = false }
        }
        .lbClosesOnOutsideClick { onClose?() }
        .modifier(DetailTitle(embedded: embedded) {
            Button("Edit") { editing = true }
                .accessibilityHint("Opens the edit sheet.")
        })
    }

    /// The list row this screen expands — the badge, the paid mark and the bookmark carry
    /// over so nothing the row offered is lost by looking closer.
    private var item: DashboardData.CommitmentItem? {
        if case .loaded(let data) = model.state {
            return data.commitments.first { $0.id == id }
        }
        return nil
    }

    // MARK: header

    /// The name people know it by, large; the amount and how often under it.
    private func header(_ sub: Subscription) -> some View {
        HStack(alignment: .top, spacing: LBSpacing.s3) {
            VStack(alignment: .leading, spacing: LBSpacing.s1) {
                Text(sub.name)
                    .lbText(embedded ? .screenTitle : .largeTitle)
                    .foregroundStyle(LBColor.textPrimary.color)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .accessibilityAddTraits(.isHeader)
                LBReflowStack(spacing: LBSpacing.s2) {
                    LBAmount((sub.isIncome ? "+" : "") + fmtMoney(sub.amount, sub.currency), prominence: .inline)
                        .foregroundStyle(LBColor.textPrimary.color)
                    Text(cadence(sub))
                        .lbText(.body)
                        .foregroundStyle(LBColor.textSecondary.color)
                    if let item, let spec = badgeSpec(item.badge) {
                        LBBadge(spec.text, tone: spec.tone)
                    }
                }
            }
            Spacer(minLength: 0)
            // The phone's Edit sits in the navigation bar.
            #if os(macOS)
            editButton
            #endif
            if let onClose {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(LBColor.textSecondary.color)
                        .frame(width: 30, height: 30)
                        .background(LBColor.chrome.color, in: Circle())
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
            }
        }
    }

    private func cadence(_ sub: Subscription) -> String {
        sub.billingCycle == .once ? "One-time" : cycleWord(sub)
    }

    // MARK: the form's fields, answered

    /// The way the money moves when it is not plainly out: the mark beside the type's name.
    private enum MoneyMark {
        case income, transfer
        var symbol: String { self == .income ? LBGlyph.income : LBGlyph.transfer }
        var word: String { self == .income ? "Money in" : "Transfer" }
    }

    /// Every field the commitment sets, in the form's order after the name and amount the
    /// header carries: rhythm, the days, the filing, the status, then the end, notes and details.
    private func rows(_ sub: Subscription) -> [DetailRow] {
        var rows = [
            DetailRow(
                label: "Type",
                value: sub.billingCycle == .once ? "One-time" : "Recurring · \(cycleWord(sub))",
                mark: sub.isIncome ? .income : (sub.isTransfer ? .transfer : nil)
            ),
        ]
        rows += dateRows(sub)
        if let tag = sub.tag {
            rows.append(DetailRow(label: "Category", value: categoryWord(tag), symbol: model.tagIcon(kind: "commitment", name: tag) ?? CategoryGlyph.symbol(tag)))
        }
        let names = model.entityNames(memberId: sub.familyMemberId, methodId: sub.paymentMethodId)
        if let method = names.method {
            rows.append(DetailRow(label: "Account", value: method, symbol: LBGlyph.account))
        }
        if let member = names.member {
            rows.append(DetailRow(label: "Person", value: member, symbol: LBGlyph.member))
        }
        if sub.billingCycle != .once {
            let status = displayStatus(sub).rawValue.capitalized
            rows.append(DetailRow(label: "Status", value: isFreeTrial(sub) ? "\(status) · Free trial" : status))
        }
        if let cancelling = sub.scheduledCancelDate.flatMap(LB.parseDate) {
            rows.append(DetailRow(label: "Ends", value: LB.longDate(cancelling)))
        }
        // The notes show whole, line by line; stored details show under them, one "Label: value"
        // line each, except those whose label the notes already carry.
        if let notes = sub.notes, !notes.isEmpty {
            rows.append(DetailRow(label: "Notes", value: notes, stacked: true))
        }
        let stored = detailLines(sub.details, besides: sub.notes)
        if !stored.isEmpty {
            rows.append(DetailRow(label: "Details", value: stored.joined(separator: "\n"), stacked: true))
        }
        return rows
    }

    /// A one-time commitment's day; a recurring one's next charge, and how far its plan
    /// runs. When nothing is ahead, the last charge that landed.
    private func dateRows(_ sub: Subscription) -> [DetailRow] {
        let all = model.charges(of: id)
        let today = LB.todayMid()
        let next = all.first { $0.date >= today }
        if sub.billingCycle == .once {
            guard let day = all.first else { return [] }
            return [DetailRow(label: "Date", value: LB.longDate(day.date) + (day.paid ? " · Paid" : ""))]
        }
        var rows: [DetailRow] = []
        if let next {
            rows.append(DetailRow(label: sub.isTransfer ? "Next transfer" : "Next charge",
                                  value: LB.longDate(next.date) + (next.paid ? " · Paid" : "")))
        } else if let last = all.last {
            rows.append(DetailRow(label: sub.isTransfer ? "Last transfer" : "Last charge", value: LB.longDate(last.date)))
        }
        if let through = all.last, next != nil, sub.scheduledCancelDate == nil {
            rows.append(DetailRow(label: "Planned until", value: LB.longDate(through.date)))
        }
        return rows
    }

    /// What money in or a transfer means, said once under the rows.
    @ViewBuilder
    private func moneyNote(_ sub: Subscription) -> some View {
        if sub.isIncome {
            Text("Money in. Kept beside your expenses, never added to them.")
                .lbText(.footnote)
                .foregroundStyle(LBColor.textTertiary.color)
                .fixedSize(horizontal: false, vertical: true)
        } else if sub.isTransfer {
            Text("Transfer. Between your own accounts. It shows on your timeline and is left out of spending.")
                .lbText(.footnote)
                .foregroundStyle(LBColor.textTertiary.color)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: history

    /// The charges before today: how many, and what they came to in each currency.
    private func history(_ sub: Subscription) -> (count: Int, total: String)? {
        let today = LB.todayMid()
        let past = model.charges(of: id).filter { $0.date < today }
        guard !past.isEmpty else { return nil }
        var sums: [String: Double] = [:]
        var order: [String] = []
        for charge in past {
            if sums[charge.currency] == nil { order.append(charge.currency) }
            sums[charge.currency, default: 0] += charge.amount
        }
        return (past.count, fmtMoneyTotals(order.map { CurrencyAmount(currency: $0, amount: sums[$0] ?? 0) }))
    }

    /// One row that opens every charge before today.
    @ViewBuilder
    private func historyRow(_ sub: Subscription) -> some View {
        if let history = history(sub) {
            let noun = sub.isTransfer ? "transfer" : "charge"
            Button { showingHistory = true } label: {
                HStack(spacing: LBSpacing.s3) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(LBColor.brandText.color)
                        .accessibilityHidden(true)
                    Text("History")
                        .lbText(.body)
                        .foregroundStyle(LBColor.textPrimary.color)
                    Spacer(minLength: LBSpacing.s2)
                    Text("\(EntityCopy.counted(history.count, noun)) · \(history.total)")
                        .lbText(.body)
                        .foregroundStyle(LBColor.textSecondary.color)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(LBColor.textQuaternary.color)
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, LBSpacing.s4)
                .frame(minHeight: 44)
                .background(LBColor.card.color, in: RoundedRectangle(cornerRadius: LBRadius.md, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: LBRadius.md, style: .continuous)
                        .strokeBorder(LBColor.hairline.color, lineWidth: 1)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Shows every \(noun) before today.")
        }
    }

    // MARK: furniture

    /// The rows in one grouped card, a hairline between each.
    private func detailCard(_ rows: [DetailRow]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                if index > 0 {
                    Rectangle()
                        .fill(LBColor.hairline.color)
                        .frame(height: 1)
                        .padding(.leading, LBSpacing.s4)
                        .accessibilityHidden(true)
                }
                detailRow(row)
            }
        }
        .background(LBColor.card.color, in: RoundedRectangle(cornerRadius: LBRadius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: LBRadius.md, style: .continuous)
                .strokeBorder(LBColor.hairline.color, lineWidth: 1)
        )
    }

    /// Whether a note is long enough to be folded to two lines.
    private static func clamps(_ row: DetailRow) -> Bool {
        row.label == "Notes" && (row.value.count > 90 || row.value.filter { $0 == "\n" }.count >= 2)
    }

    private func detailRow(_ row: DetailRow) -> some View {
        // At the accessibility sizes a label and its value share no line: side by side they
        // broke words in half ("Planne d until").
        let stacked = row.stacked || typeSize.isAccessibilitySize
        let label = HStack(spacing: LBSpacing.s2) {
            Text(row.label)
                .lbText(.body)
                .foregroundStyle(LBColor.textSecondary.color)
            if let mark = row.mark {
                Image(systemName: mark.symbol)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(LBColor.brandText.color)
                    .frame(width: 22, height: 22)
                    .background(LBColor.brand.color.opacity(0.16), in: Circle())
                    .accessibilityLabel(mark.word)
            }
        }
        let value = HStack(spacing: LBSpacing.s1) {
            if let symbol = row.symbol {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(LBColor.textTertiary.color)
                    .accessibilityHidden(true)
            }
            Text(row.value)
                .lbText(.body)
                .foregroundStyle(LBColor.textPrimary.color)
                .multilineTextAlignment(stacked ? .leading : .trailing)
                .lineLimit(Self.clamps(row) && !notesOpen ? 2 : nil)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        return Group {
            if stacked {
                VStack(alignment: .leading, spacing: LBSpacing.s1) {
                    label
                    value
                    if Self.clamps(row) {
                        Button(notesOpen ? "Show less" : "Show more") {
                            withAnimation(.snappy(duration: 0.2)) { notesOpen.toggle() }
                        }
                        .buttonStyle(.plain)
                        .lbText(.label)
                        .foregroundStyle(LBColor.brandText.color)
                    }
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: LBSpacing.s3) {
                    label
                    Spacer(minLength: LBSpacing.s3)
                    value
                }
            }
        }
        .padding(.horizontal, LBSpacing.s4)
        .padding(.vertical, LBSpacing.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    // MARK: actions

    /// The day Mark Paid acts on: the charge the detail was opened from, else the next one.
    private var markDay: (iso: String, paid: Bool)? {
        if let chargeISO, let charge = model.charges(of: id).first(where: { $0.row.date == chargeISO }) {
            return (chargeISO, charge.row.paid)
        }
        guard let item, let due = item.dueISO else { return nil }
        return (due, item.isPaid)
    }

    /// Mark Paid and Bookmark under the header, as buttons the reader can see.
    private var actionsRow: some View {
        let marked = model.bookmarks.contains(id)
        return LBReflowStack(spacing: LBSpacing.s2) {
            if let day = markDay {
                actionButton(day.paid ? "Mark Unpaid" : "Mark Paid", symbol: day.paid ? LBGlyph.unpaid : LBGlyph.paid) {
                    LBHaptics.tap()
                    model.setPaid(subscriptionId: id, dateISO: day.iso, paid: !day.paid)
                }
                .accessibilityHint(LB.parseDate(day.iso).map { "For the charge on \(LB.longDate($0))." } ?? "")
            }
            actionButton(marked ? "Remove Bookmark" : "Bookmark", symbol: marked ? "bookmark.slash" : "bookmark") {
                LBHaptics.tap()
                model.toggleBookmark(id)
            }
            if !typeSize.isAccessibilitySize { Spacer(minLength: 0) }
        }
    }

    private func actionButton(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: LBSpacing.s1) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .accessibilityHidden(true)
                Text(title)
                    .lbText(.body)
                    .lineLimit(1)
            }
            .foregroundStyle(LBColor.onBrandTint.color)
            .padding(.horizontal, LBSpacing.s3)
            .frame(minHeight: EntityActionLabel.height)
            .background(LBColor.brand.color.opacity(0.12), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    /// In the header, beside the close control, so it is in reach without scrolling.
    private var editButton: some View {
        Button { editing = true } label: {
            Text("Edit")
                .lbText(.body)
                .foregroundStyle(LBColor.brandText.color)
                .padding(.horizontal, LBSpacing.s2)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens the edit sheet.")
    }

    private func cycleWord(_ sub: Subscription) -> String {
        switch sub.billingCycle {
        case .monthly: "Monthly"
        case .yearly: "Yearly"
        case .once: "Once"
        case .custom: "Every \(max(1, sub.customCycleDays ?? 30)) days"
        }
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
}

/// The screen's bar: a small "Details" title with Edit at its end on iPhone; nothing when
/// the detail is drawn inside another screen.
private struct DetailTitle<Trailing: View>: ViewModifier {
    let embedded: Bool
    @ViewBuilder let trailing: () -> Trailing

    @ViewBuilder
    func body(content: Content) -> some View {
        if embedded {
            content
        } else {
            content.lbScreenTitle("Details", large: false, trailing: trailing)
        }
    }
}

/// Every charge of one commitment before today, newest first: its day, amount, mark and
/// note. A tap opens that charge's form.
struct CommitmentHistoryView: View {
    let model: DashboardModel
    let id: String
    let onDone: () -> Void
    @State private var editing: Charge?

    private var past: [Charge] {
        let today = LB.todayMid()
        return model.charges(of: id).filter { $0.date < today }.reversed()
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(model.subscription(id: id)?.name ?? "History")
                    .lbText(.headline)
                    .foregroundStyle(LBColor.textPrimary.color)
                    .lineLimit(1)
                Spacer()
                Button("Done", action: onDone)
                    .foregroundStyle(LBColor.brandText.color)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(LBSpacing.s4)
            List {
                Section {
                    ForEach(past) { charge in
                        Button { editing = charge } label: {
                            LBListRow(
                                LB.longDate(charge.date),
                                secondary: charge.row.note,
                                amount: fmtMoney(charge.amount, charge.currency),
                                chevron: true
                            )
                        }
                        .buttonStyle(.plain)
                        .lbListRowBackground()
                    }
                } header: {
                    LBSectionHeader("Before today")
                }
            }
            .lbGroupedList()
        }
        .background(LBColor.canvas.color)
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 480)
        #endif
        .lbClosesOnOutsideClick(onDone)
        .sheet(item: $editing) { charge in
            RenewalFormView(model: model, editingId: id, chargeISO: charge.row.date) { editing = nil }
                .lbThreeQuarterSheet()
        }
    }
}
