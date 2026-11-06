import XCTest
@testable import LongbookCore

/// The import's tour: what it shows is what was written, a kind with nothing drops out, the
/// bar rises until reading is done, and one save comes back whole. Synthetic data only.
final class StatementTourTests: XCTestCase {
    private let now = ISO8601DateFormatter().date(from: "2026-10-30T09:00:00Z")!
    private var today: Date { LB.parseDate("2026-10-30")! }

    private func emptyVault() -> [String: Any] {
        ["app": "longbook", "version": VAULT_FORMAT_VERSION, "commitments": [], "members": [], "accounts": [], "charges": [], "tags": []]
    }

    private func line(_ name: String, _ date: String, _ amount: Double, direction: String? = nil, member: String? = nil, tag: String? = "shopping") -> StatementCandidate {
        var candidate = StatementCandidate(line: StatementLine(date: date, payee: "UPI-\(name.uppercased())", amount: amount, direction: direction == "in" ? .credit : .debit),
                                           name: name, tag: tag, keep: true, skipReason: nil, file: "synthetic.pdf", member: member)
        candidate.direction = direction
        return candidate
    }

    private func gym() -> (repeated: StatementCloud.Repeat, placeholder: CommitmentPlaceholder) {
        let dates = ["2026-07-05", "2026-08-05", "2026-09-05"]
        return (StatementCloud.Repeat(name: "Gym", cycle: "monthly", customDays: nil, amount: 1500, dates: dates, category: nil, endsOn: nil),
                CommitmentPlaceholder(name: "Gym", group: "Monthly", tag: ""))
    }

    private func review(rows: [StatementCandidate], repeats: [(repeated: StatementCloud.Repeat, placeholder: CommitmentPlaceholder)] = [], members: [String] = []) -> StatementImport.Review {
        let file = StatementImport.ReviewFile(rows: rows, account: "Test Bank 4417", addsAccount: true, source: "documents/synthetic.pdf",
                                              balance: 52_000, balanceDate: "2026-09-30", owner: "Jordan Lee")
        return StatementImport.Review(members: members, accounts: [], files: [file], currency: "USD", repeats: repeats, waiting: [])
    }

    private func written() throws -> (before: [String: Any], after: [String: Any]) {
        let before = emptyVault()
        let rows = [
            line("Whole Foods", "2026-09-27", 86.4, member: nil),
            line("Payment to Maya Chen", "2026-09-28", 120, member: "Maya Chen"),
            line("Northwind Payroll", "2026-09-30", 5200, direction: "in"),
            line("Gym", "2026-07-05", 1500), line("Gym", "2026-08-05", 1500), line("Gym", "2026-09-05", 1500),
        ]
        let result = try StatementImport.write(review(rows: rows, repeats: [gym()], members: ["Maya Chen"]), to: before, now: now,
                                               schema: VaultContract.bundledSchema())
        return (before, result.vault)
    }

    // MARK: the steps

    func testAKindWithNothingDropsOutAndTheOrderHolds() {
        var findings = StatementTour.Findings()
        XCTAssertTrue(findings.steps.isEmpty)
        XCTAssertTrue(findings.isEmpty)
        let card = StatementTour.Card(id: "a", kind: .charge, title: "A", pill: nil, amount: nil, details: [], photo: nil)
        findings.earnings = [card]
        findings.charges = [card, card]
        findings.accounts = [card]
        XCTAssertEqual(findings.steps.map(\.kind), [.charge, .account, .earning])
        XCTAssertEqual(findings.steps.map(\.count), [2, 1, 1])
    }

    func testTheWalkGoesForwardBackSkipsAndJumps() {
        var walk = StatementTour.Walk(steps: [.init(kind: .charge, count: 2), .init(kind: .account, count: 1), .init(kind: .earning, count: 1)])
        XCTAssertTrue(walk.isFirst)
        XCTAssertEqual(walk.current?.kind, .charge)
        walk.back()
        XCTAssertEqual(walk.current?.kind, .charge, "nothing before the first step")
        walk.forward()
        XCTAssertEqual(walk.current?.kind, .account)
        walk.jump(to: .earning)
        XCTAssertEqual(walk.current?.kind, .earning)
        walk.jump(to: .transfer)
        XCTAssertEqual(walk.current?.kind, .earning, "a kind that dropped out is no stop")
        walk.forward()
        XCTAssertTrue(walk.isEnd, "Continue on the last step leads to the end")
        walk.forward()
        XCTAssertTrue(walk.isEnd)
        var again = StatementTour.Walk(steps: [.init(kind: .charge, count: 2), .init(kind: .account, count: 1)])
        again.skip()
        XCTAssertTrue(again.isEnd)
        var none = StatementTour.Walk(steps: [])
        XCTAssertTrue(none.isEnd)
        none.forward()
        XCTAssertTrue(none.isEnd)
    }

