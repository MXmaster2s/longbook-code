import DesignSystem
import LongbookCore
import SwiftUI
#if os(iOS)
import PhotosUI
#endif

/// Edit what describes an account or a person. An account: its name, type, balance, who it
/// belongs to, what it is linked to, and notes — a card's name among them. A person: their
/// name, tag, accounts and email. One Save is one write, of only the fields that changed.
struct EntityEditView: View {
    let model: DashboardModel
    let kind: VaultPatch.EntityKind
    let id: String
    let currentName: String
    let onDone: () -> Void
    /// Called once the delete has landed, before `onDone`, so a form that had this one
    /// chosen lets go of the id.
    var onDeleted: () -> Void = {}

    /// A sheet's subject — the smallest identifiable thing that can present one.
    struct CommitmentRef: Identifiable, Equatable {
        let id: String
    }

    /// Everything a Save could write, as one comparable value: the form as loaded is
    /// held as one of these, and "changed" is the form as typed not equalling it.
    private struct Fields: Equatable {
        var name = ""
        var tag: String?
        var balance: Double?
        var balanceDate: String?
        var ownerId: String?
        var linkedId: String?
        var notes: String?
        var email: String?
        var accounts: Set<String> = []
    }

    /// What the balance field holds: nothing, a number, or words that are not one.
    private enum BalanceEntry: Equatable {
        case empty
        case amount(Double)
        case unreadable
    }

    /// The rack's id for the chip that means nobody.
    private static let nobody = "no-one"

    @State private var typed = ""
    /// A person's picture: the bytes picked this time, or the wish to take the old one away.
    @State private var photoData: Data?
    @State private var removingPhoto = false
    #if os(iOS)
    @State private var photoItem: PhotosPickerItem?
    #endif
    @State private var tag: String?
    /// The tag set when the sheet opened leads its rack and stays put while choosing.
    @State private var openedWithTag: String?
    @State private var pickingTag = false
    /// Whether the account's details hold a card name: Save takes it out, the notes carrying it.
    @State private var holdsCardName = false
    /// Whether that card name has words: Save stands ready from the opening, so one Save moves
    /// it even when the notes already hold its line.
    @State private var movesCardName = false
    /// The notes as the form opened, a held card name folded in: what closing measures against.
    @State private var openedNotes: String?
    /// An account's balance as typed, and the day it was true.
    @State private var balanceText = ""
    @State private var balanceDay = Date()
    @State private var dayPicked = false
    @State private var pickingBalanceDay = false
    @State private var ownerId: String?
    @State private var linkedId: String?
    @State private var notes = ""
    @State private var email = ""
    /// A person's accounts as edited here; written to each account on Save.
    @State private var accounts: [String] = []
    /// The form as the file holds it — what Save measures "changed" against. nil until loaded.
    @State private var loaded: Fields?

    /// Read once on opening, and again after a sheet that could have changed them.
    @State private var linkChoices: [(id: String, name: String)] = []
    @State private var linkedHere: [(id: String, name: String)] = []
    /// The link as loaded when the rules no longer offer it: shown so it can be cleared.
    @State private var heldLink: (id: String, name: String)?
    @State private var heldLinkGone = false
    @State private var people: [DashboardModel.EntityChoice] = []
    @State private var allAccounts: [DashboardModel.EntityChoice] = []
    @State private var baseCard: DashboardModel.EntityCard?
    @State private var recent: [DashboardModel.EntityMoment] = []
    @State private var commitments: [Subscription] = []

    @State private var viewingCommitment: CommitmentRef?
    @State private var addingCommitment = false
    @State private var pickingAccount = false
    @State private var confirmingDelete = false
    /// The charges a save would turn into Transfers or back, held while Change or Cancel is awaited.
    @State private var flipping: TransferFlipWords.Flips?
    @State private var confirmingDiscard = false
    @State private var hoveringDelete = false
    /// The width the chip rails are read through, measured from the rail itself.
    @State private var railWidth: CGFloat?
    @State private var paneWidth: CGFloat = 0
    @Environment(\.dynamicTypeSize) private var typeSize

    private var isAccount: Bool { kind == .paymentMethod }
    private var word: String { EntityCopy.word(kind) }

    /// Two columns once there is room for the form and the preview side by side.
    private var isWide: Bool {
        #if os(macOS)
        paneWidth == 0 || paneWidth >= 780
        #else
        paneWidth >= 780
        #endif
    }

