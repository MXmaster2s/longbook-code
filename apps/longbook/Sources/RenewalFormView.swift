import DesignSystem
import LongbookCore
import SwiftUI

/// One form for a commitment and for any one of its charges. Adding one, it asks the
/// essentials first and keeps the filing under More Details; editing, it asks every field in
/// the order the Preview reads. Save is one write.
struct RenewalFormView: View {
    let model: DashboardModel
    /// nil = a new commitment; an id = editing that row.
    let editingId: String?
    /// The charge the form was opened on, by its day. Nil opens it on the commitment's next
    /// charge: the first unpaid one from today on, else its last.
    var chargeISO: String?
    /// A category to start from — onboarding's quick-add names the kind of thing.
    var seedCategory: String?
    /// A name already chosen — a placeholder from setup — so the form opens on the amount.
    var seedName: String?
    /// The day to start on — a month the picker found empty opens on its first.
    var seedDate: Date?
    /// What a statement saw: the amount and the rhythm, so the form opens filled in.
    var seedAmount: Double?
    var seedCycle: BillingCycle?
    var seedCustomDays: Int?
    /// The account or the person a card's "Add commitment" started from.
    var seedMethodId: String?
    var seedMemberId: String?
    /// Money in or a transfer, when the list it was opened from lists those: "in" or "transfer".
    var seedDirection: String?
    /// The form stands in a side panel, in its Preview's place, rather than in a sheet.
    var inPanel = false
    /// Raised by the panel's list when a card chosen under the form would replace it.
    var closeAsked = 0
    /// The field a Preview's row opened the form on: its list opens, or its text takes the cursor.
    var focus: EditFocus?
    /// Called once a delete has landed, before `onDone`, so a list lets go of what it chose.
    var onDeleted: () -> Void = {}
    /// Called with the new day once Save has moved the charge this form was opened on.
    var onMoved: (String) -> Void = { _ in }
    let onDone: () -> Void

    @State private var edit = SubEdit()
    /// The account on the other side, by id or by the name a statement gave it. Staged here
    /// and written with Save.
    @State private var counterpart: String?
    /// The charges Save would turn into Transfers or back, held while Change or Cancel is awaited.
    @State private var flipping: TransferFlipWords.Flips?
    /// A charge's form has moved on to its commitment, or is asking first to.
    @State private var onWholeCommitment = false
    @State private var movingToCommitment = false
    /// The charge's amount; a commitment with no charge shows its price.
    @State private var amountText = ""
    /// A new commitment's first charge, or the day the form's charge moves to.
    @State private var day = Date()
    /// The mark of the form's charge, and its note in the two parts the file holds as one.
    @State private var paid = false
    @State private var chargeNotes = ""
    @State private var chargeLine = ""
    /// The commitment's own statement line, kept in its details.
    @State private var ownLine = ""
    @State private var cancellingOn: Date?
    /// How many charges are planned ahead, which the Recurrence chip shows. On an existing
    /// commitment it starts at what the file holds, and Save writes it only once moved.
    @State private var planCount = PlannedCount(ahead: DEFAULT_PLAN_MONTHS)
    /// The day the file holds the form's charge under; nil where there is none, or where the
    /// form is on the commitment itself. A landed move rewrites it, so the form keeps reading
    /// the row it edits.
    @State private var anchorISO: String?
    /// The day of the charge the form opened on: the one named, else the commitment's next.
    /// Moved off it by the strip, the form is on one occurrence, and removes that one.
    @State private var openedOn: String?
    @State private var loadedFor: String?
    /// What the sheet last agreed with the file — every way out compares against this.
    @State private var baseline: Snapshot?
    /// How long the notes were when the sheet opened. The cap never falls below it, so notes an
    /// AI wrote longer than the form's own limit are never cut by an edit.
    @State private var notesOpenedLength = 0
    /// What was set when the form opened: those chips lead their racks, and stay put while the
    /// reader is choosing, so a tap never moves the chip out from under it.
    @State private var openedWith: (tag: String?, method: String?, member: String?) = (nil, nil, nil)
    /// The Recurrence list, and the wheel its "Other…" opens once the list is down.
    @State private var pickingRecurrence = false
    @State private var pickingCount = false
    @State private var wheelNext = false
    /// The occurrence tapped while the form's charge holds unsaved edits, waiting on the answer.
    @State private var switchingTo: String?
    @State private var pickingMoney = false
    /// Whether a sheet opened from the category, account or member rack is up.
    @State private var rackDetour = false
    /// One-time was tapped on a commitment whose charges one row cannot hold.
    @State private var refusedOneTime = false
    /// How many times the form has been blanked for another commitment.
    @State private var blankings = 0
    @State private var confirmingDelete = false
    @State private var confirmingRemove = false
    @State private var confirmingDiscard = false
    /// A new amount or day on a recurring charge from today on waits on one answer: this
    /// charge, or this and the charges after it.
    @State private var askingReach = false
    /// The day the plan then ends, when the later charges follow a move; read as the question
    /// is asked.
    @State private var laterEnd: Date?
    /// The width the chip rails are read through, measured from the rail itself.
    @State private var railWidth: CGFloat?
    /// The account and member names typed into the racks' pills, submitted before a Save.
    @State private var typing = RackTyping()
    /// The just-saved name, held for the "Saved" beat after "Add another" — without it
    /// the form blanking was the only proof a save happened.
    @State private var lastSavedName: String?
    /// Whether Category, Account, Person and Notes are open under More Details.
    @State private var showsMore = false
    /// The typed field holding the cursor, and whether the asked field has been shown once.
    @FocusState private var typingIn: EditFocus?
    @State private var revealed = false

    /// Every field a discard could lose, as one comparable value. Days are held as their ISO
    /// word, so a picked date and a stored one compare on the day rather than the hour.
    private struct Snapshot: Equatable {
        var name: String
        var direction: String?
        var cycle: BillingCycle
        var customDays: Int?
        var currency: String
        var tag: String?
        var accountId: String?
        var memberId: String?
        var notes: String
        var status: SubStatus
        var cancelISO: String?
        var amountText: String
        var dayISO: String?
        var paid: Bool
        var note: String
        var commitmentLine: String
        var count: Int
        var trial: Bool
        var counterpart: String?
    }

    private var snapshot: Snapshot {
        Snapshot(name: edit.name, direction: VaultPatch.storedDirection(edit.direction),
                 cycle: edit.billingCycle, customDays: edit.customCycleDays, currency: edit.currency,
                 tag: edit.tag, accountId: edit.paymentMethodId, memberId: edit.familyMemberId,
                 notes: edit.notes ?? "", status: edit.status,
                 cancelISO: cancellingOn.map { LB.toISO($0) }, amountText: amountText,
                 dayISO: isEditing && anchorISO == nil ? nil : LB.toISO(day),
                 paid: paid, note: note, commitmentLine: ownLine, count: chosenCount, trial: edit.freeTrial, counterpart: counterpart)
    }

    /// The same values as the file holds them now; nil for a new commitment or one gone.
    private var stored: Snapshot? {
        guard let id = editingId, let sub = model.subscription(id: id) else { return nil }
        let row = anchor
        return Snapshot(name: sub.name, direction: VaultPatch.storedDirection(sub.direction),
                        cycle: sub.billingCycle, customDays: sub.customCycleDays, currency: sub.currency,
                        tag: sub.tag, accountId: sub.paymentMethodId, memberId: sub.familyMemberId,
                        notes: sub.notes ?? "", status: sub.status,
                        cancelISO: LB.parseDate(sub.scheduledCancelDate).map { LB.toISO($0) },
                        amountText: plainAmount(row?.amount ?? sub.amount),
                        dayISO: row.map { LB.toISO($0.date) },
                        paid: row?.row.paid ?? false, note: formNote(row), commitmentLine: Self.printedLine(of: sub),
                        count: model.plannedCount(id), trial: sub.freeTrial == true, counterpart: Self.counterpart(of: sub))
    }

    /// The note as Save writes it from the form's two fields.
    private var note: String { ChargeNote.joined(statementLine: chargeLine, notes: chargeNotes) }

    /// The line a commitment's details hold.
    private static func printedLine(of sub: Subscription?) -> String {
        sub?.details?["statement_line"]?.display ?? ""
    }

    /// A charge's note as this form words it. A one-time row's only charge reads its
    /// commitment's line when its own note holds none.
    private func formNote(_ row: Charge?) -> String {
        guard let row else { return "" }
        let held = ChargeNote.parts(row.row.note)
        let printed = row.sub.billingCycle == .once ? Self.printedLine(of: row.sub) : ""
        return ChargeNote.joined(statementLine: held.statementLine ?? printed, notes: held.notes)
    }

    /// The form's note taken back apart into its fields.
    private func setNote(_ note: String) {
        let held = ChargeNote.parts(note)
        chargeLine = held.statementLine ?? ""
        chargeNotes = held.notes
    }

    /// The other side as the file names it: an account's id, else a statement's words.
    private static func counterpart(of sub: Subscription) -> String? {
        let named = CounterpartAccounts.counterpart(of: sub)
        return named.id ?? named.name
    }

    private var hasUnsavedChanges: Bool {
        guard let baseline else { return false }
        return snapshot != baseline || photoData != nil || removingPhoto
    }

    private var isEditing: Bool { editingId != nil }
    /// Keyboard focus is in this form, for Return to save it.
    @State private var focusInForm = false
    /// The commitment's picture as the Mac's form stages it; it lands with Save.
    @State private var photoData: Data?
    @State private var removingPhoto = false

    private func settlePhoto(_ id: String) {
        guard photoData != nil || removingPhoto, let folder = model.vaultFolderURL else { return }
        if let photoData, let named = VaultImages.store(photoData, kind: "commitment", id: id, in: folder) {
            model.setCommitmentPhoto(id: id, photo: named)
        } else if removingPhoto {
            if let old = model.commitmentPhotoURL(id: id) { VaultImages.remove(file: old, in: folder) }
            model.setCommitmentPhoto(id: id, photo: nil)
        }
    }

    /// The form's charge as the file holds it now; nil once it has gone, or where there is none.
    private var anchor: Charge? {
        guard let id = editingId, let iso = anchorISO else { return nil }
        return model.charges(of: id).first { $0.row.date == iso }
    }