    func testTheWordsAreTheSpecsWords() {
        let charges = StatementTour.Step(kind: .charge, count: 214)
        XCTAssertEqual(charges.heading, "Imported 214 Past Expenses")
        XCTAssertEqual(charges.line, "Charges cards are saved")
        XCTAssertEqual(charges.seeAll, "See All 214 Charges")
        XCTAssertEqual(charges.listTitle, "214 Past Expenses")
        let people = StatementTour.Step(kind: .people, count: 18)
        XCTAssertEqual(people.heading, "Found 18 People")
        XCTAssertEqual(people.line, "People cards are saved")
        XCTAssertEqual(people.seeAll, "See All 18 People")
        XCTAssertEqual(people.listTitle, "People")
        XCTAssertEqual(StatementTour.peopleLine(kept: 18), "18 People are saved. Tap one to remove it.")
        XCTAssertEqual(StatementTour.Step(kind: .account, count: 9).heading, "Found 9 Accounts")
        XCTAssertEqual(StatementTour.Step(kind: .account, count: 9).line, "Account cards are saved")
        XCTAssertEqual(StatementTour.Step(kind: .commitment, count: 7).line, "Commitment cards are saved")
        XCTAssertEqual(StatementTour.Step(kind: .transfer, count: 4).line, "Transfer cards are saved")
        XCTAssertEqual(StatementTour.Step(kind: .earning, count: 6).line, "Earning cards are saved")
        XCTAssertEqual(StatementTour.Step(kind: .earning, count: 1).heading, "Found 1 Earning")
    }

    func testSeeAllOnlyWhenTheStepCannotShowEveryCardSavePeople() {
        XCTAssertNil(StatementTour.Step(kind: .transfer, count: 4).seeAll, "four cards show on the step")
        XCTAssertEqual(StatementTour.Step(kind: .transfer, count: 5).seeAll, "See All 5 Transfers")
        XCTAssertEqual(StatementTour.Step(kind: .people, count: 1).seeAll, "See All 1 Person", "a person is removed only there")
    }

    // MARK: what was written

    func testTheCardsAreWhatWasWritten() throws {
        let vaults = try written()
        let found = StatementTour.findings(before: vaults.before, after: vaults.after, today: today)
        XCTAssertEqual(found.steps.map(\.kind), [.charge, .people, .account, .commitment, .earning], "no Transfer was written, so no step")
        XCTAssertEqual(found.charges.count, 5, "the gym's three lines stay charges; money in is not one")
        XCTAssertEqual(found.charges.first?.title, "Payment to Maya Chen", "newest first")
        XCTAssertEqual(found.charges.first?.amount, fmtMoneyExact(120, "USD"))
        XCTAssertEqual(found.charges.first?.details.map(\.fact), [.date, .category, .account, .person])
        XCTAssertEqual(found.earnings.map(\.title), ["Northwind Payroll"])
        XCTAssertEqual(found.earnings.first?.details.map(\.fact), [.date, .account], "a business is not a person")
        XCTAssertEqual(found.commitments.map(\.title), ["Gym"])
        XCTAssertEqual(found.commitments.first?.details.first { $0.fact == .cycle }?.text, "Monthly")
        XCTAssertEqual(found.accounts.map(\.title), ["Test Bank 4417"])
        XCTAssertEqual(found.accounts.first?.amount, fmtMoneyExact(52_000, "USD"))
        XCTAssertEqual(found.accounts.first?.details.map(\.text).first, "Jordan Lee")
    }

    func testSelfLeadsPeopleWithItsPillAndTheTotalIsSpendingOnly() throws {
        let vaults = try written()
        let found = StatementTour.findings(before: vaults.before, after: vaults.after, today: today)
        XCTAssertEqual(found.people.map(\.title), ["Jordan Lee", "Maya Chen"])
        XCTAssertEqual(found.people.first?.pill?.lowercased(), "self")
        XCTAssertNil(found.people.last?.pill)
        XCTAssertEqual(found.people.last?.amount, fmtMoneyExact(120, "USD"))
        XCTAssertEqual(found.people.last?.details.map(\.text), ["No account named", "1 Charge", "No commitments"])
        XCTAssertEqual(found.people.first?.amount, fmtMoneyExact(86.4 + 4500, "USD"), "money in is nobody's spending")
    }

    func testALaterImportShowsOnlyWhatItAdded() throws {
        let first = try written()
        let rows = [line("Whole Foods", "2026-10-02", 40), line("Payment to Maya Chen", "2026-10-03", 75, member: "Maya Chen")]
        let later = try StatementImport.write(review(rows: rows, members: ["Maya Chen"]), to: first.after, now: now, schema: VaultContract.bundledSchema())
        let found = StatementTour.findings(before: first.after, after: later.vault, today: today)
        XCTAssertEqual(found.steps.map(\.kind), [.charge], "the people and account are not new")
        XCTAssertEqual(found.charges.count, 2)
    }

