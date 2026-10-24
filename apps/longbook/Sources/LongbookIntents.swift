import AppIntents
import Foundation
import LongbookCore

/// The book as an intent reaches it: the folder the app itself opens, read whole once iCloud
/// has its bytes here, and written through the outside door so every write stands in Changes.
enum IntentBook {
    struct Opened {
        let folder: URL
        let loaded: VaultReader.Loaded
    }

    static func open() async throws -> Opened {
        // Siri runs with the app closed, when the file may be an iCloud placeholder: fetch it
        // first, as the app does, or the read fails as a missing folder.
        guard let folder = VaultSource.resolve() ?? VaultContainer.vaultURL() else {
            throw IntentFailure("Open longbook once first, so it knows where your folder is.")
        }
        do {
            try await VaultReader.materialize(folder.appendingPathComponent(VaultReader.dataFile), timeout: 20)
            return Opened(folder: folder, loaded: try VaultReader.load(from: folder))
        } catch VaultReader.ReadError.notDownloaded {
            throw IntentFailure("Your longbook is still downloading from iCloud. Try again in a moment.")
        }
    }

    static func apply(_ write: PendingWrite) async throws {
        let opened = try await open()
        guard case .vault(let next) = try PendingApply.apply(write, to: opened.loaded.raw, now: Date()) else { return }
        try VaultDisk.write(next, to: opened.folder, expecting: opened.loaded.bytes)
    }

    static func write(kind: String, payload: [String: Any], signedBy name: String) -> PendingWrite {
        PendingWrite(id: UUID(), kind: kind, payload: payload, sourceRef: nil, keyName: name, origin: "intent")
    }

