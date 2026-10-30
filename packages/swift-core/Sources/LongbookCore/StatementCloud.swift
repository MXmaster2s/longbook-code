// One statement goes to longbook's server in small pieces — a few pages, or a run of rows —
// and each comes back as every charge it holds; then the whole year's charges go once more
// for the people and the rhythms in them. Small pieces, so an answer is always whole.
import Foundation
#if canImport(PDFKit)
import PDFKit
#endif

public enum StatementCloud {
    public enum CloudError: LocalizedError {
        case notSignedIn
        case tooLarge(String)
        case server(String)
        case unreachable
        /// The account's share of server readings is spent for now; the words never say how many.
        case shareSpent
        /// The server looked at the file's first piece and found no statement in it.
        case notStatement(String)

        public var errorDescription: String? {
            switch self {
            case .notSignedIn: return "Sign in first — the statement is read by your own account."
            case .tooLarge(let name): return "\(name) is larger than a statement should be. Pick the statement itself, not a scan."
            case .server(let said): return said
            case .unreachable: return "longbook's server could not be reached. Check the connection and try again."
            case .shareSpent:
                return "longbook's server has read all the statements it can for your account for now. Write to us to read more, or use your own AI for this step."
            case .notStatement(let said): return said
            }
        }
    }

    /// One piece of a file as it is sent, and the words that say which piece.
    public struct Piece: Encodable, Equatable, Sendable {
        public let name: String
        public let type: String
        public let data: String
        /// "pages 4–6 of 12", "rows 151–300 of 527".
        public let label: String

        enum CodingKeys: String, CodingKey { case name, type, data }
    }

    public struct Charge: Decodable, Equatable, Sendable {
        public let date: String
        public let amount: Double
        public let name: String
        public let narration: String
        public let account: String
        public let category: String?
        public let kind: String
        public let member: String?
        /// The other account or person the line moves money to or from, when it prints one;
        /// `counterpartKind` is "account" or "person". An answer without them reads as nil.
        public let counterpart: String?
        public let counterpartKind: String?
        /// The bank account printed beside a person on the other side ("Axis savings ••1234"),
        /// or the owner's own other account; nil when the line prints none.
        public let counterpartBank: String?

        enum CodingKeys: String, CodingKey {
            case date, amount, name, narration, account, category, kind, member, counterpart
            case counterpartKind = "counterpart_kind"
            case counterpartBank = "counterpart_bank"
        }

        public init(date: String, amount: Double, name: String, narration: String, account: String, category: String?,
                    kind: String, member: String?, counterpart: String? = nil, counterpartKind: String? = nil, counterpartBank: String? = nil) {
            self.date = date
            self.amount = amount
            self.name = name
            self.narration = narration
            self.account = account
            self.category = category
            self.kind = kind
            self.member = member
            self.counterpart = counterpart
            self.counterpartKind = counterpartKind
            self.counterpartBank = counterpartBank
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            date = try c.decode(String.self, forKey: .date)
            amount = try c.decode(Double.self, forKey: .amount)
            name = try c.decode(String.self, forKey: .name)
            narration = try c.decode(String.self, forKey: .narration)
            account = try c.decode(String.self, forKey: .account)
            category = try c.decodeIfPresent(String.self, forKey: .category)
            kind = try c.decode(String.self, forKey: .kind)
            member = try c.decodeIfPresent(String.self, forKey: .member)
            counterpart = try c.decodeIfPresent(String.self, forKey: .counterpart)
            counterpartKind = try c.decodeIfPresent(String.self, forKey: .counterpartKind)
            counterpartBank = try c.decodeIfPresent(String.self, forKey: .counterpartBank)
        }

        /// The same line under another name.
        func renamed(_ name: String) -> Charge {
            Charge(date: date, amount: amount, name: name, narration: narration, account: account, category: category, kind: kind,
                   member: member, counterpart: counterpart, counterpartKind: counterpartKind, counterpartBank: counterpartBank)
        }
    }

    /// The charges task's answer for one piece.
    public struct ChargesAnswer: Decodable, Equatable, Sendable {
        public var account: String
        public var charges: [Charge]
        public var notes: String
        /// The balance the piece prints at its end, and the day — when it prints one.
        public var closingBalance: Double?
        public var closingBalanceDate: String?
        /// The ISO code the piece prints its amounts in; nil when it does not show one.
        public var currency: String?

