// The indexed reads answer exactly as the vault scans do, and stay quick at a
// thousand commitments and fifteen hundred charges.
import XCTest
@testable import LongbookCore

final class ChargeIndexTests: XCTestCase {
    private let today = LB.parseDate("2026-10-30")!

    /// Seven hundred one-time rows and three hundred monthly plans, as a year's statements make.
    static func scaleVault(today: Date) -> Vault {
        var subs: [Subscription] = []
        var rows: [ChargeRow] = []
        for i in 0..<700 {
            let id = "once-\(i)"
            let day = LB.toISO(LB.addDays(today, -(i % 365)))
            subs.append(Fx.sub(id: id, name: "Shop \(i)", amount: Double(100 + i), cycle: .once, tag: "shopping"))
            rows.append(Fx.row(id, day, amount: Double(100 + i), paid: true, basis: "statement", note: "Statement line: \(day) SHOP \(i)"))
        }
        for i in 0..<300 {
            let id = "plan-\(i)"
            subs.append(Fx.sub(id: id, name: "Plan \(i)", amount: Double(50 + i), cycle: .monthly, tag: "home"))
            for k in 0..<(i % 3 + 2) {
                let day = LB.toISO(LB.addMonths(LB.addDays(today, -(i % 28)), k - 1))
                rows.append(Fx.row(id, day, amount: Double(50 + i), paid: k == 0, basis: k == 0 ? "statement" : "plan"))
            }
        }
        return Fx.vault(subs, rows)
    }

    private func timed(_ label: String, _ work: () -> Void) -> Double {
        let start = CFAbsoluteTimeGetCurrent()
        work()
        let ms = (CFAbsoluteTimeGetCurrent() - start) * 1000
        print("TIMING \(label): \(Int(ms)) ms")
        return ms
    }

    func testTheIndexAnswersAsTheVaultScansDo() {
        let vault = Self.scaleVault(today: today)
        let index = ChargeIndex(vault, today: today)
        XCTAssertEqual(vault.subscriptions.count, 1000)
        XCTAssertGreaterThanOrEqual(vault.charges.count, 1500)
        for sub in vault.subscriptions.prefix(50) {
            XCTAssertEqual(index.charges(of: sub).map(\.row.date), charges(of: sub, in: vault, today).map(\.row.date))
            XCTAssertEqual(index.isLiveCommitment(sub), isLiveCommitment(sub, in: vault, today))
            XCTAssertEqual(index.plannedThrough(sub), plannedThrough(sub, in: vault))
        }
        XCTAssertEqual(index.nextCharges(vault).map(\.id), nextCharges(vault, today).map(\.id))
        XCTAssertEqual(index.nextDueDay(vault)?.date, nextDueDay(vault, today)?.date)
        XCTAssertEqual(index.nextDueDay(vault)?.charges.map(\.id), nextDueDay(vault, today)?.charges.map(\.id))
    }

    func testTheIndexedReadsStayQuickAtScale() {
        let vault = Self.scaleVault(today: today)
        let scanned = timed("vault scans: live + next charges + next due day") {
            _ = liveCommitments(vault, today)
            _ = nextCharges(vault, today)
            _ = nextDueDay(vault, today)
            _ = vault.subscriptions.map { plannedThrough($0, in: vault) }
        }
        let indexed = timed("charge index: build + the same reads") {
            let index = ChargeIndex(vault, today: today)
            _ = vault.subscriptions.filter { index.isLiveCommitment($0) }
            _ = index.nextCharges(vault)
            _ = index.nextDueDay(vault)
            _ = vault.subscriptions.map { index.plannedThrough($0) }
        }
        XCTAssertLessThan(indexed, max(scanned, 50), "the index must never cost more than the scans it replaces")
    }
}
