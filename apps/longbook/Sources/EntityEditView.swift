import DesignSystem
import LongbookCore
import SwiftUI

/// Edit what describes an account or a person, in the order its Preview reads. A card's name
/// lives in an account's notes; a person's accounts come last. One Save is one write, of only
/// the fields that changed.
struct EntityEditView: View {
    let model: DashboardModel
    let kind: VaultPatch.EntityKind
    let id: String
    let currentName: String
    let onDone: () -> Void
    /// Called once the delete has landed, before `onDone`, so a form that had this one
    /// chosen lets go of the id.
    var onDeleted: () -> Void = {}
    /// The form stands in a side panel, in its Preview's place, rather than in a sheet.
    var inPanel = false
    /// Raised by the panel's list when a card chosen under the form would replace it.
    var closeAsked = 0
    /// The field a Preview's row opened the form on: its list opens, or its text takes the cursor.
    var focus: EditFocus?

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

    @State private var typed = ""
    /// A person's picture: the bytes picked this time, or the wish to take the old one away.
    @State private var photoData: Data?
    @State private var removingPhoto = false
    /// Keyboard focus is in this form, for Return to save it.
    @State private var focusInForm = false
    @State private var tag: String?
    /// The tag set when the sheet opened leads its rack and stays put while choosing.
    @State private var openedWithTag: String?
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

    @State private var pickingAccount = false
    /// The typed field holding the cursor, and whether the asked field has been shown once.
    @FocusState private var typingIn: EditFocus?
    @State private var revealed = false
    @State private var confirmingDelete = false
    /// The charges a save would turn into Transfers or back, held while Change or Cancel is awaited.
    @State private var flipping: TransferFlipWords.Flips?
    @State private var confirmingDiscard = false

    private var isAccount: Bool { kind == .paymentMethod }
    private var word: String { EntityCopy.word(kind) }

    private var title: String { "Edit " + word.capitalized }

