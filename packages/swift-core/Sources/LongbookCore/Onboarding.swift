// The first run's cards, in the owner's words, and the rules that turn a tap into a
// commitment, a member or an account. Data and arithmetic only; the app draws it.
import Foundation

/// One screen of a step: a question, its symbol, the library tag its picks wear, and the
/// chips under it. Chips are kinds, never bank or brand names where a kind will do.
public struct OnboardingCard: Identifiable, Equatable, Sendable {
    public enum Kind: Sendable { case commitments, accounts }

    public let id: String
    public let kind: Kind
    public let question: String
    public let symbol: String
    public let tag: String
    public let chips: [String]
}

public enum OnboardingCards {
    /// Step 1: what the owner wants remembered.
    public static let commitments: [OnboardingCard] = [
        OnboardingCard(id: "people", kind: .commitments, question: "Salary or payments to people?", symbol: "person.2.fill", tag: "salary",
                       chips: ["Maid", "Cook", "Nanny", "Driver", "Car washer", "Accountant", "Lawyer", "Doctor", "Employee", "Worker", "Delivery man"]),
        OnboardingCard(id: "rent", kind: .commitments, question: "Monthly rent?", symbol: "house.fill", tag: "rent",
                       chips: ["Home rent", "Apartment rent", "Room rent", "Parking rent", "Garage rent", "Shop rent", "Office rent", "Co-working desk rent",
                               "Storage unit rent", "Student housing rent", "Ground rent", "HOA or condo fees", "Service charges", "Car lease"]),
        OnboardingCard(id: "loans", kind: .commitments, question: "Loans, mortgages or installments?", symbol: "building.columns.fill", tag: "emi",
                       chips: ["Home mortgage", "Vehicle mortgage", "Personal loan", "Business loan", "iPhone installment", "Mac installment", "Education loan"]),
        OnboardingCard(id: "insurance", kind: .commitments, question: "Insurances?", symbol: "checkmark.shield.fill", tag: "insurance",
                       chips: ["Health insurance", "Life insurance", "Vehicle insurance", "Home insurance", "Phone insurance", "Electronic insurance"]),
        OnboardingCard(id: "personal", kind: .commitments, question: "Personal subscriptions?", symbol: "play.rectangle.fill", tag: "subscription",
                       chips: ["Netflix", "Amazon Prime", "Spotify", "YouTube", "Disney Hotstar", "Apple TV+", "Apple Fitness+", "iCloud", "Apple One", "Games", "Dating", "Gym"]),
        OnboardingCard(id: "business", kind: .commitments, question: "Business subscriptions?", symbol: "briefcase.fill", tag: "software",
                       chips: ["Supabase", "Cloudflare", "PostHog", "Apple Developer", "Resend", "Hosting", "Domain renewals", "Email", "Google", "Microsoft",
                               "Canva", "Notion", "Adobe", "VPS", "VPN", "Obsidian", "Figma", "Claude", "ChatGPT"]),
        OnboardingCard(id: "social", kind: .commitments, question: "Social media?", symbol: "bubble.left.and.bubble.right.fill", tag: "social media",
                       chips: ["Instagram", "Facebook", "WhatsApp", "Discord", "Telegram", "LinkedIn", "X"]),
    ]

    /// Step 2: where the money sits, in the words of the device's region; no bank is named.
    public static var accounts: [OnboardingCard] { accounts(for: Locale.current.region?.identifier) }

