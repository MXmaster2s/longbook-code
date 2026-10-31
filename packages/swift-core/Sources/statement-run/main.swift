// A real statement through the app's own reading on a Mac, against a local stand-in for the
// server (scripts/statement-serve.mts), up to the Add. Prints counts and timings, never a
// line. Run: swift run statement-run --server http://127.0.0.1:8788 --out <dir> [--document | --plan] <file>...
import Foundation
import LongbookCore

func option(_ name: String) -> String? {
    guard let at = CommandLine.arguments.firstIndex(of: name), CommandLine.arguments.indices.contains(at + 1) else { return nil }
    return CommandLine.arguments[at + 1]
}
var files: [String] = []
var skip = false
for argument in CommandLine.arguments.dropFirst() {
    if skip { skip = false; continue }
    if argument == "--server" || argument == "--out" { skip = true; continue }
    if argument.hasPrefix("--") { continue }
    files.append(argument)
}
guard let server = option("--server").flatMap(URL.init(string:)), let out = option("--out"), !files.isEmpty else {
    print("usage: statement-run --server <url> --out <dir> [--document | --plan] <file>...")
    exit(2)
}
let asDocument = CommandLine.arguments.contains("--document")

let session: URLSession = {
    let config = URLSessionConfiguration.ephemeral
    config.timeoutIntervalForRequest = 600
    config.httpMaximumConnectionsPerHost = 64
    return URLSession(configuration: config)
}()

let transport: StatementLinePass.Transport = { body in
    var request = URLRequest(url: server)
    request.httpMethod = "POST"
    request.httpBody = body
    let (data, response) = try await session.data(for: request)
    guard (response as? HTTPURLResponse)?.statusCode == 200 else {
        throw StatementCloud.CloudError.server("status \((response as? HTTPURLResponse)?.statusCode ?? 0)")
    }
    return data
}

let clock = Date()
@Sendable func at() -> String { String(format: "%6.1fs", Date().timeIntervalSince(clock)) }

struct Read: Sendable {
    let name: String
    let prepared: StatementCloud.Prepared
    let report: StatementCompleteness.Report
    let filled: [StatementCandidate]
}

let tags = TagLibrary.entries(kind: "commitment").map(\.name)

struct Document {
    struct Body: Encodable {
        var task = "charges"
        let import_id: String
        let file: StatementCloud.Piece
        let account_hint: String?
        let hint: String?
        let categories: [String]
        var members: [String] = []
        var accounts: [String] = []
        var currency = "INR"
    }
    struct Review: Encodable {
        var task = "review"
        let import_id: String
        let charges: String
        let categories: [String]
        var members: [String] = []
        var accounts: [String] = []
        var currency = "INR"
    }

