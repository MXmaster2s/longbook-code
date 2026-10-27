import DesignSystem
import LongbookCore
import SwiftUI

/// The full review surface: every kept version of the memory, who wrote it, what it
/// changed, and the road back. The banner answers the pending question; this screen
/// answers every question after it. The phone shows one list; the Mac a list beside the
/// selected line in full.
struct ChangesView: View {
    let model: DashboardModel

    @State private var log: [HistoryEntry] = []
    /// The versions the list shows: the log without the bookkeeping-only ones, judged off
    /// the main actor. The list waits for the verdict, so a Keep never shows and then goes.
    @State private var shown: [HistoryEntry] = []
    @State private var historyReady = false
    /// True while the History sheet waits for the version log to come down from iCloud.
    @State private var historyArriving = false
    /// The kept versions, shown on request in their own sheet; clearing them asks twice.
    @State private var showingHistory = false
    @State private var clearingHistory = false
    @State private var clearingHistoryAgain = false
    @State private var expanded: Set<String> = []
    @State private var diffs: [String: [EntityDiff]] = [:]
    @State private var writers: [String: [String: String]] = [:]
    @State private var confirmingRestore: String?
    /// The pending row being edited before it is kept, by the editor it opens.
    @State private var editing: EditTarget?
    /// The pending row about to be dropped, held for its confirmation.
    @State private var deleting: DeleteTarget?
    @State private var showingHow = false
    /// Why Keep All, Undo All or a delete was refused, in the model's words.
    @State private var refusal: String?
    /// Why a Restore was refused, under the version it was asked of.
    @State private var restoreRefusal: RowRefusal?
    /// The Mac's selected row: a proposed line or a kept version.
    @State private var selection: Pick?
    /// The kind of row in front; nil, or a kind with nothing left, follows the first tab.
    @State private var pickedKind: String?

    private struct RowRefusal {
        let hash: String
        let words: String
    }

    /// What the Mac list can select.
    private enum Pick: Hashable {
        case line(String)
        case version(String)
    }

    private static let historyAnchor = "history"

    var body: some View {
        // Folded once per pass: the subtitle, the sections and the rows read the same diff.
        let review = model.outsideChangeFrom == nil ? nil : pendingReview()
        let groups = review.map(lineGroups) ?? []
        ScrollViewReader { proxy in
            #if os(macOS)
            macBody(review, groups: groups, proxy: proxy)
            #else
            phoneList(review, groups: groups)
                .lbScreenTitle("Proposals") {
                    Button {
                        Measure.used("how_it_works")
                        withAnimation(.snappy(duration: 0.25)) { showingHow.toggle() }
                    } label: {
                        Label("How It Works", systemImage: showingHow ? "info.circle.fill" : "info.circle")
                    }
                    .accessibilityHint(showingHow ? "Hides the explanation." : "Explains keeping, undoing and restoring.")
                    Button { Measure.used("history"); showingHistory = true } label: {
                        Label("History", systemImage: "clock.arrow.circlepath")
                    }
                    .accessibilityHint("Shows every kept version.")
                }
            #endif
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LBColor.canvas.color)
        .screenTutorial(.changes)
        .onAppear(perform: refresh)
        .measured("changes_showing_history", .sheet, when: showingHistory)
        .sheet(isPresented: $showingHistory) { historySheet }
        .measured("changes_editing", .sheet, when: editing != nil)
        .sheet(item: $editing) { target in
            editor(for: target)
        }
        // The Mac detail's Delete… asks here; a row's swipe or menu asks through its own action.
        .measured("changes_deleting", .alert, when: deleting != nil)
        .alert(deleting?.question ?? "Delete this row?",
               isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
               presenting: deleting) { target in
            Button("Delete", role: .destructive) { Measure.used("delete"); drop(target) }
            Button("Cancel", role: .cancel) { Measure.used("cancel") }
        } message: { target in
            Text(target.detail)
        }
        #if DEBUG
        .task { await seedReviewIfAsked() }
        #endif
    }

    private func refresh() {
        log = model.changeLog()
        diffs = [:]
        writers = [:]
        if Self.picturesArriving { expanded = Set(log.dropFirst().prefix(1).map(\.hash)) }
        // Open versions keep their tables; the newest outside ones name their writer
        // before they are opened.
        for entry in log where expanded.contains(entry.hash)
            || (entry.source == .outside && log.prefix(5).contains(where: { $0.hash == entry.hash })) {
            loadDiff(entry)
        }
        // A version that moved only bookkeeping — a Keep's review marks above all — stays
        // in the log and out of the list: its neighbours show the same rows.
        let versions = log
        // The list shows at once with what is already known; reading every old version to
        // judge the rest can take a while on a long history, and must never hold the list.
        let known = model.knownBookkeepingVersions()
        shown = versions.filter { !known.contains($0.hash) }
        historyReady = true
        Task {
            let hidden = await model.bookkeepingOnlyVersions()
            shown = versions.filter { !hidden.contains($0.hash) }
        }
    }

    private func loadDiff(_ entry: HistoryEntry) {
        guard diffs[entry.hash] == nil, let diff = model.diff(for: entry) else { return }
        diffs[entry.hash] = diff
        writers[entry.hash] = model.writers(for: entry)
    }

    /// A pull on the phone, a button on the Mac: the file re-read and the cloud queue fetched.
    private func refreshAll() async {
        model.load()
        await model.applyPendingWrites()
        refresh()
    }

    /// With a review waiting, the line names it and who wrote it; otherwise what the
    /// screen keeps.
    private func subtitle(_ review: Review?) -> String {
        guard let review else { return Self.howItWorks[0] }
        return "A proposal from \(writerName(review) ?? "your AI"). Keep or undo it."
    }

    /// The one outside hand that signed the pending rows; nil when none or several did.
    private func writerName(_ review: Review) -> String? {
        let ids = review.sections.flatMap { $0.added.map(\.firstId) + $0.removed.map(\.firstId) + $0.changed.map(\.id) }
        let names = Set(ids.compactMap { writer(of: $0, in: review.writers) })
            .filter { !$0.lowercased().hasPrefix("longbook") }
        return names.count == 1 ? names.first : nil
    }

    /// A charge is signed through its commitment: provenance is kept by row id.
    private func writer(of id: String, in writers: [String: String]) -> String? {
        writers[id] ?? writers[Self.commitmentKey(id)]
    }

    private static let howItWorks = [
        "Every version of your memory is kept. Review what changed, who wrote it, and bring any version back.",
        "Keep All adopts the proposal as it stands, on every device. Undo All writes the state before this proposal back, including anything you edited since.",
        rowHelp,
        "Restoring a version from history writes it back as a new change. Nothing is deleted.",
    ]

    #if os(macOS)
    private static let rowHelp = "Select a proposed row to see it in full, then edit or delete it before you keep the rest."
    #else
    private static let rowHelp = "Swipe a proposed row, or tap it, to edit or delete it before you keep the rest."
    #endif

    /// What the screen does, said once. The first line is the subtitle when nothing
    /// waits, so it is not said twice.
    private func howLines(pending: Bool) -> [String] {
        pending ? Self.howItWorks : Array(Self.howItWorks.dropFirst())
    }

    // MARK: the phone's list

    private func phoneList(_ review: Review?, groups: [LineGroup]) -> some View {
        List {
            SwiftUI.Section {
                if review != nil {
                    reviewActions(wide: true)
                        .tutorialTarget(.changesAll)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                }
            } header: {
                Text(subtitle(review))
                    .lbText(.bodySM)
                    .foregroundStyle(LBColor.textSecondary.color)
                    .textCase(nil)
                    .fixedSize(horizontal: false, vertical: true)
            } footer: {
                if let review { answerFooter(review) }
            }
            if showingHow {
                SwiftUI.Section {
                    ForEach(howLines(pending: review != nil), id: \.self) { line in
                        Text(line)
                            .lbText(.footnote)
                            .foregroundStyle(LBColor.textSecondary.color)
                            .fixedSize(horizontal: false, vertical: true)
                            .lbListRowBackground()
                    }
                } header: {
                    LBSectionHeader("How it works")
                }
            }
            if groups.count > 1 {
                SwiftUI.Section {
                    kindTabs(groups)
                        .tutorialTarget(.changesKinds)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                }
            }
            let first = shownGroups(groups).first?.lines.first?.id
            ForEach(shownGroups(groups)) { group in
                SwiftUI.Section {
                    ForEach(group.lines) { line in
                        phoneRow(line)
                            .tutorialTarget(line.id == first ? .changesFirst : nil)
                    }
                } header: {
                    LBSectionHeader(group.title)
                }
            }
            if model.proposalsHeldBack > 0 { heldBackSection }
            if !model.failedProposals.isEmpty { failedSection }
            if isQuiet(review, groups: groups) { emptySection }
        }
        .lbGroupedList()
        .refreshable { await refreshAll() }
    }

