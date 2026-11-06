// Builders every ledger test shares. Rows and commitments are built through the decoder
// where a test also wants the Codable mapping exercised; the memberwise inits elsewhere.
// Every fixture is SYNTHETIC; this repo is public.
import Foundation
@testable import LongbookCore

enum Fx {
    static func sub(
        id: String = "x", name: String = "X", amount: Double = 100, currency: String = "INR",
        cycle: BillingCycle = .monthly, customDays: Int? = nil, status: SubStatus = .active,
        endsOn: String? = nil, tag: String? = nil, memberId: String? = nil, methodId: String? = nil
    ) -> Subscription {
        Subscription(id: id, name: name, amount: amount, currency: currency,
                     billingCycle: cycle, customCycleDays: customDays, tag: tag,
                     familyMemberId: memberId, paymentMethodId: methodId,
                     status: status, scheduledCancelDate: endsOn)
    }

    static func row(
        _ commitmentId: String, _ date: String, amount: Double = 100, paid: Bool = false,
        basis: String? = "plan", currency: String? = nil, paidOn: String? = nil, note: String? = nil
    ) -> ChargeRow {
        ChargeRow(commitmentId: commitmentId, date: date, amount: amount, currency: currency,
                  paid: paid, paidOn: paidOn, basis: basis, note: note, writtenAt: "2026-01-01T00:00:00Z")
    }

    static func vault(_ subs: [Subscription], _ charges: [ChargeRow] = []) -> Vault {
        Vault(app: "longbook", subscriptions: subs, charges: charges)
    }

    /// A monthly run of rows on one day-of-month, first through last inclusive.
    static func monthly(_ id: String, from first: String, months: Int, amount: Double = 100,
                        paidThrough: String? = nil) -> [ChargeRow] {
        guard let start = LB.parseDate(first) else { return [] }
        return (0..<months).map { k in
            let date = LB.toISO(LB.addMonths(start, k))
            let paid = paidThrough.map { date <= $0 } ?? false
            return row(id, date, amount: amount, paid: paid, basis: paid ? "statement" : "plan")
        }
    }

    /// The raw dictionary a writer test starts from.
    static func raw(_ subs: [[String: Any]], charges: [[String: Any]] = []) -> [String: Any] {
        var out: [String: Any] = ["app": "longbook", "version": 3, "commitments": subs]
        if !charges.isEmpty { out["charges"] = charges }
        return out
    }

    static func rawSub(id: String, name: String = "X", amount: Double = 100, currency: String = "INR",
                       cycle: String = "monthly", status: String = "active") -> [String: Any] {
        ["id": id, "name": name, "amount": amount, "currency": currency, "billing_cycle": cycle, "status": status]
    }

    static func rawRow(_ id: String, _ date: String, amount: Double = 100, paid: Bool = false, basis: String = "plan") -> [String: Any] {
        ["commitment_id": id, "date": date, "amount": amount, "paid": paid, "basis": basis]
    }

    static func rows(_ raw: [String: Any], of id: String) -> [[String: Any]] {
        (raw["charges"] as? [[String: Any]] ?? []).filter { $0["commitment_id"] as? String == id }
            .sorted { ($0["date"] as? String ?? "") < ($1["date"] as? String ?? "") }
    }
}

/// The fixtures directory is shared across both language suites, one level up from each
/// package — resolved from this file's own path so it works regardless of the working directory.
func sharedFixturesDirectory(from filePath: String) -> URL {
    URL(fileURLWithPath: filePath)
        .deletingLastPathComponent() // .../LongbookCoreTests/
        .deletingLastPathComponent() // .../Tests/
        .deletingLastPathComponent() // .../swift-core/
        .deletingLastPathComponent() // .../packages/
        .appendingPathComponent("core/tests/fixtures")
}
