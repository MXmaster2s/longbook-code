import DesignSystem
import LongbookCore
import SwiftUI

/// One card read whole, the same for all six kinds: the Preview card with its facts, Cards
/// Control under it, then the chosen kind of card. A value row opens Edit on its field. The
/// bar stands in the pane, or in the navigation bar of a pushed phone screen.
struct CardPreviewView: View {
    let model: DashboardModel
    let card: CardRef
    /// The way out, in an inspector or a sheet.
    var onClose: (() -> Void)?
    /// Opens a card in place of this one. Without it a card is a push on the stack.
    var open: ((CardRef) -> Void)?
    /// See All is a push, so a sheet with no stack leaves it out.
    var canPush = true
    /// Edit, where something holds the form in this Preview's place: a side panel. It is given
    /// the field a row asked for, nil for the whole form. Without it the form is a sheet.
    var onEdit: ((EditFocus?) -> Void)?
    /// Called with the card this Preview's charge became once its form moved it to a new day.
    /// Without it the Preview opens that card through `open`.
    var onMoved: ((CardRef) -> Void)?

    @State private var chosen: LBCardKind?
    @State private var editing = false
    /// The field the sheet's form opens on.
    @State private var editFocus: EditFocus?
    #if DEBUG
    @State private var snapshotDoorUsed = false
    #endif
    @State private var adding = false
    @State private var showingHistory = false
    @State private var showingCommitment = false
    @State private var asking: Asking?
    @State private var scrolled = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize

    /// A question the bar's menu asks before it acts.
    private enum Asking: Identifiable {
        case cancelCommitment, deleteCommitment, deleteCharge, deleteEntity
        var id: Self { self }
    }

    // MARK: what the kinds fill in

    /// One line of the Preview card. A long value stands under its label.
    private struct Row {
        let label: String
        let value: String
        var stacked = false
        /// The Edit field the row opens; nil for a fact the form only states, or one it computes.
        var field: EditFocus?
    }

    /// One stop of Cards Control.
    private struct Stop {
        enum Rows {
            case charges([DashboardModel.ChargeItem])
            case commitments([DashboardData.CommitmentItem])
            case entities([DashboardModel.EntityCard])

            var count: Int {
                switch self {
                case .charges(let rows): rows.count
                case .commitments(let rows): rows.count
                case .entities(let rows): rows.count
                }
            }
        }

        let kind: LBCardKind
        let rows: Rows
        /// Where See All lists them; nil for the kinds no list narrows to.
        var seeAll: ListFilter?
    }

    private struct Content {
        let kind: LBCardKind
        let title: String
        var pill: (text: String, tone: LBBadgeTone)?
        var amount: String?
        var subLine: String?
        var image: URL?
        var insight: Insight?
        let rows: [Row]
        let stops: [Stop]
        let opening: LBCardKind?
    }

    private var content: Content? {
        switch card {
        case .charge(let subId, let id): chargeContent(subId: subId, id: id)
        case .commitment(let id): commitmentContent(id)
        case .entity(let kind, let id): entityContent(kind, id: id)
        }
    }

    /// The commitment behind the card, when it is a money card.
    private var commitmentId: String? {
        switch card {
        case .charge(let subId, _): subId
        case .commitment(let id): id
        case .entity: nil
        }
    }

    private var isCommitment: Bool { if case .commitment = card { true } else { false } }

    private var entityCard: DashboardModel.EntityCard? {
        guard case .entity(let kind, let id) = card else { return nil }
        return model.entityCards(kind).first { $0.id == id }
    }

    // MARK: facts

    /// The person on an account's side is whoever holds it, which the form states rather than asks.
    private func sideRows(_ sub: Subscription, _ sides: MoneySides) -> [Row] {
        [
            Row(label: "From Account", value: sides.from.account ?? "None", field: .fromAccount),
            Row(label: "From Person", value: sides.from.person ?? "None", field: sub.isIncome ? .fromPerson : nil),
            Row(label: "To Account", value: sides.to.account ?? "None", field: .toAccount),
            Row(label: "To Person", value: sides.to.person ?? "None", field: sub.isIncome || sub.isTransfer ? nil : .toPerson),
        ]
    }

    /// A category where one is set; None where the form asks for one. A transfer is asked for none.
    private func categoryRow(_ tag: String?, asked: Bool) -> [Row] {
        if let tag = tag.flatMap({ $0.isEmpty ? nil : $0 }) { return [Row(label: "Category", value: categoryWord(tag), field: .category)] }
        return asked ? [Row(label: "Category", value: "None", field: .category)] : []
    }

    /// A field the owner writes freely: whole, under its label, however long. Empty, it says None.
    private func textRow(_ label: String, _ value: String?, field: EditFocus?) -> Row {
        let text = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? Row(label: label, value: "None", field: field) : Row(label: label, value: text, stacked: true, field: field)
    }

    private func yesNo(_ label: String, _ on: Bool, field: EditFocus) -> Row {
        Row(label: label, value: on ? "Yes" : "No", field: field)
    }

    /// The line a commitment's details hold, or nothing.
    private func printedLine(_ sub: Subscription) -> String? {
        sub.details?["statement_line"]?.display
    }

    private func cadence(_ sub: Subscription) -> String { DashboardModel.cycleWord(sub) }

    private func entities(_ kind: VaultPatch.EntityKind, _ ids: [String]) -> [DashboardModel.EntityCard] {
        let cards = model.entityCards(kind)
        return ids.compactMap { id in cards.first { $0.id == id } }
    }

    // MARK: a charge, an earning, a transfer

