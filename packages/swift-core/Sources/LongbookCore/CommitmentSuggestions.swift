// What people pay for again and again, grouped the way a person says it, for setup's one
// question: "what commitments do you have?" A group carries the library tag its
// commitments wear; the words are the picker's, the tag is the file's.
import Foundation

/// A commitment named at setup and not yet filled in. Lives in the vault as `to_fill_in`,
/// so every door sees what is waiting.
public struct CommitmentPlaceholder: Identifiable, Equatable, Sendable, Codable {
    public let id: String
    public let name: String
    public let group: String
    public let tag: String

    public init(id: String = UUID().uuidString.lowercased(), name: String, group: String, tag: String) {
        self.id = id
        self.name = name
        self.group = group
        self.tag = tag
    }

    enum CodingKeys: String, CodingKey { case id, name, group, tag }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        group = try c.decodeIfPresent(String.self, forKey: .group) ?? ""
        tag = try c.decodeIfPresent(String.self, forKey: .tag) ?? ""
    }

    init?(raw: [String: String]) {
        guard let id = raw["id"], let name = raw["name"], !name.isEmpty else { return nil }
        self.init(id: id, name: name, group: raw["group"] ?? "", tag: raw["tag"] ?? "")
    }

    var raw: [String: String] { ["id": id, "name": name, "group": group, "tag": tag] }
}

/// A person or an account picked at setup, by role or kind — "Cook", "Savings account" —
/// kept in the vault as `hints` for reading statements. Never a member or an account: one
/// becomes real only when a statement or the owner names it.
public struct SetupHint: Identifiable, Equatable, Sendable, Codable {
    public enum Kind: String, Codable, Sendable { case member, account }

    public let id: String
    public let name: String
    public let kind: Kind
    /// The tag the person or account would wear: a role, or an account type.
    public let tag: String?

    public init(id: String = UUID().uuidString.lowercased(), name: String, kind: Kind, tag: String? = nil) {
        self.id = id
        self.name = name
        self.kind = kind
        self.tag = tag
    }

    enum CodingKeys: String, CodingKey { case id, name, kind, tag }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw DecodingError.dataCorruptedError(forKey: .name, in: c, debugDescription: "a hint has a name")
        }
        kind = try c.decode(Kind.self, forKey: .kind)
        tag = try c.decodeIfPresent(String.self, forKey: .tag).flatMap { $0.isEmpty ? nil : $0 }
    }

    var raw: [String: Any] {
        var out: [String: Any] = ["id": id, "name": name, "kind": kind.rawValue]
        if let tag, !tag.isEmpty { out["tag"] = tag }
        return out
    }
}

public enum CommitmentSuggestions {
    public struct Group: Identifiable, Equatable, Sendable {
        public let name: String
        public let tag: String
        public let suggestions: [String]
        public var id: String { name }
    }

    /// In the order the money matters to most households here.
    public static let groups: [Group] = [
        Group(name: "Rent", tag: "rent", suggestions: ["Home rent", "Car parking rent", "Shop or office rent"]),
        Group(name: "Household help", tag: "salary", suggestions: ["Maid salary", "Cook salary", "Nanny salary", "Driver salary", "Car washer salary", "Gardener salary"]),
        Group(name: "Loans & EMIs", tag: "emi", suggestions: ["Home loan EMI", "Car loan EMI", "Personal loan EMI", "Phone or laptop EMI", "Education loan EMI"]),
        Group(name: "Health insurance", tag: "insurance", suggestions: ["Self health insurance", "Family health insurance", "Wife health insurance", "Husband health insurance", "Parents' health insurance", "Critical illness insurance"]),
        Group(name: "Life insurance", tag: "insurance", suggestions: ["Self term insurance", "Wife term insurance", "Husband term insurance", "LIC policy"]),
        Group(name: "Vehicle", tag: "vehicle", suggestions: ["Car insurance", "Bike insurance", "Roadside assistance", "Car service plan", "FASTag top-up"]),
        Group(name: "Phone & internet", tag: "telecom", suggestions: ["Home internet", "Self phone recharge", "Wife phone recharge", "Husband phone recharge", "DTH or cable TV"]),
        Group(name: "Society & utilities", tag: "utility", suggestions: ["Society maintenance", "Electricity", "Piped gas", "Water", "Gas cylinder"]),
        Group(name: "Streaming", tag: "streaming", suggestions: ["Netflix", "Amazon Prime", "JioHotstar", "Apple TV+", "Spotify", "YouTube Premium", "Lionsgate Play"]),
        Group(name: "Cloud storage", tag: "software", suggestions: ["Apple One", "iCloud+", "Google One", "Dropbox"]),
        Group(name: "AI", tag: "ai", suggestions: ["Claude", "ChatGPT", "Gemini", "Perplexity"]),
        Group(name: "Software", tag: "software", suggestions: ["Canva", "Notion", "Adobe Creative Cloud", "Microsoft 365"]),
        Group(name: "Work & business", tag: "domain & hosting", suggestions: ["Google Workspace", "Apple Developer fees", "Domain renewal", "Web hosting", "Accountant fees"]),
        Group(name: "Social & professional", tag: "social media", suggestions: ["LinkedIn Premium", "Instagram Premium", "X Premium", "Telegram Premium"]),
        Group(name: "Health & fitness", tag: "health & fitness", suggestions: ["Gym membership", "Apple Fitness+", "Yearly health checkup", "Yoga or sports classes"]),
        Group(name: "School & learning", tag: "education", suggestions: ["School fees", "Tuition fees", "College fees", "Online course"]),
    ]

    /// Where the money sits, grouped by kind; the names are the banks and apps people
    /// here use. The tag is the library's account tag, so each lands with its kind set.
    public static let accountGroups: [Group] = [
        Group(name: "Savings account", tag: "bank account", suggestions: ["HDFC savings", "ICICI savings", "Axis savings", "Kotak savings", "SBI savings", "IDFC First savings"]),
        Group(name: "Current account", tag: "bank account", suggestions: ["HDFC current", "ICICI current", "Axis current", "Kotak current", "SBI current"]),
        Group(name: "Credit card", tag: "credit card", suggestions: ["HDFC credit card", "ICICI credit card", "Axis credit card", "SBI credit card", "Amex", "OneCard"]),
        Group(name: "UPI", tag: "upi", suggestions: ["Google Pay", "PhonePe", "Paytm", "BHIM", "CRED UPI"]),
        Group(name: "Wallets & cash", tag: "wallet", suggestions: ["Apple Pay", "Paytm wallet", "Amazon Pay", "Cash"]),
    ]

    /// Who the money is for. One group, so the list stands open.
    public static let memberGroups: [Group] = [
        Group(name: "People", tag: "member", suggestions: ["Self", "Wife", "Husband", "Mother", "Father", "Brother", "Sister", "Son", "Daughter", "Friend", "Employee"]),
    ]

    /// A typed name placed in a group, as a placeholder.
    public static func placeholder(_ name: String, in group: Group) -> CommitmentPlaceholder? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return CommitmentPlaceholder(name: trimmed, group: group.name, tag: group.tag)
    }
}
