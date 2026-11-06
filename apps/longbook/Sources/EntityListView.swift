import DesignSystem
import LongbookCore
import SwiftUI

/// Every account, or every person: a list of cards on a phone, each opening its Preview;
/// a sortable table with the selected card beside it on the Mac. Starred rows lead;
/// a search and a type filter narrow the list. One screen for both kinds.
struct EntityListView: View {
    let model: DashboardModel
    let kind: VaultPatch.EntityKind
    /// The row a door named, read in the Mac's inspector as the screen opens.
    var focus: String?

    @State private var editing: EntityTarget?
    @State private var addingFor: EntityTarget?
    @State private var deleting: EntityTarget?
    /// Whether the name card the Add button opens is showing.
    @State private var naming = false
    /// The Mac table's chosen row and the order its column headers set.
    @State private var selection: String?
    @State private var sortOrder: [KeyPathComparator<EntityRow>] = []
    /// A card opened from inside the inspector, read there in place of the chosen row.
    @State private var inspected: CardRef?
    /// The card whose Edit form stands in the panel, in its Preview's place, and how many
    /// times that form has been asked to close.
    @State private var formCard: CardRef?
    @State private var formCloseAsked = 0
    /// The field a Preview's row opened the form on; nil for the whole form.
    @State private var formFocus: EditFocus?
    /// The search, and the one type or relationship shown; nil shows every one.
    @State private var search = ""
    @State private var tagFilter: String?
    /// The rows in the order, and with the stars, the screen opened with. A star updates its
    /// own row at once but never moves it; the lead changes the next time the screen opens.
    @State private var opened: [String: Bool]?
    @State private var openedOrder: [String] = []
    /// Select, and what it asks before a bulk change writes.
    @State private var picking = ListSelection()
    @State private var prompt = BulkPrompt()
    /// Merge is picking the name to keep, and the question that pick then asks.
    @State private var pickingKept = false
    @State private var afterPick: BulkAsk?
    /// The row the screen just landed on, for the table to bring into view.
    @State private var landing: String?

    private var isAccount: Bool { kind == .paymentMethod }
    private var word: String { EntityCopy.word(kind) }

    /// One row of the Mac table, every column's value read once from the card.
    struct EntityRow: Identifiable {
        let card: DashboardModel.EntityCard
        let name: String
        let type: String
        /// For sorting only: no balance sorts below every balance.
        let balance: Double
        let balanceText: String
        let owner: String
        let accounts: Int
        let commitments: Int
        let charges: Int
        /// For sorting only: starred rows lead whatever the column order.
        let starred: Bool
        var starRank: Int { starred ? 0 : 1 }
        var id: String { card.id }
    }

    var body: some View {
        let cards = held(model.entityCards(kind))
        return content(cards)
            .screenTutorial(isAccount ? .accounts : .people)
            .onAppear {
                if opened == nil { holdOrder() }
                if selection == nil, let focus { selection = focus }
            }
            .onChange(of: selection) { _, _ in inspected = nil }
            .onChange(of: kind) { _, _ in holdOrder(); picking.finish() }
            // Show all in a search lands here with its words typed in this list's field.
            .onAppear(perform: takeHandedSearch)
            .onChange(of: SearchCenter.shared.handed) { _, _ in takeHandedSearch() }
            .onChange(of: selectableIds) { _, shown in
                // While the file reloads the list shows nothing; that narrows nothing.
                if case .loaded = model.state { picking.keep(shown) }
            }
            .onDisappear { picking.finish() }
            .measured("entity_list_picking_kept", .sheet, when: pickingKept)
            .sheet(isPresented: $pickingKept, onDismiss: {
                if let afterPick { prompt.start(afterPick) }
                afterPick = nil
            }) {
                keptPicker
                    .lbKeyboardFocusEffects()
            }
            .measured("entity_list_editing", .sheet, when: editing != nil)
            .sheet(item: $editing) { target in
                EntityEditView(model: model, kind: kind, id: target.id, currentName: target.name) {
                    editing = nil
                }
                .lbThreeQuarterSheet()
                .lbKeyboardFocusEffects()
            }
            .measured("entity_list_adding_for", .sheet, when: addingFor != nil)
            .sheet(item: $addingFor) { target in
                entityAddForm(model: model, kind: kind, id: target.id) { addingFor = nil }
                    .lbKeyboardFocusEffects()
            }
            .measured("entity_list_deleting", .dialog, when: deleting != nil)
            .confirmationDialog(
                "Delete \(deleting?.name ?? "this \(word)")?",
                isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                titleVisibility: .visible, presenting: deleting
            ) { target in
                Button("Delete", role: .destructive) {
                    Measure.used("delete")
                    model.deleteEntity(kind, id: target.id)
                    selection = nil
                }
                Button("Keep", role: .cancel) { Measure.used("keep") }
            } message: { target in
                Text(EntityCopy.removalNote(kind, use: model.entityUse(kind, id: target.id)))
            }
            .onAppear { model.clearSaveError() }
            #if DEBUG
            // The picture harness opens the first real card's editor, or the name card.
            .onChange(of: cards.first(where: \.isReal)?.id, initial: true) { _, first in
                let open = ProcessInfo.processInfo.environment["LONGBOOK_SNAPSHOT_OPEN"]
                if open == "add" { naming = true }
                let env = ProcessInfo.processInfo.environment
                if selection == nil, open != "support", open != "remembered", env["LONGBOOK_SNAPSHOT"] != nil || env["LONGBOOK_WINDOW_SNAPSHOT"] != nil {
                    // Select opens with the first real row chosen, so a picture shows the selection's line.
                    if open == "select", let first {
                        if !picking.isOn { picking.begin(with: [first]) }
                        return
                    }
                    selection = env["LONGBOOK_SNAPSHOT_ID"] ?? first
                }
                guard open == "edit", formCard == nil, let card = cards.first(where: { $0.id == selection ?? first }) else { return }
                #if os(macOS)
                formCard = card.ref
                #else
                editing = EntityTarget(id: card.id, name: card.name)
                #endif
            }
            #endif
    }