    /// The form's charge is dated today or later in the file.
    private var anchorAhead: Bool { anchor.map { !($0.date < LB.todayMid()) } ?? false }

    /// Opened on no charge, on a commitment with nothing dated today or later: the form edits
    /// the commitment itself. No Paid tick, its last charge stated, the amount its price.
    private var onCommitment: Bool { isEditing && chargeISO == nil && anchorISO == nil }

    /// Opened on one charge of a commitment: the form shows that charge's fields alone.
    private var onCharge: Bool { isEditing && chargeISO != nil }

    /// Nothing can be written to what is no longer there, so the screen says so and offers the
    /// one thing left: the commitment was removed, or the charge the form is on — the one it
    /// was opened on, or its next one once the owner changed that charge itself.
    private var isGone: Bool {
        guard let id = editingId, loadedFor != nil else { return false }
        if model.subscription(id: id) == nil { return true }
        guard anchorISO != nil, anchor == nil else { return false }
        return chargeISO != nil || chargeEdited
    }

    /// The owner changed the form's charge itself: its amount, its day, its mark or its note.
    private var chargeEdited: Bool {
        guard let was = baseline else { return false }
        let form = snapshot
        return form.amountText != was.amountText || form.dayISO != was.dayISO
            || form.paid != was.paid || form.note != was.note
    }

    // MARK: the word

    /// A charge when the form, opened on one charge, holds a day before today or the Paid
    /// tick; a commitment when it is on the commitment itself, or recurring however the tick
    /// stands; else a charge once a one-time row is marked or its day is behind today.
    private var isCharge: Bool {
        let past = LB.dayOf(day) < LB.todayMid()
        if onCharge { return true }
        if chargeISO != nil && (past || paid) { return true }
        if onCommitment { return false }
        return edit.billingCycle == .once && (paid || past)
    }

    /// The one word this screen names its subject by. Every title, label and button that
    /// names it reads it here.
    private func subject(capitalized: Bool = false) -> String {
        let sub = editingId.flatMap { model.subscription(id: $0) }
        let word = !isCharge ? "commitment" : sub?.isIncome == true ? "earning" : sub?.isTransfer == true ? "transfer" : "charge"
        return capitalized ? word.prefix(1).uppercased() + word.dropFirst() : word
    }

    @ViewBuilder
    var body: some View {
        if onWholeCommitment, let editingId {
            RenewalFormView(model: model, editingId: editingId, inPanel: inPanel, closeAsked: closeAsked,
                            onDeleted: onDeleted, onDone: onDone)
        } else {
            form
        }
    }

    /// Adding asks in a scrolling sheet; editing keeps its name and its decisions in view.
    @ViewBuilder
    private var page: some View {
        if isEditing { editPage } else { addPage }
    }

