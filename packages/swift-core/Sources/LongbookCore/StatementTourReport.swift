// What the walk through an import's cards reports when it ends: counts and fixed words, never
// a name, an amount, a person or an account. Pure, so the payload is proved without a screen.
import Foundation

extension StatementTour {
    /// How the walk ended: through its last screen, left early with Skip, or taken back whole.
    public enum Ending: String, Sendable {
        case done, skipped, undone
    }

    /// The event's properties: cards found and removed per kind, and for each removed commitment
    /// its cycle, how many statement lines showed it, whether it was a guess and its category
    /// when longbook ships it, else "other". Alike commitments are counted together.
    public static func endProperties(_ ending: Ending, found: Findings, removed: [Kind: Set<String>], vault: [String: Any]) -> [String: Any] {
        var props: [String: Any] = ["ending": ending.rawValue]
        for kind in Kind.allCases {
            let cards = found.cards(kind)
            props[kind.countWord + "_found"] = cards.count
            props[kind.countWord + "_removed"] = (removed[kind] ?? []).intersection(cards.map(\.id)).count
        }
        props["removed_commitments"] = removedCommitments(removed[.commitment] ?? [], in: found, vault: vault)
        return props
    }

    private struct Sort: Hashable {
        let cycle: String
        let sightings: String
        let guessed: Bool
        let category: String
    }

    /// The event for an imported commitment deleted later: how many, and the same grouping. A
    /// commitment is imported when a statement backed one of its rows, and deleted when it is gone
    /// or its last row is. Nil when this delete took none.
    public static func deletedProperties(before: [String: Any], after: [String: Any], bulk: Bool) -> [String: Any]? {
        var imported = Set<String>()
        for row in VaultPatch.chargeRows(before) where (row["basis"] as? String) == "statement" {
            if let id = row["commitment_id"] as? String { imported.insert(id) }
        }
        guard !imported.isEmpty else { return nil }
        let left = Set((after["commitments"] as? [[String: Any]] ?? []).compactMap { $0["id"] as? String })
        let rowsLeft = Set(VaultPatch.chargeRows(after).compactMap { $0["commitment_id"] as? String })
        let deleted = imported.filter { !left.contains($0) || !rowsLeft.contains($0) }
        guard !deleted.isEmpty else { return nil }
        return ["commitments": deleted.count, "bulk": bulk, "removed_commitments": sorts(of: deleted, vault: before)]
    }

    private static func removedCommitments(_ ids: Set<String>, in found: Findings, vault: [String: Any]) -> [[String: Any]] {
        sorts(of: ids.intersection(found.commitments.map(\.id)), vault: vault)
    }

    private static func sorts(of taken: Set<String>, vault: [String: Any]) -> [[String: Any]] {
        guard !taken.isEmpty else { return [] }
        var lines: [String: Int] = [:]
        for row in VaultPatch.chargeRows(vault) where (row["basis"] as? String) == "statement" {
            if let id = row["commitment_id"] as? String { lines[id, default: 0] += 1 }
        }
        var counts: [Sort: Int] = [:]
        for row in vault["commitments"] as? [[String: Any]] ?? [] {
            guard let id = row["id"] as? String, taken.contains(id) else { continue }
            let seen = lines[id] ?? 0
            let key = Sort(
                cycle: BillingCycle(rawValue: row["billing_cycle"] as? String ?? "")?.rawValue ?? "other",
                sightings: seen >= 3 ? "3+" : String(seen),
                guessed: (row["name"] as? String)?.hasSuffix(StatementNaming.guessedMark) ?? false,
                category: shippedCategory(row["tag"] as? String))
            counts[key, default: 0] += 1
        }
        return counts.sorted { ($0.key.cycle, $0.key.sightings, $0.key.category, $0.key.guessed ? 1 : 0) < ($1.key.cycle, $1.key.sightings, $1.key.category, $1.key.guessed ? 1 : 0) }
            .map { ["cycle": $0.key.cycle, "sightings": $0.key.sightings, "guessed": $0.key.guessed, "category": $0.key.category, "count": $0.value] }
    }

    /// A category the owner wrote is theirs and not sent; only a name from longbook's own list is.
    private static func shippedCategory(_ tag: String?) -> String {
        let name = (tag ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { return "none" }
        return TagLibrary.entry(kind: "commitment", name: name)?.name ?? "other"
    }
}

private extension StatementTour.Kind {
    var countWord: String {
        switch self {
        case .charge: "charges"
        case .people: "people"
        case .account: "accounts"
        case .commitment: "commitments"
        case .transfer: "transfers"
        case .earning: "earnings"
        }
    }
}
