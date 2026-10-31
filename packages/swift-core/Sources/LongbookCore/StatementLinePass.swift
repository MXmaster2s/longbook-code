// A statement the device can vouch for is read here and named there: every line, its day,
// amount and direction come from the file, and the model adds only what a device cannot
// know. Anything the device cannot vouch for goes to the server as a document instead.
import Foundation

public enum StatementLinePass {
    // MARK: when the device can be trusted

    /// Why a file goes as a document, each reason a different failure of proof.
    public enum Distrust: String, Equatable, Sendable {
        case unreadable, tooFewLines, oddLine, noBalances, doesNotClose
    }

    /// The fewest lines worth reading this way, the same count that makes a sheet a statement.
    public static let fewestLines = 3

    /// Nil when the device's lines can stand as the statement: at least a few, each a real
    /// day and an amount, and they carry the opening balance to the closing one to the
    /// paisa. A dropped line, a doubled one or a wrong direction all break that sum.
    public static func distrust(_ expected: StatementCompleteness.Expected?, today: String = LB.toISO(LB.todayMid())) -> Distrust? {
        guard let expected else { return .unreadable }
        guard expected.count >= fewestLines else { return .tooFewLines }
        let odd = expected.lines.contains { line in
            LB.parseDate(line.date) == nil || line.date > today || line.amount <= 0
                || !line.payee.contains(where: { $0.isLetter })
        }
        if odd { return .oddLine }
        guard expected.opening != nil, expected.closing != nil else { return .noBalances }
        return expected.closes ? nil : .doesNotClose
    }

    // MARK: what is sent

    /// One line as the server reads it.
    public struct Line: Encodable, Equatable, Sendable {
        public let n: Int
        public let date: String
        public let amount: Double
        public let direction: String
        public let text: String
    }

    /// A trusted file, ready to ask about.
    public struct Plan: Sendable {
        public let name: String
        public let expected: StatementCompleteness.Expected
        public let lines: [Line]
        public let header: String

        public init(name: String, expected: StatementCompleteness.Expected) {
            self.name = name
            self.expected = expected
            lines = expected.lines.enumerated().map { index, line in
                Line(n: index + 1, date: line.date, amount: line.amount, direction: line.direction == .credit ? "in" : "out",
                     text: StatementLinePass.masked(line.payee))
            }
            header = StatementLinePass.masked(expected.header)
        }

        /// Lines to a call: few enough that one answer is quick and, run side by side, a
        /// statement's whole reading takes no longer than its slowest batch.
        public static let linesPerBatch = 30

        public var batches: [[Line]] {
            stride(from: 0, to: lines.count, by: Self.linesPerBatch).map { Array(lines[$0..<min($0 + Self.linesPerBatch, lines.count)]) }
        }
    }