        enum CodingKeys: String, CodingKey {
            case account, charges, notes, currency
            case closingBalance = "closing_balance"
            case closingBalanceDate = "closing_balance_date"
        }
    }

    public struct Repeat: Decodable, Equatable, Sendable {
        public let name: String
        public let cycle: String
        public let customDays: Int?
        public let amount: Double
        public let dates: [String]
        public let category: String?
        public let endsOn: String?
        /// Backed by fewer than three sightings: the name says so and `reason` says why, in
        /// one sentence. An answer without the fields reads as not guessed.
        public let guessed: Bool
        public let reason: String

        enum CodingKeys: String, CodingKey {
            case name, cycle, amount, dates, category, guessed, reason
            case customDays = "custom_days"
            case endsOn = "ends_on"
        }

        public init(name: String, cycle: String, customDays: Int?, amount: Double, dates: [String], category: String?, endsOn: String?,
                    guessed: Bool = false, reason: String = "") {
            self.name = name
            self.cycle = cycle
            self.customDays = customDays
            self.amount = amount
            self.dates = dates
            self.category = category
            self.endsOn = endsOn
            self.guessed = guessed
            self.reason = guessed ? reason : ""
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let guessed = try c.decodeIfPresent(Bool.self, forKey: .guessed) ?? false
            self.init(name: try c.decode(String.self, forKey: .name), cycle: try c.decode(String.self, forKey: .cycle),
                      customDays: try c.decodeIfPresent(Int.self, forKey: .customDays), amount: try c.decode(Double.self, forKey: .amount),
                      dates: try c.decodeIfPresent([String].self, forKey: .dates) ?? [], category: try c.decodeIfPresent(String.self, forKey: .category),
                      endsOn: try c.decodeIfPresent(String.self, forKey: .endsOn), guessed: guessed,
                      reason: (try c.decodeIfPresent(String.self, forKey: .reason) ?? "").trimmingCharacters(in: .whitespacesAndNewlines))
        }

        /// The same repeat under the name the owner would say.
        func renamed(_ name: String) -> Repeat {
            Repeat(name: name, cycle: cycle, customDays: customDays, amount: amount, dates: dates, category: category, endsOn: endsOn,
                   guessed: guessed, reason: reason)
        }

        /// The name the commitment is written under: a guess says so at its end.
        public var writtenName: String { guessed ? "\(name) (Guessed)" : name }

        /// The first line of a guessed commitment's notes; nil when nothing was guessed.
        public var guessedNote: String? {
            guard guessed else { return nil }
            return "Guessed: \(reason.isEmpty ? "seen fewer than three times" : reason)"
        }
    }

    public struct Member: Decodable, Equatable, Sendable {
        public let name: String
        public let role: String
        public let reason: String

        public init(name: String, role: String, reason: String) {
            self.name = name
            self.role = role
            self.reason = reason
        }
    }

    /// The review task's answer over the year.
    public struct ReviewAnswer: Decodable, Equatable, Sendable {
        public var repeats: [Repeat]
        public var members: [Member]
        public var notes: String

        public static let empty = ReviewAnswer(repeats: [], members: [], notes: "")
    }

    /// Everything the review shows, assembled from the pieces and the look-over.
    public struct Prepared: Equatable {
        public var account: String
        public var charges: [Charge]
        public var repeats: [Repeat]
        public var members: [Member]
        public var notes: String
        /// The statement's closing balance and its day: the latest a piece printed.
        public var balance: Double?
        public var balanceDate: String?
        /// The currency most pieces say they print, as an ISO code.
        public var currency: String?

        public init(account: String, charges: [Charge], repeats: [Repeat], members: [Member], notes: String,
                    balance: Double? = nil, balanceDate: String? = nil, currency: String? = nil) {
            self.currency = currency
            self.account = account
            self.charges = charges
            self.repeats = repeats
            self.members = members
            self.notes = notes
            self.balance = balance
            self.balanceDate = balanceDate
        }

