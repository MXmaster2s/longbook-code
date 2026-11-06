// Identity ranks — the DECISION half of the colour seam, ported from
// packages/core/src/domain/avatar.ts. Colour is a key: two entities may never wear one
// hue. Every entity is ranked in ONE vault-wide ordering, which picks the ink. This
// file owns the ordering; Theme.swift owns what a rank looks like.
import Foundation

/// Normalise a free-text key the way core's `nameKey` does — trim, lowercase, collapse runs of
/// whitespace — so "AI  Subscription" and "ai subscription" rank as one category.
public func nameKey(_ s: String?) -> String {
    let trimmed = (s ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return trimmed.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
}

/// Ranks for one kind of entity across a whole vault. Build once per load and share it; building
/// scans every entity to fix the ordering.
public struct Palette {
    private let ranks: [String: Int]
    private let normalise: (String) -> String

    fileprivate init(order: [String], normalise: @escaping (String) -> String) {
        var r: [String: Int] = [:]
        for key in order where r[key] == nil { r[key] = r.count }
        self.ranks = r
        self.normalise = normalise
    }

    /// The 0-based rank of a key, or nil for a blank/unranked key — an absence wears no hue, which
    /// the theme resolves to its neutral, same as a rank past the end of the ramp.
    public func rank(_ key: String?) -> Int? {
        guard let key, !key.isEmpty else { return nil }
        return ranks[normalise(key)]
    }
}

public enum VaultPalette {
    /// Categories are free text with no row or timestamp, so order is alphabetical over
    /// the normalised name. Comparison by UTF-16 code unit, not locale, matching core's
    /// `a < b` over code units rather than `localeCompare`.
    public static func categories(_ subs: [Subscription]) -> Palette {
        var seen = Set<String>()
        var order: [String] = []
        for sub in subs {
            let key = nameKey(sub.tag)
            if !key.isEmpty, !seen.contains(key) { seen.insert(key); order.append(key) }
        }
        order.sort(by: codeUnitLess)
        return Palette(order: order, normalise: nameKey)
    }

    /// Members and payment methods are real rows, so the vault orders them by when they were added,
    /// tie-broken by id. Keyed by id, not name, so renaming someone leaves the household's colours
    /// alone. A missing/unparseable timestamp sorts as epoch 0, matching core's `NaN → 0`.
    public static func entities(_ rows: [(id: String, createdAt: String?)]) -> Palette {
        let ordered = rows.sorted { a, b in
            let ta = epochMillis(a.createdAt), tb = epochMillis(b.createdAt)
            return ta != tb ? ta < tb : codeUnitLess(a.id, b.id)
        }
        return Palette(order: ordered.map(\.id), normalise: { $0 })
    }

    /// The same, with the rows something uses ranked ahead of the rest, each half by when it
    /// was added. A vault can hold more accounts than the ramp has inks; the ones its
    /// commitments use keep a colour, and an unused one is the first to fold to the neutral.
    public static func entities(_ rows: [(id: String, createdAt: String?)], inUse: Set<String>) -> Palette {
        let ordered = rows.sorted { a, b in
            let ua = inUse.contains(a.id), ub = inUse.contains(b.id)
            if ua != ub { return ua }
            let ta = epochMillis(a.createdAt), tb = epochMillis(b.createdAt)
            return ta != tb ? ta < tb : codeUnitLess(a.id, b.id)
        }
        return Palette(order: ordered.map(\.id), normalise: { $0 })
    }
}

/// Lexicographic compare over UTF-16 code units — the exact ordering core uses, so a category that
/// sorts one way on the desktop can't sort the other way here and hand the two apps different rings.
private func codeUnitLess(_ a: String, _ b: String) -> Bool {
    let x = Array(a.utf16), y = Array(b.utf16)
    for i in 0..<min(x.count, y.count) where x[i] != y[i] { return x[i] < y[i] }
    return x.count < y.count
}

/// Parse an ISO-8601 timestamp (a full `created_at`, with time) to milliseconds since the epoch.
/// Unparseable → 0, matching core's `Number.isNaN(t) ? 0`.
private func epochMillis(_ iso: String?) -> Double {
    guard let iso, !iso.isEmpty else { return 0 }
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let d = f.date(from: iso) { return d.timeIntervalSince1970 * 1000 }
    f.formatOptions = [.withInternetDateTime]
    if let d = f.date(from: iso) { return d.timeIntervalSince1970 * 1000 }
    return 0
}

/// A category as a screen shows it: the first letter up, the rest exactly as written, and the
/// few that are initials in full.
public func categoryWord(_ name: String) -> String {
    let initials: Set<String> = ["ai", "upi", "emi", "sip", "atm", "ppf", "nps", "fd", "rd"]
    let key = name.trimmingCharacters(in: .whitespaces).lowercased()
    if initials.contains(key) { return key.uppercased() }
    return name.prefix(1).uppercased() + name.dropFirst()
}
