// Proof that an import read the whole statement: the file's own lines, read on the device,
// against the charges the server returned; the lines it left out, filled from the file; the
// balance arithmetic; and, after the Add, the shape of what was written. Pure, and tested.
import Foundation

public enum StatementCompleteness {
    /// What the file itself says, from the device's own reading of it.
    public struct Expected: Equatable, Sendable {
        public var lines: [StatementLine]
        /// The balances the file prints, when it prints them.
        public var opening: Double?
        public var closing: Double?

        public init(lines: [StatementLine], opening: Double? = nil, closing: Double? = nil) {
            self.lines = lines
            self.opening = opening
            self.closing = closing
        }

        public var count: Int { lines.count }
        public var debits: Double { lines.filter { $0.direction == .debit }.reduce(0) { $0 + $1.amount } }
        public var credits: Double { lines.filter { $0.direction == .credit }.reduce(0) { $0 + $1.amount } }
    }

    /// The printed closing balance against the opening one plus what the review holds.
    public enum Balance: Equatable, Sendable {
        case matches
        case off(by: Double)
        case unknown
    }

    /// One file's reading against the file.
    public struct Report: Equatable, Sendable {
        /// Charges the server returned.
        public var read: Int
        /// Lines the file holds; nil when the device could not read it.
        public var expectedCount: Int?
        /// Lines of the file no returned charge answers for.
        public var missing: [StatementLine]
        /// Returned charges no line of the file answers for.
        public var extra: Int
        public var balance: Balance
        /// People the lines name, by member or counterpart, and people the look-over listed.
        public var peopleNamed: Int
        public var peopleListed: Int
        /// Accounts the lines name on their other side.
        public var accountsNamed: Int
        /// How many of the people named are among those listed, and how many of the accounts
        /// named were found as accounts. Equal to the named counts unless the reading says otherwise.
        public var peopleCovered: Int
        public var accountsFound: Int

        public init(read: Int, expectedCount: Int?, missing: [StatementLine], extra: Int, balance: Balance,
                    peopleNamed: Int, peopleListed: Int, accountsNamed: Int, peopleCovered: Int? = nil, accountsFound: Int? = nil) {
            self.peopleCovered = peopleCovered ?? peopleNamed
            self.accountsFound = accountsFound ?? accountsNamed
            self.read = read
            self.expectedCount = expectedCount
            self.missing = missing
            self.extra = extra
            self.balance = balance
            self.peopleNamed = peopleNamed
            self.peopleListed = peopleListed
            self.accountsNamed = accountsNamed
        }

        /// One line for the review header: "134 of 134 lines · balance matches",
        /// "131 of 134 lines, 3 read from the file · balance off by ₹47.49".
        public func summary(currency: String) -> String {
            guard let expectedCount else {
                return "Read \(read) line\(read == 1 ? "" : "s") · the file's own count could not be checked"
            }
            var words = "\(expectedCount - missing.count) of \(expectedCount) line\(expectedCount == 1 ? "" : "s")"
            if !missing.isEmpty { words += ", \(missing.count) read from the file" }
            return words + balanceWords(currency: currency).map { " · " + $0 }.orEmpty
        }

        /// The average percent of lines read out of the file's, the balance (100 matches, 0
        /// off, left out when unknown), people named who are listed, and accounts named who
        /// are found. A part with nothing to check is left out; none at all is 100.
        public var score: Int {
            var parts: [Double] = []
            if let expectedCount, expectedCount > 0 { parts.append(Double(max(0, expectedCount - missing.count)) / Double(expectedCount)) }
            switch balance {
            case .matches: parts.append(1)
            case .off: parts.append(0)
            case .unknown: break
            }
            if peopleNamed > 0 { parts.append(Double(min(peopleCovered, peopleNamed)) / Double(peopleNamed)) }
            if accountsNamed > 0 { parts.append(Double(min(accountsFound, accountsNamed)) / Double(accountsNamed)) }
            guard !parts.isEmpty else { return 100 }
            return Int((parts.reduce(0, +) / Double(parts.count) * 100).rounded())
        }

