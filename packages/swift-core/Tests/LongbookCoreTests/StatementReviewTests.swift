import XCTest
@testable import LongbookCore

/// A statement review's Add: one write for the whole review, kept as the owner's own on
/// both devices, and an outside write still stands for review.
final class StatementReviewTests: XCTestCase {
    private let now = ISO8601DateFormatter().date(from: "2026-10-30T09:00:00Z")!

    private func openingVault() throws -> [String: Any] {
        let env = ProcessInfo.processInfo.environment["LONGBOOK_DEMO_VAULT"]
        let file = env.map { URL(fileURLWithPath: $0).appendingPathComponent(VaultReader.dataFile) }
            ?? sharedFixturesDirectory(from: #filePath).appendingPathComponent("import-golden-vault.json")
        return try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
    }

    private func line(_ name: String, _ date: String, _ amount: Double, keep: Bool = true, member: String? = nil) -> StatementCandidate {
        StatementCandidate(line: StatementLine(date: date, payee: "UPI-\(name.uppercased())-\(date)", amount: amount, direction: .debit),
                           name: name, tag: "shopping", keep: keep, skipReason: keep ? nil : "not a commitment",
                           file: "hdfc.pdf", member: member)
    }

    private func repeated(_ name: String, _ dates: [String], _ amount: Double) -> (repeated: StatementCloud.Repeat, placeholder: CommitmentPlaceholder) {
        let json = #"{"name":"\#(name)","cycle":"monthly","amount":\#(amount),"dates":\#(dates)}"#
        let decoded = try! JSONDecoder().decode(StatementCloud.Repeat.self, from: Data(json.utf8))
        return (decoded, CommitmentPlaceholder(name: name, group: "Monthly", tag: ""))
    }

    /// About seven hundred lines over a year: sixty payees, a gym that repeats monthly, a
    /// handful unticked, two people, one account found on a transfer, and a balance.
    private func bigReview(attachingTo recurring: String?) -> StatementImport.Review {
        var rows: [StatementCandidate] = []
        let months = (1...12).map { String(format: "2025-%02d", $0) }
        for (m, month) in months.enumerated() {
            for payee in 0..<57 {
                let day = String(format: "%02d", payee % 28 + 1)
                rows.append(line("Shop \(payee)", "\(month)-\(day)", Double(100 + payee * 7 + m), keep: payee % 19 != 0,
                                 member: payee == 3 ? "Anil" : payee == 4 ? "Meera" : nil))
            }
            rows.append(line("Cult gym", "\(month)-05", 1500))
        }
        let gymDates = months.map { "\($0)-05" }
        let attached: [(id: String, charges: [[String: Any]])] = recurring.map {
            [(id: $0, charges: [["date": "2025-06-30", "amount": 649.0, "paid": true, "basis": "statement"]])]
        } ?? []
        let file = StatementImport.ReviewFile(rows: rows, attached: attached, account: "HDFC savings 4417", addsAccount: true,
                                              source: "documents/hdfc.pdf", balance: 52_000, balanceDate: "2025-12-31")
        return StatementImport.Review(members: ["Anil", "Meera"], accounts: [.init(name: "Axis card 4402")], files: [file], currency: "INR",
                                      repeats: [repeated("Cult gym", gymDates, 1500), repeated("Piano lessons", [], 2500)],
                                      waiting: [])
    }

    // MARK: one write

    func testTheWholeReviewLandsInOneVaultMarkedAsTheOwnersOwn() throws {
        let raw = try openingVault()
        let recurring = (raw["commitments"] as? [[String: Any]] ?? []).first { ($0["billing_cycle"] as? String) != "once" }
        let review = bigReview(attachingTo: recurring?["id"] as? String)
        let kept = review.files[0].rows.filter(\.keep).count
        let result = try StatementImport.write(review, to: raw, now: now, schema: VaultContract.bundledSchema())
        let next = result.vault

        XCTAssertEqual(result.charges, kept + (recurring == nil ? 0 : 1))
        XCTAssertEqual(result.promoted, ["Cult gym"], "a ticked repeat becomes one recurring commitment")
        let subs = next["commitments"] as? [[String: Any]] ?? []
        let gym = subs.filter { ($0["name"] as? String) == "Cult gym" }
        XCTAssertEqual(gym.count, 1)
        XCTAssertEqual(gym.first?["billing_cycle"] as? String, "monthly")
        XCTAssertGreaterThan(VaultPatch.chargeRows(next).filter { $0["commitment_id"] as? String == gym.first?["id"] as? String }.count, 12,
                             "planned ahead")
        // Unticked lines are never written.
        let unticked = review.files[0].rows.filter { !$0.keep }.map(\.line.date)
        XCTAssertFalse(unticked.isEmpty)
        XCTAssertFalse(subs.contains { ($0["name"] as? String) == "Shop 0" }, "an unticked payee writes nothing")
        // People, the found account and the statement's own account, each once.
        let members = (next["members"] as? [[String: Any]] ?? []).compactMap { $0["name"] as? String }
        XCTAssertEqual(Set(members.filter { ["Anil", "Meera"].contains($0) }), ["Anil", "Meera"])
        let accounts = next["accounts"] as? [[String: Any]] ?? []
        XCTAssertEqual(accounts.filter { ($0["name"] as? String) == "HDFC savings 4417" }.count, 1)
        XCTAssertTrue(accounts.contains { ($0["name"] as? String) == "Axis card 4402" })
        XCTAssertEqual(accounts.first { ($0["name"] as? String) == "HDFC savings 4417" }?["balance"] as? Double, 52_000)
        // The repeat with no lines waits as a placeholder.
        XCTAssertEqual((next["to_fill_in"] as? [[String: Any]])?.compactMap { $0["name"] as? String }, ["Piano lessons"])

        // Every row it touched is vouched for, so the other device adopts it without asking.
        XCTAssertTrue(OwnEdit.isOwn(from: raw, to: try roundTrip(next)))
        XCTAssertEqual(VaultHistory.verdict(ours: false, hasOpenReview: false, base: .bytes, synced: true, unchanged: false), .adopt)
    }

    // MARK: a charge is a fact

    /// A monthly commitment with one row on the 5th, as `first` says, and the file's account.
    private func gymVault(first: [String: Any]) -> [String: Any] {
        var row = first
        row["commitment_id"] = "gym"
        row["date"] = "2026-09-05"
        return ["app": "longbook", "version": 3, "members": [["id": "m1", "name": "Asha Rao", "name_key": "asha rao"]],
                "commitments": [["id": "gym", "name": "Cult gym", "amount": 1500.0, "currency": "INR", "billing_cycle": "monthly", "status": "active",
                                 "tag": "Fitness", "member_id": "m1", "created_at": "2026-01-01T00:00:00Z", "updated_at": "2026-01-01T00:00:00Z"]],
                "charges": [row]]
    }

    private func gymLine(_ amount: Double, _ words: String) -> [String: Any] {
        ["date": "2026-09-05", "amount": amount, "paid": true, "basis": "statement", "note": StatementImport.notePrefix + words]
    }

    private func written(_ lines: [[String: Any]], over raw: [String: Any]) throws -> StatementImport.Written {
        let file = StatementImport.ReviewFile(rows: [], attached: [(id: "gym", charges: lines)], account: "HDFC savings 4417",
                                              addsAccount: true, source: "documents/hdfc.pdf")
        let review = StatementImport.Review(members: [], accounts: [], files: [file], currency: "INR", repeats: [], waiting: [])
        return try StatementImport.write(review, to: raw, now: now, schema: VaultContract.bundledSchema())
    }

    private func onTheFifth(_ vault: [String: Any]) -> [[String: Any]] {
        VaultPatch.chargeRows(vault).filter { $0["date"] as? String == "2026-09-05" }
    }

    func testASecondLineOnADayIsItsOwnChargeAndNeverOverwritesTheFirst() throws {
        let raw = gymVault(first: ["amount": 1500.0, "paid": false, "basis": "plan"])
        let result = try written([gymLine(1500, "GYM MONTHLY"), gymLine(240, "GYM LOCKER")], over: raw)
        XCTAssertEqual(result.charges, 2)
        let rows = onTheFifth(result.vault)
        XCTAssertEqual(rows.count, 2, "every line kept is a row")
        let home = try XCTUnwrap(rows.first { $0["commitment_id"] as? String == "gym" })
        XCTAssertEqual(home["amount"] as? Double, 1500)
        XCTAssertEqual(home["note"] as? String, StatementImport.notePrefix + "GYM MONTHLY", "the plan's row takes the first line")
        let apart = try XCTUnwrap(rows.first { $0["commitment_id"] as? String != "gym" })
        XCTAssertEqual(apart["amount"] as? Double, 240)
        XCTAssertEqual(apart["basis"] as? String, "statement")
        XCTAssertEqual(apart["note"] as? String, StatementImport.notePrefix + "GYM LOCKER")
        let own = try XCTUnwrap((result.vault["commitments"] as? [[String: Any]])?.first { $0["id"] as? String == apart["commitment_id"] as? String })
        XCTAssertEqual(own["name"] as? String, "Cult gym", "the same name")
        XCTAssertEqual(own["billing_cycle"] as? String, "once")
        XCTAssertEqual(own["tag"] as? String, "Fitness")
        XCTAssertEqual(own["member_id"] as? String, "m1")
        XCTAssertEqual((own["details"] as? [String: Any])?["statement_line"] as? String, "GYM LOCKER", "it carries its line")
        XCTAssertNotNil(own["account_id"], "on the statement's account")
    }

    func testAConfirmedChargeIsNeverOverwrittenByALine() throws {
        for held: [String: Any] in [["amount": 1500.0, "paid": true, "basis": "statement", "note": StatementImport.notePrefix + "GYM MONTHLY"],
                                    ["amount": 1500.0, "paid": true, "basis": "mark_paid"]] {
            let result = try written([gymLine(1725, "GYM ANNUAL PASS")], over: gymVault(first: held))
            let rows = onTheFifth(result.vault)
            XCTAssertEqual(result.charges, 1)
            XCTAssertEqual(rows.count, 2)
            let home = try XCTUnwrap(rows.first { $0["commitment_id"] as? String == "gym" })
            XCTAssertEqual(home["amount"] as? Double, 1500, "a fact stays as it was")
            XCTAssertEqual(home["note"] as? String, held["note"] as? String)
            XCTAssertEqual(home["basis"] as? String, held["basis"] as? String)
        }
    }

    func testTwoIdenticalLinesOnADayAreTwoCharges() throws {
        let result = try written([gymLine(240, "GYM LOCKER"), gymLine(240, "GYM LOCKER")], over: gymVault(first: ["amount": 240.0, "paid": false, "basis": "plan"]))
        XCTAssertEqual(result.charges, 2)
        XCTAssertEqual(onTheFifth(result.vault).count, 2)
    }

    func testALineConfirmsAChargeMarkedPaidAtItsAmountRatherThanDoublingIt() throws {
        let raw = gymVault(first: ["amount": 1500.0, "paid": true, "basis": "mark_paid", "note": "Paid at the desk"])
        let result = try written([gymLine(1500, "GYM MONTHLY")], over: raw)
        let rows = onTheFifth(result.vault)
        XCTAssertEqual(result.charges, 1)
        XCTAssertEqual(rows.count, 1, "one payment, marked and then printed")
        XCTAssertEqual(rows[0]["basis"] as? String, "statement")
        XCTAssertEqual(rows[0]["note"] as? String, "Paid at the desk", "what was written on it stays")
    }

    func testAStatementReadAgainWritesNothingTwice() throws {
        let raw = gymVault(first: ["amount": 1500.0, "paid": false, "basis": "plan"])
        let vault = try written([gymLine(1500, "GYM MONTHLY"), gymLine(240, "GYM LOCKER")], over: raw).vault
        let keys = StatementImport.importedChargeKeys(in: try JSONDecoder().decode(Vault.self, from: JSONSerialization.data(withJSONObject: vault)))
        func line(_ amount: Double, _ words: String) -> StatementCandidate {
            StatementCandidate(line: StatementLine(date: "2026-09-05", payee: words, amount: amount, direction: .debit), name: "Cult gym", tag: nil, keep: true, skipReason: nil)
        }
        var again = [line(1500, "GYM MONTHLY"), line(240, "GYM LOCKER")]
        StatementImport.markAlreadyPresent(&again, in: keys)
        XCTAssertEqual(again.map(\.keep), [false, false])
    }

    /// The owner corrects a line the bank misspelled, then reads the same file again.
    private func candidate(_ amount: Double, _ words: String, date: String = "2026-09-05", file: String = "hdfc") -> StatementCandidate {
        StatementCandidate(line: StatementLine(date: date, payee: words, amount: amount, direction: .debit), name: "Cult gym", tag: nil, keep: true, skipReason: nil, file: file)
    }

    private func decoded(_ raw: [String: Any]) throws -> Vault {
        try JSONDecoder().decode(Vault.self, from: JSONSerialization.data(withJSONObject: raw))
    }

    private func readAgain(_ lines: [StatementCandidate], over raw: [String: Any], accounts: [String: String] = ["hdfc": "HDFC savings 4417"]) throws -> [StatementCandidate] {
        let vault = try decoded(raw)
        var again = lines
        StatementImport.markAlreadyPresent(&again, in: StatementImport.importedChargeKeys(in: vault))
        StatementImport.markCorrectedLinesPresent(&again, held: StatementImport.heldLines(in: vault), accounts: accounts)
        return again
    }

    func testARowWithNoAccountDoesNotAnswerForAnotherMerchantsLineOfThatDayAndAmount() {
        let held = StatementImport.HeldLine(date: "2026-09-05", amount: 1500, accounts: [], isIncome: false, name: "Gym", keys: ["x"])
        var lines = [candidate(1500, "POS CORNER SHOP")]
        StatementImport.markCorrectedLinesPresent(&lines, held: [held], accounts: ["hdfc": "HDFC savings 4417"])
        XCTAssertEqual(lines.map(\.keep), [true], "a charge is a fact")
    }

    func testMoneyInHeldDoesNotAnswerForACharge() {
        let held = StatementImport.HeldLine(date: "2026-09-05", amount: 1500, accounts: ["HDFC savings 4417"], isIncome: true, name: "Refund", keys: ["x"])
        var lines = [candidate(1500, "POS CORNER SHOP")]
        StatementImport.markCorrectedLinesPresent(&lines, held: [held], accounts: ["hdfc": "HDFC savings 4417"])
        XCTAssertEqual(lines.map(\.keep), [true])
    }

    func testACorrectedLineOnACommitmentsChargeAddsNoTwinWhenTheFileIsReadAgain() throws {
        let raw = gymVault(first: ["amount": 1500.0, "paid": false, "basis": "plan"])
        var vault = try written([gymLine(1500, "GYM MONHTLY"), gymLine(240, "GYM LOCKER")], over: raw).vault
        vault = try VaultPatch.setCharge(commitmentId: "gym", date: "2026-09-05",
                                         note: .some(ChargeNote.joined(statementLine: "GYM MONTHLY", notes: "Paid for Asha")), in: vault, now: now)
        let home = try XCTUnwrap(onTheFifth(vault).first { $0["commitment_id"] as? String == "gym" })
        XCTAssertEqual(home["basis"] as? String, "statement", "a corrected note leaves what backs the row")
        let again = try readAgain([candidate(1500, "GYM MONHTLY"), candidate(240, "GYM LOCKER")], over: vault)
        XCTAssertEqual(again.map(\.keep), [false, false])
        XCTAssertEqual(again.map(\.skipReason), ["already in your longbook", "already in your longbook"])
    }

    func testACorrectedLineOnAOneTimeRowAddsNoTwinWhenTheFileIsReadAgain() throws {
        let raw = gymVault(first: ["amount": 1500.0, "paid": false, "basis": "plan"])
        var vault = try written([gymLine(1500, "GYM MONTHLY"), gymLine(240, "GYM LOKER")], over: raw).vault
        let apart = try XCTUnwrap(onTheFifth(vault).first { $0["commitment_id"] as? String != "gym" })
        vault = try VaultPatch.setCharge(commitmentId: try XCTUnwrap(apart["commitment_id"] as? String), date: "2026-09-05",
                                         note: .some(ChargeNote.joined(statementLine: "GYM LOCKER", notes: nil)), in: vault, now: now)
        let again = try readAgain([candidate(1500, "GYM MONTHLY"), candidate(240, "GYM LOKER")], over: vault)
        XCTAssertEqual(again.map(\.keep), [false, false])
    }

    func testNotesWrittenUnderALineLeaveItFoundByItsOwnWords() throws {
        let raw = gymVault(first: ["amount": 1500.0, "paid": false, "basis": "plan"])
        var vault = try written([gymLine(1500, "GYM MONTHLY")], over: raw).vault
        vault = try VaultPatch.setCharge(commitmentId: "gym", date: "2026-09-05",
                                         note: .some(ChargeNote.joined(statementLine: "GYM MONTHLY", notes: "Paid for Asha")), in: vault, now: now)
        let keys = StatementImport.importedChargeKeys(in: try decoded(vault))
        XCTAssertTrue(keys.contains(StatementImport.key(date: "2026-09-05", amount: 1500, narration: "GYM MONTHLY")))
    }

    func testAClearedLineStillCountsAsPresentByDayAndAmount() throws {
        let raw = gymVault(first: ["amount": 1500.0, "paid": false, "basis": "plan"])
        var vault = try written([gymLine(1500, "GYM MONTHLY")], over: raw).vault
        vault = try VaultPatch.setCharge(commitmentId: "gym", date: "2026-09-05", note: .some(nil), in: vault, now: now)
        XCTAssertEqual(try readAgain([candidate(1500, "GYM MONTHLY")], over: vault).map(\.keep), [false])
    }

    func testACorrectedRowAnswersOnceSoASecondChargeOfThatDayAndAmountComesIn() throws {
        let raw = gymVault(first: ["amount": 1500.0, "paid": false, "basis": "plan"])
        var vault = try written([gymLine(1500, "GYM MONHTLY")], over: raw).vault
        vault = try VaultPatch.setCharge(commitmentId: "gym", date: "2026-09-05",
                                         note: .some(ChargeNote.joined(statementLine: "GYM MONTHLY", notes: nil)), in: vault, now: now)
        let again = try readAgain([candidate(1500, "GYM MONHTLY"), candidate(1500, "SWIGGY")], over: vault)
        XCTAssertEqual(again.map(\.keep), [false, true])
    }

    func testAnUnrelatedLineOfThatDayAndAmountComesInBesideARowItsFileCarries() throws {
        let raw = gymVault(first: ["amount": 1500.0, "paid": false, "basis": "plan"])
        let vault = try written([gymLine(1500, "GYM MONTHLY")], over: raw).vault
        let again = try readAgain([candidate(1500, "GYM MONTHLY"), candidate(1500, "SWIGGY")], over: vault)
        XCTAssertEqual(again.map(\.keep), [false, true], "the row answers to its own line and leaves the other alone")
    }

    func testALineOnAnotherAccountIsNeverTakenForACorrectedRow() throws {
        var raw = gymVault(first: ["amount": 1500.0, "paid": false, "basis": "plan"])
        raw["accounts"] = [["id": "a1", "name": "HDFC savings 4417", "name_key": "hdfc savings 4417"]]
        var subs = raw["commitments"] as? [[String: Any]] ?? []
        subs[0]["account_id"] = "a1"
        raw["commitments"] = subs
        var vault = try written([gymLine(1500, "GYM MONHTLY")], over: raw).vault
        vault = try VaultPatch.setCharge(commitmentId: "gym", date: "2026-09-05",
                                         note: .some(ChargeNote.joined(statementLine: "GYM MONTHLY", notes: nil)), in: vault, now: now)
        let again = try readAgain([candidate(1500, "SWIGGY", file: "axis")], over: vault, accounts: ["axis": "Axis card 2222"])
        XCTAssertEqual(again.map(\.keep), [true])
    }

    func testAPlannedRowIsNeverTakenForAStatementLine() throws {
        let raw = gymVault(first: ["amount": 1500.0, "paid": false, "basis": "plan"])
        XCTAssertEqual(try readAgain([candidate(1500, "GYM MONTHLY")], over: raw).map(\.keep), [true])
    }

    func testAnImportedRowStillReadsAsNotedOnceTheOwnerWritesUnderItsLine() {
        let vault: [String: Any] = ["commitments": [["id": "c1", "name": "Shop", "billing_cycle": "once"]],
                                    "charges": [["commitment_id": "c1", "note": "Statement line: UPI-SHOP\nGift"]]]
        XCTAssertTrue(StatementCompleteness.check(vault: vault, importedIds: ["c1"]).isEmpty)
    }

    func testARepeatWithTwoLinesOnADayKeepsTheFirstAndEveryLineStaysARow() throws {
        let dates = ["2026-07-05", "2026-08-05", "2026-09-05"]
        let rows = [line("Cult gym", dates[0], 1500), line("Cult gym", dates[1], 1500), line("Cult gym", dates[1], 240), line("Cult gym", dates[2], 1500)]
        let file = StatementImport.ReviewFile(rows: rows, account: "HDFC savings 4417", addsAccount: true, source: "documents/hdfc.pdf")
        let review = StatementImport.Review(members: [], accounts: [], files: [file], currency: "INR", repeats: [repeated("Cult gym", dates, 1500)], waiting: [])
        let result = try StatementImport.write(review, to: ["app": "longbook", "version": 3], now: now, schema: VaultContract.bundledSchema())
        let proved = VaultPatch.chargeRows(result.vault).filter { $0["basis"] as? String == "statement" }
        XCTAssertEqual(result.charges, 4)
        XCTAssertEqual(proved.count, 4, "every line kept is a row")
        let gym = try XCTUnwrap((result.vault["commitments"] as? [[String: Any]])?.first { $0["billing_cycle"] as? String == "monthly" })
        let held = proved.filter { $0["commitment_id"] as? String == gym["id"] as? String }
        XCTAssertEqual(held.count, 3, "one row per day")
        XCTAssertEqual(Set(held.compactMap { $0["date"] as? String }).count, 3)
    }

    func testARepeatPlansAheadAtItsLatestSightingAndPastRowsKeepTheirOwn() throws {
        let dates = ["2026-07-05", "2026-08-05", "2026-09-05"]
        let rows = [line("Cult gym", dates[0], 1000), line("Cult gym", dates[1], 1000), line("Cult gym", dates[2], 1100)]
        let file = StatementImport.ReviewFile(rows: rows, account: "HDFC savings 4417", addsAccount: true, source: "documents/hdfc.pdf")
        let review = StatementImport.Review(members: [], accounts: [], files: [file], currency: "INR", repeats: [repeated("Cult gym", dates, 1000)], waiting: [])
        let vault = try StatementImport.write(review, to: ["app": "longbook", "version": 3], now: now, schema: VaultContract.bundledSchema()).vault
        let gym = try XCTUnwrap((vault["commitments"] as? [[String: Any]])?.first { $0["billing_cycle"] as? String == "monthly" })
        XCTAssertEqual(gym["amount"] as? Double, 1100)
        let held = Fx.rows(vault, of: try XCTUnwrap(gym["id"] as? String))
        XCTAssertEqual(held.filter { $0["basis"] as? String == "statement" }.map { $0["amount"] as? Double }, [1000, 1000, 1100], "a fact keeps its amount")
        let ahead = held.filter { $0["basis"] as? String == "plan" }
        XCTAssertFalse(ahead.isEmpty)
        XCTAssertTrue(ahead.allSatisfy { $0["amount"] as? Double == 1100 }, "the plan runs at the latest sighting")
    }

    func testAGuessedRepeatIsWrittenAsOneAndAPersonsBankIsTheirs() throws {
        let raw = try openingVault()
        var review = bigReview(attachingTo: nil)
        // The gym repeats twelve times; a premium seen twice is promoted as a guess.
        review.files[0].rows += [line("Star Health", "2025-01-12", 9200), line("Star Health", "2025-07-12", 9200)]
        for index in review.files[0].rows.indices where review.files[0].rows[index].name == "Shop 3" {
            review.files[0].rows[index].counterpartAccount = "Axis savings ••1234"
        }
        let premium = StatementCloud.Repeat(name: "Star Health", cycle: "custom", customDays: 183, amount: 9200,
                                            dates: ["2025-01-12", "2025-07-12"], category: "insurance", endsOn: nil,
                                            guessed: true, reason: "Seen twice, half a year apart; the insurer's name says it comes round.")
        review.repeats.append((premium, CommitmentPlaceholder(name: "Star Health", group: "Custom", tag: "insurance")))
        review.accounts = [.init(name: "Axis savings ••1234", person: "Anil")]

        let result = try StatementImport.write(review, to: raw, now: now, schema: VaultContract.bundledSchema())
        let next = result.vault
        XCTAssertEqual(result.promoted, ["Cult gym", "Star Health"])
        let subs = next["commitments"] as? [[String: Any]] ?? []
        let guessed = try XCTUnwrap(subs.first { ($0["name"] as? String) == "Star Health (Guessed)" }, "the name says it is a guess")
        XCTAssertEqual(guessed["billing_cycle"] as? String, "custom")
        XCTAssertEqual((guessed["notes"] as? String)?.components(separatedBy: "\n").first,
                       "Guessed: Seen twice, half a year apart; the insurer's name says it comes round.")
        XCTAssertFalse(subs.contains { ($0["name"] as? String) == "Star Health" }, "the two one-time rows are the commitment's own now")
        let gym = try XCTUnwrap(subs.first { ($0["name"] as? String) == "Cult gym" })
        XCTAssertTrue((gym["notes"] as? String ?? "").isEmpty, "a proven repeat carries no guess")

        // The found account belongs to the person named beside it, and the rows that moved
        // money to it carry its id beside its name.
        let people = next["members"] as? [[String: Any]] ?? []
        let anil = try XCTUnwrap(people.first { ($0["name"] as? String) == "Anil" }?["id"] as? String)
        let accounts = next["accounts"] as? [[String: Any]] ?? []
        let axis = try XCTUnwrap(accounts.first { ($0["name"] as? String) == "Axis savings ••1234" })
        XCTAssertEqual(axis["member_id"] as? String, anil)
        let shop3 = subs.filter { ($0["name"] as? String) == "Shop 3" }
        XCTAssertEqual(shop3.count, 12)
        for row in shop3 {
            let details = try XCTUnwrap(row["details"] as? [String: Any])
            XCTAssertEqual(details["counterpart_account"] as? String, "Axis savings ••1234")
            XCTAssertEqual(details["counterpart_account_id"] as? String, axis["id"] as? String)
        }
        XCTAssertNil((subs.first { ($0["name"] as? String) == "Shop 5" }?["details"] as? [String: Any])?["counterpart_account_id"])
        XCTAssertTrue(OwnEdit.isOwn(from: raw, to: try roundTrip(next)))
    }

    func testAnOldStatementNeverRewindsANewerBalance() throws {
        var raw = try openingVault()
        raw = try VaultPatch.ensureEntity(.paymentMethod, named: "HDFC savings 4417", in: raw, now: now).vault
        let id = try XCTUnwrap((raw["accounts"] as? [[String: Any]])?.first { ($0["name"] as? String) == "HDFC savings 4417" }?["id"] as? String)
        raw = try VaultPatch.setEntityDetails(.paymentMethod, id: id, in: raw, now: now, balance: .some(90_000), balanceDate: .some("2026-09-30"))
        let next = try StatementImport.write(bigReview(attachingTo: nil), to: raw, now: now, schema: nil).vault
        let row = (next["accounts"] as? [[String: Any]])?.first { $0["id"] as? String == id }
        XCTAssertEqual(row?["balance"] as? Double, 90_000)
        XCTAssertEqual(row?["balance_date"] as? String, "2026-09-30")
    }

    func testARefusedNameStopsTheAddWithNothingApplied() throws {
        let raw = try openingVault()
        var review = bigReview(attachingTo: nil)
        review.members = ["Anil", "4111 1111 1111 1111"]
        XCTAssertThrowsError(try StatementImport.write(review, to: raw, now: now, schema: nil))
    }

    func testAnOutsideWriteAfterTheAddStillStandsForReview() throws {
        let raw = try openingVault()
        let added = try roundTrip(StatementImport.write(bigReview(attachingTo: nil), to: raw, now: now, schema: nil).vault)
        // An AI or another program adds a row with no app signature or mark.
        let write = PendingWrite(id: UUID(), kind: "add_commitments",
                                 payload: ["rows": [["name": "Piano lessons", "amount": 2500, "currency": "INR",
                                                     "billing_cycle": "monthly", "first_charge": "2026-11-10"]]],
                                 keyName: "claude")
        guard case .vault(let outside) = try PendingApply.apply(write, to: added, now: now) else { return XCTFail("not a vault") }
        XCTAssertFalse(OwnEdit.isOwn(from: added, to: try roundTrip(outside)))
        XCTAssertEqual(VaultHistory.verdict(ours: false, hasOpenReview: false, base: .bytes, synced: false, unchanged: false), .review)
        // A hand edit to a row the import wrote is outside too.
        var edited = added
        var subs = edited["commitments"] as? [[String: Any]] ?? []
        if let i = subs.firstIndex(where: { ($0["name"] as? String) == "Shop 5" }) { subs[i]["amount"] = 1 }
        edited["commitments"] = subs
        XCTAssertFalse(OwnEdit.isOwn(from: added, to: edited))
    }

    // MARK: before and after

    /// The add as it was: one patch, write and re-read per step. The people and accounts went
    /// in through addEntity, which leaves no provenance, so the version the other device
    /// receives holds rows nobody vouched for, and its review opens.
    func testTimingAndWritesBeforeAndAfter() throws {
        let raw = try openingVault()
        let review = bigReview(attachingTo: nil)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("lb-review-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent(VaultReader.dataFile)
        let schema = VaultContract.bundledSchema()

        // Before: a commit per step, as DashboardModel ran them.
        try JSONSerialization.data(withJSONObject: raw, options: [.prettyPrinted, .sortedKeys]).write(to: file)
        var loaded = try VaultReader.load(from: folder)
        var writes = 0
        func commit(_ patch: ([String: Any]) throws -> [String: Any]) throws {
            try VaultDisk.write(try patch(loaded.raw), to: folder, expecting: loaded.bytes)
            writes += 1
            loaded = try VaultReader.load(from: folder)
        }
        func imported(_ write: PendingWrite) throws {
            try commit { current in
                guard case .vault(let applied) = try PendingApply.apply(write, to: current, now: self.now, schema: schema) else { return current }
                let ids = vaultDiff(from: current, to: applied).filter { $0.kind != "tags" }
                    .flatMap { $0.added.map(\.id) + $0.changed.map(\.id) + $0.removed.map(\.id) }
                return VaultPatch.markReviewed(ids: ids, in: applied, now: self.now)
            }
        }
        let start = Date()
        for name in review.members { try commit { try VaultPatch.ensureEntity(.familyMember, named: name, in: $0, now: self.now).vault } }
        for name in review.accounts.map(\.name) { try commit { try VaultPatch.ensureEntity(.paymentMethod, named: name, in: $0, now: self.now).vault } }
        let one = review.files[0]
        try commit { try VaultPatch.ensureEntity(.paymentMethod, named: one.account, in: $0, now: self.now).vault }
        try imported(StatementImport.proposal(one.rows, accounts: ["": one.account], currency: "INR", source: "documents/hdfc.pdf"))
        var accountId = ""
        try commit { let made = try VaultPatch.ensureEntity(.paymentMethod, named: one.account, in: $0, now: self.now); accountId = made.id; return made.vault }
        try commit { try VaultPatch.setEntityDetails(.paymentMethod, id: accountId, in: $0, now: self.now, balance: .some(52_000), balanceDate: .some("2025-12-31")) }
        var promotedVault = loaded.raw
        let before = Set((raw["commitments"] as? [[String: Any]] ?? []).compactMap { $0["id"] as? String })
        for (repeated, _) in review.repeats {
            var probe = promotedVault
            guard !StatementImport.promote([repeated], madeSince: before, in: &probe, source: "documents/hdfc.pdf", now: now, schema: schema).isEmpty
            else { continue }
            try commit { _ in probe }
            promotedVault = loaded.raw
        }
        try commit { VaultPatch.setToFillIn(review.repeats.suffix(1).map(\.placeholder), in: $0) }
        let oldSeconds = Date().timeIntervalSince(start)
        let oldWrites = writes
        // The cause: the version the other device receives carries account and person rows
        // with no provenance at all, so it is judged an outside change.
        XCTAssertFalse(OwnEdit.isOwn(from: raw, to: loaded.raw), "the old add reached the other device as an outside change")

        // After: one write.
        try JSONSerialization.data(withJSONObject: raw, options: [.prettyPrinted, .sortedKeys]).write(to: file)
        loaded = try VaultReader.load(from: folder)
        writes = 0
        let started = Date()
        let built = try StatementImport.write(review, to: loaded.raw, now: now, schema: schema)
        let buildSeconds = Date().timeIntervalSince(started)
        try commit { _ in built.vault }
        let newSeconds = Date().timeIntervalSince(started)
        XCTAssertEqual(writes, 1)
        XCTAssertTrue(OwnEdit.isOwn(from: raw, to: loaded.raw))
        print(String(format: "statement review of %d lines: before %d writes in %.2f s; after %d write in %.2f s (build %.2f s)",
                     one.rows.count, oldWrites, oldSeconds, writes, newSeconds, buildSeconds))
    }

    private func roundTrip(_ vault: [String: Any]) throws -> [String: Any] {
        let data = try JSONSerialization.data(withJSONObject: vault, options: [.sortedKeys])
        return try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