    func testAPlannedRowIsNoCharge() throws {
        let vaults = try written()
        let planned = VaultPatch.chargeRows(vaults.after).filter { ($0["basis"] as? String) != "statement" }
        XCTAssertFalse(planned.isEmpty, "the gym is planned ahead")
        let found = StatementTour.findings(before: vaults.before, after: vaults.after, today: today)
        XCTAssertEqual(found.charges.filter { $0.title == "Gym" }.count, 3)
    }

    // MARK: one save, and back

    func testUndoTakesTheWholeImportBackAsOneOwnChange() throws {
        let vaults = try written()
        XCTAssertFalse(vaultDiff(from: vaults.before, to: vaults.after).isEmpty)
        let undone = VaultPatch.signRestore(from: vaults.after, to: vaults.before, now: now.addingTimeInterval(60))
        XCTAssertTrue(vaultDiff(from: vaults.before, to: undone).isEmpty, "nothing of the import stays")
        XCTAssertEqual(VaultPatch.chargeRows(undone).count, 0)
        XCTAssertTrue(OwnEdit.isOwn(from: vaults.after, to: undone), "the other device adopts the undo")
    }

    func testRemovingAPersonAndKeepingThemAgainComesFromTheOneWrite() throws {
        let vaults = try written()
        let maya = try XCTUnwrap(StatementTour.findings(before: vaults.before, after: vaults.after, today: today).people.last?.id)
        let removed = try VaultPatch.deleteEntity(.familyMember, id: maya, in: vaults.after, now: now)
        let after = StatementTour.findings(before: vaults.before, after: removed, today: today)
        XCTAssertEqual(after.people.map(\.title), ["Jordan Lee"])
        XCTAssertEqual(after.charges.first?.details.map(\.fact), [.date, .category, .account], "a charge stays a fact, with no one named")
        XCTAssertEqual(after.charges.count, 5)
        let kept = VaultPatch.signRestore(from: removed, to: vaults.after, now: now)
        XCTAssertTrue(vaultDiff(from: vaults.after, to: kept).isEmpty)
    }

    // MARK: the event

    /// The written import with the gym guessed and seen three times, a yearly commitment on the
    /// user's own category, and one on a shipped category, so every field is exercised.
    private func commitmentsWritten() throws -> (found: StatementTour.Findings, vault: [String: Any], ids: [String: String]) {
        let vaults = try written()
        var vault = vaults.after
        var rows = vault["commitments"] as? [[String: Any]] ?? []
        let gym = try XCTUnwrap(rows.firstIndex { $0["name"] as? String == "Gym" })
        rows[gym]["name"] = "Gym" + StatementNaming.guessedMark
        rows[gym]["tag"] = "Health & Fitness"
        var school = rows[gym]
        school["id"] = "school-id"
        school["name"] = "Maya Chen school fees"
        school["tag"] = "Maya's school fees"
        school["billing_cycle"] = "yearly"
        var rent = rows[gym]
        rent["id"] = "rent-id"
        rent["name"] = "Northwind rent"
        rent["tag"] = "Rent"
        rows += [school, rent]
        vault["commitments"] = rows
        let found = StatementTour.findings(before: vaults.before, after: vault, today: today)
        XCTAssertEqual(found.commitments.count, 3)
        return (found, vault, ["gym": try XCTUnwrap(rows[gym]["id"] as? String), "school": "school-id", "rent": "rent-id"])
    }

    func testTheEndEventCountsFoundAndRemovedPerKind() throws {
        let vaults = try written()
        let found = StatementTour.findings(before: vaults.before, after: vaults.after, today: today)
        let maya = try XCTUnwrap(found.people.last?.id)
        let props = StatementTour.endProperties(.done, found: found, removed: [.people: [maya, "not-a-card"]], vault: vaults.after)
        XCTAssertEqual(props["ending"] as? String, "done")
        XCTAssertEqual(props["charges_found"] as? Int, 5)
        XCTAssertEqual(props["people_found"] as? Int, 2)
        XCTAssertEqual(props["people_removed"] as? Int, 1, "an id that is no card is not counted")
        XCTAssertEqual(props["accounts_found"] as? Int, 1)
        XCTAssertEqual(props["commitments_found"] as? Int, 1)
        XCTAssertEqual(props["transfers_found"] as? Int, 0)
        XCTAssertEqual(props["earnings_found"] as? Int, 1)
        XCTAssertEqual(props["charges_removed"] as? Int, 0)
        XCTAssertEqual((props["removed_commitments"] as? [[String: Any]])?.count, 0)
        XCTAssertEqual(StatementTour.endProperties(.skipped, found: found, removed: [:], vault: vaults.after)["ending"] as? String, "skipped")
        XCTAssertEqual(StatementTour.endProperties(.undone, found: found, removed: [:], vault: vaults.after)["ending"] as? String, "undone")
    }

