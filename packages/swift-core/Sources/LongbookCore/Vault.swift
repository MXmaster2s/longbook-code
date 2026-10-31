// Vault.swift — the longbook vault, decoded from the shared iCloud JSON. Mirrors
// longbook.schema.json (format 3); REQUIRED fields are non-optional, rest optional so
// sparse vaults still decode. The READ model, NOT the write path — that patches RAW
// JSON. Property names lag the file's nouns where a rename would churn every view.

import Foundation

public enum BillingCycle: String, Codable {
    case monthly, yearly, custom, once
}

public enum SubStatus: String, Codable {
    case active, paused, cancelled
}

/// A details value: scalar or a flat list of scalars — never nested objects.
public enum DetailValue: Codable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case null
    case list([DetailValue])

    public init(from decoder: Decoder) throws {
        let single = try decoder.singleValueContainer()
        if single.decodeNil() { self = .null }
        else if let b = try? single.decode(Bool.self) { self = .bool(b) }
        else if let n = try? single.decode(Double.self) { self = .number(n) }
        else if let s = try? single.decode(String.self) { self = .string(s) }
        else if let l = try? single.decode([DetailValue].self) { self = .list(l) }
        else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath, debugDescription: "unsupported details value"
            ))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var single = encoder.singleValueContainer()
        switch self {
        case .string(let s): try single.encode(s)
        case .number(let n): try single.encode(n)
        case .bool(let b): try single.encode(b)
        case .null: try single.encodeNil()
        case .list(let l): try single.encode(l)
        }
    }

    /// The value as words, for a detail row — a whole number as its digits, never ".0" or an
    /// exponent, as the secret scan reads it; lists join.
    public var display: String {
        switch self {
        case .string(let s): return s
        case .number(let n):
            return n == n.rounded() && abs(n) < 9e18
                ? String(Int64(n)) : String(n)
        case .bool(let b): return b ? "yes" : "no"
        case .null: return ""
        case .list(let l): return l.map(\.display).joined(separator: ", ")
        }
    }
}

public typealias Details = [String: DetailValue]

/// A detail key as a note's label: its words, the first capitalised — policy_type is "Policy
/// type". A key the guide or the old templates name in other words takes theirs: policy_doc is
/// "Document", tenure_months "Tenure (months)".
public func detailLabel(_ key: String) -> String {
    let named = [
        "policy_doc": "Document", "lease_start": "Lease starts", "lease_end": "Lease ends",
        "coverage_end": "Coverage ends", "trip_start": "Trip starts", "trip_end": "Trip ends",
        "connection_ref": "Connection", "tenure_months": "Tenure (months)",
    ]
    if let label = named[key] { return label }
    let words = key.split(separator: "_").joined(separator: " ").trimmingCharacters(in: .whitespaces)
    guard let first = words.first else { return "" }
    return "\(first.uppercased())\(words.dropFirst())"
}

/// Details longbook keeps for itself: the statement's line, and the id behind an account's
/// name. Neither reads as a line of a note.
public let ownDetailKeys: Set<String> = ["statement_line", "counterpart_account", "counterpart_account_id", "counterpart_owner", "line_direction"]

/// A commitment's details as lines of a note, "Label: value", in key order. longbook's own
/// keys are never one; a detail with no words is none either.
public func detailLines(_ details: Details?) -> [String] {
    (details ?? [:]).keys.sorted().compactMap { key in
        guard !ownDetailKeys.contains(key) else { return nil }
        let label = detailLabel(key)
        let value = (details?[key]?.display ?? "").components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: " ")
        return label.isEmpty || value.isEmpty ? nil : "\(label): \(value)"
    }
}

/// The detail lines the notes do not already carry: a detail whose label a line of the notes
/// wears before its colon, in any case or spacing, is the notes' to say.
public func detailLines(_ details: Details?, besides notes: String?) -> [String] {
    func label(_ line: Substring) -> String? {
        guard let colon = line.firstIndex(of: ":") else { return nil }
        return line[..<colon].split(whereSeparator: \.isWhitespace).joined(separator: " ").lowercased()
    }
    let carried = Set((notes ?? "").split(whereSeparator: \.isNewline).compactMap(label))
    return detailLines(details).filter { line in label(Substring(line)).map { !carried.contains($0) } ?? true }
}

/// A line of a note as the folds compare it: lowercased, its spaces collapsed, none either side
/// of its first colon — "card  NAME :Platinum Reserve" says what "Card name: Platinum Reserve"
/// says, its label and its value alike.
public func noteLineKey<Line: StringProtocol>(_ line: Line) -> String {
    let words = line.split(whereSeparator: \.isWhitespace).joined(separator: " ").lowercased()
    guard let colon = words.firstIndex(of: ":") else { return words }
    let label = words[..<colon].trimmingCharacters(in: .whitespaces)
    let value = words[words.index(after: colon)...].trimmingCharacters(in: .whitespaces)
    return "\(label):\(value)"
}