    private func chargeContent(subId: String, id: String) -> Content? {
        guard let charge = model.chargeItem(id: id), let sub = model.subscription(id: subId) else { return nil }
        let spend = !charge.isIncome && !charge.isTransfer
        var rows = [Row(label: "Date", value: chargeDay(charge, marks: !spend), field: .date)]
        if spend { rows.append(yesNo("Paid", charge.isPaid, field: .paid)) }
        rows += categoryRow(charge.category, asked: !charge.isTransfer)
        rows += sideRows(sub, charge.sides)
        let note = ChargeNote.parts(charge.note)
        rows.append(textRow("Notes", note.notes, field: .notes))
        rows.append(textRow("Statement line", note.statementLine ?? (sub.billingCycle == .once ? printedLine(sub) : nil), field: .statementLine))
        var stops = [
            Stop(kind: .people, rows: .entities(entities(.familyMember, charge.sides.personIds))),
            Stop(kind: .account, rows: .entities(entities(.paymentMethod, charge.sides.accountIds))),
        ]
        if spend, let item = model.commitmentItems(of: [sub]).first {
            stops.append(Stop(kind: .commitment, rows: .commitments([item])))
        }
        if charge.isIncome {
            stops.append(Stop(kind: .earning, rows: .charges(model.landedRows(ofCommitment: subId)),
                              seeAll: ListFilter(scope: .past, kind: .earnings, commitmentId: subId)))
        }
        return Content(
            kind: charge.cardKind, title: charge.name, amount: charge.amountText, subLine: cadence(sub),
            image: model.commitmentPhotoURL(id: subId), rows: rows, stops: stops,
            opening: charge.isTransfer ? .account : .people
        )
    }

    /// The day, with its mark where the card has no Paid row of its own to say it.
    private func chargeDay(_ charge: DashboardModel.ChargeItem, marks: Bool) -> String {
        let day = LB.parseDate(charge.dateISO).map(LB.longDate) ?? charge.dateISO
        return marks && !charge.isPast && charge.isPaid ? "\(day) · Paid" : day
    }

    // MARK: a commitment

    private func commitmentContent(_ id: String) -> Content? {
        guard let sub = model.subscription(id: id), let sides = model.sides(ofCommitment: sub) else { return nil }
        let item = model.commitmentItems(of: [sub]).first
        let spend = !sub.isIncome && !sub.isTransfer
        let once = sub.billingCycle == .once
        // The charge the form opens on, whose note and mark it edits.
        let anchor = model.nextChargeISO(of: id).flatMap { iso in model.charges(of: id).first { $0.row.date == iso } }
        var rows = [Row(label: "Repeats", value: once ? "Never" : cadence(sub), field: .repeats)]
        rows += dateRows(sub, anchor: anchor)
        rows += plannedRow(sub)
        if !once { rows.append(Row(label: "Status", value: displayStatus(sub).rawValue.capitalized, field: .status)) }
        if !once || sub.scheduledCancelDate != nil {
            rows.append(Row(label: "Ends", value: sub.scheduledCancelDate.flatMap(LB.parseDate).map(LB.longDate) ?? "None", field: .ends))
        }
        if !once, spend { rows.append(yesNo("Free trial", isFreeTrial(sub), field: .freeTrial)) }
        if once, spend, let anchor { rows.append(yesNo("Paid", anchor.paid, field: .paid)) }
        rows += categoryRow(sub.tag, asked: !sub.isTransfer)
        rows += sideRows(sub, sides)
        // A recurring commitment's line and notes are its own, its charge's beside them; a
        // one-time row's one charge holds the line.
        let note = ChargeNote.parts(anchor?.row.note)
        rows.append(textRow("Notes", sub.notes, field: .notes))
        rows.append(textRow("Statement line", once && anchor != nil ? note.statementLine ?? printedLine(sub) : printedLine(sub),
                            field: .statementLine))
        if anchor != nil, !once || !note.notes.isEmpty { rows.append(textRow("Charge note", note.notes, field: .chargeNote)) }
        if !once, let line = note.statementLine { rows.append(textRow("Charge statement line", line, field: .chargeStatementLine)) }
        // Stored details show last, one "Label: value" line each, except those the notes already carry.
        let stored = detailLines(sub.details, besides: sub.notes)
        if !stored.isEmpty {
            rows.append(Row(label: "Details", value: stored.joined(separator: "\n"), stacked: true))
        }
        let own: (kind: LBCardKind, list: ListFilter.Kind) = sub.isIncome ? (.earning, .earnings) : (sub.isTransfer ? (.transfer, .transfers) : (.charge, .charges))
        let badge = KindCards.badge(item?.badge)
        return Content(
            kind: .commitment, title: sub.name, pill: badge,
            amount: (sub.isIncome ? "+" : "") + fmtMoney(sub.amount, sub.currency), subLine: cadence(sub),
            image: model.commitmentPhotoURL(id: id), rows: rows,
            stops: [
                Stop(kind: own.kind, rows: .charges(model.landedRows(ofCommitment: id)),
                     seeAll: ListFilter(scope: .past, kind: own.list, commitmentId: id)),
                Stop(kind: .people, rows: .entities(entities(.familyMember, sides.personIds))),
                Stop(kind: .account, rows: .entities(entities(.paymentMethod, sides.accountIds))),
            ],
            opening: own.kind
        )
    }

    /// The day the form opens on: a one-time commitment's, a recurring one's next charge. When
    /// nothing is ahead, the last charge that landed.
    private func dateRows(_ sub: Subscription, anchor: Charge?) -> [Row] {
        if sub.billingCycle == .once {
            guard let day = anchor else { return [] }
            let marks = sub.isIncome || sub.isTransfer
            return [Row(label: "Date", value: LB.longDate(day.date) + (marks && day.paid ? " · Paid" : ""), field: .date)]
        }
        if let anchor {
            return [Row(label: sub.isTransfer ? "Next transfer" : "Next charge",
                        value: LB.longDate(anchor.date) + (anchor.paid ? " · Paid" : ""), field: .date)]
        }
        guard let last = model.charges(of: sub.id).last else { return [] }
        return [Row(label: sub.isTransfer ? "Last transfer" : "Last charge", value: LB.longDate(last.date))]
    }

