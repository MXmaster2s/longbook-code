// A bank or card statement as the rows llms.txt asks an AI to write: read by longbook's
// server (StatementCloud), every debit and credit a row, credits with direction "in"; own
// movements and lines dated after today unticked. StatementTriage and candidates(from:) are
// the on-device classifier, test-covered, not called by the app.
import Foundation

/// One line a statement proves: a day, a payee string, an amount, and which way it went.
public struct StatementLine: Equatable, Sendable {
    public enum Direction: Equatable, Sendable { case debit, credit }

    /// YYYY-MM-DD.
    public let date: String
    /// The narration exactly as printed.
    public let payee: String
    public let amount: Double
    public let direction: Direction
    /// The page it was printed on, counted from 1, when the file is paged.
    public let page: Int?

    public init(date: String, payee: String, amount: Double, direction: Direction, page: Int? = nil) {
        self.date = date
        self.payee = payee
        self.amount = amount
        self.direction = direction
        self.page = page
    }
}

/// One word on a page, with where it sits. Columns are geometry, not spacing: a statement
/// is set in a proportional font, so the space between two columns is a position, never a
/// count of blanks.
public struct StatementWord: Equatable, Sendable {
    public var text: String
    public var minX: Double
    public var maxX: Double
    public var minY: Double
    public var maxY: Double

    public init(text: String, minX: Double, maxX: Double, minY: Double, maxY: Double) {
        self.text = text
        self.minX = minX
        self.maxX = maxX
        self.minY = minY
        self.maxY = maxY
    }

    public var midY: Double { (minY + maxY) / 2 }

    /// True when this sits on the line that box belongs to. Height, not distance: a comma
    /// hangs below the digits beside it and a rupee sign rides above them.
    public func shares(_ other: StatementWord) -> Bool {
        (other.midY < maxY && other.midY > minY) || (midY < other.maxY && midY > other.minY)
    }
}

/// The words that share a printed line, left to right.
public struct StatementRow: Equatable, Sendable {
    public var words: [StatementWord]
    /// The page the row sits on, counted from 1; 0 when the source has no pages.
    public var page: Int
    public init(words: [StatementWord], page: Int = 0) {
        self.words = words
        self.page = page
    }
    /// The row as a person would read it aloud.
    public var line: String { words.map(\.text).joined(separator: " ") }
}

/// A line after triage and naming, as the review table holds it.
public struct StatementCandidate: Identifiable, Equatable, Sendable {
    public let id: String
    public let line: StatementLine
    public var name: String
    public var tag: String?
    public var keep: Bool
    public var skipReason: String?
    /// The statement it came from, by file name: each file is its own account.
    public var file: String
    /// Who the money was for, when the line says so.
    public var member: String?
    /// "in" for money that arrived on this line, "transfer" for the owner's own money
    /// moving; nil for a charge.
    public var direction: String?
    /// Read from the file on the device, because the server's reading left the line out.
    public var readLocally: Bool

    public var isIncome: Bool { direction == "in" }
    /// Unticked by default; kept by the owner, it is written as a transfer, never as spending.
    public var isTransfer: Bool { direction == "transfer" }
    /// A transfer the owner may still tick in: unticked for being an own movement and for
    /// nothing else. One already in the book, or dated after today, stays refused.
    public var isOpenTransfer: Bool {
        isTransfer && (skipReason == StatementTriage.ownMovement || skipReason == StatementTriage.cardBill)
    }

    public init(id: String = UUID().uuidString, line: StatementLine, name: String, tag: String?, keep: Bool, skipReason: String?,
                file: String = "", member: String? = nil, direction: String? = nil, readLocally: Bool = false) {
        self.id = id
        self.line = line
        self.name = name
        self.tag = tag
        self.keep = keep
        self.skipReason = skipReason
        self.file = file
        self.member = member
        self.direction = direction
        self.readLocally = readLocally
    }
}

/// A rhythm spotted among the kept lines: the same name at the same amount, evenly apart.
public struct StatementRepeat: Equatable {
    public let name: String
    public let amount: Double
    public let cycle: BillingCycle
    public let customDays: Int?
    public let dates: [String]
    public let candidateIds: [String]
}

// MARK: - reading lines

public enum StatementLines {
    /// Lines from a CSV export. The header is found by its column names (HDFC, ICICI, SBI,
    /// Axis shapes all name a date, a narration and withdrawal/deposit or amount columns);
    /// a file without one yields nothing rather than guesses.
    public static func fromCSV(_ text: String) -> [StatementLine] {
        fromRecords(CSV.records(text))
    }

    /// Where the header row sits among the records, when one names the columns.
    public static func headerIndex(_ records: [[String]]) -> Int? {
        findHeader(records)?.0
    }

    /// Lines from rows of cells, however they were read — a CSV or a spreadsheet.
    public static func fromRecords(_ records: [[String]]) -> [StatementLine] {
        let lines = linesFromRecords(records)
        guard let period = declaredPeriod(records) else { return lines }
        return withinDeclaredPeriod(lines, period)
    }