    /// The document path's order, as the app runs it: first piece, the rest three at a time, a re-read of
    /// pieces that left lines out, the review.
    static func read(_ url: URL, id: String) async throws -> Read {
        let name = url.lastPathComponent
        let pieces = try StatementCloud.pieces(for: url, password: nil)
        func ask(_ piece: Int, hint: String?, account: String?) async throws -> StatementCloud.ChargesAnswer {
            let data = try JSONEncoder().encode(Body(import_id: id, file: pieces[piece], account_hint: account, hint: hint, categories: tags))
            return try JSONDecoder().decode(StatementCloud.ChargesAnswer.self, from: try await transport(data))
        }
        var answers: [StatementCloud.ChargesAnswer?] = Array(repeating: nil, count: pieces.count)
        answers[0] = try await ask(0, hint: nil, account: nil)
        let hint = answers[0]?.account
        var first = 1
        while first < pieces.count {
            let batch = Array(first..<min(first + 3, pieces.count))
            await withTaskGroup(of: (Int, StatementCloud.ChargesAnswer?).self) { group in
                for piece in batch { group.addTask { (piece, try? await ask(piece, hint: nil, account: hint)) } }
                for await (piece, answer) in group { answers[piece] = answer }
            }
            first += batch.count
        }
        print("\(at()) \(name): \(pieces.count) pieces read")
        let expected = StatementCompleteness.expected(for: url, password: nil)
        let look = StatementCompleteness.compare(prepared: .assemble(answers.compactMap { $0 }, review: .empty), expected: expected)
        if !look.missing.isEmpty {
            let again = StatementCompleteness.piecesToAskAgain(missing: look.missing, pieces: pieces.count)
            await withTaskGroup(of: (Int, StatementCloud.ChargesAnswer?).self) { group in
                for (piece, lines) in again {
                    group.addTask { (piece, try? await ask(piece, hint: StatementCompleteness.hint(for: lines), account: hint)) }
                }
                for await (piece, answer) in group {
                    guard let answer else { continue }
                    answers[piece] = answers[piece].map { StatementCompleteness.merge($0, with: answer, missing: again[piece] ?? []) } ?? answer
                }
            }
            print("\(at()) \(name): \(again.count) pieces read again for \(look.missing.count) lines")
        }
        let read = answers.compactMap { $0 }
        var prepared = StatementCloud.Prepared.assemble(read, review: .empty)
        let data = try JSONEncoder().encode(Review(import_id: id, charges: prepared.chargeLines, categories: tags))
        let looked = (try? JSONDecoder().decode(StatementCloud.ReviewAnswer.self, from: try await transport(data))) ?? .empty
        prepared = StatementCloud.Prepared.assemble(read, review: looked)
        prepared = StatementCompleteness.mended(prepared, expected: expected)
        let report = StatementCompleteness.compare(prepared: prepared, expected: expected)
        print("\(at()) \(name): reviewed")
        return Read(name: name, prepared: prepared, report: report, filled: StatementCompleteness.fill(missing: report.missing, among: tags))
    }
}

func readOne(_ path: String) async throws -> Read {
    let url = URL(fileURLWithPath: path)
    let name = url.lastPathComponent
    let id = StatementCloud.newImportId()
    let started = Date()
    if asDocument { return try await Document.read(url, id: id) }
    let reading = try StatementCloud.reading(for: url, password: nil)
    print("\(at()) \(name): device reading took \(String(format: "%.2f", Date().timeIntervalSince(started)))s")
    if CommandLine.arguments.contains("--plan"), case .lines(let plan) = reading {
        let sent = plan.lines.reduce(0) { $0 + $1.text.count }
        print("  \(plan.lines.count) lines in \(plan.batches.count) batches, \(sent) characters of narration, \(plan.header.count) of header, balance closes \(plan.expected.closes)")
        exit(0)
    }
    guard case .lines(let plan) = reading else {
        if case .document(_, let why) = reading { print("\(at()) \(name): goes as a document (\(why.rawValue))") }
        return try await Document.read(url, id: id)
    }
    let asking = StatementLinePass.Asking(importId: id, categories: tags, members: [], accounts: [], currency: "INR")
    let outcome = try await StatementLinePass.read(plan, asking: asking, transport: transport) { state in
        print("\(at()) \(name): \(state.lines) lines, \(state.batchesDone)/\(state.batches) batches, \(state.named) named, \(state.people) people, \(state.accounts) accounts\(state.finished ? ", \(state.repeats) repeats, done" : "")")
    }
    return Read(name: name, prepared: outcome.prepared, report: outcome.report, filled: [])
}