/// The line a card name the details hold reads as in the notes, "Card name: Platinum Reserve";
/// nil when they hold none, or one with no words.
public func cardNameLine(_ details: Details?) -> String? {
    details?[PaymentMethod.cardNameKey].flatMap { detailLines([PaymentMethod.cardNameKey: $0]).first }
}

/// An account's notes as Edit Account opens them: its notes, then the card name its details
/// hold as its line, unless the notes hold that line by `noteLineKey` — a line naming another
/// card never hides it. Blank notes are none; nil when there is nothing to show.
public func notesFoldingCardName(_ notes: String?, details: Details?) -> String? {
    let held = notes?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? notes : nil
    guard let line = cardNameLine(details) else { return held }
    let key = noteLineKey(line)
    guard !(held ?? "").split(whereSeparator: \.isNewline).contains(where: { noteLineKey($0) == key }) else { return held }
    var kept = held ?? ""
    while kept.last?.isWhitespace == true { kept.removeLast() }
    return kept.isEmpty ? line : "\(kept)\n\(line)"
}

/// A commitment's attributes — what every charge of it shares. Nothing about an
/// occurrence lives here: its dates, its amounts and whether it was paid are rows in
/// `charges[]`. `amount` is the price now, what a newly planned charge is written at.
public struct Subscription: Codable, Identifiable {
    public let id: String
    public var name: String
    public var amount: Double
    public var currency: String
    public var billingCycle: BillingCycle
    public var customCycleDays: Int?
    public var tag: String?                 // a name from tags[] (kind "commitment"), or a new one
    public var details: Details?
    public var notes: String?
    public var familyMemberId: String?      // file key member_id — FK → FamilyMember.id
    public var paymentMethodId: String?     // file key account_id — FK → PaymentMethod.id
    public var status: SubStatus
    public var scheduledCancelDate: String? // file key ends_on — nothing is planned past it
    /// "in" for money that arrives — salary, a refund, interest. "transfer" for a movement
    /// between the owner's own accounts they still want to see. Absent or "out" is a charge,
    /// and only a charge is ever summed as spending.
    public var direction: String?
    /// True while the owner marks it a free trial: a pill on the commitment, nothing about
    /// its charges. Absent is false.
    public var freeTrial: Bool?
    public var photo: String?               // its picture: a file under the folder's images/, written by the Mac app
    public var createdAt: String?
    public var updatedAt: String?

    public var isIncome: Bool { direction == "in" }
    /// A card bill, a standing move to savings: shown and owed, in no total at all.
    public var isTransfer: Bool { direction == "transfer" }

    enum CodingKeys: String, CodingKey {
        case id, name, amount, currency
        case billingCycle = "billing_cycle"
        case customCycleDays = "custom_cycle_days"
        case tag, details, notes
        case familyMemberId = "member_id"
        case paymentMethodId = "account_id"
        case status, direction, photo
        case scheduledCancelDate = "ends_on"
        case freeTrial = "free_trial"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    public init(
        id: String, name: String, amount: Double, currency: String,
        billingCycle: BillingCycle, customCycleDays: Int? = nil,
        tag: String? = nil, notes: String? = nil, familyMemberId: String? = nil,
        paymentMethodId: String? = nil, status: SubStatus, scheduledCancelDate: String? = nil,
        createdAt: String? = nil, updatedAt: String? = nil,
        details: Details? = nil, direction: String? = nil, freeTrial: Bool? = nil
    ) {
        self.id = id
        self.name = name
        self.amount = amount
        self.currency = currency
        self.billingCycle = billingCycle
        self.customCycleDays = customCycleDays
        self.tag = tag
        self.details = details
        self.notes = notes
        self.familyMemberId = familyMemberId
        self.paymentMethodId = paymentMethodId
        self.status = status
        self.scheduledCancelDate = scheduledCancelDate
        self.direction = direction
        self.freeTrial = freeTrial
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// Wraps an element so a malformed one decodes to nil instead of failing its whole array.
/// One mistyped field from an outside tool must degrade one entry, never brick the vault.
struct Lossy<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws { value = try? T(from: decoder) }
}

public struct FamilyMember: Codable, Identifiable {
    public let id: String
    public var name: String
    public var nameKey: String
    public var tag: String?                 // a name from tags[] (kind "member"), or a new one
    public var details: Details?
    public var isIncomplete: Bool?
    public var avatarSeed: String?
    public var email: String?               // where a shared report reaches them; never required
    public var photo: String?               // their picture: a file under the folder's people/, written by the app
    /// Starred by the owner: listed first, and kept in the Mac sidebar. Absent reads as not.
    public var starred: Bool?
    public var createdAt: String?