        /// The pieces' answers as one: the account the first piece named, every charge in
        /// order with its date checked, the notes joined.
        public static func assemble(_ answers: [ChargesAnswer], review: ReviewAnswer, today: String = LB.toISO(LB.todayMid())) -> Prepared {
            let account = answers.first { !$0.account.trimmingCharacters(in: .whitespaces).isEmpty }?.account ?? ""
            var notes = answers.map(\.notes) + [review.notes]
            notes = notes.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            // The latest closing line wins; one without a date only counts when no dated one exists.
            let closing = answers.compactMap { answer -> (Double, String?)? in
                answer.closingBalance.map { ($0, answer.closingBalanceDate.flatMap { LB.parseDate($0) != nil && $0 <= today ? $0 : nil }) }
            }
            let dated = closing.filter { $0.1 != nil }.max { ($0.1 ?? "") < ($1.1 ?? "") }
            let balance = dated ?? closing.last
            let codes = answers.compactMap { $0.currency?.trimmingCharacters(in: .whitespaces).uppercased() }
                .filter { $0.count == 3 && $0.allSatisfy(\.isLetter) }
            let currency = Dictionary(codes.map { ($0, 1) }, uniquingKeysWith: +).max { $0.value < $1.value }?.key
            // Names arrive cleaned on both sides, so a repeat still names the charges it groups.
            let charges = mendDates(answers.flatMap(\.charges), today: today).map { $0.renamed(StatementNaming.clean($0.name)) }
            let repeats = review.repeats.map { $0.renamed(StatementNaming.clean($0.name)) }
            return Prepared(account: account, charges: charges, repeats: repeats,
                            members: review.members, notes: notes.joined(separator: " "),
                            balance: balance?.0, balanceDate: balance?.1, currency: currency)
        }

        /// A model reads "05/10/2026" as the fifth of October now and then; the statement
        /// meant the tenth of May. A date after today, or one that jumps out of the file's
        /// order, is read the other way round when that puts it right.
        static func mendDates(_ charges: [Charge], today: String) -> [Charge] {
            func swapped(_ iso: String) -> String? {
                let parts = iso.split(separator: "-")
                guard parts.count == 3, parts[1] != parts[2] else { return nil }
                let other = "\(parts[0])-\(parts[2])-\(parts[1])"
                return LB.parseDate(other) != nil ? other : nil
            }
            func days(_ a: String, _ b: String) -> Int? {
                guard let x = LB.parseDate(a), let y = LB.parseDate(b) else { return nil }
                return Int(x.timeIntervalSince(y) / 86_400)
            }
            var out: [Charge] = []
            var previous: String?
            for charge in charges {
                var date = charge.date
                if let other = swapped(date) {
                    let future = date > today
                    let adrift = previous.flatMap { days(date, $0) }.map { abs($0) > 45 } ?? false
                    let otherFits = other <= today && (previous.flatMap { days(other, $0) }.map { abs($0) <= 45 } ?? true)
                    if (future || adrift) && otherFits { date = other }
                }
                if date <= today { previous = date }
                out.append(date == charge.date ? charge : Charge(date: date, amount: charge.amount, name: charge.name, narration: charge.narration,
                                                                  account: charge.account, category: charge.category, kind: charge.kind, member: charge.member,
                                                                  counterpart: charge.counterpart, counterpartKind: charge.counterpartKind,
                                                                  counterpartBank: charge.counterpartBank))
            }
            return out
        }

        /// The charges as candidates: money out ticked, money in ticked and marked as such,
        /// the owner's own movements unticked with the reason. `file` carries the account.
        public func candidates(among tags: [String], today: String = LB.toISO(LB.todayMid())) -> [StatementCandidate] {
            charges.compactMap { charge in
                guard LB.parseDate(charge.date) != nil, charge.amount > 0 else { return nil }
                let line = StatementLine(date: charge.date, payee: charge.narration, amount: charge.amount,
                                         direction: charge.kind == "income" ? .credit : .debit)
                // A day ahead of today is refused first, whatever the kind: an own movement
                // dated tomorrow is no more proven than a charge is, and must not be kept.
                let skip: String?
                if charge.date > today {
                    skip = StatementTriage.afterToday
                } else {
                    switch charge.kind {
                    case "own_transfer": skip = StatementTriage.ownMovement
                    case "card_bill": skip = StatementTriage.cardBill
                    default: skip = nil
                    }
                }
                let tag = charge.category.flatMap { named in tags.first { $0.caseInsensitiveCompare(named) == .orderedSame } }
                let name = StatementNaming.clean(charge.name)
                let account = charge.account.trimmingCharacters(in: .whitespaces).isEmpty ? self.account : charge.account
                return StatementCandidate(
                    line: line, name: name.isEmpty ? StatementNaming.plainName(charge.narration) : name,
                    tag: tag, keep: skip == nil, skipReason: skip, file: account,
                    member: charge.kind == "for_member" ? charge.member : nil,
                    direction: direction(of: charge.kind),
                    counterpartAccount: StatementCounterparts.account(on: charge)?.name
                )
            }
        }