    /// One tab per kind with a line waiting, so hundreds of charges never bury one changed
    /// account. A row that does not fit scrolls sideways.
    private func kindTabs(_ groups: [LineGroup]) -> some View {
        let shown = shownGroups(groups).first?.kind
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: LBSpacing.s2) {
                ForEach(groups) { group in
                    ChangeKindTab(title: group.title, count: group.lines.count, selected: group.kind == shown) {
                        withAnimation(.snappy(duration: 0.25)) { pickedKind = group.kind }
                    }
                }
            }
            .padding(.vertical, LBSpacing.s1)
        }
    }

    /// The group in front: the picked kind while it has lines, else the first.
    private func shownGroups(_ groups: [LineGroup]) -> [LineGroup] {
        guard groups.count > 1 else { return groups }
        let kind = groups.contains { $0.kind == pickedKind } ? pickedKind : groups.first?.kind
        return groups.filter { $0.kind == kind }
    }

    /// A proposed row: a tap opens its editor; a swipe offers Edit and Delete.
    @ViewBuilder
    private func phoneRow(_ line: Line) -> some View {
        Group {
            if let edit = line.edit {
                Button(action: { Measure.used("edit"); edit() }) { lineRow(line) }
                    .lbButtonStyle()
                    .accessibilityHint("Opens this row to edit it.")
            } else {
                lineRow(line)
            }
        }
        .modifier(LineRowChrome(card: Self.isCard(line)))
        .lbRowActions(trailing: rowActions(line))
    }

    /// A charge or a commitment is the card every list wears; an account or a person a row.
    private static func isCard(_ line: Line) -> Bool {
        line.kind == "charges" || line.kind == "commitments"
    }

    private struct LineRowChrome: ViewModifier {
        let card: Bool
        func body(content: Content) -> some View {
            if card { content.lbCardRow() } else { content.lbListRowBackground() }
        }
    }

    /// Delete outermost, as a list puts it, asking first; Edit beside it.
    private func rowActions(_ line: Line) -> [LBRowAction] {
        var actions: [LBRowAction] = []
        if let target = line.delete {
            actions.append(.destructive(
                "Delete", confirm: .init(target.question, message: target.detail, button: "Delete")
            ) { drop(target) })
        }
        if let edit = line.edit {
            actions.append(LBRowAction("Edit", systemImage: "pencil", tint: LBColor.brand, run: edit))
        }
        return actions
    }

    /// A charge or a commitment as the card every list wears, the verb as its badge and
    /// its ink; an account or a person as a row: name, amount, and one line under it.
    @ViewBuilder
    private func lineRow(_ line: Line, selected: Bool = false) -> some View {
        if Self.isCard(line) {
            LBCommitmentRow(name: line.name, facts: line.facts, amount: line.amount ?? "",
                            ink: line.verb.ink, badge: line.verb == .added ? nil : (line.verb.word, line.verb.tone), selected: selected)
        } else {
            LBListRow(line.name, secondary: line.secondary, amount: line.amount) {
                if let mark = line.verb.mark {
                    Image(systemName: mark.symbol)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(mark.tint)
                        .accessibilityLabel(line.verb.word)
                }
            }
        }
    }

    // MARK: the Mac's split

    #if os(macOS)
    private func macBody(_ review: Review?, groups: [LineGroup], proxy: ScrollViewProxy) -> some View {
        let firstLine = groups.first?.lines.first?.id
        return VStack(spacing: 0) {
            macBar(review, proxy: proxy)
            Rectangle().fill(LBColor.hairline.color).frame(height: 1)
            macList(groups)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .lbInspector(isPresented: detailShown, width: 380) {
                    macDetail(review, groups: groups)
                        .background(LBColor.canvas.color)
                        .tutorialTarget(.changesDetail)
                }
        }
        .lbScreenTitle("Proposals", count: review == nil ? nil : groups.reduce(0) { $0 + $1.lines.count })
        .toolbar { macToolbar(review) }
        .onMacCommand(.refresh) { Task { await refreshAll() } }
        .onMacCommand(.history) { showingHistory = true }
        .onMacCommand(.howItWorks) { showingHow.toggle() }
        // The first proposed line is selected as the review arrives, so the right side is never blank.
        .task(id: firstLine) {
            if let firstLine, current(groups) == nil { selection = .line(firstLine) }
        }
        .onChange(of: selection) { _, picked in
            if case .version(let hash) = picked, let entry = shown.first(where: { $0.hash == hash }) { loadDiff(entry) }
        }
    }

    /// The screen's own bar: what is waiting on the left, the answers on the right. The
    /// tools sit in the window's toolbar.
    private func macBar(_ review: Review?, proxy: ScrollViewProxy) -> some View {
        HStack(alignment: .center, spacing: LBSpacing.s3) {
            VStack(alignment: .leading, spacing: 2) {
                Text(subtitle(review))
                    .lbText(.body)
                    .foregroundStyle(LBColor.textPrimary.color)
                if let review { answerFooter(review) }
            }
            Spacer(minLength: LBSpacing.s3)
            if review != nil { reviewActions(wide: false) }
        }
        .padding(.horizontal, LBSpacing.s4)
        .padding(.vertical, LBSpacing.s3)
    }

    /// The window's toolbar for this screen: Refresh, History and How It Works, each with
    /// a View menu command.
    @ToolbarContentBuilder
    private func macToolbar(_ review: Review?) -> some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
          ControlGroup {
            Button {
                Measure.used("refresh")
                Task { await refreshAll() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .help("Refresh: re-reads the file and fetches what your AI proposed")
            .accessibilityHint("Re-reads the file and fetches what your AI proposed.")
            Button { Measure.used("history"); showingHistory = true } label: {
                Label("History", systemImage: "clock.arrow.circlepath")
            }
            .help("History: every version kept, and Clear History")
            .accessibilityHint("Shows every kept version.")
            Button { Measure.used("how_it_works"); showingHow.toggle() } label: {
                Label("How It Works", systemImage: showingHow ? "info.circle.fill" : "info.circle")
            }
            .help("How It Works")
            .measured("changes_showing_how", .popover, when: showingHow)
            .popover(isPresented: $showingHow, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: LBSpacing.s2) {
                    ForEach(howLines(pending: review != nil), id: \.self) { line in
                        Text(line)
                            .lbText(.footnote)
                            .foregroundStyle(LBColor.textSecondary.color)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(LBSpacing.s4)
                .frame(width: 320)
            }
          }
        }
    }

    private var detailShown: Binding<Bool> {
        Binding(get: { selection != nil }, set: { if !$0 { selection = nil } })
    }

    private func macList(_ groups: [LineGroup]) -> some View {
        List {
            if groups.count > 1 {
                SwiftUI.Section {
                    kindTabs(groups)
                        .tutorialTarget(.changesKinds)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                }
            }
            let first = shownGroups(groups).first?.lines.first?.id
            ForEach(shownGroups(groups)) { group in
                SwiftUI.Section {
                    ForEach(group.lines) { line in
                        lineRow(line, selected: selection == .line(line.id))
                            .tutorialTarget(line.id == first ? .changesFirst : nil)
                            .lbHoverWash(Self.isCard(line) ? .label : .rounded(LBRadius.xs))
                            .lbKeyboardFocusable(radius: Self.isCard(line) ? LBRadius.md : LBRadius.xs) {
                                selection = .line(line.id)
                            }
                            .contentShape(Rectangle())
                            .onTapGesture { selection = .line(line.id) }
                            .modifier(LineRowChrome(card: Self.isCard(line)))
                            .lbRowActions(trailing: rowActions(line))
                    }
                } header: {
                    LBSectionHeader(group.title)
                }
            }
            if model.proposalsHeldBack > 0 { heldBackSection }
            if !model.failedProposals.isEmpty { failedSection }
            if isQuiet(nil, groups: groups) { emptySection }
        }
        .lbGroupedList()
    }

    /// The selection, or nil when it names a line or version that is no longer here.
    private func current(_ groups: [LineGroup]) -> Pick? {
        switch selection {
        case .line(let id): groups.contains { $0.lines.contains { $0.id == id } } ? selection : nil
        case .version(let hash): shown.contains { $0.hash == hash } ? selection : nil
        case nil: nil
        }
    }

    @ViewBuilder
    private func macDetail(_ review: Review?, groups: [LineGroup]) -> some View {
        switch current(groups) {
        case .line(let id):
            if let line = groups.lazy.flatMap(\.lines).first(where: { $0.id == id }) {
                lineDetail(line, writers: review?.writers ?? [:])
            }
        case .version(let hash):
            if let index = shown.firstIndex(where: { $0.hash == hash }) {
                versionDetail(shown[index], isCurrent: index == 0)
            }
        case nil:
            VStack(spacing: LBSpacing.s2) {
                Image(systemName: LBGlyph.change)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(LBColor.textQuaternary.color)
                    .accessibilityHidden(true)
                Text(review == nil ? "Select a version to see what it changed." : "Select a proposal to see it in full.")
                    .lbText(.bodySM)
                    .foregroundStyle(LBColor.textTertiary.color)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// One proposed line in full: everything the row leaves out, and its two actions.
    private func lineDetail(_ line: Line, writers: [String: String]) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LBSpacing.s4) {
                VStack(alignment: .leading, spacing: LBSpacing.s2) {
                    LBBadge("\(line.verb.word) · \(Self.kindNoun(line.kind, count: 1).capitalizedFirst)",
                            tone: line.verb == .removed ? .urgent : .brand)
                    Text(line.name)
                        .lbText(.title)
                        .foregroundStyle(LBColor.textPrimary.color)
                        .fixedSize(horizontal: false, vertical: true)
                    if let amount = line.amount {
                        LBAmount(amount, prominence: .stacked)
                            .foregroundStyle(LBColor.textPrimary.color)
                    }
                    if line.count > 1 {
                        Text("\(line.count) charges")
                            .lbText(.footnote)
                            .foregroundStyle(LBColor.textTertiary.color)
                    }
                }
                if !line.facts.isEmpty { LBMetaFacts(line.facts) }
                if let note = line.note {
                    Text(note)
                        .lbText(.body)
                        .foregroundStyle(LBColor.textSecondary.color)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
                if !line.lines.isEmpty {
                    LBCard {
                        VStack(alignment: .leading, spacing: LBSpacing.s2) {
                            ForEach(line.lines, id: \.self) { change in
                                Text(change)
                                    .lbText(.body)
                                    .foregroundStyle(LBColor.textPrimary.color)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                if let signer = writer(of: line.firstId, in: writers) {
                    LBMetaFacts([Self.writerMeta(signer)])
                }
                HStack(spacing: LBSpacing.s2) {
                    if let edit = line.edit {
                        Button(action: { Measure.used("edit"); edit() }) { capsule("Edit…", filled: true) }
                            .lbButtonStyle()
                    }
                    if let target = line.delete {
                        Button { Measure.used("delete"); deleting = target } label: { capsule("Delete…", filled: false, danger: true) }
                            .lbButtonStyle()
                    }
                }
                if line.edit == nil, line.delete == nil, line.verb == .removed {
                    Text("A removed row is no longer in the file, so only Undo All brings it back.")
                        .lbText(.footnote)
                        .foregroundStyle(LBColor.textTertiary.color)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(LBSpacing.s6)
            .frame(maxWidth: 640, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// A kept version in full: who and when, the road back, and every row it moved.
    private func versionDetail(_ entry: HistoryEntry, isCurrent: Bool) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LBSpacing.s4) {
                VStack(alignment: .leading, spacing: 2) {
                    if isCurrent { LBBadge("Current", tone: .brand) }
                    Text(sourceWord(entry))
                        .lbText(.title)
                        .foregroundStyle(LBColor.textPrimary.color)
                    Text(entry.at.formatted(date: .abbreviated, time: .shortened))
                        .lbText(.footnote)
                        .foregroundStyle(LBColor.textTertiary.color)
                }
                expandedBody(entry, isCurrent: isCurrent)
            }
            .padding(LBSpacing.s6)
            .frame(maxWidth: 640, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func capsule(_ title: String, filled: Bool, danger: Bool = false) -> some View {
        Text(title)
            .lbText(.label)
            .foregroundStyle(filled ? LBColor.onBrand.color : (danger ? LBColor.danger.color : LBColor.textSecondary.color))
            .padding(.horizontal, LBSpacing.s4)
            .frame(minHeight: 32)
            .background(filled ? LBColor.brand.color : LBColor.chrome.color, in: Capsule())
            .contentShape(Capsule())
    }
    #endif

    // MARK: editing before keeping

    /// A pending row and the editor that fits it: the commitment form, one charge, an
    /// account or a member.
    private enum EditTarget: Identifiable {
        case commitment(String)
        case charge(Charge)
        case account(id: String, name: String)
        case member(id: String, name: String)

        var id: String {
            switch self {
            case .commitment(let id): "commitment/\(id)"
            case .charge(let charge): "charge/\(charge.id)"
            case .account(let id, _): "account/\(id)"
            case .member(let id, _): "member/\(id)"
            }
        }
    }

    @ViewBuilder
    private func editor(for target: EditTarget) -> some View {
        switch target {
        case .commitment(let id):
            RenewalFormView(model: model, editingId: id) { editing = nil; refresh() }
        case .charge(let charge):
            RenewalFormView(model: model, editingId: charge.sub.id, chargeISO: charge.row.date) { editing = nil; refresh() }
                .lbThreeQuarterSheet()
        case .account(let id, let name):
            EntityEditView(model: model, kind: .paymentMethod, id: id, currentName: name) { editing = nil; refresh() }
        case .member(let id, let name):
            EntityEditView(model: model, kind: .familyMember, id: id, currentName: name) { editing = nil; refresh() }
        }
    }

    /// The editor a row opens, or nil for a kind without one. One charge of a commitment
    /// opens that charge; a folded plan, or a one-time commitment shown as its charge,
    /// opens the commitment.
    private func editTarget(kind: String, id: String, firstId: String, name: String, count: Int) -> EditTarget? {
        switch kind {
        case "commitments":
            return .commitment(id)
        case "charges":
            let parts = firstId.split(separator: "@", maxSplits: 1)
            if count == 1, parts.count == 2,
               let charge = model.charges(of: String(parts[0])).first(where: { $0.row.date == String(parts[1]) }) {
                return .charge(charge)
            }
            return .commitment(Self.commitmentKey(id))
        case "accounts":
            return .account(id: id, name: name)
        case "members":
            return .member(id: id, name: name)
        default:
            return nil
        }
    }

    /// Opens the row's editor, or nil for a kind without one. The target is found on the
    /// tap: a charge's lookup walks its commitment's rows.
    private func opener(kind: String, id: String, firstId: String, name: String, count: Int) -> (() -> Void)? {
        guard ["commitments", "charges", "accounts", "members"].contains(kind) else { return nil }
        return { editing = editTarget(kind: kind, id: id, firstId: firstId, name: name, count: count) }
    }

    // MARK: dropping one row before keeping

    /// One added row the owner asked to drop, with the words its confirmation says.
    private struct DeleteTarget {
        enum Row {
            case commitment(String)
            case charge(commitment: String, date: String)
            case plan(commitment: String, dates: [String])
            case account(String)
            case member(String)
        }

        let row: Row
        let question: String
        let detail: String
    }

    /// What Delete would drop, or nil where the model offers no single write for it: a
    /// category, or a changed or removed row.
    private func deleteTarget(kind: String, group: RowGroup, money: String?) -> DeleteTarget? {
        let rest = "The rest of this proposal stays for you to keep or undo."
        switch kind {
        case "commitments":
            return DeleteTarget(row: .commitment(group.id), question: "Delete \(group.name)?",
                                detail: "Its charges are removed with it. \(rest)")
        case "charges":
            let parts = Self.chargeParts(group.firstId)
            let detail = "\(group.name)\(money.map { ", \($0)" } ?? ""). Only this charge is removed. \(rest)"
            // A one-time commitment shown as its charge goes as one: the row and its day.
            if parts.count == 1 {
                return DeleteTarget(row: .commitment(group.id), question: "Delete this charge?", detail: detail)
            }
            guard group.count == 1 else {
                // A folded plan goes whole: every charge the card stands for, in one write.
                let dates = group.ids.compactMap { Self.chargeParts($0).last }.filter { !$0.isEmpty }
                guard parts.count == 2, dates.count == group.count else { return nil }
                return DeleteTarget(row: .plan(commitment: String(parts[0]), dates: dates),
                                    question: "Delete these \(group.count) charges?",
                                    detail: "\(group.name): all \(group.count) proposed charges are removed. \(rest)")
            }
            return DeleteTarget(row: .charge(commitment: String(parts[0]), date: String(parts[1])),
                                question: "Delete this charge?", detail: detail)
        case "accounts":
            return DeleteTarget(row: .account(group.id), question: "Delete \(group.name)?",
                                detail: Self.unhookWords(model.referenceCount(.paymentMethod, id: group.id), "account", "an account"))
        case "members":
            return DeleteTarget(row: .member(group.id), question: "Delete \(group.name)?",
                                detail: Self.unhookWords(model.referenceCount(.familyMember, id: group.id), "person", "a person"))
        default:
            return nil
        }
    }

    /// "commitment@day" split at the last "@": a day never holds one, an id from another
    /// hand might. One piece means a one-time commitment shown as its charge.
    private static func chargeParts(_ id: String) -> [String] {
        guard let at = id.lastIndex(of: "@") else { return [id] }
        return [String(id[..<at]), String(id[id.index(after: at)...])]
    }

    /// The count first, as the entity's own screen says it before a removal.
    private static func unhookWords(_ count: Int, _ word: String, _ without: String) -> String {
        count == 0
            ? "No commitment uses this \(word). Removing it changes nothing else."
            : "\(count) commitment\(count == 1 ? "" : "s") use\(count == 1 ? "s" : "") this \(word). They stay, without \(without)."
    }

    /// Each drop is one ordinary write. The review stays open on what is left.
    private func drop(_ target: DeleteTarget) {
        let done: Bool
        switch target.row {
        case .commitment(let id): done = model.deleteCommitment(id: id)
        case .charge(let id, let date): done = model.removeCharge(subscriptionId: id, dateISO: date)
        case .plan(let id, let dates): done = model.removeCharges(subscriptionId: id, datesISO: dates)
        case .account(let id): done = model.deleteEntity(.paymentMethod, id: id)
        case .member(let id): done = model.deleteEntity(.familyMember, id: id)
        }
        refusal = done ? nil : model.saveError
        // Nothing left to review: the review closes rather than standing open and empty.
        if done, model.reviewDiff().isEmpty {
            model.keepOutsideChange()
        }
        refresh()
    }

    #if DEBUG
    /// Snapshot harness: LONGBOOK_SNAPSHOT_ARRIVING opens the newest past version and
    /// pictures it as one iCloud still holds elsewhere.
    private static let picturesArriving = ProcessInfo.processInfo.environment["LONGBOOK_SNAPSHOT_ARRIVING"] != nil
    #else
    private static let picturesArriving = false
    #endif

    #if DEBUG
    @MainActor private static var reviewSeeded = false

    /// Snapshot harness: with LONGBOOK_SNAPSHOT_REVIEW set, one commitment signed "Claude"
    /// goes in through the outside door after the first load, so the review panel has
    /// something to show. Runs once per process. LONGBOOK_SNAPSHOT_REVIEW=usd seeds it in dollars.
    private func seedReviewIfAsked() async {
        guard let mode = ProcessInfo.processInfo.environment["LONGBOOK_SNAPSHOT_REVIEW"], !Self.reviewSeeded else { return }
        let usd = mode == "usd"
        let currency = usd ? "USD" : "INR"
        Self.reviewSeeded = true
        try? await Task.sleep(for: .milliseconds(600))
        guard let folder = model.vaultFolderURL else { return }
        let scoped = folder.startAccessingSecurityScopedResource()
        defer { if scoped { folder.stopAccessingSecurityScopedResource() } }
        let file = folder.appendingPathComponent(VaultReader.dataFile)
        guard let bytes = try? VaultReader.coordinatedRead(file),
              var next = (try? JSONSerialization.jsonObject(with: bytes)) as? [String: Any] else { return }
        let now = VaultPatch.iso8601(Date())
        var commitments = next["commitments"] as? [[String: Any]] ?? []
        var charges = next["charges"] as? [[String: Any]] ?? []
        var provenance = next["_provenance"] as? [String: Any] ?? [:]
        // One-time charges as a morning's mail gives them, then a plan, an account, a person.
        let spends: [(String, Double, String, String, String?)] = [
            ("City Marathon", usd ? 85 : 2500, "health & fitness", "2026-09-18", "Entry fee"),
            ("Corner Grocery", usd ? 38.4 : 385, "food & dining", "2026-09-20", nil),
            ("Home Services", usd ? 120 : 499, "home", "2026-09-18", "Electrician visit"),
            ("Cab ride", usd ? 18 : 120, "travel", "2026-09-18", "Paid in cash"),
        ]
        var firstSpend: String?
        for (name, amount, tag, day, note) in spends {
            let id = UUID().uuidString.lowercased()
            if firstSpend == nil { firstSpend = id }
            var row: [String: Any] = [
                "id": id, "name": name, "amount": amount, "currency": currency, "billing_cycle": "once",
                "tag": tag, "status": "active", "created_at": now, "updated_at": now,
            ]
            if let note { row["notes"] = note }
            commitments.append(row)
            charges.append([
                "commitment_id": id, "date": day, "amount": amount, "currency": currency,
                "paid": true, "paid_on": day, "basis": "email", "written_at": now,
            ])
            provenance[id] = ["edited_by": "Claude", "edited_at": now]
        }
        let plan = UUID().uuidString.lowercased()
        commitments.append([
            "id": plan, "name": "Netflix", "amount": usd ? 15.49 : 649.0, "currency": currency, "billing_cycle": "monthly",
            "tag": "streaming", "status": "active", "created_at": now, "updated_at": now,
        ])
        for day in ["2026-10-03", "2026-11-03", "2026-12-03"] {
            charges.append(["commitment_id": plan, "date": day, "amount": usd ? 15.49 : 649.0, "currency": currency,
                            "paid": false, "basis": "plan", "written_at": now])
        }
        provenance[plan] = ["edited_by": "Claude", "edited_at": now]
        let account = UUID().uuidString.lowercased(), person = UUID().uuidString.lowercased()
        next["accounts"] = (next["accounts"] as? [[String: Any]] ?? [])
            + [["id": account, "name": usd ? "Capital One 360" : "Fi Money", "name_key": usd ? "capital one 360" : "fi money", "tag": "bank account"]]
        next["members"] = (next["members"] as? [[String: Any]] ?? [])
            + [["id": person, "name": usd ? "Jordan" : "Ravikumar", "name_key": usd ? "jordan" : "ravikumar"]]
        provenance[account] = ["edited_by": "Claude", "edited_at": now]
        provenance[person] = ["edited_by": "Claude", "edited_at": now]
        next["commitments"] = commitments
        next["charges"] = charges
        next["_provenance"] = provenance
        try? VaultDisk.write(next, to: folder, expecting: bytes)
        model.load()
        refresh()
        // LONGBOOK_SNAPSHOT_DROP: one row dropped inside the review, as a Delete tap does, so
        // a second launch can show the rest still waiting.
        if ProcessInfo.processInfo.environment["LONGBOOK_SNAPSHOT_DROP"] != nil, let firstSpend {
            _ = model.deleteCommitment(id: firstSpend)
            refresh()
        }
    }
    #endif

    // MARK: suggestions that never landed

    /// Waiting, but this app may not write. Said plainly: the queue is intact, and the
    /// reason is one the owner can act on.
    /// Nothing waiting and nothing to report: the screen says so instead of standing blank.
    private func isQuiet(_ review: Review?, groups: [LineGroup]) -> Bool {
        model.outsideChangeFrom == nil && review == nil && groups.isEmpty
            && model.proposalsHeldBack == 0 && model.failedProposals.isEmpty
    }

    private var emptySection: some View {
        SwiftUI.Section {
            VStack(alignment: .leading, spacing: LBSpacing.s3) {
                HStack(spacing: LBSpacing.s3) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(LBColor.brandText.color)
                        .accessibilityHidden(true)
                    Text("Nothing to review")
                        .lbText(.headline)
                        .foregroundStyle(LBColor.textPrimary.color)
                }
                Text("When your AI or a statement writes to your longbook, the proposal waits here for you to keep or undo. Every version stays in History.")
                    .lbText(.bodySM)
                    .foregroundStyle(LBColor.textSecondary.color)
                    .fixedSize(horizontal: false, vertical: true)
                Button { Measure.used("clock_arrow_circlepath"); showingHistory = true } label: {
                    HStack(spacing: LBSpacing.s1) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 13, weight: .medium))
                        Text("Show History")
                            .lbText(.label)
                    }
                    .foregroundStyle(LBColor.brandText.color)
                    .contentShape(Rectangle())
                }
                .lbButtonStyle()
                .accessibilityHint("Shows every kept version.")
            }
            #if os(macOS)
            // The Mac's list has no card rows of its own: the note is a card at reading width.
            .padding(LBSpacing.s4)
            .frame(maxWidth: 560, alignment: .leading)
            .background(LBColor.card.color, in: RoundedRectangle(cornerRadius: LBRadius.lg, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: LBRadius.lg, style: .continuous).strokeBorder(LBColor.hairline.color, lineWidth: 1))
            .padding(LBSpacing.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
            #else
            .padding(.vertical, LBSpacing.s2)
            .lbListRowBackground()
            #endif
        }
    }

    private var heldBackSection: some View {
        SwiftUI.Section {
            Text("This account has no licence. \(model.proposalsHeldBack) suggestion\(model.proposalsHeldBack == 1 ? "" : "s") from your AI wait\(model.proposalsHeldBack == 1 ? "s" : "") until you buy longbook.")
                .lbText(.bodySM)
                .foregroundStyle(LBColor.textSecondary.color)
                .fixedSize(horizontal: false, vertical: true)
                .lbListRowBackground()
        } header: {
            LBSectionHeader("Waiting for you")
        }
    }

    /// The proposals this app tried and could not apply. Without this section they would
    /// vanish: the server stops counting them and the app never fetches them again.
    private var failedSection: some View {
        SwiftUI.Section {
            ForEach(model.failedProposals) { proposal in
                HStack(alignment: .top, spacing: LBSpacing.s2) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(proposalTitle(proposal))
                            .lbText(.bodySM)
                            .foregroundStyle(LBColor.textPrimary.color)
                        Text(proposal.failure ?? "No reason was recorded.")
                            .lbText(.footnote)
                            .foregroundStyle(LBColor.textSecondary.color)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("· \(proposal.author)\(proposal.sourceRef.map { " · \($0)" } ?? "")")
                            .lbText(.footnote)
                            .foregroundStyle(LBColor.textTertiary.color)
                    }
                    Spacer(minLength: LBSpacing.s2)
                    Button {
                        Measure.used("dismiss")
                        model.dismissFailedProposal(proposal.id)
                    } label: {
                        Text("Dismiss")
                            .lbText(.label)
                            .foregroundStyle(LBColor.textSecondary.color)
                            .padding(.horizontal, LBSpacing.s3)
                            .frame(minHeight: 28)
                            .background(LBColor.chrome.color, in: Capsule())
                            .contentShape(Capsule())
                    }
                    .lbButtonStyle()
                    .accessibilityLabel("Dismiss this suggestion")
                }
                .accessibilityElement(children: .combine)
                .lbListRowBackground()
            }
        } header: {
            LBSectionHeader("Couldn’t be applied")
        } footer: {
            Text("These suggestions could not be applied. Nothing was changed.")
                .lbText(.footnote)
                .foregroundStyle(LBColor.textTertiary.color)
        }
    }

    /// What the proposal was going to do, in the owner's words rather than a tool name.
    private func proposalTitle(_ proposal: PendingWrite) -> String {
        let name = (proposal.payload["name"] as? String)
            ?? ((proposal.payload["rows"] as? [[String: Any]])?.first?["name"] as? String)
            ?? (proposal.payload["module"] as? String)
        // A proposal that names its row by id alone is labelled with the name the memory holds.
        let byId = (proposal.payload["id"] as? String).flatMap { model.subscription(id: $0)?.name }
        switch proposal.kind {
        case "add_commitments":
            let count = (proposal.payload["rows"] as? [[String: Any]])?.count ?? 1
            return count > 1 ? "Add \(count) commitments" : "Add \(name ?? "a commitment")"
        case "update_commitment": return "Change \(name ?? "a commitment")"
        case "mark_paid": return "Mark \(name ?? "a commitment") paid"
        case "add_charges":
            let count = (proposal.payload["charges"] as? [[String: Any]])?.count ?? 1
            return "Write \(count) charge\(count == 1 ? "" : "s") for \(name ?? "a commitment")"
        case "remove_charges":
            let count = (proposal.payload["dates"] as? [String])?.count ?? 1
            return "Remove \(count) charge\(count == 1 ? "" : "s") from \(name ?? "a commitment")"
        case "promote_to_recurring": return "Make \(name ?? "these") one recurring commitment"
        case "cancel_commitment": return "Cancel \(name ?? "a commitment")"
        case "leave_insight": return "Leave a note on \(name ?? "a screen")"
        case "update_account": return name.map { "Update the account \($0)" } ?? "Update an account"
        case "update_person", "update_member": return name.map { "Update \($0)" } ?? "Update a person"
        case "update_charge":
            let day = (proposal.payload["date"] as? String).map { LB.parseDate($0).map(LB.longDate) ?? $0 } ?? "a day"
            return "Change the charge on \(day) for \(name ?? byId ?? "a commitment")"
        case "set_planned_count":
            let count = (proposal.payload["count"] as? NSNumber)?.intValue ?? 0
            return "Plan \(count) charge\(count == 1 ? "" : "s") for \(name ?? byId ?? "a commitment")"
        case "add_person", "add_member": return "Add \(name ?? "a person")"
        case "add_account": return name.map { "Add the account \($0)" } ?? "Add an account"
        case "rename_tag":
            let from = (proposal.payload["from"] as? String).map(categoryWord) ?? "a tag"
            return (proposal.payload["to"] as? String).map { "Rename the tag \(from) to \(categoryWord($0))" } ?? "Rename the tag \(from)"
        case "delete_tag": return name.map { "Delete the tag \(categoryWord($0))" } ?? "Delete a tag"
        case "delete_commitment": return "Delete \(byId ?? "a commitment")"
        case "create_report": return (proposal.payload["title"] as? String).map { "Draw the report \($0)" } ?? "Draw a report"
        default: return proposal.kind
        }
    }

    // MARK: pending review

    /// The outside edit awaiting the owner, folded: one section per kind in tab order,
    /// and who signed each row.
    private struct Review {
        let sections: [Section]
        let writers: [String: String]
    }

    // Commitments lead: what a statement found to repeat is the news; its charges follow.
    private static let tabOrder = ["commitments", "charges", "accounts", "members", "tags"]

    private func pendingReview() -> Review {
        let rank: (Section) -> Int = { Self.tabOrder.firstIndex(of: $0.kind) ?? Self.tabOrder.count }
        let shown = Self.sections(model.reviewDiff())
            .filter { !$0.added.isEmpty || !$0.removed.isEmpty || !$0.changed.isEmpty }
            .sorted { rank($0) < rank($1) }
        return Review(sections: shown, writers: pendingWriters())
    }

    /// Keep adopts the file as it stands; Undo writes the previous snapshot back as a new
    /// change. Both answer the whole change: the model keeps or undoes nothing smaller.
    private func reviewActions(wide: Bool) -> some View {
        LBReflowStack(spacing: LBSpacing.s2) {
            Button {
                Measure.used("undo_all")
                let done = model.revertOutsideChange()
                if done { Telemetry.shared.send("app.proposal_reviewed", ["decision": "undone"]) }
                settle(refused: done ? nil : model.saveError)
            } label: {
                ChangeActionLabel(title: "Undo All", symbol: "arrow.uturn.backward", filled: false, wide: wide)
            }
            .lbButtonStyle()
            .accessibilityHint("Writes the previous state back as a new change.")
            Button {
                Measure.used("keep_all")
                let done = model.keepOutsideChange()
                if done { Telemetry.shared.send("app.proposal_reviewed", ["decision": "kept"]) }
                settle(refused: done ? nil : model.saveError)
            } label: {
                ChangeActionLabel(title: "Keep All", symbol: "checkmark.circle.fill", filled: true, wide: wide)
            }
            .lbButtonStyle()
            .accessibilityHint("Adopts the proposal as it stands, on every device.")
        }
    }

    /// After an answer the review is gone, or still here with its refusal said.
    private func settle(refused: String?) {
        refusal = refused
        refresh()
    }

    /// What the change holds, and a refusal when an answer was refused.
    private func answerFooter(_ review: Review) -> some View {
        VStack(alignment: .leading, spacing: LBSpacing.s1) {
            Text(keepFootnote(review.sections))
                .lbText(.footnote)
                .foregroundStyle(LBColor.textTertiary.color)
                .fixedSize(horizontal: false, vertical: true)
            if let refusal {
                Text(refusal)
                    .lbText(.footnote)
                    .foregroundStyle(LBColor.urgent.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// What Keep All adopts, counted as the rows count: a folded plan is one line. Only
    /// additions read as the list alone, "5 charges, 1 commitment, 1 person"; a mix says
    /// which were added, changed and removed.
    private func keepFootnote(_ shown: [Section]) -> String {
        func counted(_ count: (Section) -> Int) -> String? {
            let parts = shown.compactMap { section -> String? in
                let n = count(section)
                return n > 0 ? "\(n) \(Self.kindNoun(section.kind, count: n))" : nil
            }
            return parts.isEmpty ? nil : parts.joined(separator: ", ")
        }
        let added = counted { $0.added.count }
        let changed = counted { Self.foldedChanges($0.changed, kind: $0.kind).count }
        let removed = counted { $0.removed.count }
        if let added, changed == nil, removed == nil { return added }
        let clauses = [
            added.map { "\($0) added" },
            changed.map { "\($0) changed" },
            removed.map { "\($0) removed" },
        ].compactMap { $0 }
        return clauses.isEmpty ? "Nothing changed" : clauses.joined(separator: " · ")
    }

    /// Writer names for the pending diff come from the file as it stands now.
    private func pendingWriters() -> [String: String] {
        guard let newest = log.first else { return [:] }
        return model.writers(for: newest)
    }

    // MARK: proposed lines

    /// Whether a line was added, changed or removed, with the mark a changed or removed one
    /// wears beside its name.
    private enum Verb {
        case added, changed, removed

        var word: String {
            switch self {
            case .added: "Added"
            case .changed: "Changed"
            case .removed: "Removed"
            }
        }

        var mark: (symbol: String, tint: Color)? {
            switch self {
            case .added: nil
            case .changed: ("pencil.circle", LBColor.textSecondary.color)
            case .removed: ("minus.circle", LBColor.danger.color)
            }
        }

        /// The card's edge and badge: what came in is the brand's, what changed is marked
        /// for attention, what went is the danger ink.
        var ink: LBColorValue {
            switch self {
            case .added: LBColor.brand
            case .changed: LBColor.attention
            case .removed: LBColor.danger
            }
        }

        var tone: LBBadgeTone {
            switch self {
            case .added: .positive
            case .changed: .brand
            case .removed: .urgent
            }
        }
    }

    /// One line of the review: the row's few words, and what the Mac's detail adds.
    private struct Line: Identifiable {
        let id: String
        let kind: String
        let verb: Verb
        let firstId: String
        let name: String
        let amount: String?
        let count: Int
        /// The day and the category, or what changed: the one line under the name.
        let secondary: String
        let note: String?
        let lines: [String]
        let facts: [LBMetaFact]
        let edit: (() -> Void)?
        let delete: DeleteTarget?
    }

    /// One kind's lines under its name.
    private struct LineGroup: Identifiable {
        let kind: String
        let title: String
        let lines: [Line]
        var id: String { kind }
    }

    /// The review in full — no truncation here, unlike the banner: a section per kind, added
    /// lines first, then changed, then removed.
    private func lineGroups(_ review: Review) -> [LineGroup] {
        review.sections.map { section in
            let lines = section.added.map { rowLine($0, kind: section.kind, verb: .added) }
                + Self.foldedChanges(section.changed, kind: section.kind).map { changeLine($0, kind: section.kind) }
                + section.removed.map { rowLine($0, kind: section.kind, verb: .removed) }
            return LineGroup(kind: section.kind, title: Self.kindWord(section.kind), lines: lines)
        }
    }

    /// An added or removed line. Only an added one can be edited or dropped: a removed
    /// row is no longer in the file to write to.
    private func rowLine(_ group: RowGroup, kind: String, verb: Verb) -> Line {
        let added = verb == .added
        let money = group.amount.map { fmtMoney($0, group.currency ?? "") }
        let about: (detail: String?, facts: [LBMetaFact]) = added
            ? context(kind: kind, id: group.id, firstId: group.firstId, count: group.count)
            : (nil, [])
        let facts = Self.strip(group.facts, about.facts)
        return Line(
            id: "\(kind)/\(verb.word)/\(group.id)", kind: kind, verb: verb, firstId: group.firstId, name: group.name,
            amount: money, count: group.count,
            secondary: Self.secondary(facts, count: group.count, fallback: about.detail),
            note: about.detail, lines: [], facts: facts,
            edit: added ? opener(kind: kind, id: group.id, firstId: group.firstId, name: group.name, count: group.count) : nil,
            delete: added ? deleteTarget(kind: kind, group: group, money: money) : nil
        )
    }

    /// A changed line: each field as before → after. It opens the same editor; taking
    /// one row's change back is a write the model does not offer.
    private func changeLine(_ group: ChangeGroup, kind: String) -> Line {
        let span = group.span.map { [LBMetaFact(symbol: LBGlyph.date, text: $0)] } ?? []
        // The changed row is still in the file, so its detail wears the same strip as an added one.
        let about = context(kind: kind, id: group.id, firstId: group.firstId, count: group.count)
        let counted = group.count > 1 ? ["\(group.count) charges"] + (group.span.map { [$0] } ?? []) : []
        return Line(
            id: "\(kind)/changed/\(group.id)", kind: kind, verb: .changed, firstId: group.firstId, name: group.name,
            amount: nil, count: group.count, secondary: (counted + group.lines).joined(separator: " · "),
            note: about.detail, lines: group.lines, facts: Self.strip(span, about.facts),
            edit: opener(kind: kind, id: group.id, firstId: group.firstId, name: group.name, count: group.count),
            delete: nil
        )
    }

    /// "18 Sep 2026 · Health & fitness", or "3 charges · Oct–Dec 2026 · Streaming" for a plan;
    /// the row's own words when it has no day or category, as a person's email.
    private static func secondary(_ facts: [LBMetaFact], count: Int, fallback: String?) -> String {
        let day = facts.first { $0.symbol == LBGlyph.date }?.text
        let category = facts.first { $0.symbol == LBGlyph.category }?.text
        let parts = (count > 1 ? ["\(count) charges"] : []) + [day, category].compactMap { $0 }
        return parts.isEmpty ? (fallback ?? "") : parts.joined(separator: " · ")
    }

    /// A changed charge folds by commitment, so a section's lines are counted folded.
    private static func lineCount(_ section: Section) -> Int {
        section.added.count + section.removed.count + foldedChanges(section.changed, kind: section.kind).count
    }

    /// Every line the review would show for a diff, folded as the sections count them: a plan
    /// is one line, a one-time commitment and its charge are one. The notice counts by this.
    static func foldedLineCount(_ diff: [EntityDiff]) -> Int {
        sections(diff).reduce(0) { $0 + lineCount($1) }
    }

    /// The diff's facts and the file's on one line: the day first, then what the diff
    /// says, then the links. The file's category stands in for the diff's, never beside it.
    private static func strip(_ own: [LBMetaFact], _ about: [LBMetaFact]) -> [LBMetaFact] {
        let day = about.filter { $0.symbol == LBGlyph.date }
        let links = about.filter { $0.symbol != LBGlyph.date }
        return day + own.filter { links.isEmpty || $0.symbol != LBGlyph.category } + links
    }

    /// What the file says about a row beyond the diff: its note, then the strip every list
    /// wears (day, category, member, account, placeholders where empty); an account's type;
    /// a member's address. A removed row is gone from the file and gets nothing here.
    private func context(kind: String, id: String, firstId: String, count: Int) -> (detail: String?, facts: [LBMetaFact]) {
        switch kind {
        case "commitments", "charges":
            let key = Self.commitmentKey(id)
            guard let sub = model.subscription(id: key) else { return (nil, []) }
            let parts = firstId.split(separator: "@", maxSplits: 1)
            // One charge of a standing commitment says its own note before the commitment's.
            let own = count == 1 && parts.count == 2
                ? model.charges(of: key).first { $0.row.date == String(parts[1]) }?.row.note
                : nil
            let note = (own ?? sub.notes)?.trimmingCharacters(in: .whitespacesAndNewlines)
            // The "Add member" and "Add account" prompts belong to the lists; a review shows
            // only what the row already says.
            var facts = model.linkFacts(sub).filter { !$0.placeholder }
            // A standing commitment says when it next comes round, as the list does; a
            // charge's day is already in the diff.
            if kind == "commitments", case .loaded(let data) = model.state,
               let day = data.commitments.first(where: { $0.id == key })?.facts.first(where: { $0.symbol == LBGlyph.date }) {
                facts.insert(day, at: 0)
            }
            return (note.flatMap { $0.isEmpty ? nil : $0 }, facts)
        case "accounts":
            let tag = model.entityDetails(.paymentMethod, id: id).accountTag
            return (nil, tag.map { [LBMetaFact(symbol: LBGlyph.category, text: $0)] } ?? [])
        case "members":
            return (model.entityDetails(.familyMember, id: id).email, [])
        default:
            return (nil, [])
        }
    }

    // MARK: history

    /// Every kept version in a sheet of its own: a tap opens one (the phone unfolds it in
    /// place, the Mac shows it in the preview), and Clear History at the foot takes them
    /// all away — after two questions, with the room it frees named.
    private var historySheet: some View {
        VStack(spacing: 0) {
            HStack(spacing: LBSpacing.s2) {
                Text("History")
                    .lbText(.headline)
                    .foregroundStyle(LBColor.textPrimary.color)
                Spacer()
                Button("Done") { Measure.used("done"); showingHistory = false }
                    .lbButtonStyle()
                    .lbText(.body)
                    .foregroundStyle(LBColor.brandText.color)
                    .keyboardShortcut(.cancelAction)
            }
            .padding(LBSpacing.s4)
            List {
                SwiftUI.Section {
                    if shown.isEmpty {
                        Text(historyArriving ? "Downloading your kept versions from iCloud…"
                             : historyReady ? "No versions yet. The first save creates one." : "Reading the kept versions…")
                            .lbText(.bodySM)
                            .foregroundStyle(LBColor.textTertiary.color)
                            .lbListRowBackground()
                    } else {
                        ForEach(Array(shown.enumerated()), id: \.element.hash) { index, entry in
                            #if os(macOS)
                            versionLabel(entry, isCurrent: index == 0)
                                .lbHoverWash(.rounded(LBRadius.xs))
                                .lbKeyboardFocusable(radius: LBRadius.xs) {
                                    selection = .version(entry.hash); showingHistory = false
                                }
                                .contentShape(Rectangle())
                                .onTapGesture { selection = .version(entry.hash); showingHistory = false }
                                .lbListRowBackground()
                            #else
                            entryRow(entry, isCurrent: index == 0)
                                .lbListRowBackground()
                            #endif
                        }
                    }
                } footer: {
                    if !shown.isEmpty { historyFooter }
                }
                if !shown.isEmpty {
                    SwiftUI.Section {
                        Button(role: .destructive) { Measure.used("clear_history"); clearingHistory = true } label: {
                            Text("Clear History…")
                                .lbText(.body)
                                .foregroundStyle(LBColor.danger.color)
                                .frame(maxWidth: .infinity, minHeight: 36)
                                .contentShape(Rectangle())
                        }
                        .lbButtonStyle()
                        .lbListRowBackground()
                    } footer: {
                        Text("Clearing frees \(historySizeWords) on this device and in your longbook folder. It cannot be undone.")
                            .lbText(.footnote)
                            .foregroundStyle(LBColor.textTertiary.color)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .lbGroupedList()
        }
        .background(LBColor.canvas.color)
        #if os(macOS)
        .frame(width: 480, height: 560)
        #endif
        // Read again on opening; a log iCloud still holds elsewhere is fetched first.
        .task { await openHistory() }
        .measured("changes_clearing_history", .dialog, when: clearingHistory)
        .confirmationDialog("Clear \(shown.count) kept version\(shown.count == 1 ? "" : "s")?", isPresented: $clearingHistory, titleVisibility: .visible) {
            Button("Clear", role: .destructive) { Measure.used("clear_history_confirm"); clearingHistoryAgain = true }
            Button("Keep", role: .cancel) { Measure.used("keep") }
        } message: {
            Text("Frees \(historySizeWords). Your longbook itself is not touched, but no earlier version can be restored afterwards.")
        }
        .measured("changes_clearing_history_again", .alert, when: clearingHistoryAgain)
        .alert("Are you sure?", isPresented: $clearingHistoryAgain) {
            Button("Clear History", role: .destructive) { Measure.used("clear_history"); clearHistory() }
            Button("Keep", role: .cancel) { Measure.used("keep") }
        } message: {
            Text("The kept versions are gone for good. This cannot be undone.")
        }
    }

    private func openHistory() async {
        refresh()
        guard let folder = model.vaultFolderURL, VaultHistory.awaitingLog(in: folder) else { return }
        historyArriving = true
        try? await VaultHistory.materializeLog(in: folder)
        historyArriving = false
        refresh()
    }

    private var historySizeWords: String {
        guard let folder = model.vaultFolderURL else { return "nothing" }
        return ByteCountFormatter.string(fromByteCount: Int64(VaultHistory.size(in: folder)), countStyle: .file)
    }

    private func clearHistory() {
        guard let folder = model.vaultFolderURL else { return }
        VaultHistory.clear(in: folder)
        log = []
        shown = []
        diffs = [:]
        expanded = []
        if case .version = selection { selection = nil }
        showingHistory = false
    }

    private var historySection: some View {
        SwiftUI.Section {
            if shown.isEmpty {
                if historyReady {
                    Text("No versions yet. The first save creates one.")
                        .lbText(.bodySM)
                        .foregroundStyle(LBColor.textTertiary.color)
                        .lbListRowBackground()
                        .id(Self.historyAnchor)
                }
            } else {
                ForEach(Array(shown.enumerated()), id: \.element.hash) { index, entry in
                    entryRow(entry, isCurrent: index == 0)
                        .lbListRowBackground()
                        .id(index == 0 ? Self.historyAnchor : entry.hash)
                }
            }
        } header: {
            LBSectionHeader("History")
        } footer: {
            if !shown.isEmpty { historyFooter }
        }
    }

    private var historyFooter: some View {
        Text("The last \(VaultHistory.kept) versions are kept.")
            .lbText(.footnote)
            .foregroundStyle(LBColor.textTertiary.color)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// Who wrote a version and when; the phone's row opens in place to show what it changed.
    private func versionLabel(_ entry: HistoryEntry, isCurrent: Bool) -> some View {
        HStack(spacing: LBSpacing.s2) {
            Image(systemName: entry.source == .ours ? LBGlyph.owner : LBGlyph.ai)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(entry.source == .ours ? LBColor.textTertiary.color : LBColor.attention.color)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(sourceWord(entry))
                    .lbText(.bodySM)
                    .foregroundStyle(LBColor.textPrimary.color)
                Text(entry.at.formatted(date: .abbreviated, time: .shortened))
                    .lbText(.footnote)
                    .foregroundStyle(LBColor.textTertiary.color)
            }
            Spacer(minLength: LBSpacing.s2)
            if isCurrent {
                Text("Current")
                    .lbText(.footnote)
                    .foregroundStyle(LBColor.brandText.color)
            }
        }
        .padding(.vertical, LBSpacing.s1)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func entryRow(_ entry: HistoryEntry, isCurrent: Bool) -> some View {
        VStack(alignment: .leading, spacing: LBSpacing.s2) {
            Button {
                Measure.used("toggle_version")
                toggle(entry)
            } label: {
                HStack(spacing: LBSpacing.s2) {
                    versionLabel(entry, isCurrent: isCurrent)
                    Image(systemName: expanded.contains(entry.hash) ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(LBColor.textQuaternary.color)
                        .accessibilityHidden(true)
                }
                .contentShape(Rectangle())
            }
            .lbButtonStyle()
            .accessibilityLabel("\(sourceWord(entry)), \(entry.at.formatted(date: .abbreviated, time: .shortened))")
            .accessibilityHint(expanded.contains(entry.hash) ? "Collapses this version." : "Shows what this version changed.")

            if expanded.contains(entry.hash) {
                expandedBody(entry, isCurrent: isCurrent)
                    .padding(.bottom, LBSpacing.s2)
            }
        }
    }

    @ViewBuilder
    private func expandedBody(_ entry: HistoryEntry, isCurrent: Bool) -> some View {
        VStack(alignment: .leading, spacing: LBSpacing.s3) {
            if !isCurrent {
                restoreButton(entry)
                if let restoreRefusal, restoreRefusal.hash == entry.hash {
                    Text(restoreRefusal.words)
                        .lbText(.footnote)
                        .foregroundStyle(LBColor.urgent.color)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            // A version iCloud still holds elsewhere has no story yet; it is never waited for.
            if Self.picturesArriving || model.isArriving(entry) {
                Text("Still coming down from iCloud")
                    .lbText(.footnote)
                    .foregroundStyle(LBColor.textTertiary.color)
            } else if let diff = diffs[entry.hash] {
                if diff.isEmpty {
                    Text("Only bookkeeping moved. No row changed.")
                        .lbText(.footnote)
                        .foregroundStyle(LBColor.textTertiary.color)
                } else {
                    diffTables(diff, writers: writers[entry.hash] ?? [:])
                }
            } else {
                Text("The first version. Everything in it is new.")
                    .lbText(.footnote)
                    .foregroundStyle(LBColor.textTertiary.color)
            }
        }
    }

    @ViewBuilder
    private func restoreButton(_ entry: HistoryEntry) -> some View {
        Button {
            Measure.used("restore")
            confirmingRestore = entry.hash
        } label: {
            Text("Restore…")
                .lbText(.label)
                .foregroundStyle(LBColor.textSecondary.color)
                .padding(.horizontal, LBSpacing.s3)
                .frame(minHeight: 32)
                .background(LBColor.chrome.color, in: Capsule())
                .contentShape(Capsule())
        }
        .lbButtonStyle()
        .accessibilityHint("Writes this version back as a new change. Nothing is lost.")
        .measured("changes_confirming_restore", .dialog, when: confirmingRestore == entry.hash)
        .confirmationDialog(
            "Restore the version from \(entry.at.formatted(date: .abbreviated, time: .shortened))?",
            isPresented: Binding(
                get: { confirmingRestore == entry.hash },
                set: { if !$0 { confirmingRestore = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Restore", role: .destructive) {
                Measure.used("restore")
                confirmingRestore = nil
                if model.restore(hash: entry.hash) {
                    restoreRefusal = nil
                    refresh()
                } else {
                    restoreRefusal = model.saveError.map { RowRefusal(hash: entry.hash, words: $0) }
                }
            }
            Button("Cancel", role: .cancel) { Measure.used("cancel") }
        } message: {
            Text("Your memory returns to that version, written back as a new change. Nothing is deleted.")
        }
    }

    private func toggle(_ entry: HistoryEntry) {
        if expanded.contains(entry.hash) {
            expanded.remove(entry.hash)
            return
        }
        loadDiff(entry)
        expanded.insert(entry.hash)
    }

    /// "You, in the app", or the outside hand by name once the version is open and its
    /// rows say who signed them.
    private func sourceWord(_ entry: HistoryEntry) -> String {
        guard entry.source != .ours else { return "You, in the app" }
        guard let diff = diffs[entry.hash], let signed = writers[entry.hash] else { return "Outside edit" }
        let ids = diff.flatMap { $0.added.map(\.id) + $0.removed.map(\.id) + $0.changed.map(\.id) }
        let names = Array(Set(ids.compactMap { signed[$0] ?? signed[Self.commitmentKey($0)] })).sorted()
        return names.isEmpty ? "Outside edit" : names.joined(separator: ", ")
    }

    // MARK: diff rendering

    /// The full tables — every row, every field, nothing truncated. The banner's
    /// four-row cut does not apply here; this screen exists to show it all.
    private func diffTables(_ diff: [EntityDiff], writers: [String: String]) -> some View {
        VStack(alignment: .leading, spacing: LBSpacing.s3) {
            ForEach(Self.sections(diff), id: \.kind) { entity in
                VStack(alignment: .leading, spacing: LBSpacing.s1) {
                    Text(Self.kindWord(entity.kind))
                        .lbText(.eyebrow)
                        .foregroundStyle(LBColor.textTertiary.color)
                    ForEach(entity.added) { group in
                        groupLine("plus.circle", LBColor.brandText.color, group, "added", writers[group.firstId])
                    }
                    ForEach(entity.removed) { group in
                        groupLine("minus.circle", LBColor.danger.color, group, "removed", writers[group.firstId])
                    }
                    ForEach(Self.foldedChanges(entity.changed, kind: entity.kind)) { group in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: LBSpacing.s2) {
                                diffLine("pencil.circle", LBColor.textSecondary.color, group.name, writers[group.firstId])
                                if group.count > 1 { ChangeCountPill(count: group.count) }
                            }
                            if let span = group.span {
                                LBMetaFacts([LBMetaFact(symbol: LBGlyph.date, text: span)])
                                    .padding(.leading, LBSpacing.s4)
                            }
                            ForEach(group.lines, id: \.self) { line in
                                Text(line)
                                    .lbText(.footnote)
                                    .foregroundStyle(LBColor.textTertiary.color)
                                    .padding(.leading, LBSpacing.s4)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }
        }
    }

    /// A kind's name as a section heading reads it, in sentence case.
    private static func kindWord(_ kind: String) -> String {
        switch kind {
        case "commitments": "Commitments"
        case "accounts": "Accounts"
        case "members": "People"
        case "tags": "Categories"
        case "charges": "Charges"
        default: kind
        }
    }

    /// And inside a sentence, counted: "1 category", "12 charges".
    private static func kindNoun(_ kind: String, count: Int) -> String {
        let one = count == 1
        switch kind {
        case "commitments": return one ? "commitment" : "commitments"
        case "accounts": return one ? "account" : "accounts"
        case "members": return one ? "person" : "people"
        case "tags": return one ? "category" : "categories"
        case "charges": return one ? "charge" : "charges"
        default: return kind
        }
    }

    /// One kind's story, already folded: a one-time commitment and its single charge are
    /// one charge, said once under Charges; recurring commitments stay commitments.
    private struct Section {
        let kind: String
        let added: [RowGroup]
        let removed: [RowGroup]
        let changed: [RowChange]
    }

    private static func sections(_ diff: [EntityDiff]) -> [Section] {
        let commitments = diff.first { $0.kind == "commitments" }
        let charges = diff.first { $0.kind == "charges" }
        let onceAdded = (commitments?.added ?? []).filter { $0.cycle == "One-time" }
        let onceRemoved = (commitments?.removed ?? []).filter { $0.cycle == "One-time" }
        let onceIds = Set((onceAdded + onceRemoved).map(\.id))
        // A one-time commitment's charge names its day and its paid state.
        func chargeOf(_ id: String, in rows: [RowRef]) -> RowRef? {
            rows.first { Self.commitmentKey($0.id) == id }
        }
        func asCharge(_ row: RowRef, among rows: [RowRef]) -> RowGroup {
            let charge = chargeOf(row.id, in: rows)
            let day = charge.flatMap { Self.dayPart($0.name) }.map(Self.dayWord)
            let facts = charge == nil
                ? Self.facts(cycle: row.cycle, tag: row.tag, moves: row)
                : Self.facts(tag: row.tag, paid: charge?.paid, day: day, moves: row)
            return RowGroup(id: row.id, firstId: row.id, name: row.name, count: 1, amount: row.amount,
                            currency: row.currency, facts: facts)
        }
        var out: [Section] = []
        for entity in diff {
            switch entity.kind {
            case "commitments":
                let added = folded(entity.added.filter { !onceIds.contains($0.id) }, kind: entity.kind)
                let removed = folded(entity.removed.filter { !onceIds.contains($0.id) }, kind: entity.kind)
                if !added.isEmpty || !removed.isEmpty || !entity.changed.isEmpty {
                    out.append(Section(kind: entity.kind, added: added, removed: removed, changed: entity.changed))
                }
            case "charges":
                let added = onceAdded.map { asCharge($0, among: entity.added) }
                    + folded(entity.added.filter { !onceIds.contains(Self.commitmentKey($0.id)) }, kind: entity.kind)
                let removed = onceRemoved.map { asCharge($0, among: entity.removed) }
                    + folded(entity.removed.filter { !onceIds.contains(Self.commitmentKey($0.id)) }, kind: entity.kind)
                out.append(Section(kind: entity.kind, added: added, removed: removed, changed: entity.changed))
            default:
                out.append(Section(kind: entity.kind, added: folded(entity.added, kind: entity.kind),
                                   removed: folded(entity.removed, kind: entity.kind), changed: entity.changed))
            }
        }
        if charges == nil, !onceIds.isEmpty {
            out.append(Section(kind: "charges", added: onceAdded.map { asCharge($0, among: []) },
                               removed: onceRemoved.map { asCharge($0, among: []) }, changed: []))
        }
        return out
    }

    /// Rows of one commitment, folded: a plan of 24 charges is one thing written, and reads
    /// as one line with a count and the days it spans.
    private struct RowGroup: Identifiable {
        let id: String
        let firstId: String
        let name: String
        let count: Int
        let amount: Double?
        let currency: String?
        let facts: [LBMetaFact]
        /// Every row the card stands for; a folded plan holds one id a charge.
        var ids: [String] = []
    }

    /// The facts a row wears under its name, each with the glyph its kind wears everywhere.
    /// A transfer or money in says so, as it does on the dashboard and in the lists, so a
    /// proposal is never mistaken for spending before it is kept.
    private static func facts(
        cycle: String? = nil, tag: String? = nil, paid: String? = nil, day: String? = nil, span: String? = nil,
        moves row: RowRef? = nil
    ) -> [LBMetaFact] {
        [
            span.map { LBMetaFact(symbol: LBGlyph.date, text: $0) },
            day.map { LBMetaFact(symbol: LBGlyph.date, text: $0) },
            paid.map { LBMetaFact(symbol: $0.hasPrefix("Paid") ? LBGlyph.paid : LBGlyph.unpaid, text: $0) },
            row?.directionWord.map { LBMetaFact(symbol: row?.direction == "in" ? LBGlyph.income : LBGlyph.transfer, text: $0) },
            cycle.map { LBMetaFact(symbol: LBGlyph.cycle, text: $0) },
            tag.map { LBMetaFact(symbol: LBGlyph.category, text: categoryWord($0)) },
        ].compactMap { $0 }
    }

    private static func folded(_ rows: [RowRef], kind: String) -> [RowGroup] {
        guard kind == "charges" else {
            return rows.map { RowGroup(id: $0.id, firstId: $0.id, name: $0.name, count: 1, amount: $0.amount,
                                       currency: $0.currency, facts: Self.facts(cycle: $0.cycle, tag: $0.tag, moves: $0)) }
        }
        var order: [String] = []
        var members: [String: [RowRef]] = [:]
        for row in rows {
            let key = Self.commitmentKey(row.id)
            if members[key] == nil { order.append(key) }
            members[key, default: []].append(row)
        }
        return order.compactMap { key in
            guard let list = members[key], let first = list.first else { return nil }
            let days = list.compactMap { Self.dayPart($0.name) }.sorted()
            let amounts = Set(list.map { $0.amount ?? -1 })
            let paids = Set(list.compactMap(\.paid))
            let span = Self.spanWord(days)
            return RowGroup(id: key, firstId: first.id, name: Self.namePart(first.name), count: list.count,
                            amount: amounts.count == 1 ? first.amount : nil, currency: first.currency,
                            facts: Self.facts(paid: paids.count == 1 ? paids.first : nil, span: span, moves: first),
                            ids: list.map(\.id))
        }
    }

    /// Changed rows folded like added ones: the days a multi-row group spans, then each
    /// field as before → after.
    private struct ChangeGroup: Identifiable {
        let id: String
        let firstId: String
        let name: String
        let count: Int
        let span: String?
        let lines: [String]
    }

    private static func foldedChanges(_ rows: [RowChange], kind: String) -> [ChangeGroup] {
        let lines: (RowChange) -> [String] = { row in
            row.fields.flatMap { fieldLines($0) }
        }
        guard kind == "charges" else {
            return rows.map { ChangeGroup(id: $0.id, firstId: $0.id, name: $0.name, count: 1, span: nil, lines: lines($0)) }
        }
        var order: [String] = []
        var members: [String: [RowChange]] = [:]
        for row in rows {
            let key = Self.commitmentKey(row.id)
            if members[key] == nil { order.append(key) }
            members[key, default: []].append(row)
        }
        return order.compactMap { key in
            guard let list = members[key], let first = list.first else { return nil }
            let same = list.allSatisfy { lines($0) == lines(first) }
            let days = list.compactMap { Self.dayPart($0.name) }.sorted()
            let span = Self.spanWord(days)
            let shown = same ? lines(first) : ["\(list.count) charges changed in different ways"]
            return ChangeGroup(id: key, firstId: first.id, name: list.count == 1 ? first.name : Self.namePart(first.name),
                               count: list.count, span: list.count > 1 ? span : nil, lines: shown)
        }
    }

    /// A charge's id is "commitment@day"; its name "Name — day".
    private static func commitmentKey(_ id: String) -> String {
        String(id.split(separator: "@", maxSplits: 1).first ?? Substring(id))
    }

    private static func namePart(_ name: String) -> String {
        name.components(separatedBy: " — ").first ?? name
    }

    private static func dayPart(_ name: String) -> String? {
        let parts = name.components(separatedBy: " — ")
        return parts.count > 1 ? parts[parts.count - 1] : nil
    }

    private static func dayWord(_ iso: String) -> String {
        LB.parseDate(iso).map(LB.longDate) ?? iso
    }

    /// The days a folded plan covers, by month: "Oct–Dec 2026", "Dec 2026–Feb 2027"; one
    /// month reads "3–20 Oct 2026", one day as its date. Days come sorted, as ISO strings.
    private static func spanWord(_ days: [String]) -> String? {
        guard let firstISO = days.first, let lastISO = days.last else { return nil }
        guard days.count > 1, let first = LB.parseDate(firstISO), let last = LB.parseDate(lastISO) else {
            return dayWord(firstISO)
        }
        let calendar = LB.calendar
        let month = Date.FormatStyle().month(.abbreviated)
        let year = Date.FormatStyle().year()
        if calendar.isDate(first, equalTo: last, toGranularity: .month) {
            if calendar.isDate(first, inSameDayAs: last) { return dayWord(firstISO) }
            let day = Date.FormatStyle().day()
            return "\(first.formatted(day))–\(last.formatted(day)) \(last.formatted(month)) \(last.formatted(year))"
        }
        if calendar.isDate(first, equalTo: last, toGranularity: .year) {
            return "\(first.formatted(month))–\(last.formatted(month)) \(last.formatted(year))"
        }
        return "\(first.formatted(month)) \(first.formatted(year))–\(last.formatted(month)) \(last.formatted(year))"
    }

    /// Who signed the row: the app's own stamp reads as the owner, any other name as the AI.
    private static func writerMeta(_ writer: String) -> LBMetaFact {
        let ours = writer.lowercased().hasPrefix("longbook")
        return LBMetaFact(symbol: ours ? LBGlyph.owner : LBGlyph.ai, text: ours ? "You" : writer)
    }

    private func writerFact(_ writer: String) -> some View {
        LBMetaFacts([Self.writerMeta(writer)])
    }

    /// One folded group's line: the name, the count when more than one, the money when
    /// every row carries the same, and its facts beneath.
    private func groupLine(_ symbol: String, _ tint: Color, _ group: RowGroup, _ verb: String, _ writer: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: LBSpacing.s2) {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(tint)
                    .accessibilityHidden(true)
                Text("\(group.name) — \(verb)")
                    .lbText(.bodySM)
                    .foregroundStyle(LBColor.textPrimary.color)
                if group.count > 1 { ChangeCountPill(count: group.count) }
                if let writer { writerFact(writer) }
                Spacer(minLength: LBSpacing.s2)
                if let amount = group.amount {
                    LBAmount(fmtMoney(amount, group.currency ?? ""), prominence: .inline)
                        .foregroundStyle(LBColor.textPrimary.color)
                        .lineLimit(1)
                }
            }
            if !group.facts.isEmpty {
                LBMetaFacts(group.facts)
                    .padding(.leading, LBSpacing.s4)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// A row's line, with the money on the right and its note beneath — what a reviewer
    /// needs to judge an added or removed row before keeping it.
    private func diffLine(
        _ symbol: String, _ tint: Color, _ text: String, _ writer: String?, row: RowRef? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: LBSpacing.s2) {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(tint)
                    .accessibilityHidden(true)
                Text(text)
                    .lbText(.bodySM)
                    .foregroundStyle(LBColor.textPrimary.color)
                if let writer { writerFact(writer) }
                Spacer(minLength: LBSpacing.s2)
                if let row, let amount = row.amount {
                    LBAmount(fmtMoney(amount, row.currency ?? ""), prominence: .inline)
                        .foregroundStyle(LBColor.textPrimary.color)
                        .lineLimit(1)
                }
            }
            if let row {
                let facts = Self.facts(cycle: row.cycle, tag: row.tag, paid: row.paid, moves: row)
                if !facts.isEmpty {
                    LBMetaFacts(facts)
                        .padding(.leading, LBSpacing.s4)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// The vault's field keys in the reader's words; an unknown key stays as written.
    private static func fieldWord(_ key: String) -> String {
        fieldWords[key] ?? key
    }

    private static let fieldWords: [String: String] = [
        "name": "Name", "amount": "Amount", "currency": "Currency", "billing_cycle": "Cycle",
        "custom_cycle_days": "Every N days", "tag": "Category", "details": "Details", "notes": "Notes",
        "member_id": "Person", "account_id": "Account", "status": "Status", "ends_on": "Ends on", "free_trial": "Free trial",
        "date": "Date", "paid": "Paid", "paid_on": "Paid on", "basis": "Basis", "note": "Note",
        "nickname": "Nickname", "institution": "Institution", "last4": "Last four", "icon": "Icon",
        "parent_account_id": "Linked account", "direction": "Direction", "details.card_name": "Card name",
    ]

    /// One field as "Word: before → after". A direction reads as the form names it, and
    /// `details` opens into its own keys so a card name is never shown as JSON.
    private static func fieldLines(_ field: FieldChange) -> [String] {
        // The core opens `details` and words each value as a detail row reads elsewhere:
        // "yes" or "no", a list joined. Here each key only gets its name.
        if let parts = detailChanges(field) {
            return parts.map { "\(detailWord($0.key)): \($0.before) → \($0.after)" }
        }
        let value: (String) -> String = { field.key == "direction" ? directionWord($0) : $0 }
        return ["\(fieldWord(field.key)): \(value(field.before)) → \(value(field.after))"]
    }

    /// Absent, "out" or anything unknown is money out, exactly as the arithmetic reads it.
    private static func directionWord(_ raw: String) -> String {
        switch raw {
        case "in": "Money in"
        case "transfer": "Transfer"
        default: "Money out"
        }
    }

    /// "details.card_name" in words: the app's own when it has one, else the key in
    /// sentence case, "Due day".
    private static func detailWord(_ key: String) -> String {
        fieldWords[key] ?? String(key.dropFirst("details.".count)).replacingOccurrences(of: "_", with: " ").capitalizedFirst
    }
}

extension String {
    /// "due day" → "Due day": sentence case for a key the app has no word for, and for a
    /// writer's name as the review notice says it.
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
