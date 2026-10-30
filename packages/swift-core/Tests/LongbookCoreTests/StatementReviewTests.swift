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
        return StatementImport.Review(members: ["Anil", "Meera"], accounts: ["Axis card 4402"], files: [file], currency: "INR",
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
        for name in review.accounts { try commit { try VaultPatch.ensureEntity(.paymentMethod, named: name, in: $0, now: self.now).vault } }
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