        /// The review header for one file: "Import Completeness Score: 100% · 4542.pdf: 134 of
        /// 134 lines · balance matches".
        public func headline(file: String, currency: String) -> String {
            "Import Completeness Score: \(score)% · \(file): \(summary(currency: currency))"
        }

        /// "balance matches", "balance off by ₹47.49"; nil when the file prints no balances.
        public func balanceWords(currency: String) -> String? {
            switch balance {
            case .matches: return "balance matches"
            case .off(let by): return "balance off by \(fmtMoneyExact(abs(by), currency))"
            case .unknown: return nil
            }
        }
    }

    // MARK: the file's own reading

    /// The file read on the device. Nil when it cannot be: the check then says so and
    /// never blocks the import.
    public static func expected(for url: URL, password: String?) -> Expected? {
        guard let reading = try? StatementText.read(url, password: password) else { return nil }
        return expected(from: reading)
    }

    static func expected(from reading: StatementText.Reading) -> Expected {
        let opening = printedBalance("opening", rows: reading.rows)
            ?? printedBalance("opening", records: reading.records)
            ?? tableBalance(reading, opening: true)
        let closing = printedBalance("closing", rows: reading.rows)
            ?? printedBalance("closing", records: reading.records)
            ?? tableBalance(reading, opening: false)
        return Expected(lines: reading.lines, opening: opening, closing: closing)
    }

    /// The amount printed for "Opening balance" or "Closing balance": on the same row to
    /// the label's right, or in the row under it nearest the label. Summaries sit at the
    /// end, so the search runs backwards; a table heading followed by dated rows is passed.
    static func printedBalance(_ label: String, rows: [StatementRow]) -> Double? {
        for (index, row) in rows.enumerated().reversed() {
            guard let at = row.words.indices.first(where: { labelled(row.words, at: $0, label) }) else { continue }
            let span = (row.words[at].minX + row.words[at + 1].maxX) / 2
            if let same = row.words.first(where: { $0.minX >= row.words[at + 1].maxX && StatementLines.isAmountToken($0.text) }),
               let value = StatementLines.parseAmount(same.text) {
                return value
            }
            for next in rows[(index + 1)...].prefix(2) where !next.words.isEmpty {
                guard StatementLines.leadingDate(next.line) == nil else { break }
                let amounts = next.words.filter { StatementLines.isAmountToken($0.text) }
                guard !amounts.isEmpty else { continue }
                let near = amounts.min { abs(($0.minX + $0.maxX) / 2 - span) < abs(($1.minX + $1.maxX) / 2 - span) }
                if let near, let value = StatementLines.parseAmount(near.text) { return value }
            }
        }
        return nil
    }

    private static func labelled(_ words: [StatementWord], at index: Int, _ label: String) -> Bool {
        words.indices.contains(index + 1)
            && words[index].text.lowercased().hasPrefix(label)
            && words[index + 1].text.lowercased().hasPrefix("bal")
    }

