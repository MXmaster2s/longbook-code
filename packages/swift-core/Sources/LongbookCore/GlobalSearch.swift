// One search across the whole longbook: every kind's rows, Proposals and the help articles,
// matched and ranked on the device. Nothing here reads the vault; the app hands it the words.
import Foundation

/// What a search finds, in the Mac sidebar's order.
public enum SearchKind: String, CaseIterable, Sendable {
    case accounts, commitments, charges, earnings, transfers, people, proposals, help

    /// The heading its results sit under.
    public var title: String {
        switch self {
        case .accounts: "Accounts"
        case .commitments: "Commitments"
        case .charges: "Charges"
        case .earnings: "Earnings"
        case .transfers: "Transfers"
        case .people: "People"
        case .proposals: "Proposals"
        case .help: "Help"
        }
    }

    /// The noun a count of them takes: "12 charges", "1 charge".
    public func noun(_ count: Int) -> String {
        let one = count == 1
        switch self {
        case .accounts: return one ? "account" : "accounts"
        case .commitments: return one ? "commitment" : "commitments"
        case .charges: return one ? "charge" : "charges"
        case .earnings: return one ? "earning" : "earnings"
        case .transfers: return one ? "transfer" : "transfers"
        case .people: return one ? "person" : "people"
        case .proposals: return one ? "proposal" : "proposals"
        case .help: return one ? "help article" : "help articles"
        }
    }
}

/// One thing a search can find: its name, and the other words that find it, such as account
/// and person names, a category, notes, a statement line and amounts.
public struct SearchEntry: Hashable, Sendable {
    public let kind: SearchKind
    public let id: String
    public let name: String
    let foldedName: String
    let foldedAll: String

    public init(kind: SearchKind, id: String, name: String, words: [String?]) {
        self.kind = kind
        self.id = id
        self.name = name
        foldedName = GlobalSearch.fold(name)
        foldedAll = GlobalSearch.fold(([name] + words).compactMap { $0 }.joined(separator: " "))
    }

    /// The key an app keeps what it draws under: unique across kinds.
    public var key: String { "\(kind.rawValue)/\(id)" }
}

/// One kind's results: the first few, and how many matched in all.
public struct SearchGroup: Equatable, Sendable {
    public let kind: SearchKind
    public let hits: [SearchEntry]
    public let total: Int

    /// "Show all 12 charges" while more matched than are shown; nil when every one is.
    public var showAllWords: String? {
        total > hits.count ? "Show all \(total) \(kind.noun(total))" : nil
    }
}

/// A row of the results as the keyboard moves through them: a result, or a kind's Show all.
public enum SearchRow: Equatable, Sendable {
    case hit(SearchEntry)
    case showAll(SearchKind, total: Int)
}

public enum GlobalSearch {
    /// How many results a kind shows before its Show all.
    public static let perKind = 5

    /// The text as a search compares it: no case, no accents, one space between words.
    public static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    /// How well an entry answers: 0 its name is the query, 1 its name starts with it, 2 a word
    /// of its name does, 3 its name holds every word, 4 its other words do. Nil when a word is missing.
    static func rank(_ entry: SearchEntry, phrase: String, words: [Substring]) -> Int? {
        guard words.allSatisfy({ entry.foldedAll.contains($0) }) else { return nil }
        if entry.foldedName == phrase { return 0 }
        if entry.foldedName.hasPrefix(phrase) { return 1 }
        if entry.foldedName.contains(" " + phrase) { return 2 }
        if words.allSatisfy({ entry.foldedName.contains($0) }) { return 3 }
        return 4
    }

    /// The query's results, one group per kind that matched, in `SearchKind` order. Within a
    /// kind the best answers lead and ties keep the order the entries came in.
    public static func search(_ query: String, in entries: [SearchEntry], perKind: Int = perKind) -> [SearchGroup] {
        let phrase = fold(query)
        guard !phrase.isEmpty else { return [] }
        let words = phrase.split(separator: " ")
        var ranked: [SearchKind: [(rank: Int, order: Int, entry: SearchEntry)]] = [:]
        for (order, entry) in entries.enumerated() {
            guard let rank = rank(entry, phrase: phrase, words: words) else { continue }
            ranked[entry.kind, default: []].append((rank, order, entry))
        }
        return SearchKind.allCases.compactMap { kind in
            guard let found = ranked[kind], !found.isEmpty else { return nil }
            let sorted = found.sorted { ($0.rank, $0.order) < ($1.rank, $1.order) }
            return SearchGroup(kind: kind, hits: sorted.prefix(max(perKind, 0)).map(\.entry), total: sorted.count)
        }
    }

    /// The rows the results show, top to bottom: each kind's results, then its Show all.
    public static func rows(_ groups: [SearchGroup]) -> [SearchRow] {
        groups.flatMap { group in
            group.hits.map(SearchRow.hit) + (group.showAllWords == nil ? [] : [.showAll(group.kind, total: group.total)])
        }
    }

    /// The highlighted row after ↑ or ↓: it stops at either end, and a list of none has none.
    public static func moved(_ index: Int, by step: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return min(max(index + step, 0), count - 1)
    }

    /// The recent searches with `query` put first: kept once, newest first, at most `limit`.
    public static func remembering(_ query: String, in recent: [String], limit: Int = 6) -> [String] {
        let typed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !typed.isEmpty else { return recent }
        let folded = fold(typed)
        return Array(([typed] + recent.filter { fold($0) != folded }).prefix(max(limit, 0)))
    }
}