    /// How far the plan runs, where the form asks: active, recurring, with room to plan.
    private func plannedRow(_ sub: Subscription) -> [Row] {
        guard sub.billingCycle != .once, sub.status == .active else { return [] }
        let horizon = PlanHorizon(rows: model.charges(of: sub.id).map(\.row), cycle: sub.billingCycle,
                                  customDays: sub.customCycleDays, end: sub.scheduledCancelDate,
                                  heldEnd: sub.scheduledCancelDate, today: LB.todayMid())
        guard horizon.most > 0 else { return [] }
        let times = horizon.days(count: min(model.plannedCount(sub.id), horizon.most)).count
        return [Row(label: "Planned until", value: horizon.till(count: times).map(LB.longDate) ?? "None", field: .planned)]
    }

    // MARK: an account, a person

    private func entityContent(_ kind: VaultPatch.EntityKind, id: String) -> Content? {
        guard let entity = model.entityCards(kind).first(where: { $0.id == id }) else { return nil }
        let isAccount = kind == .paymentMethod
        let key = entity.isReal ? id : nil
        let lists = model.entityRows(kind, id: key)
        let items = model.commitmentItems(of: model.entityCommitments(kind, id: key))
        func filter(_ scope: ListFilter.Scope, _ list: ListFilter.Kind?) -> ListFilter {
            isAccount ? ListFilter(scope: scope, kind: list, methodId: id) : ListFilter(scope: scope, kind: list, memberId: id)
        }
        let charges = Stop(kind: .charge, rows: .charges(lists.charges), seeAll: filter(.past, .charges))
        let commitments = Stop(kind: .commitment, rows: .commitments(items), seeAll: filter(.upcoming, nil))
        let transfers = Stop(kind: .transfer, rows: .charges(lists.transfers), seeAll: filter(.past, .transfers))
        let earnings = Stop(kind: .earning, rows: .charges(lists.earnings), seeAll: filter(.past, .earnings))
        // The date holds together when the line must wrap.
        let next = entity.next.map { "\($0.name), \(LB.longDate($0.date).replacingOccurrences(of: " ", with: "\u{00A0}"))" } ?? "None"
        let ahead = entity.window.isEmpty ? "None" : fmtMoneyTotals(entity.window)
        let tag = entity.tag.flatMap { $0.isEmpty ? nil : EntityCopy.tagWord($0) }
        let pill = tag.map { (text: $0, tone: LBBadgeTone.muted) }
        let insight = entity.isReal ? model.insight("\(EntityCopy.insightWord(kind)).\(id)") : nil
        // A person's or an account's own fields lead, in the form's order; what follows from them comes after.
        let notes = entity.isReal ? [textRow("Notes", model.entityDetails(kind, id: id).notes, field: .notes)] : []
        let reach = [Row(label: "Next commitment", value: next), Row(label: "Next 12 months", value: ahead)]
        if isAccount {
            var own: [Row] = []
            if entity.isReal {
                own.append(Row(label: "Type", value: tag ?? "None", field: .tag))
                own.append(Row(label: "Owner", value: entity.owner?.name ?? "None", field: .owner))
                // The headline carries these once there is a balance.
                if entity.balance == nil { own.append(Row(label: "Balance", value: "None", field: .balance)) }
                if entity.balanceDate == nil { own.append(Row(label: "As on", value: "None", field: .asOn)) }
                own.append(Row(label: "Linked account", value: entity.linked?.name ?? "None", field: .linkedAccount))
            }
            let rows = own + notes + reach
            let holder = entity.owner.map { entities(.familyMember, [$0.id]) } ?? []
            return Content(
                kind: .account, title: EntityCopy.name(entity), pill: pill,
                amount: entity.balance.map { fmtMoney($0, entity.balanceCurrency) },
                subLine: entity.balanceDate.map { "As on \(LB.longDate($0))" },
                image: entity.photo, insight: insight, rows: rows,
                stops: [charges, Stop(kind: .people, rows: .entities(holder)), commitments, transfers, earnings],
                opening: .charge
            )
        }
        let held = entity.isReal ? entities(.paymentMethod, model.accounts(ofMember: id).map(\.id)) : []
        var own: [Row] = []
        if entity.isReal {
            own.append(Row(label: "Relationship", value: tag ?? "None", field: .tag))
            own.append(Row(label: "Email", value: clean(model.entityDetails(kind, id: id).email) ?? "None", field: .email))
        }
        var rows = own + notes
        if entity.isReal {
            // The count only: the accounts themselves are listed under the Preview.
            let count = model.accounts(ofMember: id).count
            rows.append(Row(label: "Accounts", value: count == 0 ? "None" : "\(count) \(count == 1 ? "account" : "accounts")"))
        }
        rows += reach
        return Content(
            kind: .people, title: EntityCopy.name(entity), pill: pill,
            amount: entity.sent.isEmpty ? fmtMoney(0, entity.balanceCurrency) : fmtMoneyTotals(entity.sent),
            image: entity.photo, insight: insight, rows: rows,
            stops: [Stop(kind: .account, rows: .entities(held)), commitments, charges, transfers, earnings],
            opening: .charge
        )
    }

    private func clean(_ value: String?) -> String? {
        value.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
    }

    // MARK: the page