    private var addPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LBSpacing.s4) {
                header
                addFields
                if let saveError = model.saveError {
                    Text(saveError)
                        .lbText(.footnote)
                        .foregroundStyle(LBColor.urgent.color)
                        .fixedSize(horizontal: false, vertical: true)
                }
                actions
            }
            .padding(LBSpacing.s4)
            #if os(macOS)
            .frame(maxWidth: 680)
            #else
            .frame(maxWidth: 560)
            #endif
            .frame(maxWidth: .infinity)
        }
    }

    private var form: some View {
        page
        .environment(\.lbFormGrouped, true)
        #if os(iOS)
        .scrollDismissesKeyboard(.interactively)
        #endif
        #if os(macOS)
        // Shorter than the window minimum, so the sheet never runs past its bottom. A panel
        // gives the form its own width.
        .frame(minWidth: inPanel ? nil : (isEditing ? 460 : 560), idealWidth: inPanel ? nil : (isEditing ? 460 : 560),
               minHeight: inPanel ? nil : 520, idealHeight: inPanel ? nil : 640)
        .environment(\.lbFormDense, isEditing)
        .lbKeyboardFocusEffects()
        #endif
        .lbPanelForm(active: inPanel, dirty: hasUnsavedChanges, close: onDone)
        .lbFocusWithin($focusInForm)
        .onChange(of: closeAsked) { _, _ in close() }
        .background(LBColor.canvas.color)
        // A click on the window behind closes the sheet as the X does: a dirty form asks first.
        .lbClosesOnOutsideClick(close)
        // What a held-down chip opens sits over three quarters of the form, the rest of it
        // softened behind — the sheet is a detour, not another screen.
        .lbSoftenedWhile(rackDetour || pickingRecurrence)
        // On a phone the swipe down is refused outright while the form holds a change.
        #if os(iOS)
        .interactiveDismissDisabled(hasUnsavedChanges)
        #endif
        .measured("renewal_form_picking_recurrence", .sheet, when: pickingRecurrence)
        .sheet(isPresented: $pickingRecurrence) { recurrencePicker.lbThreeQuarterSheet().lbKeyboardFocusEffects() }
        .measured("renewal_form_picking_count", .sheet, when: pickingCount)
        .sheet(isPresented: $pickingCount) { countWheel.lbMonthSheet().lbKeyboardFocusEffects() }
        // The wheel waits for the list to be down: two sheets in one breath lose the second.
        .onChange(of: pickingRecurrence) { _, up in
            guard !up, wheelNext else { return }
            wheelNext = false
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(400))
                pickingCount = true
            }
        }
        .measured("renewal_form_switching_to", .alert, when: switchingTo != nil)
        .alert("Discard changes to this charge?", isPresented: Binding(get: { switchingTo != nil },
                                                                       set: { if !$0 { switchingTo = nil } })) {
            Button("Discard", role: .destructive) {
                Measure.used("discard")
                if let iso = switchingTo { loadCharge(iso); rebaseCharge() }
                switchingTo = nil
            }
            Button("Keep Editing", role: .cancel) { Measure.used("keep_editing"); switchingTo = nil }
        }
        .measured("renewal_form_confirming_remove", .alert, when: confirmingRemove)
        .alert("Delete this \(rowWord())?", isPresented: $confirmingRemove) {
            // A planned charge of a recurring commitment can take the plan after it too.
            if offersLater {
                Button("Only This \(rowWord(capitalized: true))", role: .destructive) {
                    Measure.used("only_this_charge")
                    if let row = anchor, model.removeCharge(subscriptionId: row.sub.id, dateISO: row.row.date) { deleted() }
                }
                Button("This and Every One After", role: .destructive) {
                    Measure.used("this_and_every_one_after")
                    if let row = anchor, model.removeChargeAndLater(subscriptionId: row.sub.id, dateISO: row.row.date) { deleted() }
                }
            } else {
                Button("Delete", role: .destructive) {
                    Measure.used("delete")
                    if let row = anchor, model.removeCharge(subscriptionId: row.sub.id, dateISO: row.row.date) { deleted() }
                }
            }
            Button("Keep It", role: .cancel) { Measure.used("keep_it") }
        } message: {
            Text(removeWords)
        }
        .measured("renewal_form_confirming_delete", .alert, when: confirmingDelete)
        .alert("Delete \(model.subscription(id: editingId ?? "")?.name ?? "this commitment")?", isPresented: $confirmingDelete) {
            Button("Delete", role: .destructive) {
                Measure.used("delete")
                if model.deleteCommitment(id: editingId ?? "") { deleted() }
            }
            Button("Cancel", role: .cancel) { Measure.used("cancel") }
        } message: {
            Text("Its charges are removed with it. The version before stays in Proposals.")
        }
        .measured("renewal_form_confirming_flip", .alert, when: flipping != nil)
        .alert("Change charges?", isPresented: Binding(get: { flipping != nil }, set: { if !$0 { flipping = nil } }),
               presenting: flipping) { _ in
            Button("Change") {
                Measure.used("change")
                // A question that follows waits for this one to be down.
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(300))
                    saveAsAnswered()
                }
            }
            Button("Cancel", role: .cancel) { Measure.used("cancel") }
        } message: { flips in
            Text(TransferFlipWords.message(flips))
        }
        .measured("renewal_form_asking_reach", .dialog, when: askingReach)
        .confirmationDialog("Apply the change to", isPresented: $askingReach, titleVisibility: .visible) {
            Button("Only This \(rowWord(capitalized: true))") { Measure.used("only_this_charge"); if saveNow(andLater: false) { onDone() } }
            Button("This and Every One After") { Measure.used("this_and_every_one_after"); if saveNow(andLater: true) { onDone() } }
            if offersPast {
                Button("All, Except Statement Charges") { Measure.used("all_except_statement_charges"); if saveNow(andLater: true, andPast: true) { onDone() } }
            }
            Button("Cancel", role: .cancel) { Measure.used("cancel") }
        } message: {
            Text(reachMessage)
        }
        // An account is never the other side of its own row.
        .onChange(of: edit.paymentMethodId) { _, account in
            if account != nil, account == counterpart { counterpart = nil }
        }
        // A first charge set ahead of today has not been paid; the toggle hides, so it clears.
        .onChange(of: day) { _, day in
            if !isEditing, LB.dayOf(day) > LB.todayMid() { paid = false }
        }
        .onAppear {
            model.clearSaveError()
            loadIfNeeded()
            #if DEBUG
            // The racks open their own lists for LONGBOOK_SNAPSHOT_OPEN.
            switch ProcessInfo.processInfo.environment["LONGBOOK_SNAPSHOT_OPEN"] {
            case "money": pickingMoney = true
            case "trial": edit.freeTrial = true
            case "paid": paid = true
            case "paused": edit.status = .paused
            case "active": edit.status = .active
            case "recurrence": pickingRecurrence = true
            case "categories", "accounts", "members", "more": showsMore = true
            default: break
            }
            #endif
        }
        // The app re-reads the vault while this sheet is open, so another device's write can
        // land under it. The form answers for what the file says now, never for what it said
        // when it opened.
        .onChange(of: stored) { _, _ in rebase() }
        .lbFormStack((isEditing ? "Edit " : "New ") + subject(capitalized: true))
    }

    /// The choice field whose list opens with the form.
    private func opens(_ field: EditFocus) -> Bool {
        #if DEBUG
        if EditFocus.snapshotPicker == field { return true }
        #endif
        return focus == field
    }

    /// Once, as the form stands: the asked field scrolls into view, and a typed one takes the
    /// cursor. Back from a pushed list leaves the form where it was.
    private func reveal(_ proxy: ScrollViewProxy) {
        guard let focus, !revealed else { return }
        revealed = true
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            withAnimation(.snappy(duration: 0.2)) { proxy.scrollTo(focus, anchor: .center) }
            if focus.isTyped { typingIn = focus }
        }
    }

    private func loadIfNeeded() {
        guard loadedFor != (editingId ?? "new") else { return }
        loadedFor = editingId ?? "new"
        if let editingId, let sub = model.subscription(id: editingId) {
            edit = SubEdit(from: sub)
            // The form writes no details: the row keeps what it holds, its statement line too.
            edit.details = nil
            openedWith = (edit.tag, edit.paymentMethodId, edit.familyMemberId)
            counterpart = Self.counterpart(of: sub)
            loadCharge(chargeISO ?? model.nextChargeISO(of: editingId))
            ownLine = Self.printedLine(of: sub)
            openedOn = anchorISO
            cancellingOn = LB.parseDate(edit.scheduledCancelDate)
            planCount = PlannedCount(ahead: model.plannedCount(editingId))
            notesOpenedLength = edit.notes?.count ?? 0
            baseline = stored
            showsMore = true
        } else {
            edit = SubEdit()
            edit.currency = model.editChoices.currencies.first ?? "INR"
            edit.tag = seedCategory
            if let seedName { edit.name = seedName }
            if let seedAmount, seedAmount > 0 {
                amountText = plainAmount(seedAmount)
            }
            if let seedCycle {
                edit.billingCycle = seedCycle
                edit.customCycleDays = seedCycle == .custom ? seedCustomDays : nil
            }
            edit.paymentMethodId = seedMethodId
            edit.familyMemberId = seedMemberId
            edit.direction = seedDirection
            day = seedDate ?? Date()
            planCount = PlannedCount(ahead: DEFAULT_PLAN_MONTHS)
            notesOpenedLength = edit.notes?.count ?? 0
            baseline = snapshot
            // Opened from an account, a person or a category, the filing is already begun.
            showsMore = seedCategory != nil || seedMethodId != nil || seedMemberId != nil
        }
    }

    /// The form moves onto one charge: its amount, day, mark and note as the file holds them,
    /// or the price and today where there is none. An armed delete never rides along.
    private func loadCharge(_ iso: String?) {
        anchorISO = iso
        let row = anchor
        amountText = plainAmount(row?.amount ?? editingId.flatMap(model.subscription(id:))?.amount ?? 0)
        day = row?.date ?? Date()
        paid = row?.row.paid ?? false
        setNote(formNote(row))
    }

    /// The baseline follows the charge the form just moved onto, so the discard question and
    /// `isGone` read that charge; the commitment's own fields keep the baseline they had.
    private func rebaseCharge() {
        guard var was = baseline, let now = stored else { return }
        was.amountText = now.amountText
        was.dayISO = now.dayISO
        was.paid = now.paid
        was.note = now.note
        baseline = was
    }

    /// The file changed under the form: another device wrote the vault, or a rack renamed or
    /// deleted what the form names. A field nobody touched follows the file; a touched one
    /// keeps its words, so Save never writes back what it did not change.
    private func rebase() {
        guard let id = editingId, model.subscription(id: id) != nil, let was = baseline else { return }
        let form = snapshot
        // Opened on no charge in particular, the form moves to the commitment's next charge
        // when its own leaves the file, as if opened there — unless the owner already changed
        // that one, whose edits belong to no other: then the form says it has gone.
        if chargeISO == nil, anchorISO != nil, anchor == nil, !chargeEdited {
            anchorISO = model.nextChargeISO(of: id)
            openedOn = anchorISO
        }
        guard !isGone, let now = stored else { return }
        if form.name == was.name { edit.name = now.name }
        if form.direction == was.direction { edit.direction = now.direction }
        if form.cycle == was.cycle { edit.billingCycle = now.cycle }
        if form.customDays == was.customDays { edit.customCycleDays = now.customDays }
        if form.currency == was.currency { edit.currency = now.currency }
        if form.tag == was.tag { edit.tag = now.tag }
        if form.accountId == was.accountId { edit.paymentMethodId = now.accountId }
        if form.memberId == was.memberId { edit.familyMemberId = now.memberId }
        if form.notes == was.notes { edit.notes = now.notes.isEmpty ? nil : now.notes }
        if form.status == was.status { edit.status = now.status }
        if form.cancelISO == was.cancelISO { cancellingOn = LB.parseDate(now.cancelISO) }
        if form.amountText == was.amountText { amountText = now.amountText }
        if form.dayISO == was.dayISO, let date = anchor?.date { day = date }
        if form.paid == was.paid { paid = now.paid }
        if form.note == was.note { setNote(now.note) }
        if form.commitmentLine == was.commitmentLine { ownLine = now.commitmentLine }
        if form.trial == was.trial { edit.freeTrial = now.trial }
        if form.counterpart == was.counterpart { counterpart = now.counterpart }
        planCount.rebase(ahead: now.count)
        baseline = now
    }

    // MARK: furniture

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                // A title's size stops at the first accessibility size: past it "commitment"
                // was wider than the sheet and broke in two.
                Text((isEditing ? "Edit " : "New ") + subject(capitalized: true))
                    .lbText(.screenTitle)
                    .foregroundStyle(LBColor.textPrimary.color)
                    .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .lbText(.footnote)
                        .foregroundStyle(LBColor.textTertiary.color)
                        .lineLimit(2)
                }
            }
            Spacer()
            Button(action: { Measure.used("close"); close() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(LBColor.textSecondary.color)
                    .frame(width: 30, height: 30)
                    .background(LBColor.chrome.color, in: Circle())
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .lbButtonStyle()
            .help("Close without saving")
            .accessibilityLabel("Close without saving")
            .measured("renewal_form_confirming_discard", .dialog, when: confirmingDiscard)
            .confirmationDialog(discardTitle, isPresented: $confirmingDiscard, titleVisibility: .visible) {
                Button("Discard", role: .destructive) { Measure.used("discard"); discarded() }
                Button("Keep Editing", role: .cancel) { Measure.used("keep_editing"); movingToCommitment = false }
            } message: {
                // A name the racks wrote is in the file already, whether or not Save landed.
                if let kept = typing.keptOnDiscard(model) { Text(kept) }
            }
        }
    }

    /// The question's yes: leave, or go on to the commitment asked for.
    private func discarded() {
        if movingToCommitment { onWholeCommitment = true } else { onDone() }
    }

    /// What the form edits, by the name the file holds. Opened on one charge, the line names
    /// what backs it, as the charge's row does.
    private var subtitle: String {
        guard let editingId else { return "" }
        if chargeISO != nil, let row = anchor {
            return row.sub.name + (row.row.basis.map { " · \(basisWord($0))" } ?? "")
        }
        return model.subscription(id: editingId)?.name ?? ""
    }

    private var discardTitle: String { isEditing ? "Discard your changes?" : "Discard what you’ve typed?" }

    /// What backs a row, in plain words.
    private func basisWord(_ basis: String) -> String {
        switch basis {
        case "statement": "From a statement"
        case "email": "From an email"
        case "user": "Set by you"
        case "mark_paid": "Marked paid"
        default: "Planned"
        }
    }

    /// Half-typed work never dies to one tap: a form holding a change asks first. One whose
    /// commitment or charge has gone has nothing left to lose.
    private func close() {
        if isGone || !hasUnsavedChanges { onDone() } else { confirmingDiscard = true }
    }

    /// What one row of this commitment is called, whichever the form is on.
    private func rowWord(capitalized: Bool = false) -> String {
        let word = edit.direction == "in" ? "earning" : edit.direction == "transfer" ? "transfer" : "charge"
        return capitalized ? word.capitalized : word
    }

    private func deleted() {
        onDeleted()
        onDone()
    }

    private func memoryLine(_ memory: String) -> some View {
        HStack(alignment: .top, spacing: LBSpacing.s2) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(LBColor.brandText.color)
            Text(memory)
                .lbText(.footnote)
                .foregroundStyle(LBColor.textSecondary.color)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(LBSpacing.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LBColor.brand.color.opacity(0.10), in: RoundedRectangle(cornerRadius: LBRadius.sm, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func footnote(_ text: String) -> some View {
        Text(text)
            .lbText(.footnote)
            .foregroundStyle(LBColor.textTertiary.color)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: editing

    /// Edit, in the order the Preview reads: the name and the decisions keep their place while
    /// the fields scroll between them. Close leads on the Mac, as every panel has it; a
    /// phone's sheet keeps its X at the trailing end.
    private var editPage: some View {
        VStack(spacing: 0) {
            #if os(macOS)
            VStack(alignment: .leading, spacing: LBSpacing.s2) {
                PanelCloseButton(help: "Close without saving (Esc)", measure: "close") { close() }
                    .measured("renewal_form_confirming_discard", .dialog, when: confirmingDiscard)
                    .confirmationDialog(discardTitle, isPresented: $confirmingDiscard, titleVisibility: .visible) {
                        Button("Discard", role: .destructive) { Measure.used("discard"); discarded() }
                        Button("Keep Editing", role: .cancel) { Measure.used("keep_editing"); movingToCommitment = false }
                    } message: {
                        if let kept = typing.keptOnDiscard(model) { Text(kept) }
                    }
                editTitle
            }
            .padding(.horizontal, LBSpacing.s4)
            .padding(.top, LBSpacing.s3)
            .padding(.bottom, LBSpacing.s2)
            .frame(maxWidth: .infinity, alignment: .leading)
            #else
            header
                .padding(.horizontal, LBSpacing.s4)
                .padding(.top, LBSpacing.s4)
            #endif
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: Self.rowGap) {
                        if onCharge, sharesItsCommitment { commitmentLine }
                        if onCharge { chargeFields } else { commitmentFields }
                        if let saveError = model.saveError {
                            Text(saveError)
                                .lbText(.footnote)
                                .foregroundStyle(LBColor.urgent.color)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        #if os(iOS)
                        if !isGone { deleteButton.frame(maxWidth: .infinity).padding(.top, LBSpacing.s2) }
                        #endif
                    }
                    .padding(.horizontal, LBSpacing.s4)
                    .padding(.vertical, LBSpacing.s2)
                    #if os(iOS)
                    .frame(maxWidth: 560)
                    .frame(maxWidth: .infinity)
                    #endif
                }
                .onAppear { reveal(proxy) }
            }
            if isGone {
                VStack(spacing: LBSpacing.s3) {
                    footnote(goneNote)
                    Button(action: { Measure.used("close"); onDone() }) { primaryLabel("Close") }
                        .lbButtonStyle()
                }
                .padding(LBSpacing.s4)
            } else {
                EditFormFooter(word: subject(capitalized: true), saveOnReturn: !inPanel || focusInForm, cancel: close, save: attemptSave) { deleteButton }
            }
        }
    }

    private static var rowGap: CGFloat {
        #if os(macOS)
        LBSpacing.s2
        #else
        LBSpacing.s3
        #endif
    }

    #if os(macOS)
    private var editTitle: some View {
        VStack(alignment: .leading, spacing: LBSpacing.s1) {
            Text("Edit " + subject(capitalized: true))
                .lbText(.screenTitle)
                .foregroundStyle(LBColor.textPrimary.color)
                .accessibilityAddTraits(.isHeader)
            if !subtitle.isEmpty {
                Text(subtitle)
                    .lbText(.body)
                    .foregroundStyle(LBColor.textTertiary.color)
                    .lineLimit(2)
            }
        }
    }
    #endif

    /// More than this one row stands on the commitment, so what lives there reaches them all.
    private var sharesItsCommitment: Bool {
        guard let editingId else { return false }
        return edit.billingCycle != .once || model.charges(of: editingId).count > 1
    }

    /// Said once, in place of a note on every field the commitment holds.
    private var commitmentLine: some View {
        let reach = edit.direction == "transfer" ? "Name and accounts change" : "Name, category, accounts and person change"
        return LBReflowStack(spacing: LBSpacing.s2) {
            Text("\(reach) every \(rowWord()).")
                .lbText(.footnote)
                .foregroundStyle(LBColor.textTertiary.color)
            Button {
                Measure.used("edit_commitment")
                if hasUnsavedChanges {
                    movingToCommitment = true
                    confirmingDiscard = true
                } else {
                    onWholeCommitment = true
                }
            } label: {
                Text("Edit Commitment")
                    .lbText(.footnote)
                    .foregroundStyle(LBColor.brandText.color)
            }
            .lbButtonStyle()
        }
    }

    /// One charge: what it alone holds, among what its commitment holds for every charge.
    @ViewBuilder
    private var chargeFields: some View {
        whatFor
        howMuch
        if anchorISO != nil { dayRows.id(EditFocus.date) }
        if showsPaid, spends { paidRow.id(EditFocus.paid) }
        categoryRow.id(EditFocus.category)
        sideRows
        plainChargeNoteField
        statementLineField("Statement line", text: $chargeLine, field: .statementLine)
    }

    /// The commitment: everything it holds, and the next charge it opens on.
    @ViewBuilder
    private var commitmentFields: some View {
        whatFor
        howMuch
        howOften.id(EditFocus.repeats)
        dayRows.id(EditFocus.date)
        plannedRow.id(EditFocus.planned)
        if edit.billingCycle != .once { statusRow.id(EditFocus.status) }
        // A one-time commitment is offered no end day, but one it already carries stays in
        // view so it can be cleared.
        if edit.billingCycle != .once || cancellingOn != nil { cancellingSection.id(EditFocus.ends) }
        if showsFreeTrial {
            FormToggleRow(title: "Free trial", isOn: $edit.freeTrial, measure: "free_trial").id(EditFocus.freeTrial)
        }
        // A one-time commitment's only charge is the commitment, so its mark is here.
        if heldOnce, showsPaid, spends { paidRow.id(EditFocus.paid) }
        categoryRow.id(EditFocus.category)
        sideRows
        #if os(macOS)
        if let editingId {
            FormRow {
                FormQuestion("Photo")
            } content: {
                PhotoMenuField(current: model.commitmentPhotoURL(id: editingId), picked: $photoData, removing: $removingPhoto, shape: .circle)
            }
        }
        #endif
        notesField
        // A recurring commitment's line and its charge's are two things; a one-time row has the one.
        statementLineField("Statement line", text: showsCommitmentLine ? $ownLine : $chargeLine, field: .statementLine)
        if showsChargeNote { plainChargeNoteField }
        if showsCommitmentLine, anchorHoldsItsOwnLine {
            statementLineField("Charge statement line", text: $chargeLine, field: .chargeStatementLine)
        }
        if let memory = editingId.flatMap({ model.rowMemory(id: $0) }) { memoryLine(memory) }
    }

    /// The commitment form's statement line is the commitment's own: on a recurring one, and on
    /// a one-time one with no charge to carry it.
    private var showsCommitmentLine: Bool { !onCharge && (!heldOnce || anchor == nil) }

    /// The charge the form is on carries a line of its own, so nothing in the file is hidden.
    private var anchorHoldsItsOwnLine: Bool {
        !chargeLine.isEmpty || ChargeNote.parts(anchor?.row.note).statementLine != nil
    }

    private func statementLineField(_ title: String, text: Binding<String>, field: EditFocus) -> some View {
        FormRow {
            FormQuestion(title)
        } content: {
            FormStatementLineField(text: text)
                .focused($typingIn, equals: field)
        }
        .id(field)
    }

    /// The form's charge by its day: Date on a charge, the next one on a commitment, with the
    /// way onto another charge under it. On a commitment with nothing ahead, the last charge.
    @ViewBuilder
    private var dayRows: some View {
        if anchorISO != nil {
            FormRow {
                FormQuestion(dayWord)
            } content: {
                FormDayButton(title: dayWord, date: $day)
                if !onCharge, edit.billingCycle != .once, occurrences.count > 1 { occurrenceMenu(occurrences) }
                if movesDay { footnote(dayMoveNote) }
            }
        } else if let lastCharge {
            FormRow {
                FormQuestion(edit.direction == "transfer" ? "Last transfer" : "Last charge")
            } content: {
                FormField {
                    Text(LB.longDate(lastCharge))
                        .lbText(.body)
                        .foregroundStyle(LBColor.textSecondary.color)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private var dayWord: String {
        if onCharge || edit.billingCycle == .once { return "Date" }
        return edit.direction == "transfer" ? "Next transfer" : "Next charge"
    }

    /// How far the plan runs: a tap lists the usual counts, and Save writes the count once moved.
    @ViewBuilder
    private var plannedRow: some View {
        if showsPlannedTill {
            let horizon = self.horizon
            let times = shownCount(horizon)
            FormRow {
                FormQuestion("Planned until")
            } content: {
                Button { Measure.used("recurrence"); pickingRecurrence = true } label: {
                    FormChoiceFace(value: horizon.till(count: times).map(LB.longDate) ?? "None", empty: times == 0)
                }
                .lbButtonStyle()
                .accessibilityLabel(times > 0 ? "Planned until, \(times) times. Tap to change." : "Planned until. Tap to plan ahead.")
                if times == 0 { footnote("Nothing planned ahead.") }
            }
        }
    }

    /// A transfer is asked for no category, though one it already wears stays in view.
    @ViewBuilder
    private var categoryRow: some View {
        if edit.direction != "transfer" || edit.tag != nil {
            CommitmentRacks(row: .category, model: model, tag: $edit.tag, accountId: $edit.paymentMethodId,
                            memberId: $edit.familyMemberId, opensOnAppear: opens(.category),
                            detourOpen: $rackDetour, typing: typing)
        }
    }

    /// The Preview's four sides in its order, From then To. The row's own account pays out,
    /// or takes money in; its person sits on the other side; a transfer has only accounts.
    /// What follows from an account, who holds it, is stated rather than asked.
    @ViewBuilder
    private var sideRows: some View {
        if edit.direction == "in" {
            counterpartRow("From Account", field: .fromAccount).id(EditFocus.fromAccount)
            personRow("From Person", field: .fromPerson).id(EditFocus.fromPerson)
            accountRow("To Account", field: .toAccount).id(EditFocus.toAccount)
            FormFactRow(title: "To Person", value: holder(of: edit.paymentMethodId))
        } else {
            accountRow("From Account", field: .fromAccount).id(EditFocus.fromAccount)
            FormFactRow(title: "From Person", value: holder(of: edit.paymentMethodId))
            counterpartRow("To Account", field: .toAccount).id(EditFocus.toAccount)
            if edit.direction == "transfer" {
                FormFactRow(title: "To Person", value: counterpartHolder)
            } else {
                personRow("To Person", field: .toPerson).id(EditFocus.toPerson)
            }
        }
    }

    private func accountRow(_ label: String, field: EditFocus) -> some View {
        CommitmentRacks(row: .account(label), model: model, tag: $edit.tag, accountId: $edit.paymentMethodId,
                        memberId: $edit.familyMemberId, opensOnAppear: opens(field),
                        detourOpen: $rackDetour, typing: typing)
    }

    private func personRow(_ label: String, field: EditFocus) -> some View {
        CommitmentRacks(row: .member(label), model: model, tag: $edit.tag, accountId: $edit.paymentMethodId,
                        memberId: $edit.familyMemberId, opensOnAppear: opens(field),
                        detourOpen: $rackDetour, typing: typing)
    }

    /// Who holds an account, by id; an account a statement only named has no one.
    private func holder(of accountId: String?) -> String {
        model.entityChoices(.paymentMethod).first { $0.id == accountId }?.owner?.name ?? "None"
    }

    /// Whoever holds the other side. A statement's name left alone reads as the Preview reads
    /// it, matched to the account it names.
    private var counterpartHolder: String {
        if let editingId, let sub = model.subscription(id: editingId), counterpart == Self.counterpart(of: sub),
           let person = model.sides(ofCommitment: sub)?.to.person {
            return person
        }
        return holder(of: counterpart)
    }

    /// The account on the other side: any of the book's but the row's own, or None, or one
    /// named here and written at once, as the racks write theirs. The pick is written with Save,
    /// which asks first when that turns rows into Transfers or back.
    private func counterpartRow(_ label: String, field: EditFocus) -> some View {
        let accounts = model.editChoices.methods.filter { $0.id != edit.paymentMethodId }
        let name = counterpartName
        let owners = Dictionary(model.entityChoices(.paymentMethod).compactMap { account in
            account.owner.map { (account.id, $0.name) }
        }, uniquingKeysWith: { first, _ in first })
        var choices = accounts.map {
            ChoicePickerView.Choice(id: $0.id, name: $0.name, symbol: LBGlyph.account, detail: owners[$0.id])
        }
        // A name no account answers to stays on the list, so it reads as chosen.
        if let name, let counterpart, !accounts.contains(where: { $0.id == counterpart }) {
            choices.insert(ChoicePickerView.Choice(id: counterpart, name: name, symbol: LBGlyph.account), at: 0)
        }
        return FormRow {
            FormQuestion(label)
        } content: {
            ChoiceField(label, value: name ?? "None", empty: name == nil, choices: choices, selected: counterpart,
                        adding: .named("Account") { addCounterpart($0) },
                        opensOnAppear: opens(field), onPick: { counterpart = $0 })
        }
    }

    /// Writes an account named on the other side and chooses it; nil once chosen, else why not.
    private func addCounterpart(_ name: String) -> String? {
        let known = Set(model.editChoices.methods.map(\.id))
        guard let id = model.addEntity(.paymentMethod, named: name) else {
            LBHaptics.warn()
            return model.saveError ?? "That didn’t save."
        }
        if !known.contains(id) { typing.noteAdded(id) }
        counterpart = id
        return nil
    }

    /// The other side as words: its account's name, or the name a statement gave one the book
    /// does not hold. Nil for an id whose account no longer exists: an id is never shown.
    private var counterpartName: String? {
        guard let counterpart else { return nil }
        if let account = model.editChoices.methods.first(where: { $0.id == counterpart }) { return account.name }
        guard let editingId, let sub = model.subscription(id: editingId) else { return nil }
        let named = CounterpartAccounts.counterpart(of: sub)
        return named.id == nil && named.name == counterpart ? counterpart : nil
    }

    /// Red at the foot, and a question before it acts. A charge the commitment stands without
    /// goes alone or with the plan after it; anything else takes the commitment.
    private var deleteButton: some View {
        Button {
            Measure.used("delete")
            if removesCharge { confirmingRemove = true } else { confirmingDelete = true }
        } label: {
            EditFormDeleteLabel(title: "Delete " + (removesCharge ? rowWord(capitalized: true) : subject(capitalized: true)))
        }
        .lbButtonStyle()
    }

    // MARK: adding

    /// The essentials first — name, how often, amount, date — and the filing under More Details.
    @ViewBuilder
    private var addFields: some View {
        whatFor
        howOften
        howMuch
        whenNext
        if showsPaidToggle { paidRow }
        if showsFreeTrial {
            FormToggleRow(title: "Free trial", isOn: $edit.freeTrial, measure: "free_trial")
        }
        moreDetails
    }

    /// Category, Account, Person and the notes: closed on a new commitment until asked for.
    private var moreDetails: some View {
        VStack(alignment: .leading, spacing: LBSpacing.s4) {
            Button {
                Measure.used("more_details")
                withAnimation(.snappy(duration: 0.2)) { showsMore.toggle() }
            } label: {
                HStack(spacing: LBSpacing.s1) {
                    Text("More Details")
                        .lbText(.body)
                    Image(systemName: showsMore ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .accessibilityHidden(true)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(LBColor.brandText.color)
                .frame(minHeight: 32)
                .contentShape(Rectangle())
            }
            .lbButtonStyle()
            .formContentColumn()
            .accessibilityValue(showsMore ? "Shown" : "Hidden")
            if showsMore {
                CommitmentRacks(model: model, tag: $edit.tag, accountId: $edit.paymentMethodId,
                                memberId: $edit.familyMemberId, openedWith: openedWith,
                                blankings: blankings, detourOpen: $rackDetour, typing: typing)
                notesField
            }
        }
    }

    /// The name, required, with the names already in the vault offered under it.
    private var whatFor: some View {
        FormRow {
            FormQuestion("Name", required: !isEditing)
        } content: {
            FormNameField(text: $edit.name)
            if let statusNote { footnote(statusNote) }
            // Names already in the vault — the "select" half of the field, and the way a
            // cancelled commitment comes back under exactly its old name.
            if !isEditing, !edit.name.isEmpty, !suggestions.isEmpty {
                LBFlow {
                    ForEach(suggestions, id: \.self) { name in
                        LBChip(name, style: .choice(selected: false)) { edit.name = name }
                    }
                }
            }
        }
    }

    /// Active, paused or cancelled, as one row that opens a menu.
    private var statusRow: some View {
        FormRow {
            FormQuestion("Status")
        } content: {
            ChoiceField("Status", value: edit.status.rawValue.capitalized,
                        choices: [SubStatus.active, .paused, .cancelled].map {
                            ChoicePickerView.Choice(id: $0.rawValue, name: $0.rawValue.capitalized, symbol: nil)
                        },
                        selected: edit.status.rawValue, allowsNone: false, searchable: false,
                        opensOnAppear: opens(.status)) { picked in
                if let status = picked.flatMap(SubStatus.init(rawValue:)) { edit.status = status }
            }
        }
    }

    private var suggestions: [String] {
        let typed = edit.name.lowercased()
        return model.editChoices.names
            .filter { $0.lowercased().contains(typed) && $0.lowercased() != typed }
            .prefix(4)
            .map { $0 }
    }

    /// What a changed status does on Save, said under the name while it differs from the
    /// file's: a stop unwrites the plan after today, a resume plans it again by the count.
    private var statusNote: String? {
        guard let editingId, let was = model.subscription(id: editingId)?.status, was != edit.status else { return nil }
        let today = LB.todayMid()
        let planned = model.charges(of: editingId).filter {
            $0.date > today && !$0.row.paid && ($0.row.basis ?? "plan") == "plan"
        }.count
        return FormWords.statusNote(from: was, to: edit.status, planned: planned, plansAhead: showsPlannedTill)
    }

    /// How often, as one row that opens a menu — Never, Monthly, Yearly or Custom — with
    /// which way the money moves beside the label, and the charge being edited under it.
    private var howOften: some View {
        FormRow {
            FormQuestion("Repeats", money: MoneyButton(direction: edit.direction) { pickingMoney = true })
        } content: {
            ChoiceField("Repeats", value: repeatsWord, symbol: isEditing ? nil : LBGlyph.cycle,
                        choices: [(BillingCycle.once, "Never"), (.monthly, "Monthly"), (.yearly, "Yearly"), (.custom, "Custom…")].map {
                            ChoicePickerView.Choice(id: $0.0.rawValue, name: $0.1, symbol: nil)
                        },
                        selected: edit.billingCycle.rawValue, allowsNone: false, searchable: false,
                        opensOnAppear: opens(.repeats)) { picked in
                if let cycle = picked.flatMap(BillingCycle.init(rawValue:)) { repeatsChoice.wrappedValue = cycle }
            }
            if refusedOneTime, let oneTimeRefusal {
                Text(oneTimeRefusal)
                    .lbText(.footnote)
                    .foregroundStyle(LBColor.urgent.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if edit.billingCycle == .custom {
                FormField {
                    TextField("", text: Binding(
                        get: { edit.customCycleDays.map(String.init) ?? "" },
                        set: { edit.customCycleDays = Self.cycleDays(typed: $0) }
                    ), prompt: Text("Days between charges").foregroundStyle(LBColor.textTertiary.color))
                        .textFieldStyle(.plain)
                        .lbText(.body)
                        .foregroundStyle(LBColor.textPrimary.color)
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #endif
                }
            }
        }
        .measured("renewal_form_picking_money", .sheet, when: pickingMoney)
        .sheet(isPresented: $pickingMoney) {
            MoneyPicker(direction: $edit.direction) { pickingMoney = false }
                .lbKeyboardFocusEffects()
        }
    }

    private var repeatsWord: String {
        switch edit.billingCycle {
        case .once: "Never"
        case .monthly: "Monthly"
        case .yearly: "Yearly"
        case .custom: edit.customCycleDays.map { "Every \($0) days" } ?? "Custom"
        }
    }

    /// The list's pick, as the chips took it: Never is refused, and said why, on a commitment
    /// whose charges one row cannot hold.
    private var repeatsChoice: Binding<BillingCycle> {
        Binding(get: { edit.billingCycle }, set: { cycle in
            guard cycle == .once else {
                edit.billingCycle = cycle
                refusedOneTime = false
                return
            }
            if let oneTimeRefusal {
                refusedOneTime = true
                LBHaptics.warn()
                AccessibilityNotification.Announcement(oneTimeRefusal).post()
            } else {
                edit.billingCycle = .once
            }
        })
    }

    // MARK: occurrences

    /// One charge the strip offers: its day and its mark.
    private struct Occurrence: Identifiable {
        let iso: String
        let day: Date
        let paid: Bool
        var id: String { iso }
    }

    /// The charges from today on — an existing commitment's rows, plus the form's own charge
    /// and the one it opened on even when behind today. One chip per day; none for a new
    /// commitment, which has no charge to move onto yet.
    private var occurrences: [Occurrence] {
        guard let editingId else { return [] }
        let today = LB.todayMid()
        var seen = Set<String>()
        return model.charges(of: editingId)
            .filter { (!($0.date < today) || $0.row.date == anchorISO || $0.row.date == chargeISO) && seen.insert($0.row.date).inserted }
            .map { Occurrence(iso: $0.row.date, day: $0.date, paid: $0.row.paid) }
    }

    /// The charge the form is on, as a menu of the charges from today on: a pick moves the
    /// form onto that charge. Each one's words are formatted once, here.
    private func occurrenceMenu(_ occurrences: [Occurrence]) -> some View {
        let words = FormWords.occurrenceWords(occurrences.map { ($0.iso, $0.day) })
        let current = anchorISO.flatMap { words[$0]?.label } ?? "Choose a charge"
        return FormMenuField(value: "Charge on \(current)") {
            ForEach(occurrences) { occurrence in
                let word = (words[occurrence.iso]?.label ?? occurrence.iso) + (occurrence.paid ? " · Paid" : "")
                Button { Measure.used("switch_occurrence"); switchOccurrence(to: occurrence.iso) } label: {
                    if occurrence.iso == anchorISO { Label(word, systemImage: "checkmark") } else { Text(word) }
                }
            }
        }
        .accessibilityLabel("Charge being edited, \(anchorISO.flatMap { words[$0]?.spoken } ?? "none")")
    }

    /// Edits on the form's charge belong to that charge alone, so moving off it asks first.
    private func switchOccurrence(to iso: String) {
        guard isEditing, iso != anchorISO else { return }
        if chargeEdited { switchingTo = iso } else { loadCharge(iso); rebaseCharge() }
    }

    /// Days between charges as typed: digits only, none for none or zero, and no more than a
    /// write takes, so a longer run reads as the limit.
    private static func cycleDays(typed text: String) -> Int? {
        let digits = text.filter { $0.isASCII && $0.isNumber }
        guard !digits.isEmpty else { return nil }
        guard let days = Int(digits) else { return CUSTOM_DAYS_LIMIT }
        return days == 0 ? nil : min(days, CUSTOM_DAYS_LIMIT)
    }

    /// Why an existing recurring commitment holding more than one charge stays recurring, or
    /// nil where One-time may be chosen. The writer refuses the switch in the same words.
    private var oneTimeRefusal: String? {
        guard let editingId, model.subscription(id: editingId)?.billingCycle != .once else { return nil }
        let held = model.charges(of: editingId).count
        return held > 1 ? VaultPatch.oneTimeRefusal(charges: held) : nil
    }

    private func cycleWord(_ cycle: BillingCycle) -> String {
        switch cycle {
        case .monthly: "Monthly"
        case .yearly: "Yearly"
        case .custom: "Custom"
        case .once: "Once"
        }
    }

    /// The amount of the charge the form is on, the currency inside its field. On the
    /// commitment itself it is the price, which the vault cannot hold a commitment without.
    private var howMuch: some View {
        FormRow {
            FormQuestion("Amount", required: !isEditing)
        } content: {
            FormAmountField(text: $amountText) {
                if picksCurrency {
                    FormCurrencyMenu(model: model, currency: $edit.currency, opensOnAppear: opens(.currency))
                } else {
                    currencyLabel
                }
            }
            if let own = anchor?.row.currency {
                footnote("Counted in \(own), carried on this charge.")
            }
            if let amountNote { footnote(amountNote) }
        }
    }

    /// The form is on a charge whose mark it can write: a new commitment's first, or the one
    /// an existing commitment was opened on.
    private var showsPaid: Bool { !isEditing || anchorISO != nil }

    /// A new commitment's first charge is marked only once its day has come.
    private var showsPaidToggle: Bool {
        showsPaid && (isEditing || !(LB.dayOf(day) > LB.todayMid()))
    }

    /// The mark on the form's charge, written in the same Save, as the list's swipe marks it.
    @ViewBuilder
    private var paidRow: some View {
        FormToggleRow(title: isEditing ? "Paid" : "Already paid", isOn: $paid, measure: "paid")
        // A spending charge behind today counts whatever its row's mark says; stated while the
        // mark is off. Money in and a transfer are in no spending total, marked or not.
        if !paid, LB.dayOf(day) < LB.todayMid(), spends {
            footnote("Charges before today count in your totals, marked or not.").formContentColumn()
        }
    }

    /// The strip sets the commitment's currency, and so every charge stating none: offered on the
    /// commitment or a one-time one's only charge. On one charge among several, or one stating
    /// its own code, which no write changes, the code is stated instead.
    private var picksCurrency: Bool {
        let sole = model.charges(of: editingId ?? "").count <= 1
        return anchor?.row.currency == nil && (chargeISO == nil || (edit.billingCycle == .once && sole))
    }

    private var currencyLabel: some View {
        Text(anchor?.currency ?? edit.currency)
            .lbText(.label)
            .foregroundStyle(LBColor.textSecondary.color)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, LBSpacing.s2)
            .frame(minWidth: 40, minHeight: Self.currencyHeight(editing: isEditing))
            .background(LBColor.chrome.color, in: Capsule())
            .accessibilityLabel("Counted in \(anchor?.currency ?? edit.currency)")
    }

    /// The Mac's Edit form holds the code inside a field that stands one line tall.
    private static func currencyHeight(editing: Bool) -> CGFloat {
        #if os(macOS)
        editing ? 18 : 34
        #else
        34
        #endif
    }

    /// What a new amount reaches on a recurring commitment: from a charge today or later, that
    /// charge and, if asked, the plan after it; from one behind today, that charge alone.
    private var amountNote: String? {
        guard isEditing, edit.billingCycle != .once else { return nil }
        if anchor != nil, !anchorAhead { return "Changes this \(rowWord()) only." }
        return "Past charges stay as they were."
    }

    /// The form's charge moves to another day on Save.
    private var movesDay: Bool { anchor.map { LB.toISO(day) != LB.toISO($0.date) } ?? false }

    /// The day of the form's charge — a new commitment's first, else the one it is on — with
    /// the Recurrence chip on its row where a plan can be set.
    private var whenNext: some View {
        VStack(alignment: .leading, spacing: LBSpacing.s2) {
            FormDayPicker(title: edit.billingCycle != .once ? "Starts" : "Date", date: $day)
            // The plan's reach reads under the date it starts from, in the fields' column.
            if showsPlannedTill {
                FormRow { Color.clear.frame(height: 1) } content: {
                    HStack { recurrenceChip; Spacer(minLength: 0) }
                }
            }
            if showsPlannedTill, shownCount(horizon) == 0 { footnote("Nothing planned ahead.") }
        }
    }

    /// The day of the commitment's last charge, when the form is on the commitment itself.
    private var lastCharge: Date? {
        guard onCommitment, let editingId else { return nil }
        return model.charges(of: editingId).last?.date
    }

    /// Said before Save, not after: a recurring plan can follow the charge to its new day, so
    /// the screen states the move and names the choice still to come.
    private var dayMoveNote: String {
        let move = "Saving moves this charge to \(LB.longDate(day))."
        guard edit.billingCycle != .once, anchorAhead else { return move }
        return move + " You then choose whether the planned charges after it follow, one cycle apart."
    }

    // MARK: recurrence

    /// The days the plan can reach, read with the cycle and cancelling date the form holds now,
    /// beside the file's own date: from today on for an existing commitment, from its first
    /// charge for a new one.
    private var horizon: PlanHorizon {
        guard let editingId else {
            return PlanHorizon(first: day, cycle: edit.billingCycle, customDays: edit.customCycleDays)
        }
        return PlanHorizon(rows: model.charges(of: editingId).map(\.row), cycle: edit.billingCycle,
                           customDays: edit.customCycleDays, end: cancellingOn.map { LB.toISO($0) },
                           heldEnd: model.subscription(id: editingId)?.scheduledCancelDate, today: LB.todayMid())
    }

    /// A count is written only for a new commitment or a Save that leaves one active, and only
    /// where a charge can still be planned, so only then is it asked.
    private var showsPlannedTill: Bool {
        edit.billingCycle != .once && (!isEditing || edit.status == .active) && horizon.most > 0
    }

    /// A stopped commitment set back to Active on this form.
    private var isResuming: Bool {
        guard let editingId, let was = model.subscription(id: editingId)?.status else { return false }
        return was != .active && edit.status == .active
    }

    /// The count the form stands on: the one chosen — or, on a resume with nothing ahead and
    /// no count picked yet, the usual default, so the Save plans it ahead again.
    private var chosenCount: Int {
        if planCount.chosen == 0, planCount.held == 0, isResuming { return DEFAULT_PLAN_MONTHS }
        return planCount.chosen
    }

    /// The count the chip shows: the one chosen, as far as the plan can reach and, once moved,
    /// no further than the ceiling a Save sets — counted as the charges that then stand, never
    /// fewer than the rows a shorter plan cannot take.
    private func shownCount(_ horizon: PlanHorizon) -> Int {
        let reach = chosenCount == planCount.held ? horizon.most : min(horizon.most, PlannedCount.ceiling)
        return horizon.days(count: min(chosenCount, reach)).count
    }

    /// The count a Save writes: the one shown, unless the file already holds exactly that — its
    /// count, and those rows still standing after the Save's own cancelling date.
    private var countToSave: Int? {
        let shown = shownCount(horizon)
        return shown == planCount.held && shown == horizon.written ? nil : shown
    }

    /// The count this Save sends: only for a recurring commitment the Save leaves active, as
    /// a pause or a cancel plans nothing.
    private var countSent: Int? {
        edit.billingCycle != .once && edit.status == .active ? countToSave : nil
    }

    /// The plan's reach on the date's row — "Until September 2028" — or "Recurrence" alone
    /// with nothing ahead. A tap lists the usual counts; Save writes the count once moved.
    private var recurrenceChip: some View {
        let horizon = self.horizon
        let times = shownCount(horizon)
        let last = horizon.till(count: times)
        return LBChip(last.map { "Until \(LB.monthYear($0))" } ?? "Recurrence", symbol: LBGlyph.cycle,
                      style: .choice(selected: false)) {
            pickingRecurrence = true
        }
        .accessibilityLabel(times > 0 ? "Recurrence, \(times) times. Tap to change." : "Recurrence. Tap to plan ahead.")
    }

    /// The usual counts as the category list lists its tags, the one shown ticked; "Other…"
    /// opens the wheel for any count. A pick is held to what the plan can reach.
    private var recurrencePicker: some View {
        let horizon = self.horizon
        let times = shownCount(horizon)
        let usual = PlannedCount.usual.map { ChoicePickerView.Choice(id: String($0), name: "\($0) times", symbol: nil) }
        return ChoicePickerView(
            title: "Recurrence",
            glyph: LBGlyph.cycle,
            choices: usual + [ChoicePickerView.Choice(id: "other", name: "Other…", symbol: nil)],
            selected: PlannedCount.usual.contains(times) ? String(times) : (times > 0 ? "other" : nil),
            onPick: { id in
                if id == "other" { wheelNext = true } else if let count = Int(id) { planCount.chosen = min(count, horizon.most) }
            },
            onDone: { pickingRecurrence = false }
        )
    }

    /// The wheel behind "Other…". With none ahead in the file it runs from none, the count
    /// the file holds; a resumed commitment is planned, so from one.
    private var countWheel: some View {
        let horizon = self.horizon
        let times = shownCount(horizon)
        let lowest = planCount.held == 0 && !isResuming ? 0 : 1
        return PlannedCountPicker(count: Binding(get: { times }, set: { planCount.chosen = $0 }),
                                  range: lowest...max(lowest, times, min(120, horizon.most))) {
            pickingCount = false
        }
    }

    // MARK: the rest of the questions

    /// Free trial is offered for every recurring spending commitment, new or edited, however
    /// the form was opened: it is a pill on the commitment, so the charges never hide it.
    private var showsFreeTrial: Bool { edit.billingCycle != .once && spends }

    /// Spending, as the form stands: neither money in nor a transfer.
    private var spends: Bool { edit.direction != "in" && edit.direction != "transfer" }

    /// The commitment's details that matter, one per line — always in view, for a new
    /// commitment and an edited one alike.
    private var notesField: some View {
        FormRow {
            FormQuestion("Notes")
        } content: {
            FormNotesField(prompt: "The details that matter, one per line", text: Binding(
                get: { edit.notes ?? "" },
                set: { edit.notes = $0.isEmpty ? nil : $0 }
            ), cap: notesCap)
            .focused($typingIn, equals: .notes)
        }
        .id(EditFocus.notes)
    }

    /// The longest the notes grow here: 500 characters, or the length they opened with, so an
    /// edit never cuts text they already hold.
    private var notesCap: Int { max(500, notesOpenedLength) }

    /// Where the form's charge carries a note of its own it is always shown, so nothing in the
    /// file is hidden; a recurring commitment's charge, whichever the form is on, offers one.
    private var showsChargeNote: Bool {
        guard anchorISO != nil else { return false }
        if !ChargeNote.parts(anchor?.row.note).notes.isEmpty || !chargeNotes.isEmpty { return true }
        return edit.billingCycle != .once && isEditing
    }

    /// On a form for one charge it is that form's only notes, so it is called Notes.
    private var plainChargeNoteField: some View {
        let field: EditFocus = onCharge ? .notes : .chargeNote
        return FormRow {
            FormQuestion(onCharge ? "Notes" : "Charge note")
        } content: {
            FormNotesField(prompt: "About this \(rowWord()) only", text: $chargeNotes,
                           cap: max(500, ChargeNote.parts(anchor?.row.note).notes.count))
            .focused($typingIn, equals: field)
        }
        .id(field)
    }

    /// A decision already made about a commitment that is still running, so it belongs on the
    /// row rather than in a status: it stays active, and the list says "cancelling" until the
    /// day arrives. None or a date, the date beside the choice once there is one.
    private var cancellingSection: some View {
        FormRow {
            FormQuestion("Ends")
        } content: {
            HStack(spacing: LBSpacing.s2) {
                // A one-time commitment's day is stated, only to be cleared: moved before its
                // charge, Save would remove that charge.
                if edit.billingCycle == .once, let cancellingOn {
                    HStack(spacing: LBSpacing.s2) {
                        Image(systemName: LBGlyph.date)
                            .font(.system(size: 11, weight: .medium))
                        Text(LB.longDate(cancellingOn)).lbText(.footnote)
                    }
                    .foregroundStyle(LBColor.textPrimary.color)
                    .frame(minHeight: 34)
                    keepingButton
                } else {
                    ChoiceField("Ends", value: cancellingOn == nil ? "None" : "On a date", empty: cancellingOn == nil,
                                choices: [ChoicePickerView.Choice(id: Self.endsOnDate, name: "On a date", symbol: LBGlyph.date)],
                                selected: cancellingOn == nil ? nil : Self.endsOnDate, searchable: false,
                                opensOnAppear: opens(.ends)) { picked in
                        cancellingOn = picked == nil ? nil : (cancellingOn ?? Date())
                    }
                    if cancellingOn != nil {
                        FormDayButton(title: "Ends", date: Binding(get: { cancellingOn ?? LB.todayMid() },
                                                                   set: { cancellingOn = $0 }))
                    }
                }
            }
            Text("No charges are planned after this date.")
                .lbText(.footnote)
                .foregroundStyle(LBColor.textTertiary.color)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The Ends list's one row besides None.
    private static let endsOnDate = "date"

    private var keepingButton: some View {
        Button { Measure.used("clear_cancel_date"); cancellingOn = nil } label: {
            Text("Clear")
                .lbText(.label)
                .foregroundStyle(LBColor.textTertiary.color)
                .padding(.vertical, LBSpacing.s2)
                .contentShape(Rectangle())
        }
        .lbButtonStyle()
    }

    // MARK: actions

    private var actions: some View {
        VStack(spacing: LBSpacing.s3) {
            #if os(macOS)
            footer
            #else
            Button(action: { Measure.used("attempt_save"); attemptSave() }) { primaryLabel("Add") }
                .lbButtonStyle()
            addAnother
            #endif
        }
        .padding(.top, LBSpacing.s2)
    }

    #if os(macOS)
    /// The Mac sheet's row: Cancel and the default at the right with Return bound to it.
    /// Each button takes only its own width.
    private var footer: some View {
        HStack(spacing: LBSpacing.s3) {
            Spacer(minLength: LBSpacing.s3)
            addAnother.fixedSize(horizontal: true, vertical: false)
            Button(action: { Measure.used("cancel"); close() }) {
                Text("Cancel")
                    .lbText(.label)
                    .foregroundStyle(LBColor.textSecondary.color)
                    .padding(.horizontal, LBSpacing.s2)
                    .padding(.vertical, LBSpacing.s2)
                    .contentShape(Rectangle())
            }
            .lbButtonStyle()
            .keyboardShortcut(.cancelAction)
            Button(action: { Measure.used("attempt_save"); attemptSave() }) { primaryLabel("Add", fills: false) }
                .lbButtonStyle()
                .keyboardShortcut(.defaultAction)
        }
    }
    #endif

    private var goneNote: String {
        guard editingId.flatMap(model.subscription(id:)) != nil else {
            return "This \(subject()) is no longer in your file. It was removed while this was open."
        }
        return "This charge is no longer in your file. It was removed or moved while this was open."
    }

    /// Full width on the phone; on the Mac's row only as wide as its word, never narrower than a button.
    private func primaryLabel(_ text: String, fills: Bool = true) -> some View {
        Text(text)
            .lbText(.body)
            .foregroundStyle(LBColor.onBrand.color)
            .padding(.horizontal, LBSpacing.s4)
            .frame(minWidth: fills ? nil : 120, maxWidth: fills ? .infinity : nil)
            .padding(.vertical, LBSpacing.s3)
            .background(LBColor.brand.color, in: RoundedRectangle(cornerRadius: LBRadius.sm, style: .continuous))
            .contentShape(Rectangle())
    }

    /// A charge of a recurring commitment, or one of a one-time commitment's several: the rest
    /// stand without it. A one-time commitment's only charge is the commitment. Opened on no
    /// charge in particular, the form is on one only once the strip has moved it off the
    /// charge it opened on.
    private var removesCharge: Bool {
        guard let editingId, anchor != nil, chargeISO != nil || anchorISO != openedOn else { return false }
        return !heldOnce || model.charges(of: editingId).count > 1
    }

    /// The file holds the commitment as one-time.
    private var heldOnce: Bool {
        editingId.flatMap(model.subscription(id:))?.billingCycle == .once
    }

    /// The form's charge is planned ahead on a recurring commitment, so the plan after it
    /// can go with it.
    private var offersLater: Bool {
        guard let row = anchor else { return false }
        return model.offersLaterRemoval(subscriptionId: row.sub.id, dateISO: row.row.date)
    }

    private var removeWords: String {
        if anchor?.row.paid == true { return "This charge is marked paid. Removing it takes that fact out of your file." }
        if heldOnce { return "Only this one is removed; the other charges stay." }
        if offersLater, let row = anchor { return model.laterRemovalWords(subscriptionId: row.sub.id, dateISO: row.row.date) }
        return "Only this one is removed; the rest of the plan stays."
    }

    private var addAnother: some View {
        Button {
            Measure.used("save_amount")
            guard amountAccepted(), typing.submit() else { return }
            let name = edit.name
            if saveNow(andLater: false) {
                resetForNext()
                // The beat that says the blank form is success, not loss.
                lastSavedName = name
                Task {
                    try? await Task.sleep(for: .seconds(2))
                    if lastSavedName == name { lastSavedName = nil }
                }
            }
        } label: {
            HStack(spacing: LBSpacing.s1) {
                if lastSavedName != nil {
                    Image(systemName: "checkmark").font(.system(size: 10, weight: .semibold))
                }
                Text(lastSavedName.map { "Saved \($0)" } ?? "Add Another")
                    .lbText(.label)
            }
            .foregroundStyle(LBColor.brandText.color)
            .frame(maxWidth: .infinity)
            .padding(.vertical, LBSpacing.s2)
            .contentShape(Rectangle())
        }
        .lbButtonStyle()
    }

    /// A clean sheet for the next one — every field, so nothing from the saved row rides along
    /// into it. The seeded category survives: "add another" inside a quick-add flow is still
    /// adding the same kind of thing.
    private func resetForNext() {
        edit = SubEdit()
        edit.currency = model.editChoices.currencies.first ?? "INR"
        edit.tag = seedCategory
        edit.direction = seedDirection
        amountText = ""
        cancellingOn = nil
        day = Date()
        paid = false
        chargeNotes = ""
        chargeLine = ""
        ownLine = ""
        planCount = PlannedCount(ahead: DEFAULT_PLAN_MONTHS)
        blankings += 1
        notesOpenedLength = 0
        refusedOneTime = false
        typing.forgetAdded()
        baseline = snapshot
    }

    // MARK: facts

    /// A number that differs from the charge's own, or nil when it is unchanged or unreadable.
    private var newAmount: Double? {
        guard let row = anchor, let typed = Double(amountText.replacingOccurrences(of: ",", with: "")) else { return nil }
        return typed == row.amount ? nil : typed
    }

    /// Compared as it is written, so spaces alone are not a change.
    private var noteChanged: Bool { note != formNote(anchor) }

    private var paidChanged: Bool { anchor.map { paid != $0.row.paid } ?? false }

    /// A new amount or day on a recurring commitment's charge from today on reaches as far as
    /// the owner says; a charge behind today is edited alone.
    private var asksReach: Bool {
        isEditing && edit.billingCycle != .once && anchorAhead && (movesDay || newAmount != nil)
    }

    /// What the reach answer decides, said for whichever change was made — including what the
    /// answer does not reach, and what a move past the cancelling date drops.
    private var reachMessage: String {
        var parts: [String] = []
        if movesDay {
            parts.append("This charge moves to \(LB.longDate(day)). With every one after, every planned charge after it follows, one cycle apart; charges you have already priced, moved or marked paid, and charges that came from a statement or an email, stay where they are.")
            if let pastEnd {
                parts.append(pastEnd.refuses
                    ? "The plan cannot be re-anchored past the cancelling date, \(LB.longDate(pastEnd.end)), so only this charge can move to that day."
                    : "With every one after, \(pastEnd.dropped) that would land past the cancelling date, \(LB.longDate(pastEnd.end)), are removed.")
            }
            if let laterEnd { parts.append("With every one after, the plan then runs to \(LB.longDate(laterEnd)).") }
        }
        if newAmount != nil {
            parts.append("With every one after, the unpaid planned charges after it take the new amount, and so do charges planned from now on. Charges paid or priced by you stay as they are.")
            if offersPast { parts.append("With all, the charges before it take the new amount too, except those from a statement.") }
        }
        if let eitherWay { parts.append(eitherWay) }
        if paidChanged || noteChanged {
            parts.append("The charge note and the paid mark are written to this charge either way.")
        }
        return parts.joined(separator: " ")
    }

    /// The form's other changes, in the change list's words: the answer never governs them.
    private var eitherWay: String? {
        guard let was = stored else { return nil }
        let form = snapshot
        let trim = { (text: String) in text.trimmingCharacters(in: .whitespacesAndNewlines) }
        let words = [(trim(form.name) != trim(was.name), "name"),
                     (form.cycle != was.cycle || form.customDays != was.customDays, "type"),
                     (form.currency != was.currency, "currency"), (form.tag != was.tag, "category"),
                     (form.accountId != was.accountId, "account"), (form.memberId != was.memberId, "member"),
                     (form.notes != was.notes, "notes"), (form.commitmentLine != was.commitmentLine, "statement line"),
                     (form.status != was.status, "status"),
                     (form.cancelISO != was.cancelISO, "cancelling date"), (countSent != nil, "recurrence"),
                     (form.trial != was.trial, "free trial"), (form.counterpart != was.counterpart, "counterpart account")]
            .filter(\.0).map(\.1)
        let fields = words.last.map { last in
            "the " + (words.count == 1 ? last : words.dropLast().joined(separator: ", ") + " and " + last)
        }
        switch (fields, form.direction != was.direction) {
        case (let fields?, true): return "Changes to \(fields), and to which way the money moves, are written either way."
        case (let fields?, false): return "Changes to \(fields) are written either way."
        case (nil, true): return "Changes to which way the money moves are written either way."
        case (nil, false): return nil
        }
    }

    /// What the cancelling date does to a move. A day past it refuses the whole run, so only
    /// this charge can go there; otherwise the rows of the run's tail landing past it are
    /// dropped, since nothing is planned past that day. The edited row never drops.
    private var pastEnd: (dropped: Int, end: Date, refuses: Bool)? {
        guard movesDay, edit.billingCycle != .once, let end = cancellingOn.map(LB.dayOf), let row = anchor else { return nil }
        let to = LB.dayOf(day)
        guard !(to > end) else { return (0, end, true) }
        // The run the writer carries along, read here only to count it: this charge, and every
        // unpaid planned one after it, stepped on the cycle the form holds.
        let run = model.charges(of: row.sub.id).filter { other in
            other.date == row.date || (other.date > row.date && !other.row.paid && (other.row.basis ?? "plan") == "plan")
        }
        var shape = row.sub
        shape.billingCycle = edit.billingCycle
        shape.customCycleDays = edit.customCycleDays
        let dropped = run.indices.dropFirst().filter { stepFrom(shape, to, $0) > end }.count
        return dropped > 0 ? (dropped, end, false) : nil
    }

    // MARK: writing

    /// Whether the typed amount is one the writer takes; when not, its refusal is on the form.
    /// A number left as the file holds it is the file's already; only a changed one is checked.
    private func amountAccepted() -> Bool {
        guard let typed = Double(amountText.replacingOccurrences(of: ",", with: "")) else {
            model.saveError = "The amount has to be a number, and not a negative one."
            return false
        }
        if let editingId, (anchor?.amount ?? model.subscription(id: editingId)?.amount) == typed { return true }
        do { try VaultPatch.checkAmount(typed) } catch {
            model.saveError = error.friendlyDescription
            return false
        }
        return true
    }

    private func attemptSave() {
        // An amount the writer would refuse is refused here, before anything is asked.
        guard amountAccepted() else { return }
        // A name still in an account or member pill is written and chosen first.
        guard typing.submit() else { return }
        if let editingId, counterpartChange != nil || edit.paymentMethodId != model.subscription(id: editingId)?.paymentMethodId {
            let flips = model.transferFlips(saving: commitmentDraft(editingId), counterpart: counterpartChange)
            if !TransferFlipWords.isZero(flips) {
                flipping = flips
                return
            }
        }
        saveAsAnswered()
    }

    /// The counterpart Save writes, as an account's id or none; nil to leave it alone. A pick
    /// is always an account or None, so a statement's name left alone is never written.
    private var counterpartChange: String?? {
        guard let editingId, let sub = model.subscription(id: editingId),
              counterpart != Self.counterpart(of: sub) else { return nil }
        return .some(counterpart)
    }

    /// Save, once any question about flipping charges has been answered.
    private func saveAsAnswered() {
        guard asksReach, let editingId else {
            if saveNow(andLater: false) { onDone() }
            return
        }
        // Where the plan ends once the later charges follow the move: this Save run on the
        // file as it stands, written nowhere, so the question can name the day.
        laterEnd = movesDay ? model.plannedEnd(of: commitmentDraft(editingId), plannedCount: countSent,
                                               charge: chargeChange(andLater: true)) : nil
        askingReach = true
    }

    /// The typed amount as a number; one the writer refuses where it is unreadable.
    private var typedAmount: Double { Double(amountText.replacingOccurrences(of: ",", with: "")) ?? -1 }

    /// An existing commitment's half of the Save. While the form is on a charge, the price stays
    /// as the file holds it: the charge's amount, and its reach, carry a new one. The trial
    /// flag is written only where the pill is offered.
    private func commitmentDraft(_ editingId: String) -> SubEdit {
        var draft = edit
        draft.scheduledCancelDate = cancellingOn.map { LB.toISO($0) }
        draft.amount = anchor == nil ? typedAmount : (model.subscription(id: editingId)?.amount ?? draft.amount)
        draft.freeTrial = edit.freeTrial && showsFreeTrial
        if let sub = model.subscription(id: editingId) { draft.details = detailsChange(sub) }
        return draft
    }

    /// The details Save writes when the line they hold changes; nil leaves them as they are. A
    /// one-time row's keeps the words as read until its line is emptied, so that it stays empty.
    private func detailsChange(_ sub: Subscription) -> Details? {
        let wanted: String
        if showsCommitmentLine {
            wanted = ChargeNote.parts(ChargeNote.joined(statementLine: ownLine, notes: nil)).statementLine ?? ""
        } else if sub.billingCycle == .once, chargeLine.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            wanted = ""
        } else {
            return nil
        }
        guard wanted != Self.printedLine(of: sub) else { return nil }
        var details = sub.details ?? [:]
        details["statement_line"] = wanted.isEmpty ? nil : .string(wanted)
        return details
    }

    /// The charge's half of the Save: its amount and day with the reach answered, its mark and
    /// its note. None while the form is on no charge.
    private func chargeChange(andLater: Bool, andPast: Bool = false) -> VaultPatch.ChargeChange? {
        anchor.map { row in
            VaultPatch.ChargeChange(from: row.row.date, to: movesDay ? LB.toISO(day) : nil,
                                    paid: paid == row.row.paid ? nil : paid, amount: newAmount,
                                    note: noteChanged ? .some(note.isEmpty ? nil : note) : nil,
                                    andLater: andLater, andPast: andPast)
        }
    }

    /// A new amount can reach back as well as forward, when charges other than a statement's
    /// lie behind today.
    private var offersPast: Bool {
        guard let editingId, newAmount != nil else { return false }
        let today = LB.todayMid()
        return model.charges(of: editingId).contains { $0.date < today && $0.row.basis != "statement" }
    }

    /// The commitment's fields and a changed count, then the form's charge, in one write. A
    /// refusal anywhere leaves the file as it was and the form open, the refusal on it.
    private func saveNow(andLater: Bool, andPast: Bool = false) -> Bool {
        guard let editingId else {
            var draft = edit
            let first = LB.toISO(day)
            draft.scheduledCancelDate = cancellingOn.map { LB.toISO($0) }
            draft.amount = typedAmount
            draft.firstCharge = first
            draft.planCount = draft.billingCycle != .once ? max(1, shownCount(horizon)) : nil
            draft.freeTrial = edit.freeTrial && showsFreeTrial
            return model.save(draft, charge: paid ? VaultPatch.ChargeChange(from: first, paid: true) : nil)
        }
        let change = chargeChange(andLater: andLater, andPast: andPast)
        guard model.save(commitmentDraft(editingId), plannedCount: countSent, charge: change, counterpart: counterpartChange) else { return false }
        settlePhoto(editingId)
        // The sheet reads the row it edits until it closes.
        if let change, change.moves {
            anchorISO = change.to
            if onCharge, let moved = change.to { onMoved(moved) }
        }
        return true
    }
}

/// A wheel for the planned count: it turns under the finger and, the moment it settles on a
/// number, the sheet closes on it.
private struct PlannedCountPicker: View {
    @Binding var count: Int
    let range: ClosedRange<Int>
    let onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: LBSpacing.s2) {
            HStack {
                Text("Charges ahead")
                    .lbText(.label)
                    .foregroundStyle(LBColor.textPrimary.color)
                Spacer()
                Button(action: { Measure.used("close"); onDone() }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(LBColor.textSecondary.color)
                        .frame(width: 30, height: 30)
                        .background(LBColor.chrome.color, in: Circle())
                }
                .lbButtonStyle()
                .help("Close")
                .accessibilityLabel("Close")
            }
            Picker("Times", selection: $count) {
                ForEach(range, id: \.self) { times in
                    Text("\(times) time\(times == 1 ? "" : "s")").tag(times)
                }
            }
            #if os(iOS)
            .pickerStyle(.wheel)
            #endif
            .frame(maxWidth: .infinity)
            .onChange(of: count) { _, _ in onDone() }
        }
        .padding(LBSpacing.s4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(LBColor.canvas.color)
    }
}
