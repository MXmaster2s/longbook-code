// Report.swift — a report the user's AI wrote into the vault's reports folder,
// following the vault's own conventions: snake_case, ISO days, an amount is a number
// WITH its currency. A module this version doesn't know renders as unknown, never
// dropped — the file may be newer than the app.

import Foundation

public struct Report: Codable, Identifiable {
    public let version: Int
    public let id: String
    public var title: String
    public var subtitle: String?
    public var createdAt: String?      // ISO YYYY-MM-DD
    /// The calendar month the report covers, `YYYY-MM`. Optional: a file written without
    /// one still reads, and its month is derived from the transactions it lists.
    public var period: String?
    /// The first and last day covered, ISO. A month file may name only `period`; its days
    /// are then the month's.
    public var startDate: String?
    public var endDate: String?
    /// What the report was drawn over. Absent or empty means every account, member and category.
    public var scope: ReportScope?
    /// Charges the owner dropped from the report for good: in no figure and on no list.
    public var hiddenIds: [String]?
    /// The default scope for modules that don't declare their own.
    public var currency: String?
    public var modules: [ReportModule]

    enum CodingKeys: String, CodingKey {
        case version, id, title, subtitle
        case createdAt = "created_at"
        case period
        case startDate = "start_date"
        case endDate = "end_date"
        case scope
        case hiddenIds = "hidden_ids"
        case currency, modules
    }
}

/// The narrowing a report was drawn with: names, as the owner wrote them. A list left out
/// or empty means all of that kind.
public struct ReportScope: Codable, Equatable {
    public var accounts: [String]
    public var members: [String]
    public var categories: [String]

    public init(accounts: [String] = [], members: [String] = [], categories: [String] = []) {
        self.accounts = accounts
        self.members = members
        self.categories = categories
    }

    public init(from decoder: Decoder) throws {
        let keyed = try decoder.container(keyedBy: CodingKeys.self)
        accounts = try keyed.decodeIfPresent([String].self, forKey: .accounts) ?? []
        members = try keyed.decodeIfPresent([String].self, forKey: .members) ?? []
        categories = try keyed.decodeIfPresent([String].self, forKey: .categories) ?? []
    }

    public var isEmpty: Bool { accounts.isEmpty && members.isEmpty && categories.isEmpty }
}

/// The days a report covers, and the words for them.
public extension Report {
    /// The file's own start and end, else the days of the month `period` names.
    var range: (start: Date, end: Date)? {
        if let start = LB.parseDate(startDate), let end = LB.parseDate(endDate), start <= end {
            return (start, end)
        }
        guard let key = periodKey, let first = LB.parseDate(key + "-01") else { return nil }
        return (first, LB.addDays(LB.addMonths(first, 1), -1))
    }

    /// "1 October 2026", "1–30 September 2026", "28 September – 3 October 2026",
    /// "30 December 2025 – 2 January 2026".
    var rangeName: String? {
        range.map { Report.rangeWords(start: $0.start, end: $0.end) }
    }

    /// The words for any two days, as a report names its own.
    static func rangeWords(start: Date, end: Date) -> String {
        let calendar = LB.calendar
        let month = DateFormatter()
        month.calendar = calendar
        month.dateFormat = "MMMM"
        let day = { (date: Date) in String(calendar.component(.day, from: date)) }
        let year = { (date: Date) in String(calendar.component(.year, from: date)) }
        let sameYear = year(start) == year(end)
        let sameMonth = sameYear && month.string(from: start) == month.string(from: end)
        if start == end { return "\(day(start)) \(month.string(from: start)) \(year(start))" }
        if sameMonth { return "\(day(start))–\(day(end)) \(month.string(from: start)) \(year(start))" }
        if sameYear { return "\(day(start)) \(month.string(from: start)) – \(day(end)) \(month.string(from: end)) \(year(end))" }
        return "\(day(start)) \(month.string(from: start)) \(year(start)) – \(day(end)) \(month.string(from: end)) \(year(end))"
    }

    /// The scope in one line, "Accounts: HDFC, Cash · Members: Rohit", or nil when it is everything.
    var scopeLine: String? {
        guard let scope, !scope.isEmpty else { return nil }
        let parts = [("Accounts", scope.accounts), ("Members", scope.members), ("Categories", scope.categories.map(categoryWord))]
            .filter { !$0.1.isEmpty }
            .map { "\($0.0): \($0.1.joined(separator: ", "))" }
        return parts.joined(separator: " · ")
    }