    var body: some View {
        page
            .background(LBColor.canvas.color)
            .modifier(PreviewBar(inPane: showsPaneBar, trailing: { phoneBar }))
            .measured("card_preview_editing", .sheet, when: editing)
            .sheet(isPresented: $editing) { editForm.lbKeyboardFocusEffects() }
            #if DEBUG
            // Snapshot harness: LONGBOOK_SNAPSHOT_FOCUS=<field> opens Edit from its row, as a click does.
            .onAppear {
                guard !snapshotDoorUsed, canEdit, let field = EditFocus.snapshotFocus else { return }
                snapshotDoorUsed = true
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(300))
                    startEditing(field)
                }
            }
            #endif
            .measured("card_preview_adding", .sheet, when: adding)
            .sheet(isPresented: $adding) {
                if case .entity(let kind, let id) = card {
                    entityAddForm(model: model, kind: kind, id: id) { adding = false }
                        .lbKeyboardFocusEffects()
                }
            }
            .measured("card_preview_history", .sheet, when: showingHistory)
            .sheet(isPresented: $showingHistory) {
                if let commitmentId {
                    CommitmentHistoryView(model: model, id: commitmentId) { showingHistory = false }
                        .lbKeyboardFocusEffects()
                }
            }
            .measured("card_preview_commitment", .sheet, when: showingCommitment)
            .sheet(isPresented: $showingCommitment) {
                if let commitmentId {
                    CardPreviewSheet(model: model, card: .commitment(id: commitmentId)) { showingCommitment = false }
                        .lbKeyboardFocusEffects()
                }
            }
            .measured("card_preview_asking", .alert, when: asking != nil)
            .alert(askingTitle, isPresented: Binding(get: { asking != nil }, set: { if !$0 { asking = nil } }), presenting: asking) { asked in
                askingButtons(asked)
            } message: { asked in
                Text(askingMessage(asked))
            }
    }

    /// The Mac always draws its bar in the pane; a phone does only in a sheet, with no
    /// navigation bar over it.
    private var showsPaneBar: Bool {
        #if os(macOS)
        true
        #else
        onClose != nil
        #endif
    }

    @ViewBuilder
    private var page: some View {
        VStack(spacing: 0) {
            if showsPaneBar { paneBar }
            ScrollView {
                if let content {
                    filled(content)
                } else {
                    // Deleted on another device between the push and this read.
                    Text("This is no longer in your folder.")
                        .lbText(.body)
                        .foregroundStyle(LBColor.textTertiary.color)
                        .padding(LBSpacing.s4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .coordinateSpace(name: Self.scrollSpace)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private static let scrollSpace = "card_preview"

    private func filled(_ content: Content) -> some View {
        // Lazy: a person or an account may carry thousands, and only those in view are drawn.
        LazyVStack(alignment: .leading, spacing: LBSpacing.s3) {
            previewCard(content)
                .onGeometryChange(for: Bool.self) { $0.frame(in: .named(Self.scrollSpace)).minY < 0 } action: { scrolled = $0 }
            cards(content)
        }
        .padding(.horizontal, LBSpacing.s4)
        .padding(.top, showsPaneBar ? 0 : LBSpacing.s2)
        .padding(.bottom, LBSpacing.s4)
        .frame(maxWidth: 700)
        .frame(maxWidth: .infinity)
    }

    // MARK: the Preview card

    private func previewCard(_ content: Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            header(content)
                .padding(.bottom, LBSpacing.s3)
            ForEach(Array(content.rows.enumerated()), id: \.offset) { _, row in
                Rectangle()
                    .fill(LBColor.hairline.color)
                    .frame(height: 1)
                    .accessibilityHidden(true)
                factRow(row)
            }
        }
        .padding(.leading, LBSpacing.s4 + 4)
        .padding(.trailing, LBSpacing.s4)
        .padding(.vertical, LBSpacing.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LBColor.card.color)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(content.kind.ink.color)
                .frame(width: 4)
                .accessibilityHidden(true)
        }
        .clipShape(RoundedRectangle(cornerRadius: LBKindCard.radius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: LBKindCard.radius, style: .continuous)
                .strokeBorder(LBColor.hairline.color, lineWidth: 1)
        )
    }

    private func header(_ content: Content) -> some View {
        HStack(spacing: LBSpacing.s3) {
            LBCardIcon(symbol: content.kind.symbol, image: content.image)
            VStack(alignment: .leading, spacing: 2) {
                // The pill stands beside the name while both fit on one line, else under it.
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: LBSpacing.s2) {
                        titleText(content).lineLimit(1)
                        if let pill = content.pill { LBBadge(pill.text, tone: pill.tone) }
                    }
                    VStack(alignment: .leading, spacing: LBSpacing.s1) {
                        titleText(content).fixedSize(horizontal: false, vertical: true)
                        if let pill = content.pill { LBBadge(pill.text, tone: pill.tone) }
                    }
                }
                LBReflowStack(spacing: LBSpacing.s2) {
                    if let amount = content.amount {
                        Text(amount)
                            .lbText(.cardTitle)
                            .monospacedDigit()
                            .foregroundStyle(LBColor.textPrimary.color)
                            .textSelection(.enabled)
                    }
                    if let subLine = content.subLine {
                        Text(subLine)
                            .lbText(.body)
                            .foregroundStyle(LBColor.textSecondary.color)
                    }
                }
                InsightMark(insight: content.insight, labelled: true)
            }
        }
    }

    private func titleText(_ content: Content) -> some View {
        Text(content.title)
            .lbText(.screenTitle)
            .foregroundStyle(LBColor.textPrimary.color)
            .textSelection(.enabled)
            .accessibilityAddTraits(.isHeader)
    }

    /// A value row opens Edit on its field; a fact the form does not ask stays a fact.
    @ViewBuilder
    private func factRow(_ row: Row) -> some View {
        if let field = row.field, canEdit {
            PreviewDoor(label: row.label) { startEditing(field) } content: { factLine(row, door: true) }
        } else {
            factLine(row, door: false).accessibilityElement(children: .combine)
        }
    }

    private func factLine(_ row: Row, door: Bool) -> some View {
        // At the accessibility sizes a label and its value share no line: side by side they
        // broke words in half ("Planne d until").
        let stacked = row.stacked || typeSize.isAccessibilitySize
        let label = Text(row.label)
            .lbText(.body)
            .foregroundStyle(LBColor.textSecondary.color)
        return Group {
            if stacked {
                VStack(alignment: .leading, spacing: LBSpacing.s1) {
                    label
                    factValue(row, stacked: true, door: door)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: LBSpacing.s3) {
                    label.layoutPriority(1)
                    Spacer(minLength: LBSpacing.s2)
                    factValue(row, stacked: false, door: door)
                }
            }
        }
        .padding(.vertical, Self.rowPadding)
    }

    private static var rowPadding: CGFloat {
        #if os(macOS)
        LBSpacing.s2
        #else
        LBSpacing.s2 + 2
        #endif
    }

    /// A door's words are its button's, so only a fact's can be selected.
    @ViewBuilder
    private func factValue(_ row: Row, stacked: Bool, door: Bool) -> some View {
        let text = Text(row.value)
            .lbText(.body)
            .foregroundStyle(LBColor.textPrimary.color)
            .multilineTextAlignment(stacked ? .leading : .trailing)
            .fixedSize(horizontal: false, vertical: true)
        if door { text } else { text.textSelection(.enabled) }
    }

    // MARK: Cards Control and the cards

    private func title(_ kind: LBCardKind) -> String {
        switch kind {
        case .charge: "Charges"
        case .people: "People"
        case .account: "Accounts"
        case .commitment: "Commitments"
        case .transfer: "Transfers"
        case .earning: "Earnings"
        case .report: "Reports"
        }
    }

    private func heading(_ kind: LBCardKind, _ count: Int) -> String {
        if count == 1 { return "1 \(kind == .people ? "Person" : String(title(kind).dropLast()))" }
        return "\(count.formatted()) \(title(kind))"
    }

    /// One kind is chosen as a Preview opens; a kind with no cards takes no stop, so the next
    /// one that has some leads instead.
    private func stop(_ content: Content) -> Stop? {
        let live = content.stops.filter { $0.rows.count > 0 }
        return live.first { $0.kind == chosen } ?? live.first { $0.kind == content.opening } ?? live.first
    }

    @ViewBuilder
    private func cards(_ content: Content) -> some View {
        if let current = stop(content) {
            LBCardsControl(
                items: content.stops.map { LBCardsControlItem(id: $0.kind, title: title($0.kind), symbol: $0.kind.symbol, count: $0.rows.count) },
                current: current.kind
            ) { kind in
                Measure.used("cards_control")
                chosen = kind
            }
            HStack(alignment: .firstTextBaseline) {
                LBSectionHeader(heading(current.kind, current.rows.count))
                Spacer(minLength: LBSpacing.s2)
                // Every card is here already, so the list is only worth a door once there are many.
                if canPush, current.rows.count > Self.seeAllFrom, let filter = current.seeAll {
                    NavigationLink(value: Destination.commitments(filter)) {
                        Text("See All")
                            .lbText(.eyebrow)
                            .foregroundStyle(LBColor.textTertiary.color)
                            .frame(minHeight: 20)
                    }
                    .lbButtonStyle()
                    .lbLinkPointer()
                }
            }
            .padding(.top, LBSpacing.s1)
            switch current.rows {
            case .charges(let rows):
                ForEach(rows) { row in
                    door(row.ref) { KindCards.card(row, photo: model.commitmentPhotoURL(id: row.subId)) }
                }
            case .commitments(let rows):
                ForEach(rows) { row in
                    door(.commitment(id: row.id)) { KindCards.card(row, photo: model.commitmentPhotoURL(id: row.id)) }
                }
            case .entities(let rows):
                ForEach(rows) { row in
                    door(row.ref) { KindCards.card(row) }
                }
            }
        }
    }

    private static let seeAllFrom = 4

    /// A card that opens its own Preview: in place where this one was given a way to, else
    /// pushed onto the stack.
    @ViewBuilder
    private func door<Card: View>(_ ref: CardRef, @ViewBuilder card: () -> Card) -> some View {
        if let open {
            Button { Measure.used("open_card"); open(ref) } label: { card() }
                .lbCardButtonStyle()
        } else {
            NavigationLink(value: ref.destination) { card() }
                .lbCardButtonStyle()
        }
    }

    // MARK: the bar

    /// Close at the leading edge; at the trailing edge Mark Paid, Bookmark and History, Edit
    /// and the rest in ⋯, as each kind has them. It stays put, a hairline under it once the
    /// page has scrolled.
    private var paneBar: some View {
        HStack(spacing: LBSpacing.s2) {
            if let onClose {
                barCircle("xmark", title: "Close", help: "Close (Esc)", measure: "close", action: onClose)
                    #if os(macOS)
                    .lbShortcut(.closePanel)
                    #endif
            }
            Spacer(minLength: 0)
            if let day = markDay { markPaid(day) }
            if commitmentId != nil { bookmarkAndHistory }
            if canEdit {
                barCircle("pencil", title: "Edit", help: "Edit (⌘E)", measure: "edit") { startEditing(nil) }
                    #if os(macOS)
                    .lbShortcut(.edit)
                    #endif
            }
            if hasMore { moreMenu }
        }
        .padding(.horizontal, LBSpacing.s4)
        .padding(.vertical, LBSpacing.s3)
        .overlay(alignment: .bottom) {
            if scrolled {
                Rectangle().fill(LBColor.hairline.color).frame(height: 1)
            }
        }
        #if os(macOS)
        // ⌘⌫ asks as ⋯'s Delete does; in a field it stays the field's, deleting to the line's start.
        .background { if canEdit { ShortcutKey(.delete) { askDelete() } } }
        #endif
    }

    /// Edit, on the field a row asked for or the whole form: in the panel where there is one.
    private func startEditing(_ field: EditFocus?) {
        if let onEdit {
            onEdit(field)
        } else {
            editFocus = field
            editing = true
        }
    }

    /// The question ⋯'s Delete asks: a charge's first, since it can go alone.
    private func askDelete() {
        switch card {
        case .charge: asking = .deleteCharge
        case .commitment: asking = .deleteCommitment
        case .entity: asking = .deleteEntity
        }
    }

    /// Whether there is a record here to act on: not one gone from the folder, nor the bucket
    /// of what names nobody.
    private var canEdit: Bool {
        switch card {
        case .charge: chargeRow != nil
        case .commitment(let id): model.subscription(id: id) != nil
        case .entity: entityCard?.isReal == true
        }
    }

    private var hasMore: Bool { canEdit }

    private func barCircle(_ symbol: String, title: String, help: String, measure: StaticString, action: @escaping () -> Void) -> some View {
        Button { Measure.used(measure); action() } label: {
            barCircleFace(symbol)
        }
        .lbButtonStyle(.capsule)
        .help(help)
        .accessibilityLabel(title)
    }

    private func barCircleFace(_ symbol: String) -> some View {
        PanelCircleFace(symbol: symbol)
    }

    /// The day Mark Paid acts on: a charge still ahead, or a commitment's next charge. A charge
    /// already landed is paid.
    private var markDay: (iso: String, paid: Bool)? {
        if case .charge = card {
            guard let row = chargeRow, !row.isPast else { return nil }
            return (row.dateISO, row.isPaid)
        }
        guard let id = commitmentId, let sub = model.subscription(id: id),
              let item = model.commitmentItems(of: [sub]).first, let due = item.dueISO else { return nil }
        return (due, item.isPaid)
    }

    private func togglePaid(_ day: (iso: String, paid: Bool)) {
        guard let id = commitmentId else { return }
        LBHaptics.tap()
        model.setPaid(subscriptionId: id, dateISO: day.iso, paid: !day.paid)
    }

    /// An empty mark until paid, then a tick and the word; ink, never the brand colour.
    private func markPaid(_ day: (iso: String, paid: Bool)) -> some View {
        Button { Measure.used("commitment_action"); togglePaid(day) } label: {
            HStack(spacing: 6) {
                Image(systemName: day.paid ? LBGlyph.paid : LBGlyph.unpaid)
                    .font(.system(size: 12, weight: .semibold))
                    .accessibilityHidden(true)
                Text(day.paid ? "Paid" : "Mark Paid")
                    .lbText(.body)
                    .lineLimit(1)
                    .fixedSize()
            }
            .foregroundStyle(LBColor.textPrimary.color)
            .padding(.horizontal, LBSpacing.s3)
            .frame(height: 36)
            .background(LBColor.chrome.color, in: Capsule())
            .overlay(Capsule().strokeBorder(LBColor.hairline.color, lineWidth: 1))
            .contentShape(Capsule())
        }
        .lbButtonStyle(.capsule)
        .help(day.paid ? "Mark Unpaid (⇧⌘P)" : "Mark Paid (⇧⌘P)")
        .accessibilityLabel(day.paid ? "Paid" : "Mark Paid")
        .accessibilityHint(LB.parseDate(day.iso).map { "For the charge on \(LB.longDate($0))." } ?? "")
        #if os(macOS)
        .lbShortcut(.markPaid)
        #endif
    }

    private var isBookmarked: Bool { commitmentId.map(model.bookmarks.contains) ?? false }

    private var hasHistory: Bool {
        guard let commitmentId else { return false }
        let today = LB.todayMid()
        return model.charges(of: commitmentId).contains { $0.date < today }
    }

    private func toggleBookmark() {
        guard let commitmentId else { return }
        LBHaptics.tap()
        model.toggleBookmark(commitmentId)
    }

    /// Two icons in one capsule: 28 pt buttons with a hairline between them.
    private var bookmarkAndHistory: some View {
        HStack(spacing: 0) {
            Button { Measure.used("commitment_action"); toggleBookmark() } label: {
                barGroupFace(isBookmarked ? "bookmark.fill" : "bookmark")
            }
            .lbButtonStyle(.capsule)
            .help(isBookmarked ? "Remove Bookmark (⌘D)" : "Bookmark (⌘D)")
            .accessibilityLabel(isBookmarked ? "Remove Bookmark" : "Bookmark")
            #if os(macOS)
            .lbShortcut(.bookmark)
            #endif
            Rectangle()
                .fill(LBColor.hairline.color)
                .frame(width: 1, height: 16)
                .padding(.horizontal, 1)
                .accessibilityHidden(true)
            Button { Measure.used("clock_arrow_circlepath"); showingHistory = true } label: {
                barGroupFace("clock.arrow.circlepath")
            }
            .lbButtonStyle(.capsule)
            .disabled(!hasHistory)
            .help("History")
            .accessibilityLabel("History")
        }
        .padding(.horizontal, 4)
        .frame(height: 36)
        .background(LBColor.chrome.color, in: Capsule())
        .overlay(Capsule().strokeBorder(LBColor.hairline.color, lineWidth: 1))
    }

    private func barGroupFace(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(LBColor.textSecondary.color)
            .frame(width: 28, height: 28)
            .contentShape(Capsule())
    }

    private var moreMenu: some View {
        Menu {
            moreItems(compact: true)
        } label: {
            barCircleFace("ellipsis")
        }
        .menuStyle(.button)
        .lbButtonStyle(.capsule)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("More")
        .accessibilityLabel("More")
    }

    /// The phone's bar: Edit where the drawings put it, and ⋯ for what the Mac's bar shows
    /// as its own buttons.
    @ViewBuilder
    private var phoneBar: some View {
        if canEdit {
            Menu {
                moreItems(compact: false)
            } label: {
                Image(systemName: "ellipsis")
            }
            .accessibilityLabel("More")
            Button("Edit") { Measure.used("edit"); startEditing(nil) }
                .accessibilityHint("Opens the edit sheet.")
        }
    }

    /// What ⋯ holds. Without the bar's own buttons beside it, `compact` false, it holds those too.
    @ViewBuilder
    private func moreItems(compact: Bool) -> some View {
        switch card {
        case .entity:
            Button("Add Commitment") { Measure.used("add_commitment", .menuItem); adding = true }
            Divider()
            Button("Delete…", role: .destructive) { Measure.used("delete", .menuItem); asking = .deleteEntity }
        case .commitment(let id):
            if !compact {
                if let day = markDay {
                    Button(day.paid ? "Mark Unpaid" : "Mark Paid") { Measure.used("mark_unpaid", .menuItem); togglePaid(day) }
                }
                sharedItems
            }
            if let sub = model.subscription(id: id), sub.billingCycle != .once, sub.status != .cancelled {
                Button("Cancel Commitment") { Measure.used("cancel_commitment", .menuItem); asking = .cancelCommitment }
            }
            Divider()
            Button("Delete…", role: .destructive) { Measure.used("delete", .menuItem); asking = .deleteCommitment }
        case .charge(let subId, let id):
            if !compact {
                if let day = markDay {
                    Button(day.paid ? "Mark Unpaid" : "Mark Paid") { Measure.used("mark_unpaid", .menuItem); togglePaid(day) }
                }
                sharedItems
            }
            // A charge reaches its commitment through Cards Control; these two have no stop for it.
            if let row = model.chargeItem(id: id), row.isIncome || row.isTransfer {
                Button("Open Commitment") {
                    Measure.used("open_commitment", .menuItem)
                    if let open { open(.commitment(id: subId)) } else { showingCommitment = true }
                }
            }
            Divider()
            Button("Delete \(rowWord)", role: .destructive) { Measure.used("delete_charge", .menuItem); asking = .deleteCharge }
            Button("Delete Commitment", role: .destructive) { Measure.used("delete_commitment", .menuItem); asking = .deleteCommitment }
        }
    }

    @ViewBuilder
    private var sharedItems: some View {
        Button(isBookmarked ? "Remove Bookmark" : "Bookmark") { Measure.used("toggle_bookmark", .menuItem); toggleBookmark() }
        Button("History") { Measure.used("clock_arrow_circlepath", .menuItem); showingHistory = true }
            .disabled(!hasHistory)
    }

    private var chargeRow: DashboardModel.ChargeItem? {
        if case .charge(let subId, let id) = card { model.chargeItem(id: id) } else { nil }
    }

    /// What this row is called when it is the one being removed.
    private var rowWord: String {
        switch chargeRow?.cardKind {
        case .earning: "Earning"
        case .transfer: "Transfer"
        default: "Charge"
        }
    }

    // MARK: editing

    /// The form a sheet holds: rising from the bottom over the Preview on a phone.
    private var editForm: some View {
        CardEditForm(model: model, card: card, focus: editFocus, onDeleted: { leave() }, onMoved: { day in
            if let moved = card.moved(to: day) { (onMoved ?? open)?(moved) }
        }) { editing = false }
            .lbThreeQuarterSheet()
    }

    // MARK: questions

    /// Gone from under the reader: back out of a pushed screen, or close the pane.
    private func leave() {
        if let onClose { onClose() } else { dismiss() }
    }

    private var askingTitle: String {
        let name = chargeRow?.name ?? commitmentId.flatMap { model.subscription(id: $0)?.name } ?? entityCard.map(EntityCopy.name) ?? ""
        return switch asking {
        case .cancelCommitment: "Cancel \(name)?"
        case .deleteCharge: "Delete this \(rowWord.lowercased())?"
        default: "Delete \(name)?"
        }
    }

    @ViewBuilder
    private func askingButtons(_ asked: Asking) -> some View {
        switch asked {
        case .cancelCommitment:
            Button("Cancel Commitment", role: .destructive) {
                Measure.used("cancel_commitment")
                if let commitmentId { model.cancelCommitment(id: commitmentId) }
            }
            Button("Keep It", role: .cancel) { Measure.used("keep_it") }
        case .deleteCommitment:
            Button("Delete", role: .destructive) {
                Measure.used("delete")
                if let commitmentId, model.deleteCommitment(id: commitmentId) { leave() }
            }
            Button("Cancel", role: .cancel) { Measure.used("cancel") }
        case .deleteCharge:
            if let row = chargeRow, model.offersLaterRemoval(subscriptionId: row.subId, dateISO: row.dateISO) {
                Button("Only This Charge", role: .destructive) {
                    Measure.used("only_this_charge")
                    if model.removeCharge(subscriptionId: row.subId, dateISO: row.dateISO) { leave() }
                }
                Button("This and Every One After", role: .destructive) {
                    Measure.used("this_and_every_one_after")
                    if model.removeChargeAndLater(subscriptionId: row.subId, dateISO: row.dateISO) { leave() }
                }
            } else if let row = chargeRow {
                Button("Delete", role: .destructive) {
                    Measure.used("delete")
                    if model.removeCharge(subscriptionId: row.subId, dateISO: row.dateISO) { leave() }
                }
            }
            Button("Cancel", role: .cancel) { Measure.used("cancel") }
        case .deleteEntity:
            Button("Delete", role: .destructive) {
                Measure.used("delete")
                if case .entity(let kind, let id) = card, model.deleteEntity(kind, id: id) { leave() }
            }
            Button("Keep", role: .cancel) { Measure.used("keep") }
        }
    }

    private func askingMessage(_ asked: Asking) -> String {
        switch asked {
        case .cancelCommitment:
            return "Its planned charges after today are removed. It stays in your folder, marked cancelled."
        case .deleteCommitment:
            return "Its charges are removed with it. The version before stays in Proposals."
        case .deleteCharge:
            guard let row = chargeRow else { return "" }
            return model.offersLaterRemoval(subscriptionId: row.subId, dateISO: row.dateISO)
                ? "\(row.name), \(row.amountText). \(model.laterRemovalWords(subscriptionId: row.subId, dateISO: row.dateISO))"
                : "\(row.name), \(row.amountText). Only this \(rowWord.lowercased()) is removed."
        case .deleteEntity:
            guard case .entity(let kind, let id) = card else { return "" }
            return EntityCopy.removalNote(kind, use: model.entityUse(kind, id: id))
        }
    }
}