    private func takeHandedSearch() {
        if let words = SearchCenter.shared.take(for: isAccount ? "accounts" : "members") { search = words; tagFilter = nil }
    }

    @ViewBuilder
    private func content(_ cards: [DashboardModel.EntityCard]) -> some View {
        #if os(macOS)
        macBody(cards)
        #else
        phoneBody(cards)
        #endif
    }

    // MARK: - Order held while open

    /// Notes the order and the stars as they stand now.
    private func holdOrder() {
        let cards = model.entityCards(kind)
        openedOrder = cards.map(\.id)
        opened = Dictionary(cards.map { ($0.id, $0.starred) }, uniquingKeysWith: { first, _ in first })
    }

    /// The cards in the order the screen opened with. A row added since stands after them,
    /// ahead of the bucket naming nobody; a row removed is simply gone.
    private func held(_ cards: [DashboardModel.EntityCard]) -> [DashboardModel.EntityCard] {
        guard opened != nil else { return cards }
        var place: [String: Int] = [:]
        for (index, id) in openedOrder.enumerated() where place[id] == nil { place[id] = index }
        func key(_ offset: Int, _ card: DashboardModel.EntityCard) -> (Int, Int) {
            if let at = place[card.id] { return (0, at) }
            return (card.isReal ? 1 : 2, offset)
        }
        return cards.enumerated().sorted { key($0.offset, $0.element) < key($1.offset, $1.element) }.map(\.element)
    }

    // MARK: - Search and filter

    /// The filter's word for the column: an account's type, a person's relationship.
    private var filterTitle: String { isAccount ? "Type" : "Relationship" }