    /// The chips a region's people recognise: its account kinds, its cards, its wallets. A
    /// region not listed gets the universal set. The library tag each card writes is the same.
    public static func accounts(for region: String?) -> [OnboardingCard] {
        let banks: [String], cards: [String], wallets: [String]
        switch region ?? "" {
        case "IN":
            banks = ["Savings account", "Current account", "Salary account", "Joint account", "NRE account", "NRO account",
                     "Fixed deposit", "Recurring deposit", "PPF account", "Demat account"]
            cards = ["Credit card", "Debit card", "RuPay card", "Forex card", "Prepaid card", "Corporate card"]
            wallets = ["UPI", "Google Pay", "PhonePe", "Paytm", "Amazon Pay", "Apple Pay", "CRED"]
        case "US":
            banks = ["Checking account", "Savings account", "High-yield savings", "Money market account", "Certificate of deposit",
                     "Joint account", "Business account", "Brokerage account", "401(k)", "IRA", "HSA"]
            cards = ["Credit card", "Debit card", "Charge card", "Store card", "Secured credit card", "Business card"]
            wallets = ["Apple Pay", "Google Pay", "PayPal", "Venmo", "Cash App", "Zelle"]
        case "CA":
            banks = ["Chequing account", "Savings account", "High-interest savings", "TFSA", "RRSP", "FHSA", "Joint account", "Business account"]
            cards = ["Credit card", "Debit card", "Prepaid card", "Store card"]
            wallets = ["Apple Pay", "Google Pay", "PayPal", "Interac e-Transfer", "Wealthsimple Cash"]
        case "GB":
            banks = ["Current account", "Savings account", "Cash ISA", "Stocks and shares ISA", "Premium Bonds", "Joint account", "Business account"]
            cards = ["Credit card", "Debit card", "Prepaid card", "Store card"]
            wallets = ["Apple Pay", "Google Pay", "PayPal", "Revolut", "Monzo", "Wise"]
        case "AU", "NZ":
            banks = ["Transaction account", "Savings account", "Offset account", "Term deposit", "Superannuation", "Joint account", "Business account"]
            cards = ["Credit card", "Debit card", "Prepaid card"]
            wallets = ["Apple Pay", "Google Pay", "PayPal", "PayID", "Afterpay"]
        case let code where Regional.europe.contains(code):
            banks = ["Current account", "Savings account", "Joint account", "Business account", "Multi-currency account", "Fixed deposit"]
            cards = ["Debit card", "Credit card", "Prepaid card", "Business card"]
            wallets = ["Apple Pay", "Google Pay", "PayPal", "Revolut", "Wise", "N26", "Wero", "iDEAL", "Bizum", "Swish", "MobilePay", "Twint", "Vipps"]
        default:
            banks = ["Savings account", "Checking account", "Current account", "Chequing account", "Joint account", "Business account", "Student account",
                     "High-yield savings", "Money market account", "Multi-currency account", "Certificate of deposit", "Cash ISA", "TFSA"]
            cards = ["Debit card", "Credit card", "Prepaid card", "Charge card", "Store card", "Business card", "Corporate card", "Virtual card",
                     "Travel card", "Secured credit card"]
            wallets = ["Apple Pay", "Google Pay", "PayPal", "Venmo", "Cash App", "Zelle", "Samsung Wallet", "Amazon Pay", "Interac e-Transfer",
                       "Revolut", "Wise", "Wero", "iDEAL", "Bizum", "Swish", "MobilePay", "Twint", "Vipps"]
        }
        return [
            OnboardingCard(id: "banks", kind: .accounts, question: "Bank accounts?", symbol: "building.columns.fill", tag: "bank account", chips: banks),
            OnboardingCard(id: "cards", kind: .accounts, question: "Cards?", symbol: "creditcard.fill", tag: "credit card", chips: cards),
            OnboardingCard(id: "wallets", kind: .accounts, question: "Online wallets?", symbol: "wallet.pass.fill", tag: "wallet", chips: wallets),
            OnboardingCard(id: "else", kind: .accounts, question: "Anything else?", symbol: "sparkles", tag: "cash", chips: ["Cash"]),
        ]
    }

    /// Roles paid a fee rather than a salary.
    static let feeRoles: Set<String> = ["accountant", "lawyer", "doctor"]
    /// Cards that draw on money already there.
    static let debitCards: Set<String> = ["debit card", "prepaid card", "travel card"]

    /// The commitment a chip names: on the people card the role plus "salary" (or "fees"),
    /// elsewhere the chip as written.
    public static func commitmentName(_ chip: String, on card: OnboardingCard) -> String {
        guard card.id == "people" else { return chip }
        return feeRoles.contains(chip.lowercased()) ? "\(chip) fees" : "\(chip) salary"
    }

    /// The person a chip implies — only the people card names one — worn as both the
    /// member's name and their tag, so a later rename keeps the role beside it.
    public static func memberRole(_ chip: String, on card: OnboardingCard) -> String? {
        card.id == "people" ? chip : nil
    }