    /// The rows the report lists as charges, and the ones taken out of it.
    var chargeRows: (kept: [ReportRow], removed: [ReportRow]) {
        for module in modules {
            guard case .transactions(let list) = module, list.title == MonthlyReport.Titles.charges else { continue }
            return (list.rows.filter { $0.removed != true }, list.rows.filter { $0.removed == true })
        }
        return ([], [])
    }

    /// The ids of the rows taken out, so a redraw keeps them out.
    var removedIds: Set<String> {
        Set(chargeRows.removed.compactMap(\.id))
    }

    /// A span of days longbook drew itself — a trip, or one an AI asked for — as opposed to a
    /// calendar month (`period` set) or a file someone else wrote. Redrawn from its own days.
    var isDrawnSpan: Bool {
        subtitle == MonthlyReport.subtitle && period == nil
            && LB.parseDate(startDate) != nil && LB.parseDate(endDate) != nil
    }

    /// A trip: a drawn span made from Settings → Trips.
    var isTrip: Bool { isDrawnSpan && id.hasPrefix(MonthlyReport.tripPrefix + "-") }

    /// The first money stat, as the list names the report's size.
    var totalStat: ReportStat? {
        for module in modules {
            guard case .stats(let stats) = module else { continue }
            if let money = stats.stats.first(where: { $0.amount != nil && $0.currency != nil }) { return money }
        }
        return nil
    }
}

/// A report covers one calendar month, and that month is what names it on screen and
/// what orders the list. `created_at` is the day the file was written — a different
/// fact, and never a substitute.
public extension Report {
    /// The month covered, as `YYYY-MM`: the file's own `period` when well-formed, else
    /// the single month every dated transaction row falls in. Nil when neither settles
    /// it, because an invented month is a claim the report never made.
    var periodKey: String? {
        if let stated = period.flatMap(Report.monthKey) { return stated }
        var months: Set<String> = []
        for module in modules {
            guard case .transactions(let list) = module else { continue }
            for row in list.rows {
                guard let day = LB.parseDate(row.date) else { continue }
                months.insert(String(LB.toISO(day).prefix(7)))
            }
        }
        return months.count == 1 ? months.first : nil
    }

    /// "July 2026" — the covered month in the app's own month style.
    var periodName: String? {
        periodKey.flatMap { LB.parseDate($0 + "-01") }.map { LB.monthYear($0) }
    }

    /// The day the file was written, named as that. Shown where no month could be
    /// derived, so an authoring date is never dressed up as the period.
    var writtenNote: String? {
        LB.parseDate(createdAt).map { "Written \(LB.longDate($0))" }
    }

    /// `YYYY-MM` with a month that exists. Held to the vault's own day parser, so a
    /// month key is read against the same calendar as every other date.
    private static func monthKey(_ value: String) -> String? {
        guard value.count == 7, let day = LB.parseDate(value + "-01"),
              LB.toISO(day).hasPrefix(value)
        else { return nil }
        return value
    }
}

/// One labelled amount inside a report — never a bare number.
public struct ReportAmount: Codable {
    public var amount: Double
    public var currency: String
}

public struct ReportStat: Codable {
    public var label: String
    public var amount: Double?
    public var currency: String?
    /// Free-text alternative for a stat that isn't money ("32 commitments").
    public var value: String?
    public var deltaPct: Double?
    /// Whether the delta is good news — a spend rising and an income rising point the
    /// same way but mean opposite things, so the file says which.
    public var deltaIsGood: Bool?
    /// What the delta is against, "vs August"; the file says, the screen never guesses.
    public var deltaLabel: String?

    enum CodingKeys: String, CodingKey {
        case label, amount, currency, value
        case deltaPct = "delta_pct"
        case deltaIsGood = "delta_is_good"
        case deltaLabel = "delta_label"
    }

    public init(label: String, amount: Double? = nil, currency: String? = nil, value: String? = nil,
                deltaPct: Double? = nil, deltaIsGood: Bool? = nil, deltaLabel: String? = nil) {
        self.label = label
        self.amount = amount
        self.currency = currency
        self.value = value
        self.deltaPct = deltaPct
        self.deltaIsGood = deltaIsGood
        self.deltaLabel = deltaLabel
    }
}