    /// The same for a sheet: the amount in the cell after the label, or after it in the row.
    static func printedBalance(_ label: String, records: [[String]]) -> Double? {
        guard let regex = try? NSRegularExpression(pattern: #"\#(label)\s+bal\w*\.?\s*:?\s*(-?[\d,]*\d\.\d{1,2}|-?\d{1,3}(?:,\d{2,3})+)?"#, options: .caseInsensitive) else { return nil }
        for record in records.reversed() {
            for (column, cell) in record.enumerated() {
                guard let match = regex.firstMatch(in: cell, range: NSRange(cell.startIndex..., in: cell)) else { continue }
                if let range = Range(match.range(at: 1), in: cell), let value = StatementLines.parseAmount(String(cell[range])) { return value }
                for later in record.dropFirst(column + 1) {
                    let trimmed = later.trimmingCharacters(in: .whitespaces)
                    guard !trimmed.isEmpty else { continue }
                    guard StatementLines.isAmountToken(trimmed) || trimmed.range(of: #"^-?\d+(\.\d+)?$"#, options: .regularExpression) != nil else { break }
                    return StatementLines.parseAmount(trimmed)
                }
            }
        }
        return nil
    }

    /// With no summary printed, the running balance column: its last figure closes the
    /// statement, and its first figure less the first line's movement opens it.
    static func tableBalance(_ reading: StatementText.Reading, opening: Bool) -> Double? {
        let dated = reading.rows.filter { StatementLines.leadingDate($0.line) != nil }
        let balances = dated.map { row in row.words.filter { StatementLines.isAmountToken($0.text) } }.filter { $0.count >= 2 }
        guard dated.count >= 2, balances.count * 10 >= dated.count * 6 else { return nil }
        if opening {
            guard let first = balances.first?.last.flatMap({ StatementLines.parseAmount($0.text) }), let line = reading.lines.first else { return nil }
            return ((first + (line.direction == .debit ? line.amount : -line.amount)) * 100).rounded() / 100
        }
        return balances.last?.last.flatMap { StatementLines.parseAmount($0.text) }
    }

    // MARK: the comparison

    /// Date and amount to the paisa: what makes a returned charge answer for a line.
    public static func key(_ date: String, _ amount: Double) -> String {
        "\(date)|\(String(format: "%.2f", abs(amount)))"
    }

    /// The date with day and month traded, when that is a day too.
    static func swapped(_ iso: String) -> String? {
        let parts = iso.split(separator: "-")
        guard parts.count == 3, parts[1] != parts[2] else { return nil }
        let other = "\(parts[0])-\(parts[2])-\(parts[1])"
        return LB.parseDate(other) != nil ? other : nil
    }

    /// Whether this charge answers for this line: the same amount on the same day, or on
    /// the day with its month and day traded, as a model reads "05/10" now and then.
    public static func answers(_ charge: StatementCloud.Charge, for line: StatementLine) -> Bool {
        guard abs(abs(charge.amount) - line.amount) < 0.005 else { return false }
        return charge.date == line.date || swapped(line.date) == charge.date
    }

    /// The server's reading against the file's. The balance is taken over what the review
    /// will hold: the charges returned plus the lines still to be read from the file.
    public static func compare(prepared: StatementCloud.Prepared, expected: Expected?) -> Report {
        let charges = prepared.charges
        let named = charges.compactMap(\.member) + charges.filter { $0.counterpartKind == "person" }.compactMap(\.counterpart)
        let listed = Set(prepared.members.map { nameKey($0.name) })
        let accountsOnLines = charges.filter { $0.counterpartKind == "account" }.compactMap(\.counterpart)
        var report = Report(
            read: charges.count, expectedCount: expected?.count, missing: [], extra: 0, balance: .unknown,
            peopleNamed: distinct(named), peopleListed: prepared.members.count,
            accountsNamed: distinct(accountsOnLines),
            peopleCovered: Set(named.map(nameKey)).filter { !$0.isEmpty && listed.contains($0) }.count,
            accountsFound: distinct(accountsOnLines.filter { StatementCounterparts.accountName($0) != nil })
        )
        guard let expected else { return report }
        var pool: [String: Int] = [:]
        for charge in charges { pool[key(charge.date, charge.amount), default: 0] += 1 }
        // The file's own columns sign every line it prints, whatever kind the reader gave it.
        var net = 0.0
        for line in expected.lines {
            let exact = key(line.date, line.amount)
            if let left = pool[exact], left > 0 {
                pool[exact] = left - 1
            } else if let other = swapped(line.date), let left = pool[key(other, line.amount)], left > 0 {
                pool[key(other, line.amount)] = left - 1
            } else {
                report.missing.append(line)
            }
            net += line.direction == .credit ? line.amount : -line.amount
        }
        report.extra = pool.values.reduce(0, +)
        // A charge the file does not print still counts against the balance.
        for charge in charges {
            let at = key(charge.date, charge.amount)
            guard let left = pool[at], left > 0 else { continue }
            pool[at] = left - 1
            net += charge.kind == "income" ? charge.amount : -charge.amount
        }
        if let opening = expected.opening, let closing = expected.closing {
            let off = ((opening + net - closing) * 100).rounded() / 100
            report.balance = abs(off) < 0.005 ? .matches : .off(by: off)
        }
        return report
    }

    /// The reading with each line's direction set by the file's own columns: money the file
    /// prints as in is never a spend, nor money out an income. A transfer keeps its kind.
    public static func mended(_ prepared: StatementCloud.Prepared, expected: Expected?) -> StatementCloud.Prepared {
        guard let expected else { return prepared }
        var directions: [String: [StatementLine.Direction]] = [:]
        for line in expected.lines { directions[key(line.date, line.amount), default: []].append(line.direction) }
        var out = prepared
        out.charges = prepared.charges.map { charge in
            let exact = key(charge.date, charge.amount)
            let at = directions[exact]?.isEmpty == false ? exact : swapped(charge.date).map { key($0, charge.amount) } ?? exact
            guard let direction = directions[at]?.first else { return charge }
            directions[at]?.removeFirst()
            let kind: String
            switch (direction, charge.kind) {
            case (.credit, "spend"), (.credit, "fee"), (.credit, "for_member"): kind = "income"
            case (.debit, "income"): kind = "spend"
            default: return charge
            }
            return StatementCloud.Charge(date: charge.date, amount: charge.amount, name: charge.name, narration: charge.narration,
                                         account: charge.account, category: charge.category, kind: kind, member: charge.member,
                                         counterpart: charge.counterpart, counterpartKind: charge.counterpartKind, counterpartBank: charge.counterpartBank)
        }
        return out
    }

    /// Each name once, however it is cased or spaced.
    static func distinct(_ names: [String]) -> Int {
        Set(names.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }.filter { !$0.isEmpty }).count
    }

    // MARK: asking again

    /// The most a hint may carry.
    public static let hintLimit = 2_000

    /// What the second reading of a piece is told: the lines the first left out, by day
    /// and amount, and to answer whole.
    public static func hint(for missing: [StatementLine]) -> String {
        let head = "An earlier reading of this piece left out \(missing.count) line\(missing.count == 1 ? "" : "s"): "
        let tail = ". Read every line of the piece and answer whole."
        var listed: [String] = []
        for line in missing {
            let next = (listed + ["\(line.date) \(String(format: "%.2f", line.amount))"]).joined(separator: ", ")
            guard head.count + next.count + 2 + tail.count <= hintLimit else { listed.append("…"); break }
            listed.append("\(line.date) \(String(format: "%.2f", line.amount))")
        }
        return head + listed.joined(separator: ", ") + tail
    }

    /// Which pieces to ask again, each with the lines it should hold: by page when the
    /// lines know theirs, every piece when they do not.
    public static func piecesToAskAgain(missing: [StatementLine], pieces: Int, pagesPerPiece: Int = StatementCloud.pagesPerPiece) -> [Int: [StatementLine]] {
        guard pieces > 0 else { return [:] }
        var out: [Int: [StatementLine]] = [:]
        for line in missing {
            if let page = line.page, page > 0 {
                out[min((page - 1) / pagesPerPiece, pieces - 1), default: []].append(line)
            } else {
                for piece in 0..<pieces { out[piece, default: []].append(line) }
            }
        }
        return out
    }

    /// The second reading's charges for the lines the first left out, added once each; the
    /// first reading stands for everything else, so nothing is written twice.
    public static func merge(_ first: StatementCloud.ChargesAnswer, with second: StatementCloud.ChargesAnswer, missing: [StatementLine]) -> StatementCloud.ChargesAnswer {
        var left = missing
        var merged = first
        for charge in second.charges {
            guard let at = left.firstIndex(where: { answers(charge, for: $0) }) else { continue }
            left.remove(at: at)
            merged.charges.append(charge)
        }
        if merged.closingBalance == nil {
            merged.closingBalance = second.closingBalance
            merged.closingBalanceDate = second.closingBalanceDate
        }
        return merged
    }

    // MARK: filling from the file

    /// The lines still missing, as candidates read from the file: ticked, named plainly,
    /// money in marked as such.
    public static func fill(missing: [StatementLine], among tags: [String] = TagLibrary.entries(kind: "commitment").map(\.name),
                            today: String = LB.toISO(LB.todayMid())) -> [StatementCandidate] {
        missing.map { line in
            let name = StatementNaming.plainName(line.payee)
            let tag = StatementCategory.known(name, among: tags) ?? StatementCategory.known(line.payee, among: tags)
            let income = line.direction == .credit
            if line.date > today {
                return StatementCandidate(line: line, name: name, tag: tag, keep: false, skipReason: StatementTriage.afterToday,
                                          direction: income ? "in" : nil, readLocally: true)
            }
            if income {
                return StatementCandidate(line: line, name: name, tag: tag, keep: true, skipReason: nil, direction: "in", readLocally: true)
            }
            return StatementCandidate(line: line, name: name, tag: tag, keep: true, skipReason: nil, readLocally: true)
        }
    }

    // MARK: after the Add

    /// One kind of thing found wrong in the written vault, and how many: never what.
    public struct Finding: Equatable, Sendable {
        public let kind: String
        public let count: Int

        public init(kind: String, count: Int) {
            self.kind = kind
            self.count = count
        }
    }

    /// The written vault looked over: every imported one-time row notes its statement
    /// line, counterpart accounts and members exist, "(Guessed)" names carry a "Guessed:"
    /// note and only those, and no name carries money or brackets.
    public static func check(vault: [String: Any], importedIds: Set<String>) -> [Finding] {
        let commitments = vault["commitments"] as? [[String: Any]] ?? []
        let accounts = vault["accounts"] as? [[String: Any]] ?? []
        let members = vault["members"] as? [[String: Any]] ?? []
        let charges = vault["charges"] as? [[String: Any]] ?? []
        let accountIds = Set(accounts.compactMap { $0["id"] as? String })
        let memberIds = Set(members.compactMap { $0["id"] as? String })
        var chargeNotes: [String: [String]] = [:]
        for charge in charges {
            guard let id = charge["commitment_id"] as? String, let note = charge["note"] as? String else { continue }
            chargeNotes[id, default: []].append(note)
        }
        var counts: [String: Int] = [:]
        func found(_ kind: String) { counts[kind, default: 0] += 1 }
        for row in commitments {
            guard let id = row["id"] as? String else { continue }
            let name = row["name"] as? String ?? ""
            let noteLines = (row["notes"] as? String ?? "").components(separatedBy: .newlines)
            if importedIds.contains(id), row["billing_cycle"] as? String == BillingCycle.once.rawValue,
               !(noteLines + (chargeNotes[id] ?? [])).contains(where: { $0.hasPrefix("Statement line:") }) {
                found("note_missing")
            }
            if let details = row["details"] as? [String: Any], let other = details["counterpart_account_id"] as? String,
               !accountIds.contains(other) {
                found("counterpart_unknown")
            }
            if name.hasSuffix("(Guessed)") != noteLines.contains(where: { $0.hasPrefix("Guessed:") }) { found("guessed_mismatch") }
            if carriesMoney(name) { found("commitment_name_untidy") }
            if let member = row["member_id"] as? String, !memberIds.contains(member) { found("member_unknown") }
        }
        for row in accounts {
            if carriesMoney(row["name"] as? String ?? "") { found("account_name_untidy") }
            if let member = row["member_id"] as? String, !memberIds.contains(member) { found("member_unknown") }
        }
        for row in members where carriesMoney(row["name"] as? String ?? "") {
            found("member_name_untidy")
        }
        return counts.keys.sorted().map { Finding(kind: $0, count: counts[$0] ?? 0) }
    }

    /// A name with a currency sign, an amount, or brackets other than a trailing "(Guessed)".
    static func carriesMoney(_ name: String) -> Bool {
        var text = name
        if text.hasSuffix("(Guessed)") { text = String(text.dropLast("(Guessed)".count)) }
        if text.contains(where: { "₹$€£¥".contains($0) || "()[]{}".contains($0) }) { return true }
        return text.range(of: #"\d[\d,]*\.\d{1,2}\b|\d{1,3}(,\d{2,3})+|\b(?:rs|inr)\.?\s*\d"#, options: [.regularExpression, .caseInsensitive]) != nil
    }
}

private extension Optional where Wrapped == String {
    var orEmpty: String { self ?? "" }
}
