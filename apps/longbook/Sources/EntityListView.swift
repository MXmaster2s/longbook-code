import DesignSystem
import LongbookCore
import SwiftUI

/// Every account, or every person: a plain list on a phone, each row opening the whole
/// card; a sortable table with the selected card beside it on the Mac. Accounts and people
/// are the same screen over a different kind.
struct EntityListView: View {
    let model: DashboardModel
    let kind: VaultPatch.EntityKind

    @State private var editing: EntityTarget?
    @State private var addingFor: EntityTarget?
    @State private var deleting: EntityTarget?
    /// Whether the name card the Add button opens is showing.
    @State private var naming = false
    /// The Mac table's chosen row and the order its column headers set.
    @State private var selection: String?
    @State private var sortOrder: [KeyPathComparator<EntityRow>] = []
    @State private var viewing: EntityEditView.CommitmentRef?

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
        var id: String { card.id }
    }

    var body: some View {
        let cards = model.entityCards(kind)
        return content(cards)
            .measured("entity_list_editing", .sheet, when: editing != nil)
            .sheet(item: $editing) { target in
                EntityEditView(model: model, kind: kind, id: target.id, currentName: target.name) {
                    editing = nil
                }
            }
            .measured("entity_list_adding_for", .sheet, when: addingFor != nil)
            .sheet(item: $addingFor) { target in
                entityAddForm(model: model, kind: kind, id: target.id) { addingFor = nil }
            }
            .measured("entity_list_viewing", .sheet, when: viewing != nil)
            .sheet(item: $viewing) { ref in
                CommitmentDetailView(model: model, id: ref.id) { viewing = nil }
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
                if selection == nil, env["LONGBOOK_SNAPSHOT"] != nil || env["LONGBOOK_WINDOW_SNAPSHOT"] != nil {
                    selection = env["LONGBOOK_SNAPSHOT_ID"] ?? first
                }
                guard open == "edit", editing == nil, let card = cards.first(where: { $0.id == first }) else { return }
                editing = EntityTarget(id: card.id, name: card.name)
            }
            #endif
    }

    @ViewBuilder
    private func content(_ cards: [DashboardModel.EntityCard]) -> some View {
        #if os(macOS)
        macBody(cards)
        #else
        phoneBody(cards)
        #endif
    }

    private var screenTitle: String { isAccount ? "Accounts" : "People" }

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

    /// The row's second line: an account's type, a person's relationship, then how many
    /// commitments name them.
    private func secondary(_ card: DashboardModel.EntityCard) -> String {
        let count = EntityCopy.counted(card.commitments, "commitment")
        guard let tag = card.tag, !tag.isEmpty else { return count }
        return isAccount ? EntityCopy.tagWord(tag) : "\(EntityCopy.tagWord(tag)) · \(count)"
    }

    private func balanceText(_ card: DashboardModel.EntityCard) -> String? {
        card.balance.map { fmtMoney($0, card.balanceCurrency) }
    }

    // MARK: - iPhone

    #if os(iOS)
    private func phoneBody(_ cards: [DashboardModel.EntityCard]) -> some View {
        List {
            if model.saveError != nil || naming || cards.isEmpty {
                Section {
                    saveErrorLine
                    if naming {
                        EntityNameCard(kind: kind, add: addNamed) { naming = false }
                    }
                    if cards.isEmpty, !naming {
                        Text(emptyWords)
                            .lbText(.footnote)
                            .foregroundStyle(LBColor.textSecondary.color)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
            if !cards.isEmpty {
                Section {
                    ForEach(cards) { card in phoneRow(card) }
                } footer: {
                    if !isAccount {
                        Text("The people your commitments are for.")
                            .lbText(.footnote)
                            .foregroundStyle(LBColor.textTertiary.color)
                    }
                }
            }
        }
        .lbGroupedList()
        .lbScreenTitle(screenTitle) {
            Button(action: { Measure.used("add_new"); startNaming() }) {
                Image(systemName: "plus")
            }
            .accessibilityLabel("Add \(word)")
        }
    }

    /// Avatar, name and type, the balance at the end; a tap opens the whole card.
    private func phoneRow(_ card: DashboardModel.EntityCard) -> some View {
        NavigationLink {
            EntityDetailView(model: model, kind: kind, id: card.id)
        } label: {
            LBListRow(EntityCopy.name(card), secondary: secondary(card), amount: isAccount ? balanceText(card) : nil) {
                EntityAvatar(name: EntityCopy.name(card), ink: card.ink, size: 32, photo: card.photo)
            }
        }
        .lbListRowBackground()
        .lbRowActions(
            leading: card.isReal ? [LBRowAction("Add Commitment", systemImage: "plus") { addingFor = target(card) }] : [],
            trailing: card.isReal ? [
                LBRowAction("Edit", systemImage: "pencil", tint: LBColor.textSecondary) { editing = target(card) },
                .destructive("Delete") { deleting = target(card) },
            ] : []
        )
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
                accounts: card.accountCount, commitments: card.commitments, charges: card.charges
            )
        }
        return sortOrder.isEmpty ? rows : rows.sorted(using: sortOrder)
    }

    private func macBody(_ cards: [DashboardModel.EntityCard]) -> some View {
        let rows = rows(cards)
        let chosen = rows.first { $0.id == selection }?.card
        return VStack(spacing: 0) {
            macHeader(chosen)
            if model.saveError != nil || naming || cards.isEmpty {
                VStack(alignment: .leading, spacing: LBSpacing.s3) {
                    saveErrorLine
                    if naming { EntityNameCard(kind: kind, add: addNamed) { naming = false } }
                    if cards.isEmpty, !naming {
                        Text(emptyWords)
                            .lbText(.body)
                            .foregroundStyle(LBColor.textSecondary.color)
                    }
                }
                .padding(.horizontal, LBSpacing.s4)
                .padding(.bottom, LBSpacing.s3)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            table(rows)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LBColor.canvas.color)
        // The preview pane comes in from the right when a row is chosen and keeps one width
        // whatever the row holds.
        .lbInspector(isPresented: previewShown, width: 360) {
            inspector(chosen)
                .background(LBColor.canvas.color)
        }
    }

    private var previewShown: Binding<Bool> {
        Binding(get: { selection != nil }, set: { if !$0 { selection = nil } })
    }

    /// The title and the selection's actions on one line — the window's toolbar, drawn in
    /// the page.
    private func macHeader(_ chosen: DashboardModel.EntityCard?) -> some View {
        let real = chosen?.isReal == true ? chosen : nil
        return VStack(alignment: .leading, spacing: LBSpacing.s1) {
            HStack(alignment: .firstTextBaseline, spacing: LBSpacing.s2) {
                LBPageTitle(screenTitle)
                Spacer()
                Button("Add Commitment") { Measure.used("add_commitment"); if let real { addingFor = target(real) } }
                    .disabled(real == nil)
                Button(action: { Measure.used("add"); startNaming() }) {
                    Label("Add \(word.capitalized)", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .tint(LBColor.brand.color)
            }
            .controlSize(.large)
            if !isAccount {
                Text("The people your commitments are for.")
                    .lbText(.body)
                    .foregroundStyle(LBColor.textSecondary.color)
            }
        }
        .padding(.horizontal, LBSpacing.s4)
        .padding(.top, LBSpacing.s6)
        .padding(.bottom, LBSpacing.s3)
    }

    private func showAll(_ card: DashboardModel.EntityCard) -> Destination {
        isAccount ? .commitments(ListFilter(methodId: card.id)) : .commitments(ListFilter(memberId: card.id))
    }

    @ViewBuilder
    private func table(_ rows: [EntityRow]) -> some View {
        if isAccount {
            tableChrome(rows, Table(rows, selection: $selection, sortOrder: $sortOrder) {
                nameColumn
                TableColumn("Type", value: \.type) { row in dimmed(row.type) }
                    .width(min: 90, ideal: 120)
                TableColumn("Balance", value: \.balance) { row in
                    HStack {
                        Spacer(minLength: 0)
                        dimmed(row.balanceText)
                    }
                }
                .width(min: 90, ideal: 120)
                TableColumn("Owner", value: \.owner) { row in dimmed(row.owner) }
                    .width(min: 80, ideal: 110)
                TableColumn("Commitments", value: \.commitments) { row in count(row.commitments) }
                    .width(min: 80, ideal: 100)
                TableColumn("Charges", value: \.charges) { row in count(row.charges) }
                    .width(min: 60, ideal: 80)
            })
        } else {
            tableChrome(rows, Table(rows, selection: $selection, sortOrder: $sortOrder) {
                nameColumn
                TableColumn("Relationship", value: \.type) { row in dimmed(row.type) }
                    .width(min: 90, ideal: 120)
                TableColumn("Accounts", value: \.accounts) { row in count(row.accounts) }
                    .width(min: 70, ideal: 80)
                TableColumn("Commitments", value: \.commitments) { row in count(row.commitments) }
                    .width(min: 80, ideal: 100)
                TableColumn("Charges", value: \.charges) { row in count(row.charges) }
                    .width(min: 60, ideal: 80)
            })
        }
    }

    private var nameColumn: some TableColumnContent<EntityRow, KeyPathComparator<EntityRow>> {
        TableColumn("Name", value: \.name) { row in
            HStack(spacing: LBSpacing.s2) {
                EntityAvatar(name: row.name, ink: row.card.ink, size: 20, photo: row.card.photo)
                Text(row.name).lineLimit(1)
            }
        }
        // Wide enough for a bank, a kind and four digits — "ICICI Joint Savings 0063".
        .width(min: 200, ideal: 260)
    }

    private func tableChrome<T: View>(_ rows: [EntityRow], _ table: T) -> some View {
        table
            .tableStyle(.inset(alternatesRowBackgrounds: false))
            .scrollContentBackground(.hidden)
            // The overlay scroll bars sat on the last column and the last row; a margin the
            // width of a bar keeps both clear of them.
            .contentMargins(.trailing, LBSpacing.s4, for: .scrollContent)
            .contentMargins(.bottom, LBSpacing.s4, for: .scrollContent)
            .lbText(.body)
            .contextMenu(forSelectionType: String.self) { ids in
                if let id = ids.first, let row = rows.first(where: { $0.id == id }), row.card.isReal {
                    Button("Edit") { Measure.used("edit", .contextMenu); editing = target(row.card) }
                    Button("Add Commitment") { Measure.used("add_commitment", .contextMenu); addingFor = target(row.card) }
                    Divider()
                    Button("Delete", role: .destructive) { Measure.used("delete", .contextMenu); deleting = target(row.card) }
                }
            } primaryAction: { ids in
                if let id = ids.first, let row = rows.first(where: { $0.id == id }), row.card.isReal {
                    editing = target(row.card)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

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

    /// The selected card whole, with its latest charges for an account.
    @ViewBuilder
    private func inspector(_ card: DashboardModel.EntityCard?) -> some View {
        if let card {
            ScrollView {
                VStack(alignment: .leading, spacing: LBSpacing.s4) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Preview")
                            .lbText(.eyebrow)
                            .foregroundStyle(LBColor.textTertiary.color)
                        Spacer()
                        if card.isReal {
                            Button("Edit") { Measure.used("edit"); editing = target(card) }
                                .buttonStyle(.plain)
                                .lbText(.label)
                                .foregroundStyle(LBColor.brandText.color)
                        }
                    }
                    EntityCardView(
                        card: card,
                        style: .preview,
                        insight: model.insight("\(EntityCopy.insightWord(kind)).\(card.id)"),
                        actions: EntityCardView.Actions(
                            delete: { deleting = target(card) },
                            addCommitment: { addingFor = target(card) },
                            edit: { editing = target(card) }
                        )
                    )
                    // Unassigned has its rows here too: the summary reads them by no id, and
                    // opening one is how a commitment gets its account or person.
                    let summary = model.entitySummary(kind, id: card.isReal ? card.id : nil)
                    EntityRecentPanel(moments: summary.recent, total: summary.charges, showAll: showAll(card)) {
                        viewing = EntityEditView.CommitmentRef(id: $0)
                    }
                    EntityRecentPanel(eyebrow: "Upcoming commitments", emptyWords: "Nothing is due here yet.",
                                      moments: summary.upcoming, total: summary.commitments, showAll: showAll(card)) {
                        viewing = EntityEditView.CommitmentRef(id: $0)
                    }
                }
                .padding(LBSpacing.s4)
            }
            .id(card.id)
        } else {
            Text("No selection")
                .lbText(.body)
                .foregroundStyle(LBColor.textTertiary.color)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
    #endif
}

/// One account or person, read whole: its card, and for an account the latest charges.
/// Edit is in the bar; the card's buttons add a commitment or list every one.
struct EntityDetailView: View {
    let model: DashboardModel
    let kind: VaultPatch.EntityKind
    let id: String

    @State private var editing = false
    @State private var adding = false
    @State private var deleting = false
    @State private var viewing: EntityEditView.CommitmentRef?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LBSpacing.s4) {
                if let card = model.entityCards(kind).first(where: { $0.id == id }) {
                    EntityCardView(
                        card: card,
                        insight: model.insight("\(EntityCopy.insightWord(kind)).\(card.id)"),
                        actions: EntityCardView.Actions(
                            delete: { deleting = true },
                            addCommitment: { adding = true },
                            edit: { editing = true },
                            open: { viewing = EntityEditView.CommitmentRef(id: $0) }
                        )
                    )
                    if kind == .paymentMethod, card.isReal {
                        let summary = model.entitySummary(kind, id: card.id)
                        EntityRecentPanel(moments: summary.recent, total: summary.charges) {
                            viewing = EntityEditView.CommitmentRef(id: $0)
                        }
                    }
                    if card.isReal {
                        Button(role: .destructive) { Measure.used("delete"); deleting = true } label: {
                            Text("Delete \(EntityCopy.word(kind).capitalized)")
                                .lbText(.body)
                                .foregroundStyle(LBColor.danger.color)
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .background(LBColor.card.color, in: RoundedRectangle(cornerRadius: LBRadius.md, style: .continuous))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    Text("This is no longer in your folder.")
                        .lbText(.body)
                        .foregroundStyle(LBColor.textTertiary.color)
                }
            }
            .lbPageColumn(.reading)
        }
        .background(LBColor.canvas.color)
        .lbScreenTitle(title, large: false) {
            if isReal { Button("Edit") { Measure.used("edit"); editing = true } }
        }
        .measured("entity_list_editing", .sheet, when: editing)
        .sheet(isPresented: $editing) {
            EntityEditView(model: model, kind: kind, id: id, currentName: title) { editing = false }
        }
        .measured("entity_list_adding", .sheet, when: adding)
        .sheet(isPresented: $adding) {
            entityAddForm(model: model, kind: kind, id: id) { adding = false }
        }
        .measured("entity_list_viewing", .sheet, when: viewing != nil)
        .sheet(item: $viewing) { ref in
            CommitmentDetailView(model: model, id: ref.id) { viewing = nil }
        }
        .measured("entity_list_deleting", .dialog, when: deleting)
        .confirmationDialog("Delete \(title)?", isPresented: $deleting, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                Measure.used("delete")
                if model.deleteEntity(kind, id: id) { dismiss() }
            }
            Button("Keep", role: .cancel) { Measure.used("keep") }
        } message: {
            Text(EntityCopy.removalNote(kind, use: model.entityUse(kind, id: id)))
        }
    }

    private var card: DashboardModel.EntityCard? { model.entityCards(kind).first { $0.id == id } }
    private var title: String { card.map(EntityCopy.name) ?? "" }
    private var isReal: Bool { card?.isReal == true }
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
                prompt: Text(isAccount ? "HDFC savings" : "Their name").foregroundStyle(LBColor.textTertiary.color)
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
                .buttonStyle(.plain)
                .disabled(cleanName.isEmpty)
                .opacity(cleanName.isEmpty ? 0.5 : 1)
                Button(action: { Measure.used("cancel"); cancel() }) {
                    EntityActionLabel(title: "Cancel", symbol: "xmark", prominent: false, fills: true)
                }
                .buttonStyle(.plain)
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
