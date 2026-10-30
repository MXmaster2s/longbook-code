// The Transfers rule, the holder, account names by owner, payment names, the completeness
// score and the signing of the app's own writes. Every name here is made up.
import XCTest
@testable import LongbookCore

final class StatementTransfersTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    /// Asha is Self; her two accounts hold a move between them; Bina is a friend with her own account.
    private func book(ashaTag: String? = "Self", sunilTag: String? = nil) -> [String: Any] {
        var asha: [String: Any] = ["id": "m1", "name": "Asha Rao", "name_key": "asha rao"]
        if let ashaTag { asha["tag"] = ashaTag }
        var sunil: [String: Any] = ["id": "m2", "name": "Sunil Rao", "name_key": "sunil rao"]
        if let sunilTag { sunil["tag"] = sunilTag }
        return [
            "members": [asha, sunil],
            "accounts": [["id": "a1", "name": "HDFC Bank", "member_id": "m1"], ["id": "a2", "name": "Axis Bank", "member_id": "m1"],
                         ["id": "a3", "name": "Axis Bank", "member_id": "m2"]],
            "commitments": [
                ["id": "t1", "name": "To savings", "billing_cycle": "once", "account_id": "a1", "direction": "transfer",
                 "details": ["counterpart_account_id": "a2", "line_direction": "out"]],
                ["id": "t2", "name": "Back in", "billing_cycle": "once", "account_id": "a1",
                 "details": ["counterpart_account_id": "a3", "line_direction": "in"]],
                ["id": "t3", "name": "Plain", "billing_cycle": "once", "account_id": "a1"],
            ],
        ]
    }

    private func direction(_ raw: [String: Any], _ id: String) -> String? {
        (raw["commitments"] as? [[String: Any]])?.first { $0["id"] as? String == id }?["direction"] as? String
    }

    func testATransferNeedsBothAccountsOwnedBySelfPeople() {
        let next = StatementTransfers.apply(book(), now: now)
        XCTAssertEqual(direction(next, "t1"), "transfer")
        XCTAssertNil(direction(next, "t3"), "no counterpart, no transfer")
        XCTAssertNil(direction(StatementTransfers.apply(book(sunilTag: "friend"), now: now), "t2"))
        XCTAssertEqual(direction(StatementTransfers.apply(book(sunilTag: "SELF"), now: now), "t2"), "transfer", "the tag matches in any case")
    }

    func testClearingSelfReturnsTheLinePrintedDirection() {
        let off = StatementTransfers.apply(book(ashaTag: nil), now: now)
        XCTAssertNil(direction(off, "t1"), "money out returns to a charge")
        var vault = book(sunilTag: "self")
        vault = StatementTransfers.apply(vault, now: now)
        XCTAssertEqual(direction(vault, "t2"), "transfer")
        var members = vault["members"] as! [[String: Any]]
        members[1]["tag"] = NSNull()
        vault["members"] = members
        XCTAssertEqual(direction(StatementTransfers.apply(vault, now: now), "t2"), "in")
        let incoming = StatementTransfers.apply(["members": [["id": "m", "name": "A"]], "accounts": [],
            "commitments": [["id": "x", "billing_cycle": "once", "direction": "transfer", "details": ["line_direction": "in"]]]], now: now)
        XCTAssertEqual(direction(incoming, "x"), "in", "money in returns to money in")
    }

    func testDeletingASelfPersonEndsTheirTransfers() throws {
        let applied = StatementTransfers.apply(book(), now: now)
        XCTAssertEqual(direction(applied, "t1"), "transfer")
        let next = try VaultPatch.deleteEntity(.familyMember, id: "m1", in: applied, now: now)
        XCTAssertNil(direction(next, "t1"))
    }

    func testAChangedRowIsSignedAsTheApps() {
        let next = StatementTransfers.apply(book(sunilTag: "self"), now: now)
        XCTAssertNotNil((next["_provenance"] as? [String: Any])?["t2"])
        XCTAssertNil((next["_provenance"] as? [String: Any])?["t3"])
    }

    func testFlipsCountBothWaysAndZero() throws {
        let vault = StatementTransfers.apply(book(), now: now)
        let toSunil = try VaultPatch.setEntityDetails(.familyMember, id: "m2", in: vault, now: now, memberTag: .some("self"))
        XCTAssertEqual(StatementTransfers.flips(from: vault, to: toSunil).intoTransfers, 1)
        XCTAssertEqual(StatementTransfers.flips(from: vault, to: toSunil).intoCharges, 0)
        let clearAsha = try VaultPatch.setEntityDetails(.familyMember, id: "m1", in: vault, now: now, memberTag: .some(nil))
        let gone = StatementTransfers.flips(from: vault, to: clearAsha)
        XCTAssertEqual(gone.intoCharges, 1)
        XCTAssertEqual(gone.intoTransfers, 0)
        let same = StatementTransfers.flips(from: vault, to: vault)
        XCTAssertEqual(same.intoTransfers + same.intoCharges, 0)
    }

    func testSettingAnOwnerOrATagReappliesTheRule() throws {
        var vault = StatementTransfers.apply(book(), now: now)
        vault = try VaultPatch.setEntityDetails(.paymentMethod, id: "a3", in: vault, now: now, ownerMemberId: .some("m1"))
        XCTAssertEqual(direction(vault, "t2"), "transfer", "an owner set flips the matching charge")
        vault = try VaultPatch.setEntityDetails(.paymentMethod, id: "a3", in: vault, now: now, ownerMemberId: .some(nil))
        XCTAssertEqual(direction(vault, "t2"), "in", "and clearing it flips it back to money in")
    }

    func testTheCounterpartSetterWritesBothKeysSignsAndRefusesAnUnknownAccount() throws {
        let vault = book()
        let set = try VaultPatch.setCounterpartAccount(commitmentId: "t3", accountId: "a2", in: vault, now: now)
        let row = try XCTUnwrap((set["commitments"] as? [[String: Any]])?.first { $0["id"] as? String == "t3" })
        let details = try XCTUnwrap(row["details"] as? [String: Any])
        XCTAssertEqual(details["counterpart_account_id"] as? String, "a2")
        XCTAssertEqual(details["counterpart_account"] as? String, "Axis Bank")
        XCTAssertEqual(row["direction"] as? String, "transfer", "the rule is re-run")
        XCTAssertNotNil((set["_provenance"] as? [String: Any])?["t3"])
        let cleared = try VaultPatch.setCounterpartAccount(commitmentId: "t3", accountId: nil, in: set, now: now)
        let after = try XCTUnwrap((cleared["commitments"] as? [[String: Any]])?.first { $0["id"] as? String == "t3" })
        XCTAssertNil(after["details"])
        XCTAssertThrowsError(try VaultPatch.setCounterpartAccount(commitmentId: "t3", accountId: "nope", in: vault, now: now))
    }

    // MARK: the holder

    func testTheHolderIsAnyLineNameSharingTwoWords() {
        XCTAssertTrue(StatementHolder.same("Asha Rao", "RAO ASHA KUMARI"))
        XCTAssertTrue(StatementHolder.same("Asha K Rao", "Asha Kumari Rao"))
        XCTAssertFalse(StatementHolder.same("Asha Rao", "Asha Menon"))
        XCTAssertEqual(StatementHolder.clean("MRS ASHA KUMARI RAO"), "Asha Kumari Rao")
    }

    func testTheHolderBecomesSelfAndOwnsTheStatementsAccount() throws {
        let answer = StatementCloud.ChargesAnswer(account: "Kotak savings", holder: "ASHA RAO", charges: [
            .init(date: "2026-07-20", amount: 5000, name: "To Asha", narration: "TRF TO ASHA K RAO", account: "Kotak savings", category: nil, kind: "spend",
                  member: nil, counterpart: "Asha Kumari Rao", counterpartKind: "person", counterpartBank: "Axis savings ••1234"),
        ], notes: "")
        let prepared = StatementCloud.Prepared.assemble([answer], review: .empty, today: "2026-10-30")
        XCTAssertEqual(prepared.holder, "Asha Rao")
        XCTAssertEqual(prepared.charges[0].counterpart, "Asha Rao", "never a second person")
        XCTAssertEqual(prepared.charges[0].name, "To Asha", "a name that is not the person's stays")
        let found = prepared.counterparts(knownAccounts: [], knownPeople: [])
        XCTAssertEqual(found.people, [])
        XCTAssertEqual(found.accounts, [.init(name: "Axis savings ••1234", person: "Asha Rao")])
        let candidates = prepared.candidates(among: [])
        XCTAssertEqual(candidates[0].direction, "transfer", "her own account to her own account")

        let file = StatementImport.ReviewFile(rows: candidates, account: "Kotak savings", addsAccount: true, source: "documents/k.pdf", owner: prepared.holder)
        let review = StatementImport.Review(members: [], accounts: found.accounts, files: [file], currency: "INR", repeats: [], waiting: [])
        let written = try StatementImport.write(review, to: ["app": "longbook", "version": 3], now: now, schema: VaultContract.bundledSchema()).vault
        let asha = try XCTUnwrap((written["members"] as? [[String: Any]])?.first)
        XCTAssertEqual((asha["tag"] as? String)?.lowercased(), "self")
        let accounts = written["accounts"] as? [[String: Any]] ?? []
        XCTAssertEqual(accounts.count, 2)
        XCTAssertTrue(accounts.allSatisfy { $0["member_id"] as? String == asha["id"] as? String })
        XCTAssertFalse(accounts.contains { ($0["name"] as? String)?.contains("Asha") == true }, "no person's name in an account's name")
        let row = try XCTUnwrap((written["commitments"] as? [[String: Any]])?.first { $0["name"] as? String == "To Asha" })
        XCTAssertEqual(row["direction"] as? String, "transfer")
        XCTAssertNotNil((row["details"] as? [String: Any])?["counterpart_account_id"])
        XCTAssertNil((row["details"] as? [String: Any])?["counterpart_owner"])
        XCTAssertEqual((row["details"] as? [String: Any])?["line_direction"] as? String, "out")
    }

    func testTwoAccountsAtOneBankWithNoDigitsStayApartPerOwner() throws {
        var vault: [String: Any] = [:]
        let mine = try VaultPatch.ensureAccount(named: "Axis Bank", ownerName: "Asha Rao", in: vault, now: now)
        vault = mine.vault
        let his = try VaultPatch.ensureAccount(named: "Axis Bank", ownerName: "Sunil Rao", in: vault, now: now)
        vault = his.vault
        XCTAssertNotEqual(mine.id, his.id)
        XCTAssertEqual(try VaultPatch.ensureAccount(named: "axis  bank", ownerName: "asha rao", in: vault, now: now).id, mine.id)
        let keys = (vault["accounts"] as? [[String: Any]] ?? []).compactMap { $0["name_key"] as? String }
        XCTAssertEqual(Set(keys), ["axis bank|asha rao", "axis bank|sunil rao"])
        // With digits printed the number tells them apart, and the name key stays plain.
        let numbered = try VaultPatch.ensureAccount(named: "Axis savings ••1234", ownerName: "Asha Rao", in: vault, now: now)
        XCTAssertEqual((numbered.vault["accounts"] as? [[String: Any]])?.last?["name_key"] as? String, "axis savings ••1234")
    }

    func testBankOfBarodaStaysWhole() {
        XCTAssertEqual(StatementCounterparts.accountName("Bank of Baroda savings ••1234"), "Bank of Baroda savings ••1234")
        XCTAssertEqual(StatementCounterparts.accountName("Bank of Baroda"), "Bank of Baroda")
    }

    func testAnAccountAtOneBankNeverTakesThePersonsNameAndTheOwnerTellsThemApart() {
        let line = StatementCloud.Charge(date: "2026-07-01", amount: 1, name: "x", narration: "x", account: "", category: nil, kind: "spend", member: nil,
                                         counterpart: "Sunil Rao", counterpartKind: "person", counterpartBank: "Axis Bank")
        XCTAssertEqual(StatementCounterparts.account(on: line), .init(name: "Axis Bank", person: "Sunil Rao"))
        let known = [StatementBook.Account(name: "Axis Bank", owner: "Asha Rao")]
        XCTAssertEqual(StatementCounterparts.found(in: [line], knownAccounts: known, knownPeople: []).accounts.count, 1, "another owner's account is another account")
        XCTAssertEqual(StatementCounterparts.found(in: [line], knownAccounts: [.init(name: "Axis Bank", owner: "Sunil Rao")], knownPeople: []).accounts.count, 0)
    }

    // MARK: payment names

    func testAChargeNamedForThePersonIsAPaymentToOrFromThem() {
        let out = StatementCloud.Charge(date: "2026-07-01", amount: 900, name: "Meena Das", narration: "UPI/MEENA DAS", account: "", category: nil, kind: "for_member", member: "Meena Das")
        let back = StatementCloud.Charge(date: "2026-07-02", amount: 100, name: "Meena Das", narration: "UPI/MEENA DAS", account: "", category: nil, kind: "income", member: "Meena Das")
        let repeated = StatementCloud.Repeat(name: "Meena Das", cycle: "monthly", customDays: nil, amount: 900, dates: ["2026-07-01"], category: nil, endsOn: nil)
        let prepared = StatementCloud.Prepared.assemble([.init(account: "A", charges: [out, back], notes: "")],
                                                        review: .init(repeats: [repeated], members: [], notes: ""), today: "2026-10-30")
        XCTAssertEqual(prepared.charges.map(\.name), ["Payment to Meena Das", "Payment from Meena Das"])
        XCTAssertEqual(prepared.repeats.map(\.name), ["Payment to Meena Das"], "a repeat takes its charges' name")
    }

    // MARK: the score

    func testTheScoreAveragesWhatCouldBeChecked() {
        func report(missing: Int = 0, balance: StatementCompleteness.Balance = .matches, named: Int = 0, covered: Int = 0) -> StatementCompleteness.Report {
            .init(read: 10, expectedCount: 10, missing: Array(repeating: StatementLine(date: "2026-07-01", payee: "x", amount: 1, direction: .debit), count: missing),
                  extra: 0, balance: balance, peopleNamed: named, peopleListed: covered, accountsNamed: 0, peopleCovered: covered)
        }
        XCTAssertEqual(report().score, 100)
        XCTAssertEqual(report(missing: 2).score, 90, "lines 80, balance 100")
        XCTAssertEqual(report(balance: .off(by: 5)).score, 50)
        XCTAssertEqual(report(balance: .unknown, named: 4, covered: 2).score, 75, "balance left out: lines 100, people 50")
        XCTAssertEqual(report(missing: 5, balance: .unknown, named: 2, covered: 2).score, 75)
        XCTAssertEqual(report().headline(file: "a.pdf", currency: "INR"), "Import Completeness Score: 100% · a.pdf: 10 of 10 lines · balance matches")
    }

    func testPastImportsKeepTheNewestTwoHundredAndOnlyCounts() {
        var workspace = Workspace()
        workspace.imports = (0..<205).map { ImportRecord(file: "f\($0).pdf", date: "2026-07-01", read: 5, expected: 5, balance: "matches", score: 100) }
        XCTAssertEqual(workspace.imports.count, 200)
        XCTAssertEqual(workspace.imports.first?.file, "f5.pdf", "the oldest are dropped")
        XCTAssertEqual(workspace.imports.last?.line, "Import Completeness Score: 100% · f204.pdf: 5 of 5 lines · balance matches")
        XCTAssertEqual(Set((workspace.raw["imports"] as? [[String: Any]] ?? [])[0].keys), ["file", "date", "read", "expected", "balance", "score"])
    }

    // MARK: signing

    private func vouched(_ before: [String: Any], _ after: [String: Any]) -> Bool { OwnEdit.isOwn(from: before, to: after) }

    func testEveryAppWriteVouchesForItself() throws {
        let base: [String: Any] = ["app": "longbook", "version": 3, "commitments": [Fx.rawSub(id: "a")]]
        let person = try VaultPatch.ensureEntity(.familyMember, named: "Asha Rao", in: base, now: now)
        XCTAssertTrue(vouched(base, person.vault), "a new person")
        let account = try VaultPatch.ensureEntity(.paymentMethod, named: "HDFC Bank", in: base, now: now)
        XCTAssertTrue(vouched(base, account.vault), "a new account")
        XCTAssertTrue(vouched(base, try VaultPatch.ensureAccount(named: "Axis Bank", ownerName: "Asha Rao", in: base, now: now).vault))
        XCTAssertTrue(vouched(base, VaultPatch.setHints([SetupHint(name: "Asha", kind: .member)], in: base, now: now)), "hints")
        let held = VaultPatch.setHints([SetupHint(name: "Asha", kind: .member)], in: base, now: now)
        XCTAssertTrue(vouched(held, VaultPatch.setHints([], in: held, now: now.addingTimeInterval(60))), "hints cleared")
        XCTAssertTrue(vouched(base, VaultPatch.setToFillIn([CommitmentPlaceholder(name: "Rent", group: "Named", tag: "")], in: base, now: now)), "to fill in")
        XCTAssertTrue(vouched(base, try VaultPatch.setCommitmentPhoto(id: "a", photo: "images/a.jpg", in: base, now: now)), "a commitment photo")
        let tagged = VaultPatch.ensureTag(kind: "commitment", named: "Streaming", in: base, now: now)
        XCTAssertTrue(vouched(base, tagged), "a tag alone")
        XCTAssertTrue(vouched(tagged, try VaultPatch.setTagPhoto(kind: "commitment", named: "Streaming", photo: "images/s.jpg", in: tagged, now: now.addingTimeInterval(60))), "a tag photo")
        var unsigned = tagged
        unsigned["_provenance"] = [String: Any]()
        XCTAssertFalse(vouched(base, unsigned), "an unsigned tag alone is still not the owner's")
    }
}