    public var isStarred: Bool { starred == true }

    enum CodingKeys: String, CodingKey {
        case id, name, tag, details, email, photo, starred
        case nameKey = "name_key"
        case isIncomplete = "is_incomplete"
        case avatarSeed = "avatar_seed"
        case createdAt = "created_at"
    }

    public init(
        id: String, name: String, nameKey: String, isIncomplete: Bool? = nil,
        avatarSeed: String? = nil, email: String? = nil, createdAt: String? = nil,
        tag: String? = nil, details: Details? = nil
    ) {
        self.id = id
        self.name = name
        self.nameKey = nameKey
        self.tag = tag
        self.details = details
        self.isIncomplete = isIncomplete
        self.avatarSeed = avatarSeed
        self.email = email
        self.createdAt = createdAt
    }
}

public struct PaymentMethod: Codable, Identifiable {
    public let id: String
    public var name: String
    public var nameKey: String
    public var tag: String?                 // a name from tags[] (kind "account"), or a new one
    public var details: Details?
    public var nickname: String?
    public var institution: String?
    public var last4: String?
    public var isIncomplete: Bool?
    public var familyMemberId: String?      // file key member_id — null for a joint account
    /// The linked account: a card to the bank account that pays it. File key
    /// parent_account_id, FK → PaymentMethod.id; one level only.
    public var parentAccountId: String?
    /// Free text about the account; scanned like every note, never a number or a credential.
    public var notes: String?
    /// What the account held on `balanceDate`, as last said. Informational only.
    public var balance: Double?
    public var balanceDate: String?
    public var photo: String?               // its picture: a file under the folder's images/, written by the Mac app
    /// Starred by the owner: listed first, and kept in the Mac sidebar. Absent reads as not.
    public var starred: Bool?
    public var createdAt: String?

    public var isStarred: Bool { starred == true }

    /// The details key a vault may hold a card's printed name under. Edit Account shows it as a
    /// line of the notes, and its Save takes it out of details.
    public static let cardNameKey = "card_name"

    /// The account this one is linked to, under the name the owner reads.
    public var linkedAccountId: String? { parentAccountId }

    enum CodingKeys: String, CodingKey {
        case id, name, tag, details, nickname, institution, last4, balance, notes, photo, starred
        case nameKey = "name_key"
        case isIncomplete = "is_incomplete"
        case familyMemberId = "member_id"
        case parentAccountId = "parent_account_id"
        case balanceDate = "balance_date"
        case createdAt = "created_at"
    }

    public init(
        id: String, name: String, nameKey: String, isIncomplete: Bool? = nil,
        familyMemberId: String? = nil, parentAccountId: String? = nil, createdAt: String? = nil,
        tag: String? = nil, details: Details? = nil, nickname: String? = nil,
        institution: String? = nil, last4: String? = nil, balance: Double? = nil, balanceDate: String? = nil,
        notes: String? = nil
    ) {
        self.id = id
        self.name = name
        self.nameKey = nameKey
        self.tag = tag
        self.details = details
        self.nickname = nickname
        self.institution = institution
        self.last4 = last4
        self.notes = notes
        self.balance = balance
        self.balanceDate = balanceDate
        self.isIncomplete = isIncomplete
        self.familyMemberId = familyMemberId
        self.parentAccountId = parentAccountId
        self.createdAt = createdAt
    }
}

/// One entry in the vault's tag vocabulary — rows wear the NAME; this carries the icon.
/// Seeded from library.json on first use, extended by the owner or their AI. No tag carries a
/// template: one a vault still holds is never read, and the writer, patching raw JSON, keeps it.
public struct TagDef: Codable, Identifiable {
    public let id: String
    public var kind: String                 // commitment | member | account
    public var name: String
    public var nameKey: String
    public var icon: String?
    public var photo: String?               // its picture: a file under the folder's images/, written by the Mac app
    public var isDefault: Bool?
    public var sort: Int?
    public var createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, kind, name, icon, sort, photo
        case nameKey = "name_key"
        case isDefault = "is_default"
        case createdAt = "created_at"
    }
}

/// One charge — a stored occurrence, past or planned. Keyed by (commitmentId, date);
/// one row per commitment per due date. What is not a row did not happen and is not planned.
public struct ChargeRow: Codable, Equatable {
    public var commitmentId: String       // file key commitment_id
    public var date: String               // ISO YYYY-MM-DD — the due date; with commitmentId, the identity
    public var amount: Double
    public var currency: String?          // only when it differs from the commitment's
    public var paid: Bool
    public var paidOn: String?            // file key paid_on — when the money actually moved
    /// What backs the row: "statement", "user", "mark_paid", or "plan" for one written ahead.
    public var basis: String?
    public var note: String?
    public var writtenAt: String?         // file key written_at — when the row was written