/// The review's show() and add(), ticked as they open, over an empty longbook.
func add(_ reads: [Read]) throws -> StatementImport.Written {
    var candidates: [(Int, [StatementCandidate])] = []
    var repeats: [StatementCloud.Repeat] = []
    var members: [StatementCloud.Member] = []
    let book = StatementBook()
    var prepared: [StatementCloud.Prepared] = []
    for (index, read) in reads.enumerated() {
        let one = read.prepared
        prepared.append(one)
        var mine = one.candidates(among: tags, book: book) + read.filled
        for i in mine.indices { mine[i].file = read.name }
        candidates.append((index, mine))
        for repeated in one.repeats where !repeats.contains(where: { $0.name.caseInsensitiveCompare(repeated.name) == .orderedSame }) { repeats.append(repeated) }
        for member in one.members where !members.contains(where: { $0.name.caseInsensitiveCompare(member.name) == .orderedSame }) { members.append(member) }
    }
    var found = candidates.flatMap(\.1)
    for name in found.compactMap(\.member) where !members.contains(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
        members.append(StatementCloud.Member(name: name, role: "", reason: "Named on a line"))
    }
    StatementImport.markAlreadyPresent(&found, in: [])
    let named = Set(repeats.map { $0.name.lowercased() })
    for ruled in StatementImport.repeats(in: found) where !named.contains(ruled.name.lowercased()) {
        repeats.append(StatementCloud.Repeat(name: ruled.name, cycle: ruled.cycle.rawValue, customDays: ruled.customDays, amount: ruled.amount,
                                             dates: ruled.dates, category: nil, endsOn: nil, guessed: ruled.guessed, reason: ruled.reason))
    }
    var others = StatementCounterparts.Found()
    for one in prepared {
        let more = one.counterparts(knownAccounts: prepared.map { StatementBook.Account(name: $0.account, owner: $0.holder) }
                                        + others.accounts.map { StatementBook.Account(name: $0.name, owner: $0.person) },
                                    knownPeople: members.map(\.name) + others.people)
        others.accounts += more.accounts
        others.people += more.people
    }
    members += others.people.map { StatementCloud.Member(name: $0, role: "", reason: "Named on a transfer") }
    var chosen = members.map(\.name)
    for row in found where row.keep {
        if let name = row.member, !chosen.contains(where: { nameKey($0) == nameKey(name) }) { chosen.append(name) }
    }
    for holder in prepared.compactMap(\.holder) where !chosen.contains(holder) { chosen.append(holder) }
    let files = reads.enumerated().map { index, read in
        StatementImport.ReviewFile(rows: found.filter { $0.file == read.name }, account: read.prepared.account, addsAccount: true,
                                   source: "documents/\(read.name)", balance: read.prepared.balance, balanceDate: read.prepared.balanceDate,
                                   owner: read.prepared.holder)
    }
    let review = StatementImport.Review(
        members: chosen, accounts: others.accounts, files: files, currency: "INR",
        repeats: repeats.map { ($0, CommitmentPlaceholder(name: $0.name, group: "Monthly", tag: $0.category ?? "")) }, waiting: [])
    return try StatementImport.write(review, to: VaultScaffold.freshMemory(), now: Date(), schema: VaultContract.bundledSchema())
}

let reads = try await withThrowingTaskGroup(of: Read.self, returning: [Read].self) { group in
    for path in files { group.addTask { try await readOne(path) } }
    var done: [Read] = []
    for try await read in group {
        print("\(at()) \(read.name): \(read.report.headline(file: read.name, currency: "INR"))")
        print("  account \(read.prepared.account.isEmpty ? "NO" : "yes"), holder \(read.prepared.holder == nil ? "NO" : "yes"), balance \(read.prepared.balance == nil ? "NO" : "yes"), charges \(read.prepared.charges.count), repeats \(read.prepared.repeats.count) (\(read.prepared.repeats.filter(\.guessed).count) guessed), people \(read.prepared.members.count)")
        done.append(read)
    }
    return done.sorted { $0.name < $1.name }
}
print("\(at()) read and reviewed")

let adding = Date()
let written = try add(reads)
print(String(format: "add took %.2fs, %d charges written", Date().timeIntervalSince(adding), written.charges))
try FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
let bytes = try JSONSerialization.data(withJSONObject: written.vault, options: [.prettyPrinted, .sortedKeys])
try bytes.write(to: URL(fileURLWithPath: out).appendingPathComponent("financial_memory.json"))
