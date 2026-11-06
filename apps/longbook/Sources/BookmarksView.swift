import DesignSystem
import LongbookCore
import SwiftUI

/// One bookmarked card: what it opens, and its card as its own screen draws it.
struct BookmarkEntry: Identifiable {
    let ref: CardRef
    /// The stored bookmark Remove Bookmark takes away.
    let savedId: String
    let card: (_ selected: Bool) -> LBKindCard
    var id: CardRef { ref }
}

/// One kind's bookmarks under its name and count: "Commitments · 2".
struct BookmarkSection: Identifiable {
    let kind: SearchKind
    let entries: [BookmarkEntry]
    var title: String { "\(kind.title) · \(entries.count)" }
    var id: SearchKind { kind }
}

/// Every bookmark in the workspace, grouped by kind in the sidebar's order. A Bookmark on a
/// charge saves its commitment, so commitments are what the workspace holds.
@MainActor
enum BookmarkSections {
    static func of(_ model: DashboardModel, matching query: String = "") -> [BookmarkSection] {
        guard case .loaded(let data) = model.state else { return [] }
        let saved = data.commitments.filter { model.bookmarks.contains($0.id) }
        var entries: [SearchEntry] = []
        var drawn: [String: BookmarkEntry] = [:]
        for item in saved {
            let entry = SearchEntry(kind: .commitments, id: item.id, name: item.name,
                                    words: [item.searchText, item.amountText, item.amountExact])
            entries.append(entry)
            drawn[entry.key] = BookmarkEntry(ref: .commitment(id: item.id), savedId: item.id) { selected in
                KindCards.card(item, photo: model.commitmentPhotoURL(id: item.id), selected: selected)
            }
        }
        let typed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if typed.isEmpty {
            let groups = Dictionary(grouping: entries, by: \.kind)
            return SearchKind.allCases.compactMap { kind in
                guard let found = groups[kind], !found.isEmpty else { return nil }
                return BookmarkSection(kind: kind, entries: found.compactMap { drawn[$0.key] })
            }
        }
        return GlobalSearch.search(typed, in: entries, perKind: .max).map { group in
            BookmarkSection(kind: group.kind, entries: group.hits.compactMap { drawn[$0.key] })
        }
    }

    static let emptyWords = "Nothing bookmarked yet. Bookmark a card from its ••• menu or a swipe."

    static func narrowedWords(_ query: String) -> String {
        "No bookmarks match “\(query.trimmingCharacters(in: .whitespacesAndNewlines))”."
    }
}

/// Everything bookmarked, from every screen, in one list: a section per kind, each card the one
/// its own screen shows. On the Mac a click shows its Preview in the side panel; on iPhone a
/// tap opens it.
struct BookmarksView: View {
    let model: DashboardModel

    static let title = "Bookmarks"
    static let definition = "Everything you bookmarked, from every screen, in one list."

    @State private var search = ""
    #if os(macOS)
    @State private var selection: CardRef?
    /// A card opened from inside the Preview, read there in place of the chosen one.
    @State private var inspected: CardRef?
    /// The card whose Edit form stands in the panel, and how many times it was asked to close.
    @State private var formCard: CardRef?
    /// The field a Preview row opened Edit on.
    @State private var formFocus: EditFocus?
    @State private var formCloseAsked = 0
    #endif

    var body: some View {
        let all = BookmarkSections.of(model)
        let sections = search.isEmpty ? all : BookmarkSections.of(model, matching: search)
        #if os(macOS)
        macBody(all: all, sections: sections)
        #else
        phoneBody(all: all, sections: sections)
        #endif
    }