    /// The period a statement declares of itself — "From 01/07/2026 To 31/07/2026" in a
    /// cell above the table — as two ISO days.
    static func declaredPeriod(_ records: [[String]]) -> (from: String, to: String)? {
        guard let regex = try? NSRegularExpression(pattern: #"(\d{1,2}[/.-]\d{1,2}[/.-]\d{2,4})\s*(?:to|-|–|till)\s*(\d{1,2}[/.-]\d{1,2}[/.-]\d{2,4})"#, options: .caseInsensitive) else { return nil }
        for record in records.prefix(40) {
            for cell in record {
                guard let match = regex.firstMatch(in: cell, range: NSRange(cell.startIndex..., in: cell)),
                      let fromRange = Range(match.range(at: 1), in: cell), let toRange = Range(match.range(at: 2), in: cell),
                      let from = parseDate(String(cell[fromRange])), let to = parseDate(String(cell[toRange])), from <= to
                else { continue }
                return (from, to)
            }
        }
        return nil
    }

    /// One bank's spreadsheet writes its dates with day and month traded, so a July
    /// statement reads as January through December. When most of the dates fall outside
    /// the period the sheet itself declares, and trading day for month puts them inside,
    /// the trade is undone.
    static func withinDeclaredPeriod(_ lines: [StatementLine], _ period: (from: String, to: String)) -> [StatementLine] {
        func swapped(_ iso: String) -> String? {
            let parts = iso.split(separator: "-")
            guard parts.count == 3 else { return nil }
            let candidate = "\(parts[0])-\(parts[2])-\(parts[1])"
            return LB.parseDate(candidate) != nil ? candidate : nil
        }
        let outside = lines.filter { $0.date < period.from || $0.date > period.to }
        guard outside.count * 2 > lines.count else { return lines }
        let mended = outside.filter { line in swapped(line.date).map { $0 >= period.from && $0 <= period.to } ?? false }
        guard mended.count * 10 >= outside.count * 9 else { return lines }
        return lines.map { line in
            guard line.date < period.from || line.date > period.to, let day = swapped(line.date) else { return line }
            return StatementLine(date: day, payee: line.payee, amount: line.amount, direction: line.direction, page: line.page)
        }
    }

    private static func linesFromRecords(_ records: [[String]]) -> [StatementLine] {
        guard let (headerIndex, columns) = findHeader(records) else { return [] }
        var out: [StatementLine] = []
        for record in records.dropFirst(headerIndex + 1) {
            guard let date = cell(record, columns.date).flatMap(parseDate),
                  let payee = cell(record, columns.narration)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !payee.isEmpty
            else { continue }
            var amount: Double?
            var direction: StatementLine.Direction = .debit
            // A reversal printed as a negative withdrawal is money back in; a negative
            // deposit is money out.
            if let value = cell(record, columns.withdrawal).flatMap(parseAmount), value != 0 {
                amount = abs(value)
                direction = value < 0 ? .credit : .debit
            } else if let value = cell(record, columns.deposit).flatMap(parseAmount), value != 0 {
                amount = abs(value)
                direction = value < 0 ? .debit : .credit
            } else if let value = cell(record, columns.amount).flatMap(parseAmount), value != 0 {
                amount = abs(value)
                let type = cell(record, columns.type)?.uppercased() ?? ""
                direction = (type.contains("CR") || value < 0) ? .credit : .debit
            }
            guard let amount else { continue }
            let page = cell(record, columns.page).flatMap { Int($0) }.flatMap { $0 > 0 ? $0 : nil }
            out.append(StatementLine(date: date, payee: payee, amount: amount, direction: direction, page: page))
        }
        return out
    }

    /// Lines from a page's rows, read as the table it is: the money columns are found by
    /// where the figures sit, and the heading above them says which is money out and which
    /// is money in. Empty when the rows carry no such table, so a caller can fall back.
    public static func fromColumns(_ rows: [StatementRow]) -> [StatementLine] {
        let dated = rows.filter { leadingDate($0.line) != nil }
        guard dated.count >= 2 else { return [] }
        // Where the figures line up: each column is a right edge the amounts share.
        var edges: [Double] = []
        var rowsAt: [Int] = []
        for row in dated {
            for word in row.words where isAmountToken(word.text) {
                if let at = edges.firstIndex(where: { abs($0 - word.maxX) < 12 }) {
                    edges[at] = (edges[at] + word.maxX) / 2
                    rowsAt[at] += 1
                } else {
                    edges.append(word.maxX)
                    rowsAt.append(1)
                }
            }
        }
        // A table has a column nearly every row writes in. Figures that land wherever the
        // words before them end are not columns, and reading them as such invents money.
        guard !edges.isEmpty, edges.count <= 4,
              Double(rowsAt.max() ?? 0) >= Double(dated.count) * 0.6
        else { return [] }
        edges = zip(edges, rowsAt).sorted { $0.0 < $1.0 }.map(\.0)

        let header = headerLabels(rows, dated: dated, columns: edges.count)
        // The page comes first so a line can be traced to the piece that carried it.
        var records: [[String]] = [["Page", "Date", "Narration"] + header]
        for block in blocks(rows) {
            let row = block.anchor
            guard let (dateToken, rest) = leadingDate(row.line), let date = parseDate(dateToken) else { continue }
            var record = [String(row.page), date, ""]
            record += Array(repeating: "", count: edges.count)
            var payee: [String] = []
            var marker = ""
            var pastAmount = false
            // The words before the date are a row number and the date itself.
            let prefix = max(0, row.words.count - rest.split(separator: " ").count)
            for word in row.words.dropFirst(prefix) {
                let upper = word.text.uppercased()
                if upper == "CR" || upper == "DR" || (pastAmount && (upper == "CREDIT" || upper == "DEBIT")) {
                    marker = String(upper.prefix(2))
                    continue
                }
                if currencyWords.contains(upper) { continue }
                guard !isAmountToken(word.text) else {
                    let column = edges.enumerated().min { abs($0.element - word.maxX) < abs($1.element - word.maxX) }?.offset ?? 0
                    if record[3 + column].isEmpty { record[3 + column] = word.text }
                    pastAmount = true
                    continue
                }
                if parseDate(word.text) == nil { payee.append(word.text) }
            }
            // A narration wrapped onto the lines around its row reads as one.
            let around = block.above.map(\.line) + [payee.joined(separator: " ")] + block.below.map(\.line)
            record[2] = around.filter { !$0.isEmpty }.joined(separator: " ")
            // A marked row says its own direction; the columns say the rest.
            records.append(marker.isEmpty ? record : record + [marker])
        }
        if !records[0].contains(where: { $0.lowercased().contains("type") }),
           records.dropFirst().contains(where: { $0.count > records[0].count }) {
            records[0].append("Type")
        }
        return fromRecords(records)
    }

    static let currencyWords: Set<String> = ["₹", "INR", "INR.", "RS", "RS.", "₹."]

    /// A dated row with the undated lines that belong to it: a narration wraps below its
    /// row until the next date, the page's end, or a gap of two lines; a dated row with
    /// no narration of its own owns the line just above it, as one bank prints it.
    struct Block {
        var anchor: StatementRow
        var above: [StatementRow]
        var below: [StatementRow]
    }

    static func blocks(_ rows: [StatementRow]) -> [Block] {
        let ys = rows.compactMap { $0.words.first?.midY }
        var gaps = zip(ys, ys.dropFirst()).map { $0 - $1 }.filter { $0 > 0.5 && $0 < 60 }
        gaps.sort()
        let pitch = gaps.isEmpty ? 12 : gaps[gaps.count / 2]

        var out: [Block] = []
        var open = false
        var previous: StatementRow?
        var previousAttached = false
        for row in rows {
            guard let first = row.words.first else {
                open = false
                previous = nil
                continue
            }
            defer { previous = row }
            if leadingDate(row.line) != nil {
                var block = Block(anchor: row, above: [], below: [])
                if narration(of: row).isEmpty, let above = previous, let aboveFirst = above.words.first,
                   leadingDate(above.line) == nil, aboveFirst.midY - first.midY < pitch * 1.4 {
                    block.above = [above]
                    if previousAttached, !out.isEmpty { out[out.count - 1].below.removeLast() }
                }
                out.append(block)
                open = true
                previousAttached = false
                continue
            }
            if open, !out.isEmpty, out[out.count - 1].below.count < 8,
               let last = previous?.words.first, last.midY - first.midY < pitch * 2.2 {
                out[out.count - 1].below.append(row)
                previousAttached = true
            } else {
                open = false
                previousAttached = false
            }
        }
        return out
    }

    /// The words of a dated row that name the payee: not the row number, the date, the
    /// figures, a currency sign, or a Cr/Dr mark.
    static func narration(of row: StatementRow) -> [String] {
        guard let (_, rest) = leadingDate(row.line) else { return [] }
        let prefix = max(0, row.words.count - rest.split(separator: " ").count)
        return row.words.dropFirst(prefix).map(\.text).filter { word in
            let upper = word.uppercased()
            return !isAmountToken(word) && parseDate(word) == nil && !currencyWords.contains(upper)
                && !["CR", "DR", "CREDIT", "DEBIT"].contains(upper)
        }
    }

    /// What the heading calls each money column, in the order the columns run. A heading
    /// that names none of them leaves the commonest layout for that many columns.
    private static func headerLabels(_ rows: [StatementRow], dated: [StatementRow], columns: Int) -> [String] {
        let known = ["withdrawal", "debit", "deposit", "credit", "amount", "balance", "type"]
        let firstDatedY = dated.first?.words.first?.midY ?? 0
        for row in rows where (row.words.first?.midY ?? 0) >= firstDatedY {
            let labels = row.words.map { $0.text.lowercased() }.filter { label in known.contains { label.contains($0) } }
            if labels.count == columns, row.words.contains(where: { $0.text.lowercased().contains("date") }) {
                return labels.map { $0.capitalized }
            }
        }
        switch columns {
        case 1: return ["Amount"]
        case 2: return ["Amount", "Balance"]
        case 3: return ["Withdrawal", "Deposit", "Balance"]
        default: return ["Withdrawal", "Deposit", "Balance", "Amount"]
        }
    }

    /// Lines from a PDF's text: a date first, a payee, then the amounts at the end. With a
    /// running balance, its rise or fall says which way the money went; a lone amount is a
    /// spend unless the line marks it Cr, as card statements do.
    public static func fromText(_ text: String) -> [StatementLine] {
        var out: [StatementLine] = []
        var previousBalance: Double?
        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard let (dateToken, rest) = leadingDate(line), let date = parseDate(dateToken) else { continue }
            var tokens = rest.split(separator: " ").map(String.init).filter { !$0.isEmpty }
            var amounts: [Double] = []
            var credit = false
            while let last = tokens.last {
                let upper = last.uppercased()
                if ["CR", "DR", "CREDIT", "DEBIT"].contains(upper) {
                    if amounts.isEmpty { credit = upper.hasPrefix("CR") }
                    tokens.removeLast()
                } else if currencyWords.contains(upper) {
                    tokens.removeLast()
                } else if isAmountToken(last), let value = parseAmount(last) {
                    amounts.insert(value, at: 0)
                    tokens.removeLast()
                } else {
                    break
                }
            }
            guard let amount = amounts.first, amount > 0 else { continue }
            let payee = tokens.joined(separator: " ")
            guard !payee.isEmpty else { continue }
            var direction: StatementLine.Direction = credit ? .credit : .debit
            if amounts.count >= 2, let balance = amounts.last {
                if let previousBalance, !credit {
                    direction = balance < previousBalance ? .debit : .credit
                }
                previousBalance = balance
            }
            out.append(StatementLine(date: date, payee: payee, amount: amount, direction: direction))
        }
        return out
    }

