// A bank's SMS read into what it says: an amount, which way it went, the day, whom it
// went to, and the last four digits of the account. Read on the device, in the words
// banks here use; a message that names no amount is no charge at all.
import Foundation

public struct BankMessage: Equatable, Sendable {
    public let amount: Double
    public let currency: String
    /// "in" when the account was credited; "out" when it was debited or spent.
    public let direction: String
    /// YYYY-MM-DD, the day the message names, else the day it was read.
    public let date: String
    /// Whom the money went to, as the message wrote it, without codes.
    public let payee: String
    /// A short name for the row, drawn from the payee.
    public let name: String
    public let last4: String?

    public var isIncome: Bool { direction == "in" }

    private static let taken = #"\b(?:debited|credited|spent|sent|received|withdrawn|deposited|paid|deducted|transferred|purchase|dr|cr)\b"#
    private static let monthNames = "jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec"

    /// Nil when the text names no amount that moved: a password asked for, a debit still
    /// to come, a payment turned away, a balance, a bill or an offer.
    public static func parse(_ text: String, today: Date = LB.todayMid()) -> BankMessage? {
        let flat = text.replacingOccurrences(of: #"[\r\n]+"#, with: " ", options: .regularExpression)
        let lower = flat.lowercased()
        // What follows "if" is a warning, not what happened.
        let head = found(#"\b(?:if|in\s?case)\b"#, in: lower).first.map { String(lower[..<$0.at]) } ?? lower
        let moved = !found(taken + #"|\b(?:refund(?:ed)?|reversed|reversal|(?:txn|trxn|transaction)\s+of|used\s+(?:for|at|on))\b"#, in: lower).isEmpty
        guard moved, !isNotYetACharge(lower, head: head), let sum = firstAmount(in: flat) else { return nil }
        let has = { (pattern: String) in head.range(of: pattern, options: .regularExpression) != nil }
        let credited = has(#"\b(?:credited|received|refund(?:ed)?|deposited|credit of)\b|\bcr\b\.?\s+to\b"#)
        let debited = has(#"\b(?:debited|spent|paid|withdrawn|purchase|sent|transferred to|trf to)\b|\bdr\b\.?\s+from\b"#)
        // Money given back is money in, whatever debit the message recalls.
        let back = has(#"(?<!be )\b(?:reversed|reversal|credited back)\b|\b(?:refund(?:ed)?|cashback|interest)\b.*?(?<!be )\b(?:credited|received|paid)\b"#)
        // "Payment … received towards" is the owner's own payment arriving: a card bill is a
        // movement between their accounts and no charge; anything else is money out.
        let settled = has(#"\bpayment\b"#) && has(#"\btowards\b"#) && has(#"\b(?:received|successful)\b"#)
        if settled, has(#"\bcredit\s*card\b|\bcard\s+(?:ending|no\b|x+\d|\*+\d)"#) { return nil }
        let direction = back || (credited && !debited && !settled) ? "in" : "out"
        let payee = payeeIn(text)
        // A payee of codes names nobody; one of digits and letters names itself.
        let plain = StatementNaming.plainName(payee)
        let unnamed = direction == "in" ? "Unnamed money in" : "Unnamed charge"
        let name = plain != StatementNaming.plainName("") ? plain : payee.contains(where: \.isLetter) ? payee : unnamed
        return BankMessage(amount: sum.amount, currency: sum.currency, direction: direction, date: dateIn(flat) ?? LB.toISO(today),
                           payee: payee, name: name, last4: last4In(flat))
    }

    /// A one-time password asks leave for a charge, a notice says one is coming, a refusal
    /// says none was made. A notice or refusal counts only before any money moved, and
    /// never when the money came back; a warning under a charge unmakes nothing.
    private static func isNotYetACharge(_ lower: String, head: String) -> Bool {
        let first = { (pattern: String, text: String) in found(pattern, in: text).first?.at }
        let password = #"\b(?:otp|one[\s-]?time\s+pass\w*)\b"#
        let asked = #"\b(?:is|as)\s+(?:the\s+|your\s+)?(?:otp\b|one[\s-]?time\s+pass)|"# + password + #"(?:.{0,60}?\bis)?\s*[:\-]?\s*\d{4,8}\b"#
        let coming = #"\b(?:will|shall|would|to)\s+be\s+(?:auto[\s-]?)?(?:debited|deducted|charged)\b"#
        let refused = #"\b(?:declined|unsuccessful|not\s+successful|could\s+not\s+be\s+processed|has\s+failed|is\s+failed|txn\s+failed|transaction\s+failed)\b"#
        let moved = first(taken, head)
        let vetoed = [coming, refused].contains { veto in first(veto, head).map { at in moved.map { at < $0 } ?? true } ?? false }
        let undone = first(#"(?<!be )\b(?:credited|reversed|refunded)\b"#, head) != nil
        if first(asked, lower) != nil || (vetoed && !undone) { return true }
        return first(password, lower) != nil && first(taken, lower) == nil
    }

    /// The first amount after a currency that is not a balance, a limit, a sum due or an
    /// offer; failing one, the bare number some banks print after "debited by".
    private static func firstAmount(in text: String) -> (amount: Double, currency: String)? {
        let number = #"([0-9][0-9,]*(?:\.[0-9]{1,2})?)(?!\d|\s*(?:lakhs?|lacs?|crores?)\b)"#
        let left = #"(\b(?:(?:avl|avail(?:able)?)\s*)?(?:bal(?:ance)?|lmt|limit|outstanding|due|up\s?to)\b[^.;]{0,24}?|\b(?:avl|avail(?:able)?)\b\W*)?"#
        let money = left + #"(\b(?:rs|inr|usd|eur|gbp|aed|sgd|aud|cad|jpy|chf)|₹|\$)[.:]?\s*"# + number
        let bare = #"\b(?:debited|credited)\s+(?:by|for|with)\s+"# + number + #"\b(?!\s*(?:reward|bonus|points|pts|miles))"#
        let sum = { (digits: String?) in digits.flatMap { Double($0.replacingOccurrences(of: ",", with: "")) } }
        if let hit = matches(money, in: text).first(where: { $0[0] == nil }), let amount = sum(hit[2]) {
            let code = (hit[1] ?? "").uppercased()
            return (amount, ["RS", "INR", "₹"].contains(code) ? "INR" : code == "$" ? "USD" : code)
        }
        return sum(matches(bare, in: text).first?.first ?? nil).map { ($0, "INR") }
    }

    /// The first day the message names, in the orders banks here print — 2026-09-12,
    /// 12-09-26, 12/09/2026, 12-Sep-26, 12Sep26, Sep 12, 2026 — never a day the calendar
    /// lacks, never part of a longer number, and never a guess when it names none.
    static func dateIn(_ text: String) -> String? {
        let months = monthNames.split(separator: "|").map(String.init)
        let orders: [(pattern: String, day: Int, month: Int, year: Int)] = [
            (#"(?<![\d\-/:])(20\d{2})([-/:])(\d{2})\2(\d{2})(?!\d|[-/]\d)"#, 3, 2, 0),
            (#"(?<![\d\-/.])(\d{1,2})([-/.])(\d{1,2})\2(\d{4}|\d{2})(?!\d|[-/]\d)"#, 0, 2, 3),
            (#"(?<!\d)(\d{1,2})(?:st|nd|rd|th)?[-\s]?("# + monthNames + #")[a-z]*[-\s,.]*'?(\d{4}|\d{2})(?!\d)"#, 0, 1, 2),
            (#"\b("# + monthNames + #")[a-z]*\.?\s+(\d{1,2})(?:st|nd|rd|th)?,?\s+(\d{4})\b"#, 1, 0, 2),
        ]
        let named = orders.compactMap { order in
            found(order.pattern, in: text).lazy.compactMap { hit -> (at: String.Index, day: String)? in
                let part = { (group: Int) in hit.groups[group].flatMap { Int($0) ?? months.firstIndex(of: $0.lowercased()).map { $0 + 1 } } }
                guard let day = part(order.day), let month = part(order.month), let year = part(order.year),
                      let whole = iso(day: day, month: month, year: year)
                else { return nil }
                return (hit.at, whole)
            }.first
        }
        return named.min { $0.at < $1.at }?.day
    }

    private static func iso(day: Int, month: Int, year: Int) -> String? {
        let fullYear = year < 100 ? 2000 + year : year
        guard (1...12).contains(month), (1...31).contains(day),
              let date = LB.calendar.date(from: DateComponents(year: fullYear, month: month, day: day)),
              LB.calendar.component(.day, from: date) == day
        else { return nil }
        return LB.toISO(date)
    }

    /// The bank's own field first, then a name in brackets after a handle, then ICICI's
    /// "NAME credited"; then the name after "to", "at" or "towards", after "by" or "from",
    /// and last after "on". Failing all, a line or a stretch that frames nothing.
    static func payeeIn(_ text: String) -> String {
        if let named = fieldPayee(text) { return named }
        let stop = "on|at|as|is|was|has|from|for|ref|refno|upi|txn|info|avl|avail|bal|using|via|with|thru|through|vide|ending|dated|if not|not you|not u"
        // A hyphen ends a name only before a space, a digit or the end: D-MART stays whole.
        let tail = #"(?:\s+vpa)?\s+([^\r\n]+?)(?=\s+(?:"# + stop + #")\b|[.(;]|-(?=[\s\d]|$)|\s+-|\s*[\r\n]|\s*$)"#
        let leads = [#"\b(?:towards|trf to|to|at)"#, #"\b(?:by|from)"#, #"\bon"#].map { $0 + tail }
        for pattern in [#"@[\w.\-]+\s*\(([^)]+)\)"#, #";\s*([^;.]+?)\s+credited\b"#] + leads {
            if let named = captures(pattern, in: text).lazy.compactMap(nameFrom).first { return named }
        }
        // Axis on one line: the merchant stands between the clock and the limit left.
        let clock = #"\d{1,2}:\d{2}(?::\d{2})?(?:\s+IST)?\s+([^\r\n]+?)(?=\s+avl\b)"#
        return linePayee(text) ?? captures(clock, in: text).lazy.compactMap(nameFrom).first ?? ""
    }

    /// What is never a payee: the owner, a clock, a day with no year, an account with its
    /// number, a mask or a long number, a warning with a number to ring, and a currency,
    /// a rail or a channel standing alone.
    private static let notAName = [
        #"^(?:your\b|date\b|(?:you|u|me)$)|^\d{1,2}:\d{2}|^\d{1,2}(?:st|nd|rd|th)?[-\s]?(?:"# + monthNames + #")[a-z]*$"#,
        #"\b(?:a/c|ac{1,2}t?|account|card)\b\W*(?:no\b\W*)?[x*]*\d|\b(?:a/c|account)$|(?-i:\b[Cc]ard$)"#,
        #"(?<![a-z])[x*]+\d{3,}|\d{5,}|\b(?:call|sms|block|dial)\b\D{0,12}\d{3,}"#,
        #"^(?:rs|inr|rupees?|usd|eur|gbp|aed|sgd|aud|cad|jpy|chf|upi|imps|neft|rtgs|nach|ach|pos|ecom|vps|transfer|cash|cheque|mob\w*\s*b\w*k\w*|net\s*banking|dr|mr|mrs|ms|m/s)$"#,
    ].joined(separator: "|")

    /// A piece of the message kept as a payee: trimmed, a handle cut at its @. Outside the
    /// bank's own field it must hold a capital or come from a handle, since banks print
    /// names so and prose ("to report") not; digits may be half of it, never more.
    private static func nameFrom(_ found: String) -> String? { nameFrom(found, inField: false) }

    private static func nameFrom(_ found: String, inField: Bool) -> String? {
        var piece = found.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        let handle = piece.firstIndex(of: "@")
        if let handle { piece = String(piece[..<handle]) }
        piece = piece.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        guard piece.contains(where: \.isLetter), piece.filter(\.isNumber).count * 2 <= piece.count,
              inField || handle != nil || piece.contains(where: \.isUppercase),
              piece.range(of: notAName, options: [.regularExpression, .caseInsensitive]) == nil,
              firstAmount(in: piece) == nil, dateIn(piece) == nil
        else { return nil }
        return piece
    }

    /// "Info: UPI-4255…-SWIGGY", or a bare "UPI/P2A/1234/PAYER NAME/THEIR BANK": the first
    /// name after the reference number, else the first. A bare field counts only with a
    /// reference, a code or a name all in capitals, so "Use UPI-Lite!" names nobody.
    private static func fieldPayee(_ text: String) -> String? {
        let kinds = "upi|imps|neft|rtgs|nach|ach|pos|ecom|vps"
        let end = #"(?=\.\s|\.$|\.(?-i:[A-Z][a-z])|\s+(?:avl|avail|bal|ref|refno|not you|not u|if not|call|sms|(?-i:from|to|on|at|for|by|towards))\b|\s*[\r\n]|\s*$)"#
        let info = captures(#"\binfo[:\-\s]+((?:"# + kinds + #")\b[^\r\n]*?)"# + end, in: text).first
        let bare = captures(#"(?<![/.\w])((?:"# + kinds + #")(?:\s+[cd]r)?[/-][^\r\n]*?)"# + end, in: text).first
        guard let field = info ?? bare, let mark = field.first(where: { "-/".contains($0) }) else { return nil }
        let codes = kinds + "|p2m|p2a|p2p|dr|cr|mob|inb|si"
        let isCode = { (piece: String) in piece.range(of: "^(?:" + codes + ")$", options: [.regularExpression, .caseInsensitive]) != nil }
        // The field's first mark parts it; a code led in by the other mark is shed.
        let parts = field.split(separator: mark).dropFirst().map {
            $0.trimmingCharacters(in: .whitespaces)
                .replacingOccurrences(of: #"^(?:(?:"# + codes + #")\s*[-/]\s*)+"#, with: "", options: [.regularExpression, .caseInsensitive])
        }
        // "M/S", "D-MART", "7-ELEVEN": a piece of a letter or two belongs to the next.
        let pieces = parts.reduce(into: [String]()) { joined, piece in
            if let last = joined.last, last.count <= 2, !isCode(last) { joined[joined.count - 1] = last + String(mark) + piece } else { joined.append(piece) }
        }
        let digits = { (piece: String) in piece.filter(\.isNumber).count }
        let reference = pieces.firstIndex { digits($0) >= 4 && digits($0) * 2 > $0.count }
        // The last piece is often a bank signing off; it is the payee only right after the reference.
        let names = pieces.indices.filter { at in
            let signsOff = at == pieces.count - 1 && pieces[at].lowercased().hasSuffix("bank") && reference.map { at != $0 + 1 } ?? true
            return !isCode(pieces[at]) && !signsOff && nameFrom(pieces[at], inField: true) != nil
        }
        guard let chosen = reference.flatMap({ past in names.first { $0 > past } }) ?? names.first else { return nil }
        let coded = field.range(of: #"(?:^\w+\s+[cd]r|[-/](?:p2[map]|dr|cr))[-/]"#, options: [.regularExpression, .caseInsensitive]) != nil
        let sure = info != nil || coded || pieces.contains { digits($0) >= 6 && digits($0) * 2 > $0.count } || !pieces[chosen].contains(where: \.isLowercase)
        return sure ? nameFrom(pieces[chosen], inField: true) : nil
    }

    /// A message printed a field to a line names its payee on a line of its own: the one
    /// line that is no amount, account, day, warning, greeting, bare verb or bank signing off.
    private static func linePayee(_ text: String) -> String? {
        let lines = text.split(whereSeparator: \.isNewline).map(String.init)
        guard lines.count > 1 else { return nil }
        let frame = #"\b(?:not you|not u|if not|dispute|fraud|https?|www|dear|hi|hello|alert|update|team|ref|refno|txn|avl|bal)\b|bank\W*$"#
            + #"|^\W*(?:to|at|towards|from|by|on)\s"#
            + #"|^\W*(?:amount\s+)?(?:spent|sent|debited|credited|received|paid|withdrawn|debit|credit|purchase)\W*$"#
        let named = lines.filter { $0.range(of: frame, options: [.regularExpression, .caseInsensitive]) == nil }.compactMap(nameFrom)
        return named.count == 1 ? named[0] : nil
    }

    /// Every match of the pattern, case-insensitively: where it starts, and its capture
    /// groups in order, a group that took no part being nil.
    private static func found(_ pattern: String, in text: String) -> [(at: String.Index, groups: [String?])] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
            guard let whole = Range(match.range, in: text) else { return nil }
            let groups = (1..<match.numberOfRanges).map { group in Range(match.range(at: group), in: text).map { String(text[$0]) } }
            return (whole.lowerBound, groups)
        }
    }

    private static func matches(_ pattern: String, in text: String) -> [[String?]] {
        found(pattern, in: text).map(\.groups)
    }

    /// Every first capture of the pattern, in order.
    private static func captures(_ pattern: String, in text: String) -> [String] {
        matches(pattern, in: text).compactMap { $0.first ?? nil }
    }

    /// The four digits after an account word, masked or not ("A/c ...1234", "XXXX-1234");
    /// after a bank's name only when masked, so a helpline is never an account.
    static func last4In(_ text: String) -> String? {
        let pattern = #"\b(?:a/c|account|acct|card|ac)\s*(?:no\.?|number|ending(?:\s+(?:in|with))?)?[\s:.\-]{0,4}[x*]*[\s.\-]{0,2}(\d{4})\b|\bbank\s*[x*]+[\s\-]?(\d{4})\b"#
        return matches(pattern, in: text).first.flatMap { $0[0] ?? $0[1] }
    }
}