    private func definitionLine() -> some View {
        Text(Self.definition)
            .lbText(.footnote)
            .foregroundStyle(LBColor.textTertiary.color)
            .lineLimit(2)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func emptyLine(all: [BookmarkSection]) -> some View {
        Text(all.isEmpty ? BookmarkSections.emptyWords : BookmarkSections.narrowedWords(search))
            .lbText(.footnote)
            .foregroundStyle(LBColor.textSecondary.color)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func removeAction(_ entry: BookmarkEntry) -> LBRowAction {
        LBRowAction("Remove Bookmark", systemImage: "bookmark.slash", tint: LBColor.textSecondary) {
            Measure.used("remove_bookmark")
            model.toggleBookmark(entry.savedId)
        }
    }

    #if os(iOS)
    private func phoneBody(all: [BookmarkSection], sections: [BookmarkSection]) -> some View {
        List {
            VStack(alignment: .leading, spacing: LBSpacing.s3) {
                definitionLine()
                ListSearchField(text: $search, prompt: "Search bookmarks")
                if sections.isEmpty { emptyLine(all: all) }
            }
            .lbCardRow()
            ForEach(sections) { section in
                Section {
                    ForEach(section.entries) { entry in
                        CardListLink(destination: entry.ref.destination) { entry.card(false) }
                            .lbCardRow()
                            .lbRowActions(leading: [removeAction(entry)])
                    }
                } header: {
                    LBSectionHeader(section.title)
                }
            }
        }
        .lbCardList()
        .scrollDismissesKeyboard(.immediately)
        .lbScreenTitle(Self.title)
    }
    #endif

    #if os(macOS)
    private func macBody(all: [BookmarkSection], sections: [BookmarkSection]) -> some View {
        let shown = sections.flatMap(\.entries)
        return VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: LBSpacing.s3) {
                LBPageTitle(Self.title)
                definitionLine()
                ListSearchField(text: $search, prompt: "Search bookmarks")
                    .lbBesidePanel(true)
            }
            .padding(.horizontal, LBSpacing.s4)
            .padding(.top, LBSpacing.s6)
            .frame(height: SidePanel.line, alignment: .top)
            Group {
                if sections.isEmpty {
                    emptyLine(all: all)
                        .padding(LBSpacing.s4)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                } else {
                    List {
                        ForEach(sections) { section in
                            Section {
                                ForEach(section.entries) { entry in
                                    macCard(entry)
                                        .lbCardRow()
                                }
                            } header: {
                                LBSectionHeader(section.title)
                            }
                        }
                    }
                    .lbGroupedList()
                    .lbKeyboardFocusEffects()
                }
            }
            .lbSidePanel(isPresented: panelShown) { panel }
            // A chosen card that has left the list, unbookmarked or searched away, closes its Preview.
            .onChange(of: model.isLoaded && formCard == nil && selection.map { ref in !shown.contains { $0.ref == ref } } == true) { _, gone in
                if gone { selection = nil }
            }
            .onChange(of: selection) { _, _ in inspected = nil }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LBColor.canvas.color)
        #if DEBUG
        .onAppear {
            let env = ProcessInfo.processInfo.environment
            if selection == nil, env["LONGBOOK_SNAPSHOT_OPEN"] == "first" { selection = shown.first?.ref }
        }
        #endif
    }

    /// The panel stands open on this screen: the chosen card's Preview, or a line saying how to choose one.
    private var panelShown: Binding<Bool> {
        Binding(get: { true }, set: { if !$0 { selection = nil; formCard = nil } })
    }