public struct ReportSlice: Codable {
    public var label: String
    public var amount: Double
    public var currency: String
}

public struct ReportBar: Codable {
    public var label: String
    public var amount: Double
}

public struct ReportRow: Codable {
    /// The charge behind the row, as the vault names it, so a row taken out stays out of a
    /// redraw. A file written by hand may leave it blank.
    public var id: String?
    public var name: String
    public var date: String?           // ISO YYYY-MM-DD
    public var amount: Double
    public var currency: String
    public var category: String?
    public var account: String?
    public var member: String?
    /// Taken out of the report by the owner: listed at the end and counted in no figure.
    public var removed: Bool?

    public init(id: String? = nil, name: String, date: String?, amount: Double, currency: String,
                category: String? = nil, account: String? = nil, member: String? = nil, removed: Bool? = nil) {
        self.id = id
        self.name = name
        self.date = date
        self.amount = amount
        self.currency = currency
        self.category = category
        self.account = account
        self.member = member
        self.removed = removed
    }
}

public struct StatsModule: Codable {
    public var id: String?
    public var title: String?
    public var comment: String?
    public var stats: [ReportStat]
}

public struct ProseModule: Codable {
    public var id: String?
    public var title: String?
    public var comment: String?
    public var text: String
}

public struct DonutModule: Codable {
    public var id: String?
    public var title: String?
    public var comment: String?
    public var currency: String?
    public var slices: [ReportSlice]
}

public struct BarsModule: Codable {
    public var id: String?
    public var title: String?
    public var comment: String?
    public var currency: String?
    public var bars: [ReportBar]
}

public struct TransactionsModule: Codable {
    public var id: String?
    public var title: String?
    public var comment: String?
    public var rows: [ReportRow]
}

/// Any JSON value — how an unknown module keeps its data. The AI may know modules this
/// app doesn't; the data still belongs to the user and still shows. Integers keep their
/// own case: boxed as Double, an id or timestamp would lose digits on the round trip.
public indirect enum ReportValue: Codable {
    case string(String)
    case integer(Int64)
    case number(Double)
    case bool(Bool)
    case null
    case array([ReportValue])
    case object([String: ReportValue])

    public init(from decoder: Decoder) throws {
        let single = try decoder.singleValueContainer()
        if single.decodeNil() { self = .null }
        else if let value = try? single.decode(Bool.self) { self = .bool(value) }
        else if let value = try? single.decode(Int64.self) { self = .integer(value) }
        else if let value = try? single.decode(Double.self) { self = .number(value) }
        else if let value = try? single.decode(String.self) { self = .string(value) }
        else if let value = try? single.decode([ReportValue].self) { self = .array(value) }
        else { self = .object(try single.decode([String: ReportValue].self)) }
    }

    public func encode(to encoder: Encoder) throws {
        var single = encoder.singleValueContainer()
        switch self {
        case .string(let value): try single.encode(value)
        case .integer(let value): try single.encode(value)
        case .number(let value): try single.encode(value)
        case .bool(let value): try single.encode(value)
        case .null: try single.encodeNil()
        case .array(let value): try single.encode(value)
        case .object(let value): try single.encode(value)
        }
    }
}

private struct AnyKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }
    init(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}

/// The module library, discriminated by `type`. Every module may carry a `comment` —
/// the owner's annotation, written back through the share path.
public enum ReportModule: Codable {
    case stats(StatsModule)
    case prose(ProseModule)
    case donut(DonutModule)
    case bars(BarsModule)
    case transactions(TransactionsModule)
    /// A type this app doesn't know — its fields ride along and render generically.
    case unknown(type: String, fields: [String: ReportValue])

    private enum TypeKey: String, CodingKey {
        case type
    }