    func testRemovedCommitmentsAreGroupedByCycleSightingsGuessAndShippedCategory() throws {
        let book = try commitmentsWritten()
        let props = StatementTour.endProperties(.done, found: book.found, removed: [.commitment: Set(book.ids.values)], vault: book.vault)
        let removed = try XCTUnwrap(props["removed_commitments"] as? [[String: Any]])
        let words = removed.map { row in ["cycle", "sightings", "category"].map { row[$0] as? String ?? "" } + ["\(row["guessed"] as? Bool ?? false)", "\(row["count"] as? Int ?? 0)"] }
        XCTAssertEqual(words, [
            ["monthly", "0", "rent", "false", "1"],
            ["monthly", "3+", "health & fitness", "true", "1"],
            ["yearly", "0", "other", "false", "1"],
        ])
        XCTAssertEqual(props["commitments_removed"] as? Int, 3)
    }

    func testAlikeRemovedCommitmentsAreCountedTogether() throws {
        var book = try commitmentsWritten()
        var rows = book.vault["commitments"] as? [[String: Any]] ?? []
        let school = try XCTUnwrap(rows.firstIndex { $0["id"] as? String == "school-id" })
        rows[school]["tag"] = "Rent"
        rows[school]["billing_cycle"] = "monthly"
        book.vault["commitments"] = rows
        let props = StatementTour.endProperties(.done, found: book.found, removed: [.commitment: ["school-id", "rent-id"]], vault: book.vault)
        let removed = try XCTUnwrap(props["removed_commitments"] as? [[String: Any]])
        XCTAssertEqual(removed.count, 1)
        XCTAssertEqual(removed.first?["count"] as? Int, 2)
    }

    func testTheEndEventNeverCarriesAName() throws {
        let book = try commitmentsWritten()
        let maya = try XCTUnwrap(book.found.people.last?.id)
        let props = StatementTour.endProperties(.done, found: book.found,
                                                removed: [.people: [maya], .commitment: Set(book.ids.values), .charge: Set(book.found.charges.map(\.id))],
                                                vault: book.vault)
        let text = String(decoding: try JSONSerialization.data(withJSONObject: props, options: [.sortedKeys]), as: UTF8.self)
        for word in ["Gym", "Maya", "Chen", "Jordan", "Lee", "Whole Foods", "Northwind", "Payroll", "Test Bank", "4417", "school", "fees", "UPI", "synthetic"] {
            XCTAssertFalse(text.localizedCaseInsensitiveContains(word), "\(word) is in \(text)")
        }
        XCTAssertFalse(text.contains(maya), "no id of the book is sent")
        let top = Set(props.keys)
        let kinds = ["charges", "people", "accounts", "commitments", "transfers", "earnings"]
        XCTAssertEqual(top, Set(["ending", "removed_commitments"] + kinds.flatMap { [$0 + "_found", $0 + "_removed"] }))
        let row = try XCTUnwrap((props["removed_commitments"] as? [[String: Any]])?.first)
        XCTAssertEqual(Set(row.keys), ["cycle", "sightings", "guessed", "category", "count"])
    }

    func testACommitmentWithNoCategoryOrAnOddCycleHasFixedWords() throws {
        var book = try commitmentsWritten()
        var rows = book.vault["commitments"] as? [[String: Any]] ?? []
        let at = try XCTUnwrap(rows.firstIndex { $0["id"] as? String == "rent-id" })
        rows[at]["tag"] = ""
        rows[at]["billing_cycle"] = "Every Tuesday, ask Maya"
        book.vault["commitments"] = rows
        let props = StatementTour.endProperties(.done, found: book.found, removed: [.commitment: ["rent-id"]], vault: book.vault)
        let row = try XCTUnwrap((props["removed_commitments"] as? [[String: Any]])?.first)
        XCTAssertEqual(row["category"] as? String, "none")
        XCTAssertEqual(row["cycle"] as? String, "other")
    }

    // MARK: the log

    func testTheLogLineCarriesCountsAndNothingOfTheStatement() {
        let record = ImportRecord(file: "statement-1234567890.pdf", date: "2026-10-30", read: 130, expected: 134, balance: "off", score: 97, named: 120,
                                  gaps: ["Maya Chen not found"])
        XCTAssertEqual(record.logLine, "Import Completeness Score 97%: read 130 of 134, balance off, named 120, 1 gaps")
        XCTAssertFalse(record.logLine.contains("1234567890"))
        XCTAssertFalse(record.logLine.contains("Maya"))
    }
}