    @ViewBuilder
    private var panel: some View {
        if let formCard {
            CardEditForm(model: model, card: formCard, inPanel: true, closeAsked: formCloseAsked, focus: formFocus,
                         onDeleted: { selection = nil; inspected = nil },
                         onMoved: { day in inspected = formCard.moved(to: day); self.formCard = nil }) { self.formCard = nil }
                .id(formCard)
        } else if let selection {
            let shown = inspected ?? selection
            CardPreviewView(model: model, card: shown, onClose: { self.selection = nil }, open: { inspected = $0 },
                            onEdit: { field in formFocus = field; formCard = shown })
                .id(shown)
        } else {
            Text("Select a bookmark to see it here.")
                .lbText(.body)
                .foregroundStyle(LBColor.textTertiary.color)
                .multilineTextAlignment(.center)
                .padding(LBSpacing.s4)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// A click chooses the card and shows its Preview; a right click offers Remove Bookmark.
    private func macCard(_ entry: BookmarkEntry) -> some View {
        let choose = {
            PanelForm.shared.ask {
                formCard = nil
                selection = entry.ref
                inspected = nil
            }
        }
        return entry.card(selection == entry.ref)
            .lbHoverWash()
            .lbKeyboardFocusable(radius: LBRadius.md) { choose() }
            .contentShape(Rectangle())
            .onTapGesture { Measure.used("bookmark_card"); choose() }
            .lbRowActions(leading: [removeAction(entry)])
    }
    #endif
}

#if os(iOS)
/// The phone's Search screen, the first row of Settings: before typing, the bookmarked cards and the recent searches; with
/// typing, the results grouped by kind, each its kind's card, a tap opening its Preview.
struct SearchScreen: View {
    let model: DashboardModel
    @Binding var path: [Destination]
    @State private var center = SearchCenter.shared
    @State private var reading: HelpArticle?

    var body: some View {
        let typed = center.query.trimmingCharacters(in: .whitespacesAndNewlines)
        List {
            ListSearchField(text: $center.query, prompt: "Commitments, charges, people…")
                .onSubmit { center.remember(typed) }
                .lbCardRow()
            if typed.isEmpty {
                idle
            } else {
                results(typed)
            }
        }
        .lbCardList()
        .scrollDismissesKeyboard(.immediately)
        .lbScreenTitle("Search")
        .measured("search_reading_article", .sheet, when: reading != nil)
        .sheet(item: $reading) { article in
            HelpArticleView(article: article) { reading = nil }
                .lbKeyboardFocusEffects()
        }
    }

    /// Before typing: the bookmarked cards, then the last few searches, each running again on a tap.
    @ViewBuilder
    private var idle: some View {
        let sections = BookmarkSections.of(model)
        Section {
            if sections.isEmpty {
                Text(BookmarkSections.emptyWords)
                    .lbText(.footnote)
                    .foregroundStyle(LBColor.textSecondary.color)
                    .fixedSize(horizontal: false, vertical: true)
                    .lbCardRow()
            }
            ForEach(sections.flatMap(\.entries)) { entry in
                CardListLink(destination: entry.ref.destination) { entry.card(false) }
                    .lbCardRow()
            }
        } header: {
            LBSectionHeader(BookmarksView.title)
        }
        if !center.recent.isEmpty {
            Section {
                ForEach(center.recent, id: \.self) { words in
                    Button {
                        Measure.used("search_recent")
                        center.query = words
                        center.remember(words)
                    } label: {
                        HStack(spacing: LBSpacing.s3) {
                            Image(systemName: "clock.arrow.circlepath")
                                .foregroundStyle(LBColor.textTertiary.color)
                                .accessibilityHidden(true)
                            Text(words)
                                .lbText(.body)
                                .foregroundStyle(LBColor.textPrimary.color)
                            Spacer(minLength: 0)
                        }
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .lbCardRow()
                }
            } header: {
                LBSectionHeader("Recent")
            }
        }
    }

    @ViewBuilder
    private func results(_ typed: String) -> some View {
        let results = center.results(model)
        if results.groups.isEmpty {
            Text("Nothing matches “\(typed)”.")
                .lbText(.footnote)
                .foregroundStyle(LBColor.textSecondary.color)
                .lbCardRow()
        }
        ForEach(results.groups, id: \.kind) { group in
            Section {
                ForEach(group.hits, id: \.key) { entry in
                    if let item = results.items[entry.key] {
                        Button {
                            Measure.used("search_result")
                            open(item, typed)
                        } label: {
                            searchCard(item, model: model)
                        }
                        .lbCardButtonStyle()
                        .lbCardRow()
                    }
                }
                if let words = group.showAllWords {
                    Button {
                        Measure.used("search_show_all")
                        showAll(group.kind, typed)
                    } label: {
                        Text(words)
                            .lbText(.body)
                            .foregroundStyle(LBColor.brandText.color)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .lbCardRow()
                }
            } header: {
                LBSectionHeader(group.kind.title)
            }
        }
    }

    private func open(_ item: SearchItem, _ typed: String) {
        center.remember(typed)
        switch item.target {
        case .card(let ref): path.append(ref.destination)
        case .proposals: path.append(.changes)
        case .help(let slug): reading = HelpArticle.named(slug)
        }
    }

    private func showAll(_ kind: SearchKind, _ typed: String) {
        center.remember(typed)
        let screen = SearchIndex.screen(for: kind)
        if let name = screen.name { center.hand(typed, to: name) }
        path.append(screen.destination)
    }
}
#endif