    var body: some View {
        #if os(iOS)
        // Save in the bar, where iPhone puts it; Delete is the form's last row.
        NavigationStack {
            page
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel", action: { Measure.used("cancel"); close() })
                            .measured("entity_edit_confirming_discard", .dialog, when: confirmingDiscard)
                            .confirmationDialog("Discard your changes?", isPresented: $confirmingDiscard, titleVisibility: .visible) {
                                Button("Discard", role: .destructive) { Measure.used("discard"); onDone() }
                                Button("Keep Editing", role: .cancel) { Measure.used("keep_editing") }
                            }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { Measure.used("save"); save() }
                            .disabled(!ready)
                    }
                }
        }
        #else
        page
        #endif
    }

    private var title: String { isAccount ? "Edit account" : "Edit person" }

    private var page: some View {
        // On the Mac the decisions keep the foot of the screen, under everything they act on.
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: LBSpacing.s4) {
                    #if os(macOS)
                    header
                    #else
                    saveErrorLine
                    #endif
                    if isWide {
                        HStack(alignment: .top, spacing: LBSpacing.s6) {
                            fields.frame(maxWidth: .infinity, alignment: .topLeading)
                            side.frame(width: 360)
                        }
                    } else {
                        fields
                        side
                    }
                    #if os(iOS)
                    deleteRow
                    #endif
                }
                .padding(LBSpacing.s4)
                .frame(maxWidth: isWide ? 1000 : 560)
                .frame(maxWidth: .infinity)
            }
            #if os(iOS)
            .scrollDismissesKeyboard(.interactively)
            #endif
            #if os(macOS)
            footer
            #endif
        }
        #if os(macOS)
        .frame(minWidth: 860, minHeight: 640)
        .lbKeyboardFocusEffects()
        #endif
        .background(
            GeometryReader { proxy in
                Color.clear
                    .onAppear { paneWidth = proxy.size.width }
                    .onChange(of: proxy.size.width) { _, width in paneWidth = width }
            }
        )
        .background(LBColor.canvas.color)
        // Every way out asks first when something typed would be lost: the X, Cancel, a
        // click on the window behind, and on a phone the swipe down.
        .lbClosesOnOutsideClick(close)
        #if os(iOS)
        .interactiveDismissDisabled(hasUnsavedChanges)
        #endif
        .onAppear { model.clearSaveError(); loadIfNeeded() }
        .measured("entity_edit_viewing_commitment", .sheet, when: viewingCommitment != nil)
        .sheet(item: $viewingCommitment, onDismiss: refreshFacts) { ref in
            CommitmentDetailView(model: model, id: ref.id) { viewingCommitment = nil }
        }
        .measured("entity_edit_adding_commitment", .sheet, when: addingCommitment)
        .sheet(isPresented: $addingCommitment, onDismiss: refreshFacts) {
            entityAddForm(model: model, kind: kind, id: id) { addingCommitment = false }
        }
        .measured("entity_edit_picking_balance_day", .sheet, when: pickingBalanceDay)
        .sheet(isPresented: $pickingBalanceDay) {
            DayPickerView(
                title: "Balance on",
                selected: balanceDayToStore ?? LB.todayMid(),
                onPick: { balanceDay = $0; dayPicked = true },
                onDone: { pickingBalanceDay = false }
            )
            .lbDaySheet()
        }
        .measured("entity_edit_picking_account", .sheet, when: pickingAccount)
        .sheet(isPresented: $pickingAccount) {
            ChoicePickerView(
                title: "Link an account", glyph: LBGlyph.account,
                choices: linkable.map { account in
                    ChoicePickerView.Choice(
                        id: account.id,
                        name: account.owner.map { "\(account.name) · belongs to \($0.name)" } ?? account.name,
                        symbol: model.tagIcon(kind: "account", name: account.tag) ?? LBGlyph.account
                    )
                },
                selected: nil,
                onPick: { if !accounts.contains($0) { accounts.append($0) } },
                onDone: { pickingAccount = false }
            )
            .lbThreeQuarterSheet()
        }
        .measured("entity_edit_confirming_delete", .dialog, when: confirmingDelete)
        .confirmationDialog(
            "Delete \(currentName)?", isPresented: $confirmingDelete, titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                Measure.used("delete")
                if model.deleteEntity(kind, id: id) {
                    onDeleted()
                    onDone()
                }
            }
            Button("Keep", role: .cancel) { Measure.used("keep") }
        } message: {
            Text(EntityCopy.removalNote(kind, use: model.entityUse(kind, id: id)))
        }
        .measured("entity_edit_confirming_flip", .alert, when: flipping != nil)
        .alert("Change charges?", isPresented: Binding(get: { flipping != nil }, set: { if !$0 { flipping = nil } }),
               presenting: flipping) { _ in
            Button("Change") {
                Measure.used("change")
                if saveNow() { onDone() }
            }
            Button("Cancel", role: .cancel) { Measure.used("cancel") }
        } message: { flips in
            Text(TransferFlipWords.message(flips))
        }
    }

    /// Save, after asking when it would turn charges into Transfers or back. Nothing to
    /// change means no question.
    private func save() {
        refreshFacts()
        let flips = flipsOnSave()
        if TransferFlipWords.isZero(flips) {
            if saveNow() { onDone() }
        } else {
            flipping = flips
        }
    }

    /// The rows the edit would move across: a person's relationship, an account's owner, or
    /// the accounts a person's editor linked or unlinked. Counted without writing.
    private func flipsOnSave() -> TransferFlipWords.Flips {
        guard ready, let loaded else { return (0, 0) }
        let now = current
        var total: TransferFlipWords.Flips = (0, 0)
        func add(_ flips: TransferFlipWords.Flips) {
            total.intoTransfers += flips.intoTransfers
            total.intoCharges += flips.intoCharges
        }
        if isAccount {
            if now.ownerId != loaded.ownerId { add(model.transferFlips(settingOwner: now.ownerId, onAccount: id)) }
        } else {
            if now.tag != loaded.tag { add(model.transferFlips(settingRelationship: now.tag, onPerson: id)) }
            for account in now.accounts.subtracting(loaded.accounts) {
                add(model.transferFlips(settingOwner: id, onAccount: account))
            }
            for account in loaded.accounts.subtracting(now.accounts) {
                add(model.transferFlips(settingOwner: nil, onAccount: account))
            }
        }
        return total
    }

    /// Half-typed work never dies to one tap: a changed form asks before it closes.
    private func close() {
        if hasUnsavedChanges { confirmingDiscard = true } else { onDone() }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .lbText(.screenTitle)
                    .foregroundStyle(LBColor.textPrimary.color)
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
            .accessibilityLabel("Close")
            // On the X, as the commitment form has it: the root already carries the delete
            // question, and one view presents one dialog reliably.
            .measured("entity_edit_confirming_discard", .dialog, when: confirmingDiscard)
            .confirmationDialog("Discard your changes?", isPresented: $confirmingDiscard, titleVisibility: .visible) {
                Button("Discard", role: .destructive) { Measure.used("discard"); onDone() }
                Button("Keep Editing", role: .cancel) { Measure.used("keep_editing") }
            }
        }
    }

    // MARK: the form

    private var fields: some View {
        VStack(alignment: .leading, spacing: LBSpacing.s4) {
            nameSection
            tagSection
            if isAccount {
                balanceSection
                ownerSection
                linkSection
                #if os(macOS)
                photoSection
                #endif
                notesSection
            } else {
                photoSection
                accountsSection
                emailSection
            }
        }
    }

    // MARK: the picture

    private var photoChanged: Bool { photoData != nil || removingPhoto }
    private var hasPhoto: Bool { photoData != nil || (baseCard?.photo != nil && !removingPhoto) }

    /// A picture of the account or the person, kept as a small file inside the longbook
    /// folder and nowhere else. Choose replaces, Remove takes it away; both land with Save.
    /// The phone picks a person's from Photos; the Mac picks any from a file.
    private var photoSection: some View {
        VStack(alignment: .leading, spacing: LBSpacing.s2) {
            question("Photo")
            #if os(iOS)
            HStack(spacing: LBSpacing.s3) {
                EntityAvatar(name: current.name.isEmpty ? currentName : current.name, ink: baseCard?.ink, size: 56,
                             photo: removingPhoto ? nil : baseCard?.photo, photoData: photoData)
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Text(hasPhoto ? "Change Photo" : "Choose Photo")
                        .lbText(.label)
                        .foregroundStyle(LBColor.brandText.color)
                        .frame(minHeight: 32)
                }
                .lbButtonStyle()
                .onChange(of: photoItem) { _, item in
                    guard let item else { return }
                    Task {
                        if let data = try? await item.loadTransferable(type: Data.self) { photoData = data; removingPhoto = false }
                    }
                }
                if hasPhoto {
                    Button("Remove") { Measure.used("remove"); photoData = nil; removingPhoto = true }
                        .lbButtonStyle()
                        .lbText(.label)
                        .foregroundStyle(LBColor.textSecondary.color)
                }
            }
            #else
            PhotoPickRow(current: baseCard?.photo, picked: $photoData, removing: $removingPhoto, shape: isAccount ? .rounded : .circle)
            #endif
            helper("Kept in your longbook folder, never anywhere else.")
        }
    }

    /// Writes or removes the file, and says what the row should name. Nil: nothing to change.
    private func settlePhoto() -> String?? {
        guard photoChanged, let folder = model.vaultFolderURL else { return nil }
        let kind = isAccount ? "account" : "person"
        if let photoData, let named = VaultImages.store(photoData, kind: kind, id: id, in: folder) { return .some(named) }
        if removingPhoto {
            VaultImages.remove(VaultImages.name(kind: kind, id: id), in: folder)
            if let old = baseCard?.photo { VaultImages.remove(file: old, in: folder) }
            return .some(nil)
        }
        return nil
    }

    private var nameSection: some View {
        VStack(alignment: .leading, spacing: LBSpacing.s2) {
            question("Name")
            field {
                TextField("", text: $typed, prompt: Text(currentName).foregroundStyle(LBColor.textTertiary.color))
                    .textFieldStyle(.plain)
                    .lbText(.body)
                    .foregroundStyle(LBColor.textPrimary.color)
                    .accessibilityLabel("Name")
            }
            helper("Every commitment using this \(word) takes the new name.")
        }
    }

    /// The library's tags for this kind and the book's own, the one set on opening first.
    private var tagChoices: [(name: String, icon: String?)] {
        var list = model.tagChoices(kind: isAccount ? "account" : "member")
        if let tag, !list.contains(where: { nameKey($0.name) == nameKey(tag) }) { list.insert((tag, nil), at: 0) }
        if let openedWithTag, let at = list.firstIndex(where: { nameKey($0.name) == nameKey(openedWithTag) }) {
            list.insert(list.remove(at: at), at: 0)
        }
        return list
    }

    /// An account's type, or a person's relationship, as one row that opens the same
    /// search-or-add list the category has: the library's and the book's own, and any typed.
    private var tagSection: some View {
        let choices = tagChoices
        let chosen = choices.first { nameKey($0.name) == nameKey(tag) }
        let label = isAccount ? "Type" : "Relationship"
        let glyph = isAccount ? LBGlyph.account : LBGlyph.member
        return VStack(alignment: .leading, spacing: LBSpacing.s2) {
            question(label)
            Button { Measure.used("none"); pickingTag = true } label: {
                field {
                    HStack(spacing: LBSpacing.s2) {
                        Image(systemName: chosen?.icon ?? glyph)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(LBColor.textTertiary.color)
                            .accessibilityHidden(true)
                        Text(tag.map(EntityCopy.tagWord) ?? "None")
                            .lbText(.body)
                            .foregroundStyle((tag == nil ? LBColor.textTertiary : LBColor.textPrimary).color)
                        Spacer(minLength: LBSpacing.s2)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(LBColor.textTertiary.color)
                            .accessibilityHidden(true)
                    }
                    .contentShape(Rectangle())
                }
            }
            .lbButtonStyle()
            .accessibilityLabel("\(label), \(tag.map(EntityCopy.tagWord) ?? "none")")
        }
        .measured("entity_edit_picking_tag", .sheet, when: pickingTag)
        .sheet(isPresented: $pickingTag) {
            let picker = ChoicePickerView(
                title: label, glyph: glyph,
                choices: [ChoicePickerView.Choice(id: Self.noTag, name: "None", symbol: nil)]
                    + choices.map { ChoicePickerView.Choice(id: $0.name, name: EntityCopy.tagWord($0.name), symbol: $0.icon ?? glyph) },
                selected: chosen?.name ?? (tag == nil ? Self.noTag : nil),
                onPick: { tag = $0 == Self.noTag ? nil : $0 },
                onCreate: { name in
                    tag = name
                    pickingTag = false
                    return nil
                },
                createPrompt: isAccount ? "Name the type" : "Name the relationship",
                onDone: { pickingTag = false }
            )
            #if os(iOS)
            picker.presentationDetents([.medium, .large])
            #else
            picker
            #endif
        }
    }

    /// The list's "None": no library tag is called this, so picking it clears the field.
    private static let noTag = "\u{0}none"

    /// What the account holds, and the day that was true: typed here, or set by a
    /// statement's closing line. Nothing is computed from it.
    private var balanceSection: some View {
        VStack(alignment: .leading, spacing: LBSpacing.s2) {
            question("Balance")
            // The amount and its day share a line until an accessibility text size parts
            // them. Decided by the size, never by the words, so typing cannot move the field.
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: LBSpacing.s2) {
                    balanceField
                    balanceDayButton
                }
            } else {
                HStack(spacing: LBSpacing.s2) {
                    balanceField.frame(minWidth: 120, maxWidth: .infinity)
                    balanceDayButton
                }
            }
            if balanceEntry == .unreadable {
                // Words that are not a number are never read as "clear the balance".
                Text("Type the amount as a number, like 5200 or -12450.")
                    .lbText(.footnote)
                    .foregroundStyle(LBColor.urgent.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
            helper("For a card, the amount you owe.")
        }
    }

    private var balanceField: some View {
        field {
            TextField("", text: $balanceText, prompt: Text("0").foregroundStyle(LBColor.textTertiary.color))
                .textFieldStyle(.plain)
                .lbText(.body)
                .foregroundStyle(LBColor.textPrimary.color)
                #if os(iOS)
                // Not the decimal pad: an overdrawn balance needs its minus sign.
                .keyboardType(.numbersAndPunctuation)
                .autocorrectionDisabled()
                #endif
                .accessibilityLabel("Current balance")
        }
    }

    /// The button says the day Save will leave beside the balance, or that there is none.
    private var balanceDayButton: some View {
        let day = balanceDayToStore.map { LB.longDate($0) }
        return dateButton(day.map { "as on \($0)" } ?? "Add the day") { pickingBalanceDay = true }
            .disabled(typedBalance == nil)
            .lbPhoneDimmed(typedBalance == nil)
            .accessibilityLabel(day.map { "The day the balance was true, \($0)" } ?? "Add the day the balance was true")
    }

    /// Whose account it is: one person, or nobody.
    private var ownerSection: some View {
        VStack(alignment: .leading, spacing: LBSpacing.s2) {
            question("Owner")
            chipRack(chosen: ownerId ?? Self.nobody) {
                LBChip("Shared", symbol: "person.2", style: .choice(selected: ownerId == nil)) {
                    ownerId = nil
                }
                .id(Self.nobody)
                ForEach(people) { person in
                    LBChip(person.name, symbol: LBGlyph.member, style: .choice(selected: ownerId == person.id)) {
                        ownerId = ownerId == person.id ? nil : person.id
                    }
                    .rackChipWidth()
                    .id(person.id)
                }
            }
            if people.isEmpty {
                helper("No person is written yet. Once one is, this account can belong to them.")
            }
        }
    }

    /// A rack of chips. On the Mac they wrap, as the Accounts card's do: the sheet is wide
    /// enough, and a long row ran off its edge. The phone keeps its sideways strip.
    @ViewBuilder
    private func chipRack<Content: View>(chosen: String?, @ViewBuilder content: @escaping () -> Content) -> some View {
        #if os(macOS)
        LBFlow(spacing: LBSpacing.s2, lineSpacing: LBSpacing.s2) { content() }
        #else
        RackStrip(chosen: chosen, railWidth: $railWidth, content: content)
        #endif
    }

    /// A card to the bank account that pays it. One level: an account others are linked
    /// to cannot itself be linked, and the writer refuses it if tried.
    private var linkSection: some View {
        VStack(alignment: .leading, spacing: LBSpacing.s2) {
            question("Linked to")
            // A link the rules no longer offer still leads the rack, so it can be cleared.
            let offered = (heldLink.map { [$0] } ?? []) + (linkedHere.isEmpty ? linkChoices : [])
            if !offered.isEmpty {
                chipRack(chosen: linkedId) {
                    ForEach(offered, id: \.id) { choice in
                        LBChip(choice.name, symbol: "link", style: .choice(selected: linkedId == choice.id)) {
                            linkedId = linkedId == choice.id ? nil : choice.id
                        }
                        .rackChipWidth()
                        .id(choice.id)
                    }
                }
            }
            helper("Link a card to the bank account that pays it.")
            if let heldLink, linkedId == heldLink.id {
                helper(heldLinkGone
                       ? "This link names an account that is no longer here. Tap it to clear the link."
                       : "\(heldLink.name) is linked to another account itself, and links go one level. Tap it to clear the link.")
            }
            if !linkedHere.isEmpty {
                let names = linkedHere.map(\.name).joined(separator: ", ")
                helper("\(names) \(linkedHere.count == 1 ? "is" : "are") paid from this account.")
            } else if linkChoices.isEmpty {
                helper("No other account can be linked to yet.")
            }
        }
    }

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: LBSpacing.s2) {
            question("Notes")
            field {
                VStack(alignment: .trailing, spacing: LBSpacing.s1) {
                    TextField(
                        "", text: $notes,
                        prompt: Text("Anything worth remembering about this account").foregroundStyle(LBColor.textTertiary.color),
                        axis: .vertical
                    )
                    .textFieldStyle(.plain)
                    .lbText(.body)
                    .foregroundStyle(LBColor.textPrimary.color)
                    .lineLimit(3...8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel("Notes")
                    Text("\(notes.count)/\(notesLimit)")
                        .lbText(.footnote)
                        .foregroundStyle((notesOver ? LBColor.urgent : LBColor.textTertiary).color)
                        .accessibilityLabel("\(notes.count) of \(notesLimit) characters")
                }
            }
            if notesOver {
                Text("Shorten the notes to \(notesLimit) characters to save.")
                    .lbText(.footnote)
                    .foregroundStyle(LBColor.urgent.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
            helper("Don’t store card numbers, PINs or passwords here.")
        }
    }

    /// 200 characters, or as many as the notes opened with, a held card name folded in: what
    /// an AI wrote longer is never cut. Nothing typed is cut either; past the limit the counter
    /// warns and Save waits.
    private var notesLimit: Int {
        max(200, loaded?.notes?.count ?? 0, openedNotes?.count ?? 0)
    }

    private var notesOver: Bool { notes.count > notesLimit }

    // MARK: a person's accounts

    /// The accounts not already theirs. One that belongs to someone else can be moved.
    private var linkable: [DashboardModel.EntityChoice] {
        allAccounts.filter { !accounts.contains($0.id) }
    }

    /// One source of truth: the account's own member. Linking or unlinking here is
    /// staged, then written to each account in the same Save as everything else.
    private var accountsSection: some View {
        VStack(alignment: .leading, spacing: LBSpacing.s2) {
            question("Accounts")
            ForEach(accounts, id: \.self) { accountId in
                if let account = allAccounts.first(where: { $0.id == accountId }) { accountRow(account) }
            }
            Button { Measure.used("link_an_account"); pickingAccount = true } label: {
                EntityActionLabel(title: "Link an Account", symbol: "plus", prominent: true, fills: true)
            }
            .lbButtonStyle()
            .disabled(linkable.isEmpty)
            .lbPhoneDimmed(linkable.isEmpty)
            if allAccounts.isEmpty {
                helper("No account is written yet. Add one from Accounts, then link it here.")
            } else if linkable.isEmpty {
                helper("Every account already belongs to them.")
            }
        }
    }

    private func accountRow(_ account: DashboardModel.EntityChoice) -> some View {
        HStack(spacing: LBSpacing.s3) {
            EntityGlyphTile(symbol: model.tagIcon(kind: "account", name: account.tag) ?? LBGlyph.account, ink: account.ink)
            VStack(alignment: .leading, spacing: 2) {
                Text(account.name)
                    .lbText(.bodySM)
                    .foregroundStyle(LBColor.textPrimary.color)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if let tag = account.tag, !tag.isEmpty {
                    Text(EntityCopy.tagWord(tag))
                        .lbText(.footnote)
                        .foregroundStyle(LBColor.textSecondary.color)
                }
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: LBSpacing.s2)
            Button { Measure.used("remove_account_chip"); accounts.removeAll { $0 == account.id } } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(LBColor.textSecondary.color)
                    .frame(width: 26, height: 26)
                    .background(LBColor.chrome.color, in: Circle())
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .lbButtonStyle()
            .padding(.trailing, -LBSpacing.s2)
            .accessibilityLabel("Unlink \(account.name)")
        }
        .padding(.horizontal, LBSpacing.s3)
        .padding(.vertical, LBSpacing.s1)
        .background(LBColor.card.color, in: RoundedRectangle(cornerRadius: LBRadius.xs, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: LBRadius.xs, style: .continuous)
                .strokeBorder(LBColor.hairline.color, lineWidth: 1)
        )
    }

    private var emailSection: some View {
        VStack(alignment: .leading, spacing: LBSpacing.s2) {
            question("Email")
            field {
                TextField("", text: $email, prompt: Text("Email address").foregroundStyle(LBColor.textTertiary.color))
                    .textFieldStyle(.plain)
                    .lbText(.body)
                    .foregroundStyle(LBColor.textPrimary.color)
                    #if os(iOS)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    #endif
                    .accessibilityLabel("Email")
            }
            helper("Used when you share a report.")
        }
    }

    // MARK: beside the form

    /// The list card, drawn from the fields as they stand rather than from the vault.
    private var liveCard: DashboardModel.EntityCard? {
        guard var card = baseCard else { return nil }
        let now = current
        card.name = now.name.isEmpty ? currentName : now.name
        card.tag = now.tag
        guard isAccount else {
            card.accountCount = now.accounts.count
            return card
        }
        card.balance = now.balance
        card.balanceDate = now.balanceDate.flatMap(LB.parseDate)
        card.owner = people.first { $0.id == now.ownerId }.map { ($0.id, $0.name, $0.ink) }
        let offered = linkChoices + (heldLink.map { [$0] } ?? [])
        card.linked = offered.first { $0.id == now.linkedId }.map { ($0.id, $0.name) }
        return card
    }

    @ViewBuilder
    private var preview: some View {
        if let card = liveCard { EntityPreviewPanel(card: card) }
    }

    /// Wide, the preview leads this column; a phone has no preview, the form is the preview.
    private var side: some View {
        VStack(alignment: .leading, spacing: LBSpacing.s4) {
            if isWide { preview }
            if isAccount {
                EntityRecentPanel(moments: recent, total: baseCard?.charges ?? recent.count) {
                    viewingCommitment = CommitmentRef(id: $0)
                }
            }
            EntityQuickActions(
                kind: kind, commitments: commitments,
                add: { addingCommitment = true },
                open: { viewingCommitment = CommitmentRef(id: $0) }
            )
        }
    }

    // MARK: the decisions

    @ViewBuilder
    private var saveErrorLine: some View {
        if let saveError = model.saveError {
            Text(saveError)
                .lbText(.footnote)
                .foregroundStyle(LBColor.urgent.color)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The phone's Delete: a red row at the very end of the form, away from Save.
    private var deleteRow: some View {
        Button { Measure.used("delete"); confirmingDelete = true } label: {
            Text("Delete \(word.capitalized)")
                .lbText(.body)
                .foregroundStyle(LBColor.danger.color)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(LBColor.card.color, in: RoundedRectangle(cornerRadius: LBRadius.sm, style: .continuous))
                .contentShape(Rectangle())
        }
        .lbButtonStyle()
        .padding(.top, LBSpacing.s4)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: LBSpacing.s2) {
            if let saveError = model.saveError {
                Text(saveError)
                    .lbText(.footnote)
                    .foregroundStyle(LBColor.urgent.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if isWide {
                HStack(spacing: LBSpacing.s3) {
                    deleteButton(fills: false)
                    Spacer(minLength: LBSpacing.s3)
                    Button(action: { Measure.used("cancel"); close() }) { decision("Cancel", ink: LBColor.textPrimary, fill: LBColor.chrome.color, fills: false) }
                        .lbButtonStyle()
                    saveButton(fills: false)
                }
            } else {
                // Side by side while both labels fit; Save above Delete once they do not.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: LBSpacing.s3) {
                        deleteButton(fills: true)
                        saveButton(fills: true)
                    }
                    VStack(spacing: LBSpacing.s2) {
                        saveButton(fills: true)
                        deleteButton(fills: true)
                    }
                }
            }
        }
        .padding(LBSpacing.s4)
        .frame(maxWidth: isWide ? 1000 : 560)
        .frame(maxWidth: .infinity)
        .background(LBColor.canvas.color)
        .overlay(alignment: .top) {
            Rectangle().fill(LBColor.hairline.color).frame(height: 1)
        }
    }

    private func decision(_ title: String, symbol: String? = nil, ink: LBColorValue, fill: Color,
                          border: Color = .clear, fills: Bool) -> some View {
        HStack(spacing: 6) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .accessibilityHidden(true)
            }
            Text(title)
                .lbText(.body)
                .lineLimit(1)
        }
        .foregroundStyle(ink.color)
        .padding(.horizontal, LBSpacing.s4)
        .frame(maxWidth: fills ? .infinity : nil, minHeight: 44)
        .background(fill, in: RoundedRectangle(cornerRadius: LBRadius.sm, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: LBRadius.sm, style: .continuous).strokeBorder(border, lineWidth: 1))
        .contentShape(Rectangle())
    }

    private func saveButton(fills: Bool) -> some View {
        Button {
            Measure.used("save")
            save()
        } label: {
            decision("Save", ink: ready ? LBColor.onBrand : LBColor.textTertiary,
                     fill: ready ? LBColor.brand.color : LBColor.chrome.color, fills: fills)
        }
        .lbButtonStyle()
        .disabled(!ready)
    }

    /// Quiet red at rest, filled under the pointer, and a question before it acts — the
    /// manner every destructive control here keeps.
    private func deleteButton(fills: Bool) -> some View {
        Button { Measure.used("delete"); confirmingDelete = true } label: {
            decision("Delete \(word.capitalized)", symbol: "trash",
                     ink: hoveringDelete ? LBColor.onBrand : LBColor.danger,
                     fill: hoveringDelete ? LBColor.dangerFill.color : LBColor.danger.color.opacity(0.10),
                     border: LBColor.danger.color.opacity(0.45), fills: fills)
        }
        .lbButtonStyle(hovers: false)
        .onHover { hoveringDelete = $0 }
    }

    // MARK: loading and saving

    private func loadIfNeeded() {
        guard loaded == nil else { return }
        let details = model.entityDetails(kind, id: id)
        let heldNotes = clean(details.notes) == nil ? nil : details.notes
        typed = currentName
        tag = isAccount ? details.accountTag : details.memberTag
        openedWithTag = tag
        ownerId = details.ownerMemberId
        linkedId = details.parentAccountId
        // A card name the details hold opens as a line of the notes, seen before Save writes it there.
        notes = notesFoldingCardName(details.notes, details: details.accountDetails) ?? ""
        openedNotes = clean(notes) == nil ? nil : notes
        holdsCardName = details.accountDetails?[PaymentMethod.cardNameKey] != nil
        movesCardName = cardNameLine(details.accountDetails) != nil
        email = details.email ?? ""
        balanceText = details.balance.map(plainAmount) ?? ""
        balanceDay = details.balanceDate.flatMap(LB.parseDate) ?? LB.todayMid()
        // A link whose account is not on offer (it is linked itself, or gone) is still
        // named, so it can be seen and cleared.
        if let held = details.parentAccountId, !details.parentChoices.contains(where: { $0.id == held }) {
            let name = model.entityNames(memberId: nil, methodId: held).method
            heldLink = (held, name ?? "Missing account")
            heldLinkGone = name == nil
        }
        refreshFacts()
        accounts = isAccount ? [] : allAccounts.filter { $0.owner?.id == id }.map(\.id)
        loaded = Fields(
            name: currentName.trimmingCharacters(in: .whitespaces), tag: tag,
            balance: details.balance, balanceDate: details.balanceDate,
            ownerId: details.ownerMemberId, linkedId: details.parentAccountId,
            notes: heldNotes, email: details.email, accounts: Set(accounts)
        )
    }

    /// What the vault says about this one account or person, apart from what is typed.
    /// Only the other kind's names are read for the pickers, never its cards.
    private func refreshFacts() {
        if isAccount {
            people = model.entityChoices(.familyMember)
            let details = model.entityDetails(kind, id: id)
            linkChoices = details.parentChoices
            linkedHere = details.linkedHere
        } else {
            allAccounts = model.entityChoices(.paymentMethod)
        }
        baseCard = model.entityCard(kind, id: id)
        recent = isAccount ? model.entitySummary(kind, id: id).recent : []
        commitments = model.entityCommitments(kind, id: id)
        dropWhatIsGone()
    }

    /// An account or person deleted elsewhere while this sheet was open leaves the staged
    /// choices, so one stale id cannot make every Save throw.
    private func dropWhatIsGone() {
        guard var held = loaded else { return }
        if isAccount {
            if let ownerId, ownerId != held.ownerId, !people.contains(where: { $0.id == ownerId }) {
                self.ownerId = held.ownerId
            }
            if let linkedId, linkedId != held.linkedId, !linkChoices.contains(where: { $0.id == linkedId }) {
                self.linkedId = held.linkedId
            }
        } else {
            let here = Set(allAccounts.map(\.id))
            accounts.removeAll { !here.contains($0) }
            held.accounts.formIntersection(here)
            loaded = held
        }
    }

    private func clean(_ text: String?) -> String? {
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Empty clears the balance; a number is kept; anything else is neither, and Save
    /// waits. A leading currency symbol, spaces and grouping commas are read past.
    private var balanceEntry: BalanceEntry {
        var text = Substring(balanceText.trimmingCharacters(in: .whitespaces))
        guard !text.isEmpty else { return .empty }
        var sign = 1.0
        var sawSign = false
        while let first = text.first {
            let isSymbol = first.unicodeScalars.allSatisfy { $0.properties.generalCategory == .currencySymbol }
            if first.isWhitespace || isSymbol {
                text = text.dropFirst()
            } else if !sawSign, "-−+".contains(first) {
                sawSign = true
                if first != "+" { sign = -1 }
                text = text.dropFirst()
            } else {
                break
            }
        }
        let digits = text.replacingOccurrences(of: ",", with: "")
        let isNumber = digits.contains(where: \.isNumber)
            && digits.allSatisfy { $0.isASCII && ($0.isNumber || $0 == ".") }
            && digits.filter { $0 == "." }.count <= 1
        guard isNumber, let value = Double(digits), value.isFinite else { return .unreadable }
        return .amount(sign * value)
    }

    private var typedBalance: Double? {
        if case .amount(let value) = balanceEntry { return value }
        return nil
    }

    /// The day Save will leave beside the balance, which is the day the button shows: the
    /// one picked; else the stored one while the amount is untouched, which may be none;
    /// else today, since a newly typed balance is most likely today's.
    private var balanceDayToStore: Date? {
        guard let amount = typedBalance else { return nil }
        if dayPicked { return balanceDay }
        if amount == loaded?.balance { return loaded?.balanceDate.flatMap(LB.parseDate) }
        return LB.todayMid()
    }

    /// The form as it stands, in the shape it was loaded in.
    private var current: Fields {
        let balance = typedBalance
        let untouched = !dayPicked && balance == loaded?.balance
        return Fields(
            name: typed.trimmingCharacters(in: .whitespaces),
            tag: tag,
            balance: balance,
            // The day only matters alongside a balance, and is left alone with it.
            balanceDate: balance == nil ? nil : untouched ? loaded?.balanceDate : balanceDayToStore.map(LB.toISO),
            ownerId: ownerId,
            linkedId: linkedId,
            notes: clean(notes) == nil ? nil : notes,
            // Empty means cleared; anything else is kept exactly as typed — never trimmed.
            email: email.isEmpty ? nil : email,
            accounts: Set(accounts)
        )
    }

    /// The form as it opened: the file's fields, the notes as shown with a held card name
    /// folded in. Closing measures against it; Save measures against the file.
    private var opened: Fields? {
        guard var fields = loaded else { return nil }
        fields.notes = openedNotes
        return fields
    }

    /// Anything typed that closing would lose, saveable or not: a balance that does not
    /// read as a number is still typing. The fold is not typing.
    private var hasUnsavedChanges: Bool {
        guard let opened else { return false }
        return current != opened || balanceEntry == .unreadable
    }

    /// Save writes what differs from the file, and moves a held card name into the notes.
    private var ready: Bool {
        guard let loaded else { return false }
        let now = current
        return !now.name.isEmpty && balanceEntry != .unreadable && !notesOver && (now != loaded || movesCardName || photoChanged)
    }

    /// One Save, one write: the name, the details and a person's accounts go together,
    /// each passed only when it changed, so a refusal leaves the vault as it was.
    private func saveNow() -> Bool {
        // Read again first: what was deleted elsewhere leaves the staged choices here.
        refreshFacts()
        guard ready, let loaded else { return false }
        let now = current
        func changed<T: Equatable>(_ path: KeyPath<Fields, T?>) -> T?? {
            now[keyPath: path] == loaded[keyPath: path] ? nil : .some(now[keyPath: path])
        }
        let owners: [(accountId: String, memberId: String?)] = isAccount ? [] :
            now.accounts.subtracting(loaded.accounts).sorted().map { (accountId: $0, memberId: id) }
            + loaded.accounts.subtracting(now.accounts).sorted().map { (accountId: $0, memberId: nil) }
        return model.setEntityDetails(
            kind, id: id,
            accountTag: isAccount ? changed(\.tag) : nil,
            parentAccountId: changed(\.linkedId),
            email: changed(\.email),
            balance: changed(\.balance),
            balanceDate: changed(\.balanceDate),
            memberTag: isAccount ? nil : changed(\.tag),
            ownerMemberId: changed(\.ownerId),
            accountNotes: changed(\.notes),
            // The notes carry the card name, so Save takes it out of details.
            removingCardName: isAccount && holdsCardName,
            name: now.name == loaded.name ? nil : now.name,
            accountOwners: owners, photo: settlePhoto()
        )
    }

    // MARK: furniture

    /// A section's name on a row of one height, with or without its plus, so the form's
    /// rhythm holds from section to section.
    private func question(_ text: String, note: String? = nil,
                          adding noun: String? = nil, add: (() -> Void)? = nil) -> some View {
        HStack(spacing: LBSpacing.s2) {
            HStack(alignment: .firstTextBaseline, spacing: LBSpacing.s1) {
                // A quiet 13 pt heading over its field, so the answers are louder.
                Text(text)
                    .lbText(FormQuestion<EmptyView>.groupedRole)
                    .foregroundStyle(LBColor.textSecondary.color)
                if let note {
                    Text("(\(note))")
                        .lbText(.footnote)
                        .foregroundStyle(LBColor.textTertiary.color)
                }
            }
            if let noun, let add {
                Button(action: { Measure.used("add_new"); add() }) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(LBColor.brandText.color)
                        .frame(width: 26, height: 26)
                        .background(LBColor.brand.color.opacity(0.16), in: Circle())
                        .padding(9)
                        .contentShape(Rectangle())
                        .padding(-9)
                }
                .lbButtonStyle()
                .accessibilityLabel("Add a \(noun)")
            }
        }
        .frame(minHeight: 26, alignment: .leading)
    }

    private func helper(_ text: String) -> some View {
        Text(text)
            .lbText(.footnote)
            .foregroundStyle(LBColor.textTertiary.color)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func field<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(.horizontal, LBSpacing.s3)
            .padding(.vertical, LBSpacing.s3)
            .background(LBColor.card.color, in: RoundedRectangle(cornerRadius: LBRadius.xs, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: LBRadius.xs, style: .continuous)
                    .strokeBorder(LBColor.hairline.color, lineWidth: 1)
            )
    }

    private func dateButton(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: { Measure.used("pick_date"); action() }) {
            HStack(spacing: LBSpacing.s2) {
                Image(systemName: LBGlyph.date)
                    .font(.system(size: 11, weight: .medium))
                Text(label).lbText(.footnote)
            }
            .foregroundStyle(LBColor.textPrimary.color)
            .padding(.horizontal, LBSpacing.s3)
            .frame(minHeight: 34)
            .background(LBColor.chrome.color, in: Capsule())
            .contentShape(Capsule())
        }
        .lbButtonStyle()
    }
}

private extension View {
    /// A long name stops a strip chip at 230 points. In the Mac's wrapping rack the frame
    /// would take the whole 230 and spread the chips apart, so there the chip keeps its size.
    @ViewBuilder
    func rackChipWidth() -> some View {
        #if os(macOS)
        self
        #else
        frame(maxWidth: 230, alignment: .leading)
        #endif
    }
}