    var body: some View {
        // The name and the decisions keep their place while the fields scroll between them.
        VStack(spacing: 0) {
            top
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: Self.rowGap) {
                        fields
                        saveErrorLine
                        #if os(iOS)
                        deleteButton.frame(maxWidth: .infinity).padding(.top, LBSpacing.s2)
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
            #if os(iOS)
            .scrollDismissesKeyboard(.interactively)
            #endif
            EditFormFooter(word: word.capitalized, canSave: savable, saveOnReturn: !inPanel || focusInForm, cancel: close, save: save) { deleteButton }
        }
        .environment(\.lbFormGrouped, true)
        #if os(macOS)
        // Shorter than the window minimum, so the sheet never runs past its bottom. A panel
        // gives the form its own width.
        .frame(minWidth: inPanel ? nil : 460, idealWidth: inPanel ? nil : 460, minHeight: inPanel ? nil : 520, idealHeight: inPanel ? nil : 640)
        .environment(\.lbFormDense, true)
        .lbKeyboardFocusEffects()
        #endif
        .lbPanelForm(active: inPanel, dirty: hasUnsavedChanges, close: onDone)
        .lbFocusWithin($focusInForm)
        .onChange(of: closeAsked) { _, _ in close() }
        .background(LBColor.canvas.color)
        // Every way out asks first when something typed would be lost: the X, Cancel, a
        // click on the window behind, and on a phone the swipe down.
        .lbClosesOnOutsideClick(close)
        #if os(iOS)
        .interactiveDismissDisabled(hasUnsavedChanges)
        #endif
        .onAppear { model.clearSaveError(); loadIfNeeded() }
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
            .lbKeyboardFocusEffects()
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
        .lbFormStack(title)
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

    private static var rowGap: CGFloat {
        #if os(macOS)
        LBSpacing.s2
        #else
        LBSpacing.s3
        #endif
    }

    /// Save, after asking when it would turn charges into Transfers or back. Nothing to
    /// change means no question.
    private func save() {
        refreshFacts()
        // A form nothing changed in has nothing to write.
        guard ready else { return onDone() }
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

    /// Close leads on the Mac, as every panel has it; a phone's sheet keeps its X at the end.
    private var top: some View {
        VStack(alignment: .leading, spacing: LBSpacing.s2) {
            #if os(macOS)
            PanelCloseButton(help: "Close without saving (Esc)", measure: "close") { close() }
                .measured("entity_edit_confirming_discard", .dialog, when: confirmingDiscard)
                .confirmationDialog("Discard your changes?", isPresented: $confirmingDiscard, titleVisibility: .visible) {
                    Button("Discard", role: .destructive) { Measure.used("discard"); onDone() }
                    Button("Keep Editing", role: .cancel) { Measure.used("keep_editing") }
                }
            naming
            #else
            HStack(alignment: .top) {
                naming
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
                .measured("entity_edit_confirming_discard", .dialog, when: confirmingDiscard)
                .confirmationDialog("Discard your changes?", isPresented: $confirmingDiscard, titleVisibility: .visible) {
                    Button("Discard", role: .destructive) { Measure.used("discard"); onDone() }
                    Button("Keep Editing", role: .cancel) { Measure.used("keep_editing") }
                }
            }
            #endif
        }
        .padding(.horizontal, LBSpacing.s4)
        .padding(.top, Self.topInset)
        .padding(.bottom, LBSpacing.s2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private static var topInset: CGFloat {
        #if os(macOS)
        LBSpacing.s3
        #else
        LBSpacing.s4
        #endif
    }

    /// The title names what is edited, the line under it which one.
    private var naming: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .lbText(.screenTitle)
                .foregroundStyle(LBColor.textPrimary.color)
                .accessibilityAddTraits(.isHeader)
            Text(currentName)
                .lbText(Self.namingRole)
                .foregroundStyle(LBColor.textTertiary.color)
                .lineLimit(2)
        }
    }

    private static var namingRole: LBTextStyle {
        #if os(macOS)
        .body
        #else
        .footnote
        #endif
    }

    // MARK: the form

    @ViewBuilder
    private var fields: some View {
        nameSection
        tagSection.id(EditFocus.tag)
        if isAccount {
            ownerSection.id(EditFocus.owner)
            balanceSection.id(EditFocus.balance)
            balanceDaySection.id(EditFocus.asOn)
            linkSection.id(EditFocus.linkedAccount)
            #if os(macOS)
            photoSection
            #endif
            notesSection.id(EditFocus.notes)
        } else {
            photoSection
            emailSection.id(EditFocus.email)
            notesSection.id(EditFocus.notes)
            accountsSection
        }
    }

    // MARK: the picture

    private var photoChanged: Bool { photoData != nil || removingPhoto }
    private var hasPhoto: Bool { photoData != nil || (baseCard?.photo != nil && !removingPhoto) }

    /// A picture of the account or the person, kept as a small file inside the longbook
    /// folder and nowhere else. Every verb lands with Save. The phone chooses a person's from
    /// Photos; the Mac chooses any from a file. Both paste one too.
    private var photoSection: some View {
        FormRow {
            FormQuestion("Photo")
        } content: {
            #if os(iOS)
            HStack(spacing: LBSpacing.s3) {
                PhotoMenu(has: hasPhoto, shape: .circle, picked: $photoData, removing: $removingPhoto) {
                    FormChoiceFace(value: hasPhoto ? "Change" : "Add", empty: !hasPhoto)
                }
                if hasPhoto {
                    EntityAvatar(name: current.name.isEmpty ? currentName : current.name, ink: baseCard?.ink, size: 36,
                                 photo: removingPhoto ? nil : baseCard?.photo, photoData: photoData)
                }
            }
            #else
            PhotoMenuField(current: baseCard?.photo, picked: $photoData, removing: $removingPhoto, shape: .circle)
            #endif
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
        FormRow {
            FormQuestion("Name")
        } content: {
            FormField {
                TextField("", text: $typed, prompt: Text(currentName).foregroundStyle(LBColor.textTertiary.color))
                    .textFieldStyle(.plain)
                    .lbText(.body)
                    .foregroundStyle(LBColor.textPrimary.color)
                    .accessibilityLabel("Name")
            }
            if current.name != loaded?.name { helper("Every commitment using this \(word) takes the new name.") }
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

    /// An account's type, or a person's relationship, as one field that opens the same
    /// search-or-add list the category has: the library's and the book's own, and any typed.
    private var tagSection: some View {
        let choices = tagChoices
        let chosen = choices.first { nameKey($0.name) == nameKey(tag) }
        let label = isAccount ? "Type" : "Relationship"
        let glyph = isAccount ? LBGlyph.account : LBGlyph.member
        return FormRow {
            FormQuestion(label)
        } content: {
            ChoiceField(label, value: tag.map(EntityCopy.tagWord) ?? "None", empty: tag == nil,
                        choices: choices.map { ChoicePickerView.Choice(id: $0.name, name: EntityCopy.tagWord($0.name), symbol: $0.icon ?? glyph) },
                        selected: chosen?.name ?? tag,
                        adding: ChoiceAdding { name in
                            tag = name
                            return nil
                        },
                        opensOnAppear: opens(.tag)) { tag = $0 }
        }
    }

    /// What the account holds, typed here or set by a statement's closing line. Nothing is
    /// computed from it.
    private var balanceSection: some View {
        FormRow {
            FormQuestion("Balance")
        } content: {
            FormField {
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
                    .focused($typingIn, equals: .balance)
            }
            if balanceEntry == .unreadable {
                // Words that are not a number are never read as "clear the balance".
                Text("Type the amount as a number, like 5200 or -12450.")
                    .lbText(.footnote)
                    .foregroundStyle(LBColor.urgent.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// The day Save will leave beside the balance, or that there is none. No balance, no day.
    private var balanceDaySection: some View {
        let day = balanceDayToStore
        return FormRow {
            FormQuestion("As on")
        } content: {
            FormDayButton(title: "Balance on",
                          date: Binding(get: { day ?? LB.todayMid() }, set: { balanceDay = $0; dayPicked = true }),
                          unset: day == nil ? "None" : nil)
                .disabled(typedBalance == nil)
                .lbPhoneDimmed(typedBalance == nil)
        }
    }

    /// Whose account it is: one person, or nobody. A name typed that nobody carries is written
    /// to People at once, as the racks write theirs, and chosen.
    private var ownerSection: some View {
        let owner = people.first { $0.id == ownerId }
        return FormRow {
            FormQuestion("Owner")
        } content: {
            ChoiceField("Owner", value: owner?.name ?? "None", empty: owner == nil,
                        choices: people.map {
                            ChoicePickerView.Choice(id: $0.id, name: $0.name, symbol: LBGlyph.member,
                                                    detail: $0.tag.flatMap { $0.isEmpty ? nil : EntityCopy.tagWord($0) })
                        },
                        selected: owner?.id,
                        adding: .named("Person") { addPerson($0) },
                        opensOnAppear: opens(.owner)) { ownerId = $0 }
            if people.isEmpty {
                helper("No person is written yet. Type a name in Owner to add one.")
            }
        }
    }

    /// Writes a person named in Owner and chooses them; nil once chosen, else why not.
    private func addPerson(_ name: String) -> String? {
        guard let made = model.addEntity(.familyMember, named: name) else {
            LBHaptics.warn()
            return model.saveError ?? "That didn’t save."
        }
        refreshFacts()
        ownerId = made
        return nil
    }

    /// Writes an account named in Linked account and links it; nil once linked, else why not.
    private func addLink(_ name: String) -> String? {
        guard let made = model.addEntity(.paymentMethod, named: name) else {
            LBHaptics.warn()
            return model.saveError ?? "That didn’t save."
        }
        refreshFacts()
        linkedId = made
        return nil
    }

    /// A card to the bank account that pays it. One level: an account others are linked
    /// to cannot itself be linked, and the writer refuses it if tried.
    private var linkSection: some View {
        // A link the rules no longer offer still leads the list, so it can be cleared.
        let offered = (heldLink.map { [$0] } ?? []) + (linkedHere.isEmpty ? linkChoices : [])
        let chosen = offered.first { $0.id == linkedId }
        let owners = Dictionary(model.entityChoices(.paymentMethod).compactMap { account in
            account.owner.map { (account.id, $0.name) }
        }, uniquingKeysWith: { first, _ in first })
        return FormRow {
            FormQuestion("Linked account")
        } content: {
            ChoiceField("Linked account", value: chosen?.name ?? "None", empty: chosen == nil,
                        choices: offered.map {
                            ChoicePickerView.Choice(id: $0.id, name: $0.name, symbol: LBGlyph.account, detail: owners[$0.id])
                        },
                        selected: chosen?.id,
                        // An account others are paid from links to nothing, so nothing is added from it.
                        adding: linkedHere.isEmpty ? ChoiceAdding.named("Account", create: addLink) : nil,
                        opensOnAppear: opens(.linkedAccount)) { linkedId = $0 }
            .disabled(offered.isEmpty && !linkedHere.isEmpty)
            if let heldLink, linkedId == heldLink.id {
                helper(heldLinkGone
                       ? "This link names an account that is no longer here. Choose None to clear the link."
                       : "\(heldLink.name) is linked to another account itself, and links go one level. Choose None to clear the link.")
            }
            if !linkedHere.isEmpty {
                let names = linkedHere.map(\.name).joined(separator: ", ")
                helper("\(names) \(linkedHere.count == 1 ? "is" : "are") paid from this account.")
            } else if linkChoices.isEmpty {
                helper("No other account can be linked to yet. Type a name in Linked account to add one.")
            }
        }
    }

    private var notesSection: some View {
        FormRow {
            FormQuestion("Notes")
        } content: {
            FormField {
                VStack(alignment: .trailing, spacing: LBSpacing.s1) {
                    TextField(
                        "", text: $notes,
                        prompt: Text("Add").foregroundStyle(LBColor.textTertiary.color),
                        axis: .vertical
                    )
                    .textFieldStyle(.plain)
                    .lbText(.body)
                    .foregroundStyle(LBColor.textPrimary.color)
                    .lineLimit(3...8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel("Notes")
                    .focused($typingIn, equals: .notes)
                    // The count arrives as the notes near the limit, or pass it.
                    if notes.count > notesLimit - 40 {
                        Text("\(notes.count)/\(notesLimit)")
                            .lbText(.footnote)
                            .foregroundStyle((notesOver ? LBColor.urgent : LBColor.textTertiary).color)
                            .accessibilityLabel("\(notes.count) of \(notesLimit) characters")
                    }
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
        FormRow {
            FormQuestion("Accounts")
        } content: {
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
            .help("Unlink \(account.name)")
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
        FormRow {
            FormQuestion("Email")
        } content: {
            FormField {
                TextField("", text: $email, prompt: Text("Add").foregroundStyle(LBColor.textTertiary.color))
                    .textFieldStyle(.plain)
                    .lbText(.body)
                    .foregroundStyle(LBColor.textPrimary.color)
                    #if os(iOS)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    #endif
                    .accessibilityLabel("Email")
                    .focused($typingIn, equals: .email)
            }
            helper("Used when you share a report.")
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

    /// Red at the foot, and a question before it acts.
    private var deleteButton: some View {
        Button { Measure.used("delete"); confirmingDelete = true } label: {
            EditFormDeleteLabel(title: "Delete \(word.capitalized)")
        }
        .lbButtonStyle()
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
        return current != opened || balanceEntry == .unreadable || photoChanged
    }

    /// Whether the form can be saved at all, whatever has changed.
    private var savable: Bool {
        !current.name.isEmpty && balanceEntry != .unreadable && !notesOver
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
            accountNotes: isAccount ? changed(\.notes) : nil,
            memberNotes: isAccount ? nil : changed(\.notes),
            // The notes carry the card name, so Save takes it out of details.
            removingCardName: isAccount && holdsCardName,
            name: now.name == loaded.name ? nil : now.name,
            accountOwners: owners, photo: settlePhoto()
        )
    }

    // MARK: furniture

    private func helper(_ text: String) -> some View {
        Text(text)
            .lbText(.footnote)
            .foregroundStyle(LBColor.textTertiary.color)
            .fixedSize(horizontal: false, vertical: true)
    }
}
