// The owner's own write made while a review is open must not join it: what the write
// changed is carried onto the review's base, so Changes holds only the outside edit and
// Undo keeps the owner's rows.
import Foundation

public enum ReviewBase {
    /// `base` with every row, provenance entry and top-level value that `before` → `after`
    /// added, changed or removed set as `after` holds it. Rows are matched as the review
    /// diffs them: by id, a tag by kind and name_key without one, a charge by commitment and day.
    public static func carry(from before: [String: Any], to after: [String: Any],
                             onto base: [String: Any]) -> [String: Any] {
        var out = base
        for key in Set(before.keys).union(after.keys) {
            let row: (([String: Any]) -> String?)?
            switch key {
            case "commitments", "accounts", "members": row = { $0["id"] as? String }
            case "tags": row = tagKey
            case "charges": row = chargeKey
            case "_provenance":
                if let entries = carryEntries(before[key], after[key], onto: base[key]) { out[key] = entries }
                continue
            default:
                if !same(before[key], after[key]) { out[key] = after[key] }
                continue
            }
            if let row, let rows = carryRows(before[key], after[key], onto: base[key], key: row) { out[key] = rows }
        }
        return out
    }

    private static func tagKey(_ row: [String: Any]) -> String? {
        if let id = row["id"] as? String { return id }
        guard let kind = row["kind"] as? String, let key = row["name_key"] as? String else { return nil }
        return "\(kind)/\(key)"
    }

    private static func chargeKey(_ row: [String: Any]) -> String? {
        guard let commitment = row["commitment_id"] as? String, let date = row["date"] as? String else { return nil }
        return "\(commitment)@\(date)"
    }

    private static func same(_ a: Any?, _ b: Any?) -> Bool {
        switch (a, b) {
        case (nil, nil): true
        case let (a?, b?): (a as AnyObject).isEqual(b)
        default: false
        }
    }

    private static func keyed(_ rows: [[String: Any]], _ key: ([String: Any]) -> String?) -> [String: [String: Any]] {
        Dictionary(rows.compactMap { row in key(row).map { ($0, row) } }, uniquingKeysWith: { first, _ in first })
    }

    /// The base's rows with the touched ones replaced in place or dropped, and the ones the
    /// write added after them. Nil when the write touched no row of the kind.
    private static func carryRows(_ before: Any?, _ after: Any?, onto base: Any?,
                                  key: ([String: Any]) -> String?) -> [[String: Any]]? {
        let afterRows = after as? [[String: Any]] ?? []
        let was = keyed(before as? [[String: Any]] ?? [], key)
        let now = keyed(afterRows, key)
        var touched = Set(now.keys.filter { !same(was[$0], now[$0]) })
        touched.formUnion(was.keys.filter { now[$0] == nil })
        guard !touched.isEmpty else { return nil }
        var placed = Set<String>()
        var out: [[String: Any]] = []
        for row in base as? [[String: Any]] ?? [] {
            guard let id = key(row), touched.contains(id) else { out.append(row); continue }
            if let new = now[id], placed.insert(id).inserted { out.append(new) }
        }
        for row in afterRows {
            if let id = key(row), touched.contains(id), placed.insert(id).inserted { out.append(row) }
        }
        return out
    }

    /// The provenance entries the write set or removed, carried the same way.
    private static func carryEntries(_ before: Any?, _ after: Any?, onto base: Any?) -> [String: Any]? {
        let was = before as? [String: Any] ?? [:]
        let now = after as? [String: Any] ?? [:]
        let touched = Set(was.keys).union(now.keys).filter { !same(was[$0], now[$0]) }
        guard !touched.isEmpty else { return nil }
        var out = base as? [String: Any] ?? [:]
        for id in touched { out[id] = now[id] }
        return out
    }
}