        /// Money in, the owner's own money moving (left unticked, a transfer if kept), or a charge.
        private func direction(of kind: String) -> String? {
            switch kind {
            case "income": return "in"
            case "own_transfer", "card_bill": return "transfer"
            default: return nil
            }
        }

        /// The charges as the review task reads them: one a line.
        public var chargeLines: String {
            charges.map { "\($0.date) | \($0.amount) | \($0.name) | \(StatementNaming.scrubbed($0.narration)) | \($0.kind)" }
                .joined(separator: "\n")
        }
    }

    // MARK: pieces

    /// How much goes in one call: pages of a PDF, rows of a sheet. Small enough that the
    /// answer is always whole.
    public static let pagesPerPiece = 3
    public static let rowsPerPiece = 150

    /// The file cut into what one call can answer for: a short open PDF as the bank wrote
    /// it, a long or locked one rebuilt a few pages at a time, a sheet as runs of rows
    /// under the header.
    public static func pieces(for url: URL, password: String?) throws -> [Piece] {
        let name = url.lastPathComponent
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        switch StatementText.kind(of: url) {
        case .pdf?:
            return try pdfPieces(url, name: name, password: password)
        case .csv?, .text?, .xlsx?, .xls?:
            let records = try StatementText.records(for: url)
            // A sheet with no dated lines and amounts is not a statement; it never leaves the device.
            guard StatementLines.fromRecords(records).count >= 3 else {
                throw StatementText.ReadError.noLines("The sheet has \(records.count) rows, but no header row naming a date, a description and an amount.")
            }
            return rowPieces(records, name: name)
        case nil:
            throw StatementText.ReadError.unsupported(url.pathExtension.lowercased())
        }
    }

    static func pdfPieces(_ url: URL, name: String, password: String?) throws -> [Piece] {
        #if canImport(PDFKit)
        guard let document = PDFDocument(url: url) else { throw StatementText.ReadError.unreadable }
        if document.isLocked {
            guard let password, !password.isEmpty else { throw StatementText.ReadError.locked }
            guard document.unlock(withPassword: password) else { throw StatementText.ReadError.wrongPassword }
        }
        let pages = document.pageCount
        guard pages > 0 else { throw StatementText.ReadError.unreadable }
        // Every PDF is rebuilt page by page, the short ones too: what goes to the server is
        // the pages alone, never a script, a form or a file the original may carry.
        var out: [Piece] = []
        var first = 0
        while first < pages {
            let last = min(first + pagesPerPiece, pages)
            let open = PDFDocument()
            for index in first..<last {
                if let page = document.page(at: index) { open.insert(page, at: open.pageCount) }
            }
            guard let bytes = open.dataRepresentation() else { throw StatementText.ReadError.unreadable }
            guard bytes.count <= 4_000_000 else { throw CloudError.tooLarge(name) }
            let label = pages <= pagesPerPiece ? (pages == 1 ? "1 page" : "\(pages) pages")
                : last - first == 1 ? "page \(first + 1) of \(pages)" : "pages \(first + 1)–\(last) of \(pages)"
            out.append(Piece(name: name, type: "pdf", data: bytes.base64EncodedString(), label: label))
            first = last
        }
        return out
        #else
        throw StatementText.ReadError.unsupported("pdf")
        #endif
    }

    /// Runs of rows, the header row above each so every piece names its columns. A cell
    /// that is a date goes as YYYY-MM-DD in the order the sheet itself shows — a "31/12"
    /// anywhere settles it — so the model is never left to guess which of 05/10 is the month.
    static func rowPieces(_ sheet: [[String]], name: String) -> [Piece] {
        guard !sheet.isEmpty else { return [] }
        let order = StatementLines.dateOrder(sheet)
        let headerAt = StatementLines.headerIndex(sheet) ?? 0
        // A bare five-digit number is a date only under a date heading; anywhere else it is an
        // amount, and 42000.00 must not travel as 2014-12-27.
        let dateColumns = Set((sheet.indices.contains(headerAt) ? sheet[headerAt] : []).enumerated()
            .filter { $0.element.lowercased().contains("date") || $0.element.lowercased().hasSuffix(" dt") }.map(\.offset))
        let records = sheet.map { row in
            row.enumerated().map { column, cell in
                if !dateColumns.contains(column), cell.trimmingCharacters(in: .whitespaces).range(of: #"^\d+(\.\d+)?$"#, options: .regularExpression) != nil {
                    return cell
                }
                return StatementLines.parseDate(cell, order: order) ?? cell
            }
        }
        let header = Array(records.prefix(headerAt + 1))
        let rows = Array(records.dropFirst(headerAt + 1))
        guard rows.count > rowsPerPiece else {
            return [Piece(name: name, type: "text", data: CSV.text(records), label: "\(rows.count) row\(rows.count == 1 ? "" : "s")")]
        }
        var out: [Piece] = []
        var first = 0
        while first < rows.count {
            let last = min(first + rowsPerPiece, rows.count)
            out.append(Piece(name: name, type: "text", data: CSV.text(header + Array(rows[first..<last])),
                             label: "rows \(first + 1)–\(last) of \(rows.count)"))
            first = last
        }
        return out
    }