    /// A long run of digits printed against a word, as a reference column overrun by a
    /// narration is, set apart so the word survives whatever is later done to the number.
    static func separated(_ text: String) -> String {
        text.replacingOccurrences(of: #"(\p{L})(\d{9,})"#, with: "$1 $2", options: .regularExpression)
    }

    /// A line as it may leave the device: a long number hides all but its last four, one dot
    /// a digit, so its length still says what kind it is. A bank's public IFSC code stays whole.
    public static func masked(_ text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"(?<![A-Z])[A-Z]{4}0[A-Z0-9]{6}(?![A-Z0-9])|\d(?:[ -]?\d){4,}"#) else { return text }
        let source = separated(text)
        var out = source
        for match in regex.matches(in: source, range: NSRange(source.startIndex..., in: source)).reversed() {
            guard let range = Range(match.range, in: out), out[range].first?.isNumber == true else { continue }
            let digits = out[range].filter(\.isNumber)
            out.replaceSubrange(range, with: String(repeating: "•", count: digits.count - 4) + digits.suffix(4))
        }
        return out
    }

    // MARK: what comes back

    /// The head: the gate's yes, and the header's three facts.
    public struct Head: Decodable, Equatable, Sendable {
        public let account: String
        public let holder: String?
        public let currency: String?
    }

    /// What the model adds to one line.
    public struct Row: Decodable, Equatable, Sendable {
        public let n: Int
        public let name: String
        public let kind: String
        public let category: String?
        public let member: String?
        public let counterpart: String?
        public let counterpartKind: String?
        public let counterpartBank: String?

        enum CodingKeys: String, CodingKey {
            case n, name, kind, category, member, counterpart
            case counterpartKind = "counterpart_kind"
            case counterpartBank = "counterpart_bank"
        }

        public init(n: Int, name: String, kind: String, category: String? = nil, member: String? = nil, counterpart: String? = nil,
                    counterpartKind: String? = nil, counterpartBank: String? = nil) {
            self.n = n
            self.name = name
            self.kind = kind
            self.category = category
            self.member = member
            self.counterpart = counterpart
            self.counterpartKind = counterpartKind
            self.counterpartBank = counterpartBank
        }
    }

    struct RowsAnswer: Decodable { let rows: [Row] }

    /// One repeat as the model groups it: by line number, so its days and amount stay facts.
    public struct RepeatRow: Decodable, Equatable, Sendable {
        public let name: String
        public let lines: [Int]
        public let cycle: String
        public let customDays: Int?
        public let category: String?
        public let endsOn: String?
        public let reason: String

        enum CodingKeys: String, CodingKey {
            case name, lines, cycle, category, reason
            case customDays = "custom_days"
            case endsOn = "ends_on"
        }

        public init(name: String, lines: [Int], cycle: String, customDays: Int? = nil, category: String? = nil, endsOn: String? = nil, reason: String = "") {
            self.name = name
            self.lines = lines
            self.cycle = cycle
            self.customDays = customDays
            self.category = category
            self.endsOn = endsOn
            self.reason = reason
        }
    }

    struct RepeatsAnswer: Decodable { let repeats: [RepeatRow] }

    // MARK: assembling

    /// Every line of the plan as a charge, with what the model added to it. The file settles
    /// the day, the amount and the direction; a line with no row is named as printed.
    public static func answer(_ plan: Plan, head: Head, rows: [Row], notes: String = "") -> StatementCloud.ChargesAnswer {
        let byLine = Dictionary(rows.map { ($0.n, $0) }, uniquingKeysWith: { first, _ in first })
        let tags = TagLibrary.entries(kind: "commitment").map(\.name)
        let charges = plan.expected.lines.enumerated().map { index, line -> StatementCloud.Charge in
            let row = byLine[index + 1].map { bankedPerson(ownLine(realAccount($0), printed: line.payee, holder: head.holder), printed: line.payee) }
            let incoming = line.direction == .credit
            let plain = StatementNaming.plainName(separated(line.payee))
            let kind = incoming ? "income" : (row?.kind == "income" || row == nil ? "spend" : row?.kind ?? "spend")
            return StatementCloud.Charge(
                date: line.date, amount: line.amount, name: row?.name ?? plain, narration: StatementNaming.scrubbed(separated(line.payee)),
                account: head.account, category: row?.category ?? (row == nil ? StatementCategory.known(plain, among: tags) : nil),
                kind: kind, member: row?.member, counterpart: row?.counterpart, counterpartKind: row?.counterpartKind,
                counterpartBank: row?.counterpartBank
            )
        }
        return StatementCloud.ChargesAnswer(
            account: head.account, holder: head.holder, charges: charges, notes: notes,
            closingBalance: plan.expected.closing, closingBalanceDate: plan.expected.lines.map(\.date).max(), currency: head.currency
        )
    }

    /// An other side the model called an account when no account can be named from it, as
    /// "CRED" or "UPI": the line has none. The charge stands, and nothing waits to be found.
    static func realAccount(_ row: Row) -> Row {
        guard row.counterpartKind == "account", let raw = row.counterpart, StatementCounterparts.accountName(raw) == nil else { return row }
        return Row(n: row.n, name: row.name, kind: row.kind, category: row.category, member: row.member, counterpartBank: row.counterpartBank)
    }

    /// A line is the holder's only when it prints two words of their name, or all of a shorter
    /// one: the people rule the device can check, and what the Transfers rule stands on. An
    /// account the model put on such a line is the holder's.
    static func ownLine(_ row: Row, printed: String, holder: String?) -> Row {
        guard let holder = StatementHolder.clean(holder) else { return row }
        let known = StatementHolder.words(holder)
        guard !known.isEmpty else { return row }
        let shared = StatementHolder.words(separated(printed)).intersection(known)
        guard shared.count >= min(2, known.count) else { return notHolder(row, printed: printed, holder: holder, shared: shared) }
        let bank = row.counterpartBank ?? (row.counterpartKind == "account" ? row.counterpart : nil)
        return Row(n: row.n, name: row.name, kind: row.kind == "for_member" ? "spend" : row.kind, category: row.category, member: nil, counterpart: holder,
                   counterpartKind: "person", counterpartBank: bank)
    }

    /// A model that called a line's person the holder when the line does not print enough of
    /// their name has guessed. The person is what the line prints, or nobody, and neither they
    /// nor their account are the holder's. The charge's name follows.
    static func notHolder(_ row: Row, printed: String, holder: String, shared: Set<String>) -> Row {
        let said = row.member ?? (row.counterpartKind == "person" ? row.counterpart : nil)
        guard let said, StatementHolder.same(said, holder) else { return row }
        let person = printedName(printed, sharing: shared)
        let plain = StatementNaming.plainName(separated(printed))
        let renamed = person.map { StatementNaming.swapPerson(row.name, from: holder, to: $0) } ?? plain
        let name = StatementHolder.same(renamed, holder) || nameCarries(renamed, holder) ? (person ?? plain) : renamed
        guard let person else {
            return Row(n: row.n, name: name, kind: row.kind == "for_member" ? "spend" : row.kind, category: row.category)
        }
        return Row(n: row.n, name: name, kind: row.kind, category: row.category, member: row.member == nil ? nil : person,
                   counterpart: row.counterpartKind == "person" ? person : row.counterpart, counterpartKind: row.counterpartKind,
                   counterpartBank: row.counterpartBank)
    }

    /// Whether a name still carries the person, in a form swapPerson did not recognise.
    private static func nameCarries(_ name: String, _ person: String) -> Bool {
        StatementHolder.words(name).intersection(StatementHolder.words(person)).count >= 2
    }

    /// The name the line prints around the words it shares with the holder: the stretch of the
    /// line between separators, as the line has it. Nil when it shares none.
    static func printedName(_ printed: String, sharing shared: Set<String>) -> String? {
        guard !shared.isEmpty else { return nil }
        let stretches = separated(printed).split(whereSeparator: { "-/|:".contains($0) }).map(String.init)
        return stretches.first { !StatementHolder.words($0).isDisjoint(with: shared) && !$0.contains("@") }.flatMap(StatementCounterparts.personName)
    }

    /// The bank an IFSC code names, the way the statement rules say it. Unknown codes stay
    /// with the model, which reads the line itself.
    static let ifscBanks: [String: String] = [
        "UTIB": "Axis Bank", "BARB": "Bank of Baroda", "HDFC": "HDFC Bank", "ICIC": "ICICI Bank", "SBIN": "State Bank of India",
        "KKBK": "Kotak", "SURY": "Suryoday Small Finance Bank", "PUNB": "Punjab National Bank", "CNRB": "Canara Bank",
        "UBIN": "Union Bank of India", "BKID": "Bank of India", "IDFB": "IDFC First Bank", "INDB": "IndusInd Bank", "YESB": "Yes Bank",
        "FDRL": "Federal Bank", "IDIB": "Indian Bank", "IOBA": "Indian Overseas Bank", "MAHB": "Bank of Maharashtra",
        "CBIN": "Central Bank of India", "AUBL": "AU Small Finance Bank", "RATN": "RBL Bank", "KARB": "Karnataka Bank",
        "PYTM": "Paytm Payments Bank", "AIRP": "Airtel Payments Bank", "DBSS": "DBS Bank", "SCBL": "Standard Chartered", "HSBC": "HSBC",
        "BDBL": "Bandhan Bank", "UCBA": "UCO Bank", "PSIB": "Punjab & Sind Bank", "SIBL": "South Indian Bank", "CIUB": "City Union Bank",
        "KVBL": "Karur Vysya Bank", "TMBL": "Tamilnad Mercantile Bank", "DCBL": "DCB Bank", "IBKL": "IDBI Bank", "ESFB": "Equitas Small Finance Bank",
        "UJVN": "Ujjivan Small Finance Bank", "JAKA": "J&K Bank", "JIOP": "Jio Payments Bank", "FINO": "Fino Payments Bank", "IPOS": "India Post Payments Bank",
        "NSPB": "NSDL Payments Bank", "CITI": "Citibank",
    ]

    /// A person on a line that prints an IFSC code has an account at that bank: the code
    /// counts as printed, and every account a statement names becomes an Account.
    static func bankedPerson(_ row: Row, printed: String) -> Row {
        guard row.counterpartBank == nil, row.counterpartKind == "person" || row.member != nil,
              let range = printed.range(of: #"(?<![A-Z])[A-Z]{4}0[A-Z0-9]{6}(?![A-Z0-9])"#, options: .regularExpression),
              let bank = ifscBanks[String(printed[range].prefix(4))]
        else { return row }
        return Row(n: row.n, name: row.name, kind: row.kind, category: row.category, member: row.member,
                   counterpart: row.counterpart ?? row.member, counterpartKind: row.counterpartKind ?? "person", counterpartBank: bank)
    }

    /// The named lines, grouped by name, as the look-over reads them.
    public static func groups(_ plan: Plan, charges: [StatementCloud.Charge]) -> String {
        var order: [String] = []
        var held: [String: [Int]] = [:]
        for (index, charge) in charges.enumerated() {
            let key = charge.name.lowercased()
            if held[key] == nil { order.append(key) }
            held[key, default: []].append(index)
        }
        return order.map { key -> String in
            let at = held[key] ?? []
            let first = charges[at[0]]
            let sightings = at.map { "\(plan.lines[$0].n) \(plan.lines[$0].date) \(String(format: "%.2f", plan.lines[$0].amount))" }
            return [first.name, plan.lines[at[0]].direction, first.category ?? "", String(plan.lines[at[0]].text.prefix(120)),
                    sightings.joined(separator: "; ")].joined(separator: " | ")
        }.joined(separator: "\n")
    }

    /// The model's groupings as repeats. Days and amount come from the lines themselves, a
    /// line of another name is left out, and fewer than three sightings is a guess.
    public static func repeats(_ rows: [RepeatRow], plan: Plan, charges: [StatementCloud.Charge]) -> [StatementCloud.Repeat] {
        rows.compactMap { row in
            let at = Array(Set(row.lines)).map { $0 - 1 }.filter { charges.indices.contains($0) && nameKey(charges[$0].name) == nameKey(row.name) }
            guard !at.isEmpty else { return nil }
            let amounts = at.map { plan.expected.lines[$0].amount }
            let amount = Dictionary(amounts.map { ($0, 1) }, uniquingKeysWith: +).max { ($0.value, $0.key) < ($1.value, $1.key) }?.key ?? amounts[0]
            let guessed = at.count < 3
            return StatementCloud.Repeat(name: charges[at[0]].name, cycle: row.cycle, customDays: row.customDays, amount: amount,
                                         dates: at.map { plan.expected.lines[$0].date }.sorted(), category: row.category, endsOn: row.endsOn,
                                         guessed: guessed, reason: guessed ? row.reason.trimmingCharacters(in: .whitespacesAndNewlines) : "")
        }
    }

    /// Everyone a line names, once, in line order: the member and the person on the other
    /// side, who need not be spelled alike.
    public static func members(in charges: [StatementCloud.Charge]) -> [StatementCloud.Member] {
        var seen: Set<String> = []
        return charges.flatMap { charge -> [String] in
            [charge.member, charge.counterpartKind == "person" ? charge.counterpart : nil].compactMap { $0 }
        }.compactMap { person in
            let name = person.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, seen.insert(nameKey(name)).inserted else { return nil }
            return StatementCloud.Member(name: name, role: "", reason: "Named on a line")
        }
    }

    // MARK: reading

    /// How far a file has come, as plain state for the reading screen. `lines` is known
    /// before anything is asked; the rest count up as batches return.
    public struct Progress: Equatable, Sendable {
        public var lines: Int
        public var batches: Int
        public var batchesDone = 0
        public var named = 0
        public var people = 0
        public var accounts = 0
        public var repeats = 0
        public var finished = false

        public init(lines: Int, batches: Int) {
            self.lines = lines
            self.batches = batches
        }
    }

    /// The reading, and what it proved.
    public struct Outcome: Sendable {
        public let prepared: StatementCloud.Prepared
        public let report: StatementCompleteness.Report
    }

    /// No batch came back: the caller reads the file as a document instead.
    public struct NothingNamed: Error {}

    /// The server's answers as bytes, however they are carried: over the network in the app.
    public typealias Transport = @Sendable (Data) async throws -> Data

    /// The book's words the model is told, and the call's identity.
    public struct Asking: Sendable {
        public let importId: String
        public let categories: [String]
        public let members: [String]
        public let accounts: [String]
        public let currency: String

        public init(importId: String, categories: [String], members: [String], accounts: [String], currency: String) {
            self.importId = importId
            self.categories = categories
            self.members = members
            self.accounts = accounts
            self.currency = currency
        }
    }

    private struct HeadBody: Encodable {
        let task = "head"
        let import_id: String
        let file_name: String
        let header: String
        let lines: [Line]
        let categories: [String] = []
        let members: [String] = []
        let accounts: [String] = []
        let currency: String
    }

    private struct LinesBody: Encodable {
        let task = "lines"
        let import_id: String
        let account_hint: String
        let holder: String?
        let lines: [Line]
        let categories: [String]
        let members: [String]
        let accounts: [String]
        let currency: String
    }

    private struct RepeatsBody: Encodable {
        let task = "repeats"
        let import_id: String
        let groups: String
        let categories: [String]
        let members: [String] = []
        let accounts: [String] = []
        let currency: String
    }

    /// How many of the first lines the head looks at beside the header.
    static let headLines = 12

    /// One file: the head names it and is the gate; the batches go side by side; a batch that
    /// failed or lines left out are asked once more, then named as printed; then the look-over.
    /// A share spent or a file refused is thrown as it came.
    public static func read(_ plan: Plan, asking: Asking, transport: @escaping Transport,
                            progress: @Sendable (Progress) async -> Void = { _ in }) async throws -> Outcome {
        var state = Progress(lines: plan.lines.count, batches: plan.batches.count)
        await progress(state)
        let head: Head = try await ask(HeadBody(import_id: asking.importId, file_name: plan.name, header: plan.header,
                                                lines: Array(plan.lines.prefix(headLines)), currency: asking.currency), transport)
        var rows: [Row] = []
        var failure: Error?
        func body(_ lines: [Line]) -> LinesBody {
            LinesBody(import_id: asking.importId, account_hint: head.account, holder: head.holder, lines: lines,
                      categories: asking.categories, members: asking.members, accounts: asking.accounts, currency: asking.currency)
        }
        func side(_ batches: [[Line]], counting: Bool) async {
            await withTaskGroup(of: Result<RowsAnswer, Error>.self) { group in
                for lines in batches {
                    let carried = body(lines)
                    group.addTask {
                        do { return .success(try await ask(carried, transport)) } catch { return .failure(error) }
                    }
                }
                for await result in group {
                    switch result {
                    case .success(let answer):
                        rows += answer.rows
                    case .failure(let error):
                        failure = failure ?? error
                    }
                    if counting { state.batchesDone += 1 }
                    state.named = Set(rows.map(\.n)).count
                    state.people = Set(rows.compactMap { $0.member ?? ($0.counterpartKind == "person" ? $0.counterpart : nil) }.map(nameKey)).count
                    state.accounts = Set(rows.compactMap { $0.counterpartKind == "account" ? $0.counterpart : $0.counterpartBank }.map(nameKey)).count
                    await progress(state)
                }
            }
        }
        await side(plan.batches, counting: true)
        if case .shareSpent? = failure as? StatementCloud.CloudError { throw StatementCloud.CloudError.shareSpent }
        let left = plan.lines.filter { line in !rows.contains { $0.n == line.n } }
        if !left.isEmpty {
            await side(stride(from: 0, to: left.count, by: Plan.linesPerBatch).map { Array(left[$0..<min($0 + Plan.linesPerBatch, left.count)]) }, counting: false)
        }
        guard !rows.isEmpty else { throw failure ?? NothingNamed() }

        let unnamed = plan.lines.filter { line in !rows.contains { $0.n == line.n } }.count
        let notes = unnamed == 0 ? "" : "\(unnamed) line\(unnamed == 1 ? " is" : "s are") named as the statement prints \(unnamed == 1 ? "it" : "them")."
        let read = answer(plan, head: head, rows: rows, notes: notes)
        let named = StatementCloud.Prepared.assemble([read], review: .empty, mendingDates: false)
        var looked: [RepeatRow] = []
        if let answered: RepeatsAnswer = try? await ask(RepeatsBody(import_id: asking.importId, groups: groups(plan, charges: named.charges),
                                                                     categories: asking.categories, currency: asking.currency), transport) {
            looked = answered.repeats
        }
        let found = repeats(looked, plan: plan, charges: named.charges)
        let prepared = StatementCloud.Prepared.assemble([read], review: StatementCloud.ReviewAnswer(repeats: found, members: members(in: named.charges), notes: ""), mendingDates: false)
        state.repeats = found.count
        state.finished = true
        await progress(state)
        var report = StatementCompleteness.compare(prepared: prepared, expected: plan.expected)
        report.named = plan.lines.count - unnamed
        return Outcome(prepared: prepared, report: report)
    }

    private static func ask<Answer: Decodable>(_ body: some Encodable, _ transport: Transport) async throws -> Answer {
        let data = try JSONEncoder().encode(body)
        await StatementCloud.gate.enter()
        defer { StatementCloud.gate.leave() }
        return try JSONDecoder().decode(Answer.self, from: try await transport(data))
    }
}