    /// The library tag an account chip wears: the card's, unless the chip says otherwise.
    public static func accountTag(_ chip: String, on card: OnboardingCard) -> String {
        if card.id == "cards", debitCards.contains(chip.lowercased()) { return "debit card" }
        if card.id == "wallets", chip.caseInsensitiveCompare("UPI") == .orderedSame { return "upi" }
        return card.tag
    }

    public static func placeholder(_ chip: String, on card: OnboardingCard) -> CommitmentPlaceholder {
        CommitmentPlaceholder(name: commitmentName(chip, on: card), group: card.question, tag: card.tag)
    }

    /// The least a longbook holds before its dashboard opens. The reader never sees the list.
    public static let minimums = (commitments: 3, charges: 10, accounts: 1, members: 1)

    public static func dashboardAllowed(commitments: Int, charges: Int, accounts: Int, members: Int) -> Bool {
        commitments >= minimums.commitments && charges >= minimums.charges
            && accounts >= minimums.accounts && members >= minimums.members
    }
}

/// What changes with the device's region outside the onboarding cards: the example a new
/// account's name field shows, and the library tags only one region's people use. The same
/// signal as the cards, `Locale.current.region`.
public enum Regional {
    /// The countries the cards treat as Europe.
    public static let europe: Set<String> = ["AT", "BE", "DE", "ES", "FI", "FR", "IE", "IT", "NL", "PT", "GR", "LU", "SK", "SI", "EE", "LV", "LT",
                                             "MT", "CY", "HR", "CH", "SE", "NO", "DK", "PL", "CZ"]

    /// The "Name the account" field's example, in the region's own words.
    public static var accountNameExample: String { accountNameExample(for: Locale.current.region?.identifier) }

    public static func accountNameExample(for region: String?) -> String {
        switch region ?? "" {
        case "IN": return "HDFC savings"
        case "US": return "Chase checking"
        case let code where europe.contains(code): return "Current account"
        default: return "Everyday savings"
        }
    }

    /// Library tags offered only in one region, as "kind:name" to the region's code. A vault
    /// that already wears one keeps it, since the vault's own registry lists it.
    static let regionOnlyTags: [String: String] = ["account:upi": "IN"]

    /// Whether the shipped library offers this tag on a device in this region.
    public static func offersLibraryTag(kind: String, name: String, region: String?) -> Bool {
        guard let only = regionOnlyTags["\(kind):\(name.lowercased())"] else { return true }
        return region == only
    }

    public static func offersLibraryTag(kind: String, name: String) -> Bool {
        offersLibraryTag(kind: kind, name: name, region: Locale.current.region?.identifier)
    }
}

/// Where the first run stands, as the sidecar and the account store it. Written after every
/// step, so another device can offer to pick up where this one left off.
public enum OnboardingStage: Equatable, Hashable, Sendable {
    case commitments(card: Int)
    case commitmentsDone
    case accounts(card: Int)
    case accountsDone(empty: Bool)
    case finish
    case done

    public var raw: String {
        switch self {
        case .commitments(let card): return "s1c\(card + 1)"
        case .commitmentsDone: return "t1"
        case .accounts(let card): return "s2c\(card + 1)"
        case .accountsDone(let empty): return empty ? "t2z" : "t2"
        case .finish: return "s3"
        case .done: return "done"
        }
    }

    public init?(raw: String) {
        switch raw {
        case "t1": self = .commitmentsDone
        case "t2": self = .accountsDone(empty: false)
        case "t2z": self = .accountsDone(empty: true)
        case "s3": self = .finish
        case "done": self = .done
        default:
            guard raw.count >= 4, let card = Int(raw.dropFirst(3)), card >= 1 else { return nil }
            if raw.hasPrefix("s1c"), card <= OnboardingCards.commitments.count { self = .commitments(card: card - 1) }
            else if raw.hasPrefix("s2c"), card <= OnboardingCards.accounts.count { self = .accounts(card: card - 1) }
            else { return nil }
        }
    }

    /// The step the header counts: 1, 2 or 3.
    public var step: Int {
        switch self {
        case .commitments, .commitmentsDone: return 1
        case .accounts, .accountsDone: return 2
        case .finish, .done: return 3
        }
    }
}