    public init(from decoder: Decoder) throws {
        let type = try decoder.container(keyedBy: TypeKey.self).decode(String.self, forKey: .type)
        switch type {
        case "stats": self = .stats(try StatsModule(from: decoder))
        case "prose": self = .prose(try ProseModule(from: decoder))
        case "donut": self = .donut(try DonutModule(from: decoder))
        case "bars": self = .bars(try BarsModule(from: decoder))
        case "transactions": self = .transactions(try TransactionsModule(from: decoder))
        default:
            let raw = try decoder.container(keyedBy: AnyKey.self)
            var fields: [String: ReportValue] = [:]
            for key in raw.allKeys where key.stringValue != "type" {
                fields[key.stringValue] = try raw.decode(ReportValue.self, forKey: key)
            }
            self = .unknown(type: type, fields: fields)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var typed = encoder.container(keyedBy: TypeKey.self)
        switch self {
        case .stats(let module):
            try typed.encode("stats", forKey: .type)
            try module.encode(to: encoder)
        case .prose(let module):
            try typed.encode("prose", forKey: .type)
            try module.encode(to: encoder)
        case .donut(let module):
            try typed.encode("donut", forKey: .type)
            try module.encode(to: encoder)
        case .bars(let module):
            try typed.encode("bars", forKey: .type)
            try module.encode(to: encoder)
        case .transactions(let module):
            try typed.encode("transactions", forKey: .type)
            try module.encode(to: encoder)
        case .unknown(let type, let fields):
            try typed.encode(type, forKey: .type)
            var raw = encoder.container(keyedBy: AnyKey.self)
            for (key, value) in fields {
                try raw.encode(value, forKey: AnyKey(stringValue: key))
            }
        }
    }
}

/// The fields every module kind shares, read and written in one place so the share path
/// and a redraw agree on where a comment lives. An unknown kind keeps them among its own
/// fields, so a module this version doesn't know still carries its annotation.
public extension ReportModule {
    var id: String? {
        switch self {
        case .stats(let module): return module.id
        case .prose(let module): return module.id
        case .donut(let module): return module.id
        case .bars(let module): return module.id
        case .transactions(let module): return module.id
        case .unknown(_, let fields):
            if case .string(let value)? = fields["id"] { return value }
            return nil
        }
    }

    var title: String? {
        switch self {
        case .stats(let module): return module.title
        case .prose(let module): return module.title
        case .donut(let module): return module.title
        case .bars(let module): return module.title
        case .transactions(let module): return module.title
        case .unknown(_, let fields):
            if case .string(let value)? = fields["title"] { return value }
            return nil
        }
    }

    var comment: String? {
        get {
            switch self {
            case .stats(let module): return module.comment
            case .prose(let module): return module.comment
            case .donut(let module): return module.comment
            case .bars(let module): return module.comment
            case .transactions(let module): return module.comment
            case .unknown(_, let fields):
                if case .string(let value)? = fields["comment"] { return value }
                return nil
            }
        }
        set {
            switch self {
            case .stats(var module):
                module.comment = newValue
                self = .stats(module)
            case .prose(var module):
                module.comment = newValue
                self = .prose(module)
            case .donut(var module):
                module.comment = newValue
                self = .donut(module)
            case .bars(var module):
                module.comment = newValue
                self = .bars(module)
            case .transactions(var module):
                module.comment = newValue
                self = .transactions(module)
            case .unknown(let type, var fields):
                fields["comment"] = newValue.map(ReportValue.string)
                self = .unknown(type: type, fields: fields)
            }
        }
    }
}

public extension Report {
    /// This report carrying the comments a stored copy holds — a redraw must, because a
    /// viewer's words live in the file's own modules. Matched by id, then by title, then by
    /// position, so a draw that gained a module keeps each note under its own heading.
    func carryingComments(from stored: Report) -> Report {
        var carried = self
        for (index, old) in stored.modules.enumerated() {
            guard let line = old.comment, !line.isEmpty else { continue }
            var target: Int?
            if let id = old.id, let at = carried.modules.firstIndex(where: { $0.id == id }) {
                target = at
            } else if let title = old.title, !title.isEmpty,
                      let at = carried.modules.firstIndex(where: { $0.title == title }) {
                // A drawn report's titles are unique within it, so a heading is an identity
                // where the file names no id. Position alone would shift every note below a
                // module the draw gained.
                target = at
            } else if carried.modules.indices.contains(index) {
                target = index
            }
            guard let target else { continue }
            // Two old modules can land on one new module; both sets of words stay, as a
            // second pull of the same share would keep them.
            if let held = carried.modules[target].comment {
                if held != line { carried.modules[target].comment = held + "\n" + line }
            } else {
                carried.modules[target].comment = line
            }
        }
        return carried
    }
}

/// Reads the vault's reports folder. Reading only — reports are written by the user's
/// AI; the app draws them.
public enum ReportReader {
    public static let folderName = "reports"

