// The owner's tag over their categories — "business", "household" — read from the vault's
// groups array. A tag is a label above category, which is why totals can be grouped by it
// without any category losing its own identity.
import Foundation

public struct CategoryTags {
    /// category name_key → the tag's name, in the owner's words.
    private let byCategory: [String: String]
    /// Tag names in the order the file lists them, so a report doesn't reshuffle month to month.
    public let order: [String]

    public init(_ groups: [VaultGroup]?) {
        var map: [String: String] = [:]
        var seen: [String] = []
        let tags = (groups ?? [])
            .filter { $0.kind == "tag" }
            .sorted { ($0.sort ?? Int.max, $0.name) < ($1.sort ?? Int.max, $1.name) }
        for tag in tags {
            let keys = (tag.tagKeys ?? []).map { nameKey($0) }.filter { !$0.isEmpty }
            guard !keys.isEmpty else { continue }
            if !seen.contains(tag.name) { seen.append(tag.name) }
            for key in keys where map[key] == nil {
                // First tag wins: the contract says a category wears at most one, and
                // silently reassigning it would move money between totals.
                map[key] = tag.name
            }
        }
        byCategory = map
        order = seen
    }

    public var isEmpty: Bool { byCategory.isEmpty }

    /// Nil means untagged, which is a real answer — never a bucket called "other".
    public func tag(for category: String?) -> String? {
        let key = nameKey(category)
        return key.isEmpty ? nil : byCategory[key]
    }
}