/// A Preview's value row as a door into Edit on that row's field. On the Mac the row lights
/// under the pointer, a pencil at its end; on a phone a tap shades it.
private struct PreviewDoor<Content: View>: View {
    let label: String
    let action: () -> Void
    @ViewBuilder let content: () -> Content
    @State private var hovering = false

    var body: some View {
        Button { Measure.used("edit_field"); action() } label: {
            HStack(alignment: .firstTextBaseline, spacing: LBSpacing.s2) {
                content()
                #if os(macOS)
                Image(systemName: "pencil")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(LBColor.textTertiary.color)
                    .opacity(hovering ? 1 : 0)
                    .accessibilityHidden(true)
                #endif
            }
            .contentShape(Rectangle())
        }
        .lbButtonStyle(.inset(LBRadius.xs, EdgeInsets(top: 0, leading: -6, bottom: 0, trailing: -6)))
        #if os(macOS)
        .onHover { hovering = $0 }
        #endif
        .help("Edit \(Self.fieldWord(label))")
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Opens Edit on this field.")
    }

    /// The label as the tooltip says it: a name in its own capitals kept, "Notes" as "notes".
    private static func fieldWord(_ label: String) -> String {
        guard !label.dropFirst().contains(where: \.isUppercase) else { return label }
        return label.prefix(1).lowercased() + label.dropFirst()
    }
}