    /// Every readable report, newest last covered day first: a month by its last day, a span
    /// by its end. created_at then filename break ties, giving a total order no enumeration
    /// can shuffle. A report with no days lists last. The caller counts unreadable files.
    public static func list(in vaultFolder: URL) -> (reports: [Report], unreadable: Int) {
        let folder = vaultFolder.appendingPathComponent(folderName, isDirectory: true)
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else {
            return ([], 0)
        }
        var found: [(last: String, created: String, name: String, report: Report)] = []
        var unreadable = 0
        for name in names.sorted() where name.hasSuffix(".json") {
            let file = folder.appendingPathComponent(name)
            try? FileManager.default.startDownloadingUbiquitousItem(at: file)
            guard let bytes = try? VaultReader.coordinatedRead(file) else { continue }
            guard let report = try? JSONDecoder().decode(Report.self, from: bytes) else {
                if isReportShaped(bytes) { unreadable += 1 }
                continue
            }
            found.append((report.range.map { LB.toISO($0.end) } ?? "", report.createdAt ?? "", name, report))
        }
        found.sort { a, b in
            if a.last != b.last { return a.last > b.last }
            if a.created != b.created { return a.created > b.created }
            return a.name < b.name
        }
        return (found.map { $0.report }, unreadable)
    }

    /// Whether a file is a report at all. A copy of the ledger parked in the folder is
    /// a different file, not a broken report, and passes without a word. A report is
    /// modules under a title, so `modules`, or an `id` with a `title`, marks one.
    private static func isReportShaped(_ bytes: Data) -> Bool {
        guard let object = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any] else {
            return false
        }
        if object.keys.contains("modules") { return true }
        return object.keys.contains("id") && object.keys.contains("title")
    }

    /// The file behind one report — what sharing sends and comment merging patches.
    public static func file(id: String, in vaultFolder: URL) -> (url: URL, bytes: Data)? {
        let folder = vaultFolder.appendingPathComponent(folderName, isDirectory: true)
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { return nil }
        for name in names.sorted() where name.hasSuffix(".json") {
            let url = folder.appendingPathComponent(name)
            guard let bytes = try? VaultReader.coordinatedRead(url),
                  let report = try? JSONDecoder().decode(Report.self, from: bytes)
            else { continue }
            if report.id == id { return (url, bytes) }
        }
        return nil
    }

    /// Merges viewer comments into a report file's module `comment` fields, keyed by the
    /// module's id — "m3" also matches the fourth module when no id is written. Appending
    /// is idempotent: a line already present is never added twice. Returns lines added.
    public static func mergeViewerComments(
        _ notes: [(module: String, line: String)], intoReportAt url: URL
    ) throws -> Int {
        let bytes = try VaultReader.coordinatedRead(url)
        guard var object = try JSONSerialization.jsonObject(with: bytes) as? [String: Any],
              var modules = object["modules"] as? [[String: Any]]
        else { throw WriteError.invalid("That report file couldn't be read as a report.") }

        var added = 0
        for note in notes {
            var index: Int?
            if let at = modules.firstIndex(where: { ($0["id"] as? String) == note.module }) {
                index = at
            } else if note.module.hasPrefix("module-"),
                      let n = Int(note.module.dropFirst(7)), modules.indices.contains(n) {
                // The viewer's fallback key for a module the AI left unnamed.
                index = n
            }
            guard let index else { continue }
            let existing = modules[index]["comment"] as? String ?? ""
            guard !existing.components(separatedBy: "\n").contains(note.line) else { continue }
            modules[index]["comment"] = existing.isEmpty ? note.line : existing + "\n" + note.line
            added += 1
        }
        guard added > 0 else { return 0 }

        object["modules"] = modules
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        var coordError: NSError?
        var writeError: Error?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &coordError) { target in
            do { try data.write(to: target, options: .atomic) } catch { writeError = error }
        }
        if let coordError { throw coordError }
        if let writeError { throw writeError }
        return added
    }
}