    /// The types or relationships the cards wear, each once, in the words a row shows.
    private func tagChoices(_ cards: [DashboardModel.EntityCard]) -> [String] {
        var seen = Set<String>()
        return cards.compactMap { card -> String? in
            guard card.isReal, let tag = card.tag?.trimmingCharacters(in: .whitespaces), !tag.isEmpty,
                  seen.insert(tag.lowercased()).inserted else { return nil }
            return tag
        }
        .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    /// The cards the search and the filter leave: a name, a type or an owner holding the
    /// words, and the chosen type. The bucket naming nobody has no type to match.
    private func narrowed(_ cards: [DashboardModel.EntityCard]) -> [DashboardModel.EntityCard] {
        let needle = search.trimmingCharacters(in: .whitespaces).lowercased()
        let wanted = tagFilter?.lowercased()
        return cards.filter { card in
            if let wanted, card.tag?.trimmingCharacters(in: .whitespaces).lowercased() != wanted { return false }
            guard !needle.isEmpty else { return true }
            let words = [EntityCopy.name(card), card.tag ?? "", card.owner?.name ?? ""].joined(separator: " ").lowercased()
            return words.contains(needle)
        }
    }

    private var narrowedWords: String {
        "No \(isAccount ? "account" : "person") matches. Clear the search or the filter."
    }

    /// The star on a table row: always there, faint until set. The toggle writes the vault.
    private func starButton(_ card: DashboardModel.EntityCard) -> some View {
        Button {
            if card.starred { Measure.used("unstar_entity") } else { Measure.used("star_entity") }
            model.setStarred(kind, id: card.id, !card.starred)
        } label: {
            Image(systemName: card.starred ? "star.fill" : "star")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(card.starred ? LBColor.brand.color : LBColor.textQuaternary.color)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .lbBorderlessButtonStyle(.rounded(LBRadius.xs))
        .opacity(card.isReal ? 1 : 0)
        .disabled(!card.isReal)
        .help(card.starred ? "Remove the star" : "Add a star")
        .accessibilityLabel(card.starred ? "Starred" : "Star")
        .accessibilityHint(card.starred ? "Takes the star off \(EntityCopy.name(card))" : "Keeps \(EntityCopy.name(card)) first")
    }

    private var screenTitle: String { isAccount ? "Accounts" : "People" }

    /// The one Add the list's first line holds.
    private var addTitle: String { isAccount ? "Add Account" : "Add Person" }

    // MARK: - Select

    /// Every real row the list shows. Read only while selecting, so the list does not compute it
    /// otherwise; the bucket naming nobody is not a row to act on.
    private var selectableIds: [String] {
        guard picking.isOn else { return [] }
        return narrowed(held(model.entityCards(kind))).filter(\.isReal).map(\.id)
    }

    private var manyNoun: (one: String, many: String) {
        isAccount ? (one: "account", many: "accounts") : (one: "person", many: "people")
    }

    @ViewBuilder
    private func bulkActions(_ count: Int) -> some View {
        SelectionBarButton(title: "Merge", measure: "bulk_merge", enabled: count > 1) { pickingKept = true }
        SelectionBarButton(title: "Delete \(count.formatted())", measure: "bulk_delete", destructive: true, enabled: count > 0) { askDelete() }
    }

    #if os(iOS)
    private var bulkBar: some View {
        SelectionBar(selection: picking, problem: model.saveError) { bulkActions($0) }
            .bulkPopups(prompt)
    }
    #endif

    /// Deleting many is the confirmation deleting one shows, made plural.
    private func askDelete() {
        let ids = Array(picking.ids)
        let whole = BulkWords.counted(ids.count, manyNoun)
        let use = model.entityUse(kind, ids: ids)
        prompt.start(BulkAsk(title: "Delete \(whole)?", message: ids.count == 1 ? EntityCopy.removalNote(kind, use: use) : EntityCopy.removalNote(kind, many: use),
                             confirm: "Delete \(whole.capitalized)", destructive: true, cancel: "Keep", asDialog: true,
                             flips: model.transferFlips(deleting: kind, ids: ids)) {
            if model.deleteEntities(kind, ids: ids) { finishPicking() }
        })
    }

    private func finishPicking() {
        picking.finish()
        selection = nil
    }

    /// The chosen rows, each with its relationship or type beside it, so choosing whom to keep
    /// shows what stays. Picking one asks before anything is written.
    private var keptPicker: some View {
        let chosen = model.entityCards(kind).filter { picking.ids.contains($0.id) }
        return ChoicePickerView(
            title: "Name to keep",
            glyph: isAccount ? LBGlyph.account : LBGlyph.member,
            choices: chosen.map { card in
                let tag = card.tag.flatMap { $0.isEmpty ? nil : EntityCopy.tagWord($0) }
                return ChoicePickerView.Choice(id: card.id, name: tag.map { "\(card.name) · \($0)" } ?? card.name, symbol: nil)
            },
            selected: nil,
            onPick: { keep in
                guard let kept = chosen.first(where: { $0.id == keep }) else { return }
                let ids = chosen.map(\.id)
                let words = BulkWords.merge(kind, count: ids.count, into: kept.name)
                afterPick = BulkAsk(title: words.title, message: words.message, confirm: "Merge",
                                    flips: model.transferFlips(merging: kind, keeping: keep, ids: ids)) {
                    if model.mergeEntities(kind, keeping: keep, ids: ids) { finishPicking() }
                }
            },
            onDone: { pickingKept = false }
        )
    }

    private func target(_ card: DashboardModel.EntityCard) -> EntityTarget {
        EntityTarget(id: card.id, name: card.name)
    }

    private func startNaming() {
        model.clearSaveError()
        naming = true
    }

    /// The refusal, if any, lands in saveError and shows above the list.
    private func addNamed(_ typed: String) {
        guard let id = model.addEntity(kind, named: typed) else { return }
        // A name matched to one already here opens under the spelling the vault holds.
        let held = model.entityNames(memberId: isAccount ? nil : id, methodId: isAccount ? id : nil)
        naming = false
        editing = EntityTarget(id: id, name: (isAccount ? held.method : held.member) ?? typed)
    }

    private var emptyWords: String {
        isAccount
            ? "No account is written yet. Add one to say where a commitment is paid from."
            : "No person is written yet. Add one to say who a commitment is for."
    }

    @ViewBuilder
    private var saveErrorLine: some View {
        if let saveError = model.saveError {
            Text(saveError)
                .lbText(.footnote)
                .foregroundStyle(LBColor.urgent.color)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func balanceText(_ card: DashboardModel.EntityCard) -> String? {
        card.balance.map { fmtMoney($0, card.balanceCurrency) }
    }

    // MARK: - iPhone

    #if os(iOS)
    private func phoneBody(_ all: [DashboardModel.EntityCard]) -> some View {
        let cards = narrowed(all)
        let choices = tagChoices(all)
        // A list, so each card takes the system's own swipe actions; it draws only the rows in view.
        return List {
            VStack(alignment: .leading, spacing: LBSpacing.s3) {
                ListDefinition(kind: isAccount ? .account : .people)
                ListSearchField(text: $search, prompt: isAccount ? "Search accounts" : "Search people")
                if !choices.isEmpty { filterChips(choices) }
                saveErrorLine
                if naming {
                    EntityNameCard(kind: kind, add: addNamed) { naming = false }
                }
                if cards.isEmpty, !naming {
                    Text(all.isEmpty ? emptyWords : narrowedWords)
                        .lbText(.footnote)
                        .foregroundStyle(LBColor.textSecondary.color)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .lbCardRow()
            // Every row on show is lit together: the list as far as the screen shows it.
            ForEach(cards) { card in phoneRow(card, spot: .entityList) }
        }
        .lbCardList()
        .scrollDismissesKeyboard(.immediately)
        .lbScreenTitle(screenTitle) {
            if picking.isOn {
                Button("Done") { Measure.used("select_done"); picking.finish() }
            } else {
                Button("Select") { Measure.used("select"); naming = false; picking.begin() }
                Button(action: { Measure.used("add_new"); startNaming() }) {
                    Image(systemName: "plus")
                }
                .tutorialTarget(.entityAdd)
                .accessibilityLabel(addTitle)
            }
        }
        .toolbar {
            if picking.isOn {
                ToolbarItem(placement: .topBarLeading) {
                    SelectAllButton(selection: picking) { selectableIds }
                }
            }
        }
        .navigationBarBackButtonHidden(picking.isOn)
        .preference(key: HidesTabBarKey.self, value: picking.isOn)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if picking.isOn { bulkBar }
        }
    }

    /// All, then one chip per type or relationship the cards wear; one chosen at a time.
    private func filterChips(_ choices: [String]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: LBSpacing.s2) {
                LBChip("All", style: .choice(selected: tagFilter == nil)) {
                    Measure.used("entity_filter_all")
                    tagFilter = nil
                }
                ForEach(choices, id: \.self) { tag in
                    LBChip(EntityCopy.tagWord(tag), style: .choice(selected: tagFilter?.lowercased() == tag.lowercased())) {
                        Measure.used("entity_filter_tag")
                        tagFilter = tagFilter?.lowercased() == tag.lowercased() ? nil : tag
                    }
                }
            }
            .padding(.vertical, LBSpacing.s1)
        }
        .accessibilityLabel(filterTitle)
    }

    /// The card every list wears; a tap opens its Preview. Add Commitment and the star lead
    /// the swipes, Edit and Delete trail them. While selecting, a tap toggles it; the bucket
    /// naming nobody has nothing to choose.
    @ViewBuilder
    private func phoneRow(_ card: DashboardModel.EntityCard, spot: TutorialTarget? = nil) -> some View {
        if picking.isOn {
            if card.isReal {
                SelectableCard(selection: picking, id: card.id) { KindCards.card(card, selected: $0, marked: true) }
                    .tutorialTarget(spot)
                    .lbCardRow()
            }
        } else {
            CardListLink(destination: card.ref.destination) { KindCards.card(card) }
                .tutorialTarget(spot)
                .lbCardRow()
                .lbRowActions(
                    leading: card.isReal ? [
                        LBRowAction("Add Commitment", systemImage: "plus") { addingFor = target(card) },
                        LBRowAction(card.starred ? "Remove Star" : "Star", systemImage: card.starred ? "star.slash" : "star", tint: LBColor.textSecondary) {
                            if card.starred { Measure.used("unstar_entity") } else { Measure.used("star_entity") }
                            model.setStarred(kind, id: card.id, !card.starred)
                        },
                    ] : [],
                    trailing: card.isReal ? [
                        LBRowAction("Edit", systemImage: "pencil", tint: LBColor.textSecondary) { editing = target(card) },
                        .destructive("Delete") { deleting = target(card) },
                    ] : []
                )
        }
    }
    #endif

    // MARK: - Mac

    #if os(macOS)
    private func rows(_ cards: [DashboardModel.EntityCard]) -> [EntityRow] {
        let rows = cards.map { card in
            EntityRow(
                card: card, name: EntityCopy.name(card),
                type: card.tag.map(EntityCopy.tagWord) ?? "—",
                balance: card.balance ?? -.greatestFiniteMagnitude,
                balanceText: balanceText(card) ?? "—",
                owner: card.owner?.name ?? "—",
                accounts: card.accountCount, commitments: card.commitments, charges: card.charges,
                starred: card.starred
            )
        }
        let sorted = sortOrder.isEmpty ? rows : rows.sorted(using: sortOrder)
        // A column's order sorts within each side; the side starred when the screen opened
        // stays on top, so a star pressed now does not move its row.
        func leads(_ row: EntityRow) -> Bool { opened?[row.id] ?? row.starred }
        return sorted.filter(leads) + sorted.filter { !leads($0) }
    }

    private func macBody(_ all: [DashboardModel.EntityCard]) -> some View {
        let cards = narrowed(all)
        let rows = rows(cards)
        let chosen = rows.first { $0.id == selection }?.card
        return VStack(spacing: 0) {
            macHeader(choices: tagChoices(all))
            macList(all, cards: cards, rows: rows)
                // The preview pane comes in from the right when a row is chosen and keeps one
                // width whatever the row holds.
                .lbSidePanel(isPresented: previewShown) {
                    if let formCard {
                        CardEditForm(model: model, card: formCard, inPanel: true, closeAsked: formCloseAsked, focus: formFocus,
                                     onDeleted: { selection = nil; inspected = nil },
                                     onMoved: { followMovedCharge(to: $0) }) { self.formCard = nil }
                            .id(formCard)
                    } else {
                        inspector(chosen)
                    }
                }
                // A chosen row that has left the list closes the panel, once no form stands in it.
                .onChange(of: model.isLoaded && formCard == nil && selection != nil && chosen == nil) { _, gone in
                    if gone { selection = nil }
                }
                // Another row chosen under the form closes it, asking first if it holds changes.
                .onChange(of: selection) { old, new in
                    if let formCard, rows.first(where: { $0.id == new })?.card.ref != formCard {
                        PanelForm.shared.onKeep = { selection = old }
                        formCloseAsked += 1
                    }
                }
                .lbRemembersRow(
                    on: kind.memoryKey, row: $selection, ready: model.isLoaded && focus == nil,
                    holds: { id in all.contains { $0.id == id } },
                    clearing: { search = ""; tagFilter = nil; picking.finish() },
                    landed: { landing = $0 }
                )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LBColor.canvas.color)
        .bulkPopups(prompt)
    }

    /// The panel's ×: the row stays closed on the next visit too.
    private func closePanel() {
        selection = nil
        ScreenMemory.shared.forget(on: kind.memoryKey)
    }

    /// A charge opened inside this Preview, moved to a new day by its form: the Preview follows it.
    private func followMovedCharge(to day: String) {
        guard let moved = formCard?.moved(to: day) else { return }
        formCard = nil
        inspected = moved
    }

    /// Double click and the menu's Edit open the form the Preview's Edit opens, in its place.
    private func edit(_ row: EntityRow) {
        let opened = row.card.ref
        let shown = selection == row.id ? inspected ?? opened : opened
        PanelForm.shared.ask {
            selection = row.id
            inspected = shown == opened ? nil : shown
            formFocus = nil
            formCard = shown
        }
    }

    /// What stands beside the panel: the note, what the screen has to say, the table, the bar.
    private func macList(_ all: [DashboardModel.EntityCard], cards: [DashboardModel.EntityCard], rows: [EntityRow]) -> some View {
        VStack(spacing: 0) {
            if model.saveError != nil || naming || cards.isEmpty {
                VStack(alignment: .leading, spacing: LBSpacing.s3) {
                    saveErrorLine
                    if naming { EntityNameCard(kind: kind, add: addNamed) { naming = false } }
                    if cards.isEmpty, !naming {
                        Text(all.isEmpty ? emptyWords : narrowedWords)
                            .lbText(.body)
                            .foregroundStyle(LBColor.textSecondary.color)
                    }
                }
                .padding(.horizontal, LBSpacing.s4)
                .padding(.bottom, LBSpacing.s3)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            // Its own body, so a toggle redraws the table and never reads the cards again.
            ObservingView {
                let _ = picking.ids
                table(rows)
            }
                .lbLandsOnRow($landing)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background { SelectAllKey { macSelectAll() } }
        }
    }

    private var previewShown: Binding<Bool> {
        Binding(get: { formCard != nil || (selection != nil && !picking.isOn) }, set: { if !$0 { selection = nil; formCard = nil } })
    }

    /// ⌘A: Select comes on, with everything the list shows.
    private func macSelectAll() {
        beginPicking()
        picking.choose(all: selectableIds)
    }

    /// Select comes on, holding the row that was chosen, and the Preview goes.
    private func beginPicking(with chosen: Set<String>? = nil) {
        guard !picking.isOn else {
            if let chosen { picking.replace(with: chosen) }
            return
        }
        picking.begin(with: chosen ?? selection.map { [$0] } ?? [])
        selection = nil
    }

    /// The table's selection. Outside Select it is the one row the Preview reads, and a second
    /// row turns Select on. Inside it, ⌘ and ⇧ work as the table's own do and a plain click
    /// toggles, as a tap does on a phone. The bucket naming nobody is never held.
    private func tableSelection(_ rows: [EntityRow]) -> Binding<Set<String>> {
        Binding(
            get: { picking.isOn ? picking.ids : selection.map { [$0] } ?? [] },
            set: { new in
                let real = Set(rows.filter { $0.card.isReal && new.contains($0.id) }.map(\.id))
                guard picking.isOn else {
                    let adding = !NSEvent.modifierFlags.isDisjoint(with: [.command, .shift]) && !real.isEmpty
                    if new.count > 1 || adding {
                        beginPicking(with: real)
                    } else if new.isEmpty {
                        closePanel()
                    } else {
                        selection = new.first
                    }
                    return
                }
                let plainClick = NSApp.currentEvent.map { [.leftMouseDown, .leftMouseUp].contains($0.type) } == true
                    && NSEvent.modifierFlags.isDisjoint(with: [.command, .shift])
                if plainClick, real.count == 1, let only = real.first {
                    picking.toggle(only)
                } else {
                    picking.replace(with: real)
                }
            }
        )
    }

    /// The title and Add on one line — the window's toolbar, drawn in the page — or, while
    /// selecting, the count with Merge and Delete. Then what the list holds, the search and the
    /// one filter, and Select All while selecting. Select itself is the star column's header.
    private func macHeader(choices: [String]) -> some View {
        VStack(alignment: .leading, spacing: LBSpacing.s3) {
            if picking.isOn {
                HeaderSelectionBar(selection: picking) { bulkActions($0) }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: LBSpacing.s2) {
                    LBPageTitle(screenTitle)
                    Spacer()
                    Button(action: { Measure.used("add"); startNaming() }) {
                        Label(addTitle, systemImage: "plus")
                    }
                    .tutorialTarget(.entityAdd)
                }
                .controlSize(.large)
            }
            ListDefinition(kind: isAccount ? .account : .people)
            HStack(spacing: LBSpacing.s2) {
                ListSearchField(text: $search, prompt: isAccount ? "Search accounts" : "Search people")
                filterMenu(choices)
                if picking.isOn {
                    SelectAllButton(selection: picking) { selectableIds }
                        .help("Select All (⌘A)")
                }
            }
            .lbBesidePanel(previewShown.wrappedValue)
        }
        .padding(.horizontal, LBSpacing.s4)
        .padding(.top, LBSpacing.s6)
        .frame(height: SidePanel.line, alignment: .top)
    }

    /// The star column's header: a click turns Select on, the checkboxes standing where the
    /// stars stood, and a second click turns it off. A click on any other header sorts.
    private var sortOrFlip: Binding<[KeyPathComparator<EntityRow>]> {
        Binding(get: { sortOrder }, set: { order in
            guard order.first?.keyPath == \EntityRow.starRank else {
                sortOrder = order
                return
            }
            Measure.used("select_header")
            if picking.isOn { finishPicking() } else { beginPicking() }
        })
    }

    private var starHeaderTip: String {
        picking.isOn ? "Done selecting: show the stars" : "Select \(screenTitle) · ⌘A selects all · ⌘-click or ⇧-click adds"
    }

    /// The type or relationship to show, as Commitments' filter ticks its choice.
    private func filterMenu(_ choices: [String]) -> some View {
        Menu {
            Picker(selection: Binding(get: { tagFilter }, set: { picked in
                Measure.used("entity_filter_tag", .menuItem)
                tagFilter = picked
            })) {
                Text("Any").tag(String?.none)
                ForEach(choices, id: \.self) { tag in
                    Text(EntityCopy.tagWord(tag)).tag(String?.some(tag))
                }
            } label: {
                Text(filterTitle)
            }
            .pickerStyle(.inline)
        } label: {
            Image(systemName: tagFilter == nil ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
        }
        .fixedSize()
        .disabled(choices.isEmpty && tagFilter == nil)
        .help(tagFilter.map { "Filter by \(filterTitle.lowercased()): \(EntityCopy.tagWord($0))" } ?? "Filter by \(filterTitle.lowercased())")
        .lbLinkPointer()
        .accessibilityLabel(tagFilter == nil ? "Filter by \(filterTitle.lowercased())" : "Filter by \(filterTitle.lowercased()), one chosen")
    }

    @ViewBuilder
    private func table(_ rows: [EntityRow]) -> some View {
        if isAccount {
            tableChrome(rows, Table(rows, selection: tableSelection(rows), sortOrder: sortOrFlip) {
                starColumn
                nameColumn
                TableColumn("Type", value: \.type) { row in dimmed(row.type) }
                    .width(min: Self.narrowest, ideal: 120)
                TableColumn("Balance", value: \.balance) { row in
                    HStack {
                        Spacer(minLength: 0)
                        dimmed(row.balanceText)
                    }
                }
                .width(min: Self.narrowest, ideal: 120)
                TableColumn("Owner", value: \.owner) { row in dimmed(row.owner) }
                    .width(min: Self.narrowest, ideal: 110)
                TableColumn("Commitments", value: \.commitments) { row in count(row.commitments) }
                    .width(min: Self.narrowest, ideal: 100)
                TableColumn("Charges", value: \.charges) { row in count(row.charges) }
                    .width(min: Self.narrowest, ideal: 80)
            })
        } else {
            tableChrome(rows, Table(rows, selection: tableSelection(rows), sortOrder: sortOrFlip) {
                starColumn
                nameColumn
                TableColumn("Relationship", value: \.type) { row in dimmed(row.type) }
                    .width(min: Self.narrowest, ideal: 120)
                TableColumn("Accounts", value: \.accounts) { row in count(row.accounts) }
                    .width(min: Self.narrowest, ideal: 80)
                TableColumn("Commitments", value: \.commitments) { row in count(row.commitments) }
                    .width(min: Self.narrowest, ideal: 100)
                TableColumn("Charges", value: \.charges) { row in count(row.charges) }
                    .width(min: Self.narrowest, ideal: 80)
            })
        }
    }

    /// The star, unlabelled, ahead of the name; a click sets or clears it without choosing the
    /// row. While selecting the checkbox stands in its place.
    private var starColumn: some TableColumnContent<EntityRow, KeyPathComparator<EntityRow>> {
        TableColumn(Text(Image(systemName: picking.isOn ? "checkmark.square" : "star")), value: \.starRank) { row in
            if picking.isOn {
                if row.card.isReal {
                    let chosen = picking.ids.contains(row.id)
                    Button { Measure.used("select_card"); picking.toggle(row.id) } label: {
                        LBSelectionMark(selected: chosen)
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                    .lbBorderlessButtonStyle(.rounded(LBRadius.xs))
                    .accessibilityLabel(row.name)
                    .accessibilityAddTraits(chosen ? .isSelected : [])
                }
            } else {
                starButton(row.card)
            }
        }
        .width(28)
    }

    private var nameColumn: some TableColumnContent<EntityRow, KeyPathComparator<EntityRow>> {
        TableColumn("Name", value: \.name) { row in
            HStack(spacing: LBSpacing.s2) {
                EntityAvatar(name: row.name, ink: row.card.ink, size: 20, photo: row.card.photo)
                Text(row.name).lineLimit(1)
            }
        }
        // The ideal fits a bank, a kind and four digits — "ICICI Joint Savings 0063".
        .width(min: Self.narrowest, ideal: 260)
    }

    private static let narrowest = CGFloat(ColumnSets.narrowest)
    /// The widths the columns above ask for, for a set of widths nothing has been dragged in.
    private var columnIdeals: [String: CGFloat] {
        isAccount
            ? ["Name": 260, "Type": 120, "Balance": 120, "Owner": 110, "Commitments": 100, "Charges": 80]
            : ["Name": 260, "Relationship": 120, "Accounts": 80, "Commitments": 100, "Charges": 80]
    }

    private func tableChrome<T: View>(_ rows: [EntityRow], _ table: T) -> some View {
        table
            .lbRemembersColumns(on: kind.memoryKey, panelOpen: previewShown.wrappedValue, ideals: columnIdeals, leadTip: starHeaderTip)
            .tableStyle(.inset(alternatesRowBackgrounds: false))
            .scrollContentBackground(.hidden)
            // The overlay scroll bars sat on the last column and the last row; a margin the
            // width of a bar keeps both clear of them.
            .contentMargins(.trailing, LBSpacing.s4, for: .scrollContent)
            .contentMargins(.bottom, LBSpacing.s4, for: .scrollContent)
            .lbText(.body)
            .contextMenu(forSelectionType: String.self) { ids in
                if picking.isOn {
                    // What the bar offers, for the rows chosen.
                    if picking.ids.count > 1 {
                        Button("Merge…") { Measure.used("bulk_merge", .contextMenu); pickingKept = true }
                    }
                    if !picking.ids.isEmpty {
                        Button("Delete \(picking.ids.count)…", role: .destructive) { Measure.used("bulk_delete", .contextMenu); askDelete() }
                    }
                } else if let id = ids.first, let row = rows.first(where: { $0.id == id }), row.card.isReal {
                    Button("Edit") { Measure.used("edit", .contextMenu); edit(row) }
                    Button("Add Commitment") { Measure.used("add_commitment", .contextMenu); addingFor = target(row.card) }
                    Divider()
                    Button("Delete", role: .destructive) { Measure.used("delete", .contextMenu); deleting = target(row.card) }
                }
            } primaryAction: { ids in
                if !picking.isOn, let id = ids.first, let row = rows.first(where: { $0.id == id }), row.card.isReal {
                    edit(row)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // The table fills the pane; the tutorial lights its header and rows, not the space under them.
            .tutorialTarget(.entityList) { pane in
                CGRect(x: pane.minX, y: pane.minY, width: pane.width, height: min(pane.height, Self.tableHeader + CGFloat(rows.count) * Self.tableRow))
            }
    }

    private static let tableHeader: CGFloat = 32
    private static let tableRow: CGFloat = 30

    private func dimmed(_ text: String) -> some View {
        Text(text)
            .foregroundStyle(text == "—" ? LBColor.textTertiary.color : LBColor.textPrimary.color)
            .lineLimit(1)
    }

    private func count(_ value: Int) -> some View {
        HStack {
            Spacer(minLength: 0)
            Text("\(value)").monospacedDigit()
        }
    }

    /// The selected card's Preview; a card inside it opens here too, in its place.
    @ViewBuilder
    private func inspector(_ card: DashboardModel.EntityCard?) -> some View {
        if let card {
            let shown = inspected ?? card.ref
            CardPreviewView(model: model, card: shown, onClose: closePanel, open: { inspected = $0 },
                            onEdit: { field in
                                formFocus = field
                                formCard = shown
                            })
                .id(shown)
        } else {
            VStack(alignment: .leading, spacing: LBSpacing.s3) {
                PanelCloseButton(measure: "close_no_selection", action: closePanel)
                Text("No selection")
                    .lbText(.body)
                    .foregroundStyle(LBColor.textTertiary.color)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(LBSpacing.s4)
        }
    }
    #endif
}

/// A new account or person starts as a name; the editor then opens on it for the rest.
/// Its own view, so typing a name redraws this card and never the list under it.
private struct EntityNameCard: View {
    let kind: VaultPatch.EntityKind
    let add: (String) -> Void
    let cancel: () -> Void

    @State private var typedName = ""
    @FocusState private var nameFocused: Bool

    private var isAccount: Bool { kind == .paymentMethod }
    private var word: String { EntityCopy.word(kind) }
    private var cleanName: String { typedName.trimmingCharacters(in: .whitespaces) }

    private func addNamed() {
        guard !cleanName.isEmpty else { return }
        add(cleanName)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: LBSpacing.s2) {
            Text(isAccount ? "Name the account" : "Name the person")
                .lbText(.body)
                .foregroundStyle(LBColor.textPrimary.color)
            TextField(
                "", text: $typedName,
                prompt: Text(isAccount ? Regional.accountNameExample : "Their name").foregroundStyle(LBColor.textTertiary.color)
            )
            .textFieldStyle(.plain)
            .lbText(.body)
            .foregroundStyle(LBColor.textPrimary.color)
            .focused($nameFocused)
            // The field takes the cursor once it exists; before that there is nothing to focus.
            .onAppear { nameFocused = true }
            .submitLabel(.done)
            .onSubmit(addNamed)
            .padding(LBSpacing.s3)
            .background(LBColor.sunken.color, in: RoundedRectangle(cornerRadius: LBRadius.xs, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: LBRadius.xs, style: .continuous)
                    .strokeBorder(LBColor.hairline.color, lineWidth: 1)
            )
            .accessibilityLabel(isAccount ? "Account name" : "Their name")
            Text("A name already here is opened, never added twice.")
                .lbText(.footnote)
                .foregroundStyle(LBColor.textTertiary.color)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: LBSpacing.s2) {
                Button(action: { Measure.used("add"); addNamed() }) {
                    EntityActionLabel(title: "Add \(word.capitalized)", symbol: "plus", prominent: true, fills: true)
                }
                .lbButtonStyle()
                .disabled(cleanName.isEmpty)
                .lbPhoneDimmed(cleanName.isEmpty)
                Button(action: { Measure.used("cancel"); cancel() }) {
                    EntityActionLabel(title: "Cancel", symbol: "xmark", prominent: false, fills: true)
                }
                .lbButtonStyle()
            }
        }
        .padding(LBSpacing.s4)
        .frame(maxWidth: 560, alignment: .leading)
        .background(LBColor.card.color, in: RoundedRectangle(cornerRadius: LBRadius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: LBRadius.md, style: .continuous)
                .strokeBorder(LBColor.hairline.color, lineWidth: 1)
        )
    }
}