/// The navigation bar's part of a pushed Preview: no title, the actions at its end. A pane
/// draws its own bar and has none of this.
private struct PreviewBar<Trailing: View>: ViewModifier {
    let inPane: Bool
    @ViewBuilder let trailing: () -> Trailing

    @ViewBuilder
    func body(content: Content) -> some View {
        if inPane {
            content
        } else {
            content.lbScreenTitle("", large: false, trailing: trailing)
        }
    }
}

/// One card's Edit form: its charge's, its commitment's, its account's or its person's. A side
/// panel holds it in the Preview's place on the Mac; anywhere else it stands in a sheet.
struct CardEditForm: View {
    let model: DashboardModel
    let card: CardRef
    var inPanel = false
    var closeAsked = 0
    /// The field a Preview's row opened Edit on.
    var focus: EditFocus?
    var onDeleted: () -> Void = {}
    var onMoved: (String) -> Void = { _ in }
    let onDone: () -> Void

    /// The charge's day as it opened: a move on Save must not leave the form on no charge.
    @State private var chargeISO: String?
    @State private var chargeRead = false

    var body: some View {
        switch card {
        case .charge(let subId, let id):
            if chargeRead {
                RenewalFormView(model: model, editingId: subId, chargeISO: chargeISO, inPanel: inPanel, closeAsked: closeAsked,
                                focus: focus, onDeleted: onDeleted, onMoved: onMoved, onDone: onDone)
            } else {
                Color.clear.onAppear {
                    chargeISO = model.chargeItem(id: id)?.dateISO
                    chargeRead = true
                }
            }
        case .commitment(let id):
            RenewalFormView(model: model, editingId: id, inPanel: inPanel, closeAsked: closeAsked, focus: focus,
                            onDeleted: onDeleted, onDone: onDone)
        case .entity(let kind, let id):
            EntityEditView(model: model, kind: kind, id: id,
                           currentName: model.entityCards(kind).first { $0.id == id }.map(EntityCopy.name) ?? "",
                           onDone: onDone, onDeleted: onDeleted, inPanel: inPanel, closeAsked: closeAsked, focus: focus)
        }
    }
}

/// A Preview on a pushed screen. Its charge moved to a new day, it follows it there.
struct PushedCardPreview: View {
    let model: DashboardModel
    @State private var card: CardRef

    init(model: DashboardModel, card: CardRef) {
        self.model = model
        _card = State(initialValue: card)
    }

    var body: some View {
        CardPreviewView(model: model, card: card, onMoved: { card = $0 })
            .id(card)
    }
}

/// A Preview in a sheet: a card opened from it takes its place, there being no stack to push.
struct CardPreviewSheet: View {
    let model: DashboardModel
    let onClose: () -> Void
    @State private var card: CardRef

    init(model: DashboardModel, card: CardRef, onClose: @escaping () -> Void) {
        self.model = model
        self.onClose = onClose
        _card = State(initialValue: card)
    }

    var body: some View {
        CardPreviewView(model: model, card: card, onClose: onClose, open: { card = $0 }, canPush: false)
            .id(card)
            #if os(macOS)
            .frame(minWidth: 520, minHeight: 480)
            #endif
            .lbClosesOnOutsideClick(onClose)
    }
}