    /// "220", "₹220", "220 rupees", "Rs 1,499.50", "20 dollars": the number, and the
    /// currency the words name, else the book's own.
    static func money(_ text: String, fallback: String) -> (amount: Double, currency: String)? {
        let lower = text.lowercased()
        guard let match = lower.range(of: #"[0-9][0-9,]*(?:\.[0-9]{1,2})?"#, options: .regularExpression),
              let amount = Double(lower[match].replacingOccurrences(of: ",", with: "")), amount > 0
        else { return nil }
        let words: [(String, String)] = [
            (#"₹|\brupees?\b|\brs\.?\b|\binr\b"#, "INR"), (#"\$|\bdollars?\b|\busd\b|\bbucks?\b"#, "USD"),
            (#"£|\bpounds?\b|\bgbp\b|\bquid\b"#, "GBP"), (#"€|\beuros?\b|\beur\b"#, "EUR"),
            (#"\bdirhams?\b|\baed\b"#, "AED"), (#"\byen\b|\bjpy\b"#, "JPY"),
        ]
        let currency = words.first { lower.range(of: $0.0, options: .regularExpression) != nil }?.1 ?? fallback
        return (amount, currency)
    }

    /// The book's own currency: what most commitments are in, else the rupee.
    static func currency(_ vault: Vault) -> String {
        var counts: [String: Int] = [:]
        for sub in vault.subscriptions { counts[sub.currency, default: 0] += 1 }
        return counts.max { $0.value < $1.value }?.key ?? "INR"
    }
}

struct IntentFailure: LocalizedError {
    let text: String
    init(_ text: String) { self.text = text }
    var errorDescription: String? { text }
}

// MARK: - what Siri and Spotlight offer

/// The next commitment due — every one that lands on that day.
struct NextCommitmentIntent: AppIntent {
    static var title: LocalizedStringResource = "What’s my next commitment"
    static var description = IntentDescription("Says the next commitment due in longbook, and when.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let vault = try await IntentBook.open().loaded.vault
        // The next day anything is owed, so a card bill due tomorrow is not skipped. Each is
        // said with its own amount, a transfer named as one; no total is spoken.
        guard let day = nextDueDay(vault) else {
            return .result(dialog: IntentDialog(stringLiteral: "Nothing is due. Nothing recurring is coming up."))
        }
        let names = day.charges.map { "\($0.sub.name), \(fmtMoney($0.amount, $0.currency))" }
            + day.transfers.map { "\($0.sub.name), a transfer of \(fmtMoney($0.amount, $0.currency))" }
        let when = day.days == 0 ? "today" : day.days == 1 ? "tomorrow" : "in \(day.days) days, on \(LB.longDate(day.date))"
        let lead = names.count == 1 ? "Your next commitment is" : "\(names.count) commitments are due"
        return .result(dialog: IntentDialog(stringLiteral: "\(lead) \(when): " + names.joined(separator: "; ") + "."))
    }
}

/// A commitment by name, amount and the day it is due: one-time, on that day. Making it
/// repeat is the form's step, where the rhythm is a choice, never an assumption.
struct AddCommitmentIntent: AppIntent {
    static var title: LocalizedStringResource = "Add a commitment"
    static var description = IntentDescription("Adds a one-time commitment due on a day to longbook. It waits in Proposals.")

    @Parameter(title: "Name", requestValueDialog: "What is the commitment called?")
    var name: String
    @Parameter(title: "Amount", requestValueDialog: "How much is it?")
    var amountText: String
    @Parameter(title: "Due on", requestValueDialog: "When is it due?")
    var dueOn: Date

    static var parameterSummary: some ParameterSummary {
        Summary("Add \(\.$name) at \(\.$amountText), due \(\.$dueOn)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let clean = name.trimmingCharacters(in: .whitespaces)
        guard !clean.isEmpty else { throw IntentFailure("A commitment needs a name.") }
        let vault = try await IntentBook.open().loaded.vault
        guard let money = IntentBook.money(amountText, fallback: IntentBook.currency(vault)) else {
            throw $amountText.needsValueError("Say the amount as a number, like 220 or 220 rupees.")
        }
        let day = LB.dayOf(dueOn)
        let row: [String: Any] = [
            "name": clean, "amount": money.amount, "currency": money.currency,
            "billing_cycle": "once", "date": LB.toISO(day), "paid": false,
        ]
        try await IntentBook.apply(IntentBook.write(kind: "add_commitments", payload: ["rows": [row]], signedBy: "Siri"))
        return .result(dialog: IntentDialog(stringLiteral: "\(clean), \(fmtMoney(money.amount, money.currency)) due \(LB.longDate(day)), added. It waits in Proposals."))
    }
}

/// An expense that already happened: a one-time row, paid, on the day it was paid.
struct AddExpenseIntent: AppIntent {
    static var title: LocalizedStringResource = "Add an expense"
    static var description = IntentDescription("Records an expense already paid in longbook. It waits in Proposals.")

    @Parameter(title: "Name", requestValueDialog: "What was it for?")
    var name: String
    @Parameter(title: "Amount", requestValueDialog: "How much was it?")
    var amountText: String
    @Parameter(title: "Paid on", requestValueDialog: "When was it paid?")
    var paidOn: Date

    static var parameterSummary: some ParameterSummary {
        Summary("Add \(\.$name) at \(\.$amountText), paid \(\.$paidOn)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let clean = name.trimmingCharacters(in: .whitespaces)
        guard !clean.isEmpty else { throw IntentFailure("An expense needs a name.") }
        let vault = try await IntentBook.open().loaded.vault
        guard let money = IntentBook.money(amountText, fallback: IntentBook.currency(vault)) else {
            throw $amountText.needsValueError("Say the amount as a number, like 220 or 220 rupees.")
        }
        let day = LB.dayOf(paidOn)
        let row: [String: Any] = [
            "name": clean, "amount": money.amount, "currency": money.currency,
            "billing_cycle": "once", "date": LB.toISO(day), "paid": true, "basis": "user",
        ]
        try await IntentBook.apply(IntentBook.write(kind: "add_commitments", payload: ["rows": [row]], signedBy: "Siri"))
        return .result(dialog: IntentDialog(stringLiteral: "\(clean), \(fmtMoney(money.amount, money.currency)) on \(LB.longDate(day)), recorded. It waits in Proposals."))
    }
}

// MARK: - what Shortcuts can run

/// A bank's messages, one or many, offered to the Shortcuts app rather than as a Siri
/// phrase: each that names an amount becomes a one-time charge, once. The same message
/// handed over twice records nothing new.
struct RecordBankMessageIntent: AppIntent {
    static var title: LocalizedStringResource = "Record a charge from a message"
    static var description = IntentDescription("Reads a bank’s messages and records each charge in longbook, where it waits in Proposals.")

    @Parameter(title: "Messages")
    var messages: [String]

    static var parameterSummary: some ParameterSummary {
        Summary("Record the charges in \(\.$messages)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let texts = messages.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let read = texts.compactMap { BankMessage.parse($0) }
        guard !read.isEmpty else {
            let head = texts.first.map { String($0.prefix(90)) } ?? "nothing"
            return .result(dialog: IntentDialog(stringLiteral: "No amount found, so nothing was recorded. The text read: \(head)"))
        }
        let vault = try await IntentBook.open().loaded.vault
        let fresh = read.filter { !Self.alreadyRecorded($0, in: vault) }
        guard !fresh.isEmpty else {
            return .result(dialog: IntentDialog(stringLiteral: read.count == 1
                ? "That charge is already in longbook." : "Those \(read.count) charges are already in longbook."))
        }
        let rows = fresh.map { Self.row(for: $0, in: vault) }
        try await IntentBook.apply(IntentBook.write(kind: "add_commitments", payload: ["rows": rows], signedBy: "bank message"))
        if fresh.count == 1, let one = fresh.first {
            let what = one.isIncome ? "Money in of" : "A charge of"
            return .result(dialog: IntentDialog(stringLiteral: "\(what) \(fmtMoney(one.amount, one.currency)), \(one.name), recorded. It waits in Proposals."))
        }
        let skipped = read.count - fresh.count
        let tail = skipped == 0 ? "" : " \(skipped) already in longbook."
        return .result(dialog: IntentDialog(stringLiteral: "\(fresh.count) charges recorded. They wait in Proposals.\(tail)"))
    }

    private static func row(for read: BankMessage, in vault: Vault) -> [String: Any] {
        var row: [String: Any] = [
            "name": read.name, "amount": read.amount, "currency": read.currency,
            "billing_cycle": "once", "date": read.date, "paid": true, "basis": "statement",
            "details": ["statement_line": read.payee],
        ]
        if read.isIncome { row["direction"] = "in" }
        if let last4 = read.last4, let account = vault.paymentMethods.first(where: { $0.name.contains(last4) }) {
            row["account"] = account.name
        }
        return row
    }

    /// A nightly automation reads yesterday's messages again: the same payee line, day and
    /// amount already in the book is the same charge, not a twin.
    private static func alreadyRecorded(_ read: BankMessage, in vault: Vault) -> Bool {
        vault.subscriptions.contains { sub in
            guard sub.billingCycle == .once, sub.details?["statement_line"]?.display == read.payee else { return false }
            return vault.charges.contains { $0.commitmentId == sub.id && $0.date == read.date && $0.amount == read.amount }
        }
    }
}

/// What Siri and Spotlight know, the app's name in each phrase; Info.plist adds its spoken spellings.
struct LongbookShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: NextCommitmentIntent(),
            phrases: ["What’s my next commitment in my \(.applicationName)", "What’s my next commitment in \(.applicationName)",
                      "Next commitment in my \(.applicationName)", "What do I pay next in my \(.applicationName)",
                      "What do I pay next in \(.applicationName)", "What’s due next in my \(.applicationName)",
                      "What’s due in my \(.applicationName)", "What’s upcoming in my \(.applicationName)",
                      "What’s coming up in my \(.applicationName)"],
            shortTitle: "Next commitment",
            systemImageName: "calendar"
        )
        AppShortcut(
            intent: AddCommitmentIntent(),
            phrases: ["Add a commitment in my \(.applicationName)", "Add a commitment in \(.applicationName)",
                      "Add a bill in my \(.applicationName)", "Add a subscription in my \(.applicationName)"],
            shortTitle: "Add a commitment",
            systemImageName: "plus"
        )
        AppShortcut(
            intent: AddExpenseIntent(),
            phrases: ["Add an expense in my \(.applicationName)", "Add an expense in \(.applicationName)",
                      "Record an expense in my \(.applicationName)", "Log an expense in my \(.applicationName)"],
            shortTitle: "Add an expense",
            systemImageName: "indianrupeesign.circle"
        )
    }
}