    // MARK: pieces

    private struct Columns {
        var date: Int?
        var narration: Int?
        var withdrawal: Int?
        var deposit: Int?
        var amount: Int?
        var type: Int?
        /// The page column fromColumns writes; a bank's own sheet has none.
        var page: Int?
    }

    /// The first record naming a date, a narration and some amount column.
    private static func findHeader(_ records: [[String]]) -> (Int, Columns)? {
        for (index, record) in records.prefix(40).enumerated() {
            let names = record.map {
                $0.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                    .replacingOccurrences(of: #"\s*/\s*"#, with: "/", options: .regularExpression)
            }
            var columns = Columns()
            // The transaction date, not the value date, when both are named.
            columns.date = names.firstIndex { $0.contains("date") && !$0.contains("value") }
                ?? names.firstIndex { $0.contains("date") }
            for (i, name) in names.enumerated() {
                if name.contains("date") { continue }
                if name == "page" {
                    columns.page = columns.page ?? i
                } else if ["narration", "description", "particulars", "remarks", "details"].contains(where: name.contains) {
                    columns.narration = columns.narration ?? i
                } else if ["withdrawal", "debit"].contains(where: name.contains) || name == "dr" {
                    columns.withdrawal = columns.withdrawal ?? i
                } else if ["deposit", "credit"].contains(where: name.contains) || name == "cr" {
                    columns.deposit = columns.deposit ?? i
                } else if name.contains("amount") || name.contains("amt") {
                    columns.amount = columns.amount ?? i
                } else if name == "type" || name.contains("dr/cr") || name.contains("cr/dr") || name.contains("transaction type") {
                    columns.type = columns.type ?? i
                }
            }
            if columns.date != nil, columns.narration != nil,
               columns.withdrawal != nil || columns.deposit != nil || columns.amount != nil {
                return (index, columns)
            }
        }
        return nil
    }

    private static func cell(_ record: [String], _ index: Int?) -> String? {
        guard let index, index < record.count else { return nil }
        let value = record[index].trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    /// The date a line starts with, and the rest. A row number printed before the date,
    /// as some banks do, is stepped over.
    static func leadingDate(_ line: String) -> (String, String)? {
        let patterns = [
            #"^(?:\d{1,4}\.?\s+)?(\d{1,2}[./-]\d{1,2}[./-]\d{2,4})\s+(.+)$"#,
            #"^(?:\d{1,4}\.?\s+)?(\d{4}-\d{2}-\d{2})\s+(.+)$"#,
            #"^(?:\d{1,4}\.?\s+)?(\d{1,2}[ -][A-Za-z]{3}[ -,'’‘]+\d{2,4})\s+(.+)$"#,
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
                  let dateRange = Range(match.range(at: 1), in: line),
                  let restRange = Range(match.range(at: 2), in: line)
            else { continue }
            return (String(line[dateRange]), String(line[restRange]))
        }
        return nil
    }

    /// Statement amounts carry a decimal point or grouping commas; a bare integer at the
    /// end of a narration is a reference, not money.
    static func isAmountToken(_ token: String) -> Bool {
        let cleaned = token.replacingOccurrences(of: "₹", with: "").replacingOccurrences(of: "INR", with: "")
        return cleaned.range(of: #"^-?\d[\d,]*\.\d{1,2}$|^-?\d{1,3}(,\d{2,3})+$"#, options: .regularExpression) != nil
    }

    static let dateFormats = [
        "dd/MM/yyyy", "dd-MM-yyyy", "dd.MM.yyyy", "dd/MM/yy", "dd-MM-yy", "dd.MM.yy", "yyyy-MM-dd",
        "dd MMM yyyy", "dd-MMM-yyyy", "dd MMM yy", "dd-MMM-yy", "dd MMM, yyyy", "dd MMMM yyyy",
    ]

    /// The same shapes with the month first, for a statement whose dates say so.
    static let monthFirstFormats = ["MM/dd/yyyy", "MM-dd-yyyy", "MM.dd.yyyy", "MM/dd/yy", "MM-dd-yy", "MM.dd.yy"]

    public enum DateOrder: Equatable { case dayFirst, monthFirst }

    /// Which of "05/10/2026"'s numbers is the day, read from the sheet itself: one cell
    /// with a first number past 12 settles day-first, one with a second number past 12
    /// settles month-first. A sheet that never shows its hand reads day-first, as banks
    /// here print.
    public static func dateOrder(_ records: [[String]]) -> DateOrder {
        guard let regex = try? NSRegularExpression(pattern: #"^(\d{1,2})[./-](\d{1,2})[./-]\d{2,4}$"#) else { return .dayFirst }
        for record in records {
            for cell in record {
                let trimmed = cell.trimmingCharacters(in: .whitespaces)
                guard let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
                      let firstRange = Range(match.range(at: 1), in: trimmed), let secondRange = Range(match.range(at: 2), in: trimmed),
                      let first = Int(trimmed[firstRange]), let second = Int(trimmed[secondRange])
                else { continue }
                if first > 12 { return .dayFirst }
                if second > 12 { return .monthFirst }
            }
        }
        return .dayFirst
    }

    /// A printed date as YYYY-MM-DD in the order the sheet was found to use.
    public static func parseDate(_ text: String, order: DateOrder) -> String? {
        guard order == .monthFirst else { return parseDate(text) }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = formatter.timeZone
        let out = DateFormatter()
        out.locale = formatter.locale
        out.timeZone = formatter.timeZone
        out.dateFormat = "yyyy-MM-dd"
        for format in monthFirstFormats {
            formatter.dateFormat = format
            if let date = formatter.date(from: trimmed), calendar.component(.year, from: date) >= 1970 {
                return out.string(from: date)
            }
        }
        return parseDate(text)
    }

    /// A printed date as YYYY-MM-DD, trying the shapes Indian statements use — slashes,
    /// dashes, dots, month names, and a card statement's "18 Jul '26".
    public static func parseDate(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"['’‘]"#, with: "", options: .regularExpression)
        guard !trimmed.isEmpty else { return nil }
        // A spreadsheet's date cell can arrive as Excel's day count from 1899-12-30, with
        // the time of day as its fraction.
        if trimmed.range(of: #"^\d{5}(\.\d+)?$"#, options: .regularExpression) != nil,
           let serial = Double(trimmed).map({ $0.rounded(.down) }), (30_000...70_000).contains(serial) {
            let utc = DateFormatter()
            utc.locale = Locale(identifier: "en_US_POSIX")
            utc.timeZone = TimeZone(identifier: "UTC")
            utc.dateFormat = "yyyy-MM-dd"
            return utc.string(from: Date(timeIntervalSince1970: (serial - 25_569) * 86_400))
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        let out = DateFormatter()
        out.locale = formatter.locale
        out.timeZone = formatter.timeZone
        out.dateFormat = "yyyy-MM-dd"
        // "26" read by a four-digit format is the year 26; the two-digit shape gets its turn.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = formatter.timeZone
        for format in dateFormats {
            formatter.dateFormat = format
            if let date = formatter.date(from: trimmed), calendar.component(.year, from: date) >= 1970 {
                return out.string(from: date)
            }
        }
        return nil
    }

    /// "1,50,000.00", "₹649", "Rs. 3,597" — a number, or nil. Sign survives.
    public static func parseAmount(_ text: String) -> Double? {
        var cleaned = text.uppercased()
        for noise in ["₹", "INR", "RS.", "RS", ",", " "] { cleaned = cleaned.replacingOccurrences(of: noise, with: "") }
        cleaned = cleaned.replacingOccurrences(of: "CR", with: "").replacingOccurrences(of: "DR", with: "")
        guard cleaned.range(of: #"^-?\d+(\.\d+)?$"#, options: .regularExpression) != nil else { return nil }
        return Double(cleaned)
    }
}

/// A small CSV reader: quoted cells, doubled quotes, newlines inside quotes.
enum CSV {
    /// Rows of cells as CSV text, every cell quoted, for a sheet that travels as text.
    static func text(_ records: [[String]]) -> String {
        records.map { record in
            record.map { "\"" + $0.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }.joined(separator: ",")
        }.joined(separator: "\n")
    }

    static func records(_ text: String) -> [[String]] {
        var records: [[String]] = []
        var record: [String] = []
        var cell = ""
        var quoted = false
        var iterator = text.makeIterator()
        var pending: Character? = nil
        func next() -> Character? {
            if let p = pending { pending = nil; return p }
            return iterator.next()
        }
        while let ch = next() {
            if quoted {
                if ch == "\"" {
                    if let peek = next() {
                        if peek == "\"" { cell.append("\"") } else { quoted = false; pending = peek }
                    } else { quoted = false }
                } else {
                    cell.append(ch)
                }
            } else if ch == "\"" {
                quoted = true
            } else if ch == "," {
                record.append(cell); cell = ""
            } else if ch == "\n" || ch == "\r" {
                if ch == "\r", let peek = next(), peek != "\n" { pending = peek }
                record.append(cell); cell = ""
                if record.contains(where: { !$0.isEmpty }) { records.append(record) }
                record = []
            } else {
                cell.append(ch)
            }
        }
        record.append(cell)
        if record.contains(where: { !$0.isEmpty }) { records.append(record) }
        return records
    }
}

// MARK: - triage

public enum StatementTriage {
    public enum Verdict: Equatable { case keep, skip(String) }

    /// The words that mark the owner's own money moving rather than a spend.
    static let ownMovements = [
        "ATM", "ATW", "CASH WDL", "CASH WITHDRAWAL", "CREDIT CARD PAYMENT", "CARD PAYMENT", "CC PAYMENT",
        "CARD BILL", "WALLET TOPUP", "WALLET TOP UP", "ADD MONEY", "SELF TRANSFER", "OWN ACCOUNT", "TO SELF",
    ]

    /// What money in says of itself, for a statement whose columns cannot be told apart by
    /// position. Said plainly, because one word is not enough: a salary paid to a cook is
    /// money out, and only "salary credit" is money in.
    static let moneyIn = [
        "SALARY CREDIT", "CREDIT SALARY", "SAL CREDIT", "REFUND", "REVERSAL", "REVERSED",
        "CASHBACK", "DIVIDEND", "INTEREST PAID", "INTEREST CREDIT", "INT CREDIT",
        "INTEREST CAPITALISED", "NEFT-CR", "IMPS-CR", "UPI-CR",
    ]

    /// Money in is skipped, and so is money moved between the owner's own places. Every
    /// other debit is a fact and stays.
    public static func verdict(_ line: StatementLine) -> Verdict {
        if line.direction == .credit { return .skip("money in") }
        let upper = " \(line.payee.uppercased()) "
        if moneyIn.contains(where: { upper.contains($0) }) { return .skip("money in") }
        if ownMovements.contains(where: { upper.contains(" \($0) ") || upper.contains($0) }) {
            return .skip(ownMovement)
        }
        return .keep
    }

    /// Why a line between the owner's own places is left unticked.
    public static let ownMovement = "your own money moved"
    /// The same for a card's bill paid from another account, as the server names it.
    public static let cardBill = "a card bill — its charges are on the card's statement"
    /// Why a line dated ahead of today is refused, whatever kind it is.
    public static let afterToday = "dated after today — a statement proves the past"
}

// MARK: - names

public enum StatementNaming {
    static let noise: Set<String> = [
        "UPI", "POS", "NEFT", "IMPS", "RTGS", "ACH", "BIL", "ONL", "BILLPAY", "ECOM", "PUR", "DC", "SI", "INB", "TXN",
        "DR", "CR", "MMT", "MPS", "INF", "IB", "ATD", "EDC", "CMS", "CHQ",
        "REF", "PAYMENT", "PAYMENTS", "PVT", "LTD", "LIMITED", "MUM", "BLR", "DEL", "VPS", "ME", "AUTOPAY", "NACH", "DEBIT",
    ]

    /// The name an owner would say, from a narration: separators become spaces, handles,
    /// numbers and bank noise go, a web suffix is dropped, the first few words stay.
    public static func plainName(_ payee: String) -> String {
        var text = payee
        for separator in ["/", "-", "_", "|", ":", "*"] { text = text.replacingOccurrences(of: separator, with: " ") }
        var words: [String] = []
        var previousWasNoise = true
        for raw in text.split(separator: " ") {
            var word = String(raw)
            if word.contains("@") || word.contains(where: \.isNumber) { continue }
            for suffix in [".COM", ".IN", ".NET", ".ORG", ".CO"] where word.uppercased().hasSuffix(suffix) {
                word = String(word.dropLast(suffix.count))
            }
            word = word.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
            guard !word.isEmpty else { continue }
            let upper = word.uppercased()
            if noise.contains(upper) { previousWasNoise = true; continue }
            if word.count == 1, previousWasNoise { continue }
            previousWasNoise = false
            // A narration that repeats itself — a label line, then the line that spells it
            // out — names the payee once.
            let plain = word.lowercased().capitalized
            if words.contains(plain) { continue }
            words.append(plain)
            if words.count == 5 { break }
        }
        return words.isEmpty ? "Unnamed charge" : words.joined(separator: " ")
    }

    /// The narration with every long number gone, fit to sit in details without carrying a
    /// card, an account or a reference.
    public static func scrubbed(_ payee: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"[-/ ]?[A-Za-z]*\d{4,}[A-Za-z0-9]*"#) else { return "" }
        let range = NSRange(payee.startIndex..., in: payee)
        let stripped = regex.stringByReplacingMatches(in: payee, range: range, withTemplate: "")
        return stripped
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: " -/"))
            .prefix(80)
            .trimmingCharacters(in: .whitespaces)
    }
}

// MARK: - categories

public enum StatementCategory {
    /// What a payee plainly is, by the words it uses. Rent is rent and an EMI is an EMI in
    /// every statement printed here; the model is asked only about the rest.
    static let rules: [(word: String, tag: String)] = [
        ("RENT", "rent"), ("LANDLORD", "rent"),
        ("NETFLIX", "streaming"), ("SPOTIFY", "streaming"), ("HOTSTAR", "streaming"), ("PRIME VIDEO", "streaming"),
        ("SONYLIV", "streaming"), ("ZEE5", "streaming"), ("YOUTUBE", "streaming"),
        ("AIRTEL", "telecom"), ("JIO", "telecom"), ("VODAFONE", "telecom"), ("BSNL", "telecom"),
        ("BROADBAND", "telecom"), ("ACT FIBER", "telecom"), ("HATHWAY", "telecom"),
        ("INSURANCE", "insurance"), ("PREMIUM", "insurance"), ("ERGO", "insurance"), ("LIC", "insurance"),
        ("POLICYBAZAAR", "insurance"), ("STAR HEALTH", "insurance"),
        ("EMI", "emi"), ("LOAN", "emi"),
        ("ELECTRICITY", "utility"), ("BESCOM", "utility"), ("BSES", "utility"), ("MSEB", "utility"),
        ("GAS", "utility"), ("WATER", "utility"), ("POWER", "utility"),
        ("MAINT", "home"), ("SOCIETY", "home"), ("APARTMENT", "home"),
        ("SCHOOL", "education"), ("COLLEGE", "education"), ("TUITION", "education"), ("COACHING", "education"),
        ("GYM", "health & fitness"), ("FITNESS", "health & fitness"), ("HOSPITAL", "health & fitness"),
        ("PHARMA", "health & fitness"), ("APOLLO", "health & fitness"), ("CULT", "health & fitness"),
        ("ADOBE", "software"), ("MICROSOFT", "software"), ("ICLOUD", "software"), ("DROPBOX", "software"),
        ("NOTION", "software"), ("FIGMA", "software"), ("CANVA", "software"),
        ("OPENAI", "ai"), ("ANTHROPIC", "ai"), ("CLAUDE", "ai"), ("CHATGPT", "ai"), ("PERPLEXITY", "ai"),
        ("GODADDY", "domain & hosting"), ("HOSTING", "domain & hosting"), ("DOMAIN", "domain & hosting"),
        ("NAMECHEAP", "domain & hosting"), ("AWS", "domain & hosting"),
        ("IRCTC", "travel"), ("INDIGO", "travel"), ("MAKEMYTRIP", "travel"), ("UBER", "travel"),
        ("OLA", "travel"), ("REDBUS", "travel"), ("AIRLINES", "travel"),
        ("COOK", "salary"), ("MAID", "salary"), ("DRIVER", "salary"), ("HELPER", "salary"), ("SALARY", "salary"),
        ("TAX", "tax"), ("GST", "tax"),
    ]

    /// The category a name plainly wears, when the vault knows that category. A short word
    /// must stand on its own; a long one may sit inside a longer name.
    public static func known(_ name: String, among: [String]) -> String? {
        let upper = name.uppercased()
        let words = Set(upper.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init))
        for rule in rules {
            let hit = rule.word.count >= 5 || rule.word.contains(" ") ? upper.contains(rule.word) : words.contains(rule.word)
            guard hit, let tag = among.first(where: { $0.caseInsensitiveCompare(rule.tag) == .orderedSame }) else { continue }
            return tag
        }
        return nil
    }
}

// MARK: - the import

public enum StatementImport {
    /// Every line triaged, plainly named, and wearing the category its words plainly say.
    public static func candidates(from lines: [StatementLine], among: [String] = TagLibrary.entries(kind: "commitment").map(\.name), file: String = "") -> [StatementCandidate] {
        lines.map { line in
            let name = StatementNaming.plainName(line.payee)
            let tag = StatementCategory.known(name, among: among) ?? StatementCategory.known(line.payee, among: among)
            switch StatementTriage.verdict(line) {
            case .keep:
                return StatementCandidate(line: line, name: name, tag: tag, keep: true, skipReason: nil, file: file)
            case .skip(let why):
                // A movement the owner ticks back in is remembered as a transfer, never as spending.
                return StatementCandidate(line: line, name: name, tag: tag, keep: false, skipReason: why, file: file,
                                          direction: why == StatementTriage.ownMovement ? "transfer" : nil)
            }
        }
    }

    /// What makes a charge the same charge on a second reading: its day, its amount, and
    /// its narration with the numbers gone.
    public static func key(date: String, amount: Double, narration: String) -> String {
        "\(date)|\(String(format: "%.2f", amount))|\(StatementNaming.scrubbed(narration).lowercased())"
    }

    /// Lines the book already holds, or that another picked file already carried, are left
    /// unticked: a statement read twice writes nothing twice. The same line twice in one
    /// file stays; two identical charges on one day do happen. A transfer arrives unticked
    /// and is checked too.
    public static func markAlreadyPresent(_ candidates: inout [StatementCandidate], in existing: Set<String>) {
        var carriedBy: [String: String] = [:]
        for index in candidates.indices where candidates[index].keep || candidates[index].isTransfer {
            let candidate = candidates[index]
            let key = key(date: candidate.line.date, amount: candidate.line.amount, narration: candidate.line.payee)
            if existing.contains(key) {
                candidates[index].keep = false
                candidates[index].skipReason = "already in your longbook"
            } else if let first = carriedBy[key], first != candidate.file {
                candidates[index].keep = false
                candidates[index].skipReason = "already in \(first)"
            } else if carriedBy[key] == nil {
                carriedBy[key] = candidate.file
            }
        }
    }

    /// The kept lines grouped by name and amount; a group evenly spaced is a rhythm worth
    /// asking about. Order is first appearance.
    public static func repeats(in candidates: [StatementCandidate]) -> [StatementRepeat] {
        var order: [String] = []
        var groups: [String: [StatementCandidate]] = [:]
        for candidate in candidates where candidate.keep {
            let key = "\(candidate.name.lowercased())|\(String(format: "%.2f", candidate.line.amount))"
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(candidate)
        }
        var out: [StatementRepeat] = []
        for key in order {
            let group = groups[key]!.sorted { $0.line.date < $1.line.date }
            guard group.count >= 2 else { continue }
            let days = group.compactMap { LB.parseDate($0.line.date) }.map { $0.timeIntervalSince1970 / 86_400 }
            let gaps = zip(days.dropFirst(), days).map { $0 - $1 }.sorted()
            guard !gaps.isEmpty else { continue }
            let median = gaps[gaps.count / 2]
            let cycle: (BillingCycle, Int?)
            switch median {
            case 26...35: cycle = (.monthly, nil)
            case 350...380: cycle = (.yearly, nil)
            case 85...96: cycle = (.custom, 91)
            case 175...190: cycle = (.custom, 183)
            default: continue
            }
            out.append(StatementRepeat(
                name: group[0].name, amount: group[0].line.amount, cycle: cycle.0, customDays: cycle.1,
                dates: group.map(\.line.date), candidateIds: group.map(\.id)
            ))
        }
        return out
    }

    /// One add_commitments proposal of the kept lines: each a one-time row, paid, basis
    /// statement, on the account the statement is, signed as the import so Changes says so.
    public static func proposal(_ candidates: [StatementCandidate], account: String, currency: String, source: String) -> PendingWrite {
        proposal(candidates, accounts: ["": account], currency: currency, source: source)
    }

    /// The same, with each file's lines on that file's own account. With no map at all, a
    /// candidate's `file` is already the account's name.
    public static func proposal(_ candidates: [StatementCandidate], accounts: [String: String], currency: String, source: String) -> PendingWrite {
        let rows: [[String: Any]] = candidates.filter(\.keep).map { candidate in
            var row: [String: Any] = [
                "name": candidate.name,
                "amount": candidate.line.amount,
                "currency": currency,
                "billing_cycle": BillingCycle.once.rawValue,
                "date": candidate.line.date,
                "paid": true,
                "basis": "statement",
                "account": accounts[candidate.file] ?? accounts[""] ?? (accounts.isEmpty ? candidate.file : ""),
            ]
            if let tag = candidate.tag, !tag.isEmpty { row["tag"] = tag }
            if let direction = VaultPatch.storedDirection(candidate.direction) { row["direction"] = direction }
            if let member = candidate.member?.trimmingCharacters(in: .whitespaces), !member.isEmpty { row["member"] = member }
            let line = StatementNaming.scrubbed(candidate.line.payee)
            if !line.isEmpty { row["details"] = ["statement_line": line] }
            return row
        }
        return PendingWrite(
            id: UUID(), kind: "add_commitments", payload: ["rows": rows],
            sourceRef: source, keyName: "statement import", origin: "statement"
        )
    }
}