    enum CodingKeys: String, CodingKey {
        case commitmentId = "commitment_id"
        case date, amount, currency, paid, basis, note
        case paidOn = "paid_on"
        case writtenAt = "written_at"
    }

    public init(commitmentId: String, date: String, amount: Double, currency: String? = nil,
                paid: Bool = false, paidOn: String? = nil, basis: String? = nil,
                note: String? = nil, writtenAt: String? = nil) {
        self.commitmentId = commitmentId
        self.date = date
        self.amount = amount
        self.currency = currency
        self.paid = paid
        self.paidOn = paidOn
        self.basis = basis
        self.note = note
        self.writtenAt = writtenAt
    }
}

/// One of the owner's own labels over what already exists. `kind` stays a String: an
/// arrangement this build has never heard of must not fail the whole file.
public struct VaultGroup: Codable {
    public var id: String
    public var kind: String                 // account | member | tag
    public var name: String
    public var nameKey: String?
    public var icon: String?
    public var sort: Int?
    public var accountIds: [String]?
    public var memberIds: [String]?
    /// Normalised tag names, since rows wear a tag by name rather than by id.
    public var tagKeys: [String]?

    enum CodingKeys: String, CodingKey {
        case id, kind, name, icon, sort
        case nameKey = "name_key"
        case accountIds = "account_ids"
        case memberIds = "member_ids"
        case tagKeys = "tag_keys"
    }
}

/// The format this build reads and writes. Anything else is not a memory it understands.
public let VAULT_FORMAT_VERSION = 3

/// The top-level vault. Groups are read, never written here — the phone doesn't arrange them,
/// and the raw-JSON round trip carries every field this struct doesn't name through a save.
public struct Vault: Codable {
    public var app: String
    public var version: Int
    public var subscriptions: [Subscription]        // file key commitments — the only required list
    public var familyMembers: [FamilyMember]        // file key members
    public var paymentMethods: [PaymentMethod]      // file key accounts
    public var tags: [TagDef]?
    /// Every charge, past and planned. Absent in the file means none written yet.
    public var charges: [ChargeRow]
    public var groups: [VaultGroup]?
    /// Named at setup, waiting for details. Absent means nothing waits.
    public var toFillIn: [CommitmentPlaceholder]?
    /// People and accounts picked at setup, kept as hints for reading statements.
    public var hints: [SetupHint]?

    enum CodingKeys: String, CodingKey {
        case app, version, tags, groups, charges, hints
        case toFillIn = "to_fill_in"
        case subscriptions = "commitments"
        case familyMembers = "members"
        case paymentMethods = "accounts"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        app = try c.decode(String.self, forKey: .app)
        version = try c.decode(Int.self, forKey: .version)
        // An older or newer format decodes as nothing rather than as a vault with the wrong
        // shape read confidently — the reader turns this into "not a memory this version reads".
        guard version == VAULT_FORMAT_VERSION else {
            throw DecodingError.dataCorrupted(.init(codingPath: [CodingKeys.version],
                                                    debugDescription: "format \(version) is not \(VAULT_FORMAT_VERSION)"))
        }
        subscriptions = try c.decode([Subscription].self, forKey: .subscriptions)
        // The only required list is commitments — an absent list is an empty one.
        familyMembers = try c.decodeIfPresent([FamilyMember].self, forKey: .familyMembers) ?? []
        paymentMethods = try c.decodeIfPresent([PaymentMethod].self, forKey: .paymentMethods) ?? []
        tags = try c.decodeIfPresent([TagDef].self, forKey: .tags)
        // Element-lossy: an AI's one bad row drops alone; the charges around it survive.
        charges = (try c.decodeIfPresent([Lossy<ChargeRow>].self, forKey: .charges))?
            .compactMap(\.value) ?? []
        groups = try c.decodeIfPresent([VaultGroup].self, forKey: .groups)
        toFillIn = (try? c.decodeIfPresent([Lossy<CommitmentPlaceholder>].self, forKey: .toFillIn))?.compactMap(\.value)
        hints = (try? c.decodeIfPresent([Lossy<SetupHint>].self, forKey: .hints))?.compactMap(\.value)
    }

    public init(
        app: String, version: Int = VAULT_FORMAT_VERSION, subscriptions: [Subscription],
        familyMembers: [FamilyMember] = [], paymentMethods: [PaymentMethod] = [],
        tags: [TagDef]? = nil, charges: [ChargeRow] = [], groups: [VaultGroup]? = nil,
        toFillIn: [CommitmentPlaceholder]? = nil, hints: [SetupHint]? = nil
    ) {
        self.app = app
        self.version = version
        self.subscriptions = subscriptions
        self.familyMembers = familyMembers
        self.paymentMethods = paymentMethods
        self.tags = tags
        self.charges = charges
        self.toFillIn = toFillIn
        self.hints = hints
        self.groups = groups
    }
}