    // MARK: calls

    /// One piece up, its charges down. `importId` names the file every piece belongs to,
    /// so the server can count the whole file's reading against one budget. `hint` is
    /// what a second reading is told about the first, at most `StatementCompleteness.hintLimit`.
    public static func charges(of piece: Piece, importId: String, accountHint: String?, categories: [String], members: [String], accounts: [String], currency: String, token: String?, hint: String? = nil) async throws -> ChargesAnswer {
        struct Body: Encodable {
            let task = "charges"
            let import_id: String
            let file: Piece
            let account_hint: String?
            let categories: [String]
            let members: [String]
            let accounts: [String]
            let currency: String
            let hint: String?
        }
        let clipped = hint.map { String($0.prefix(StatementCompleteness.hintLimit)) }
        return try await call(Body(import_id: importId, file: piece, account_hint: accountHint, categories: categories, members: members, accounts: accounts, currency: currency, hint: clipped), token: token)
    }

    /// The year's charges up, the people and the rhythms down.
    public static func review(_ prepared: Prepared, importId: String, categories: [String], members: [String], currency: String, token: String?) async throws -> ReviewAnswer {
        struct Body: Encodable {
            let task = "review"
            let import_id: String
            let charges: String
            let categories: [String]
            let members: [String]
            let accounts: [String]
            let currency: String
        }
        return try await call(Body(import_id: importId, charges: prepared.chargeLines, categories: categories, members: members, accounts: [prepared.account], currency: currency), token: token)
    }

    /// A new id for one file's reading, as the server counts it.
    public static func newImportId() -> String { UUID().uuidString.lowercased() }

    /// How many calls may be in flight at once, across every file being read.
    public static let callsInFlight = 8
    private static let gate = CallGate(limit: callsInFlight)

    /// A counting gate: a call waits its turn when the limit is in flight.
    actor CallGate {
        private let limit: Int
        private var inFlight = 0
        private var waiting: [CheckedContinuation<Void, Never>] = []

        init(limit: Int) { self.limit = limit }

        func enter() async {
            if inFlight < limit {
                inFlight += 1
                return
            }
            await withCheckedContinuation { waiting.append($0) }
        }

        nonisolated func leave() { Task { await self.release() } }

        private func release() {
            if let next = waiting.first {
                waiting.removeFirst()
                next.resume()
            } else {
                inFlight -= 1
            }
        }
    }

    private static func call<Body: Encodable, Answer: Decodable>(_ body: Body, token: String?) async throws -> Answer {
        guard let token, !token.isEmpty else { throw CloudError.notSignedIn }
        var request = URLRequest(url: SUPABASE_URL.appendingPathComponent("functions/v1/statement-extract"))
        request.httpMethod = "POST"
        request.timeoutInterval = 300
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(SUPABASE_ANON_KEY, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        let data: Data
        let response: URLResponse
        // Several files read at once, each a few pieces at a time: the gate keeps the
        // calls in flight to what the server and the model take without refusing.
        await gate.enter()
        defer { gate.leave() }
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw CloudError.unreachable
        }
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            let said = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            switch said?["code"] as? String {
            case "share_spent": throw CloudError.shareSpent
            case "not_statement": throw CloudError.notStatement(said?["error"] as? String ?? "That file does not look like a statement, so it was not read.")
            default: break
            }
            throw CloudError.server(said?["error"] as? String ?? "The statement could not be read right now. Try again in a minute.")
        }
        return try JSONDecoder().decode(Answer.self, from: data)
    }
}
