// DemoVault.swift — a made-up household written into a folder, so a reader can walk around
// a filled longbook before theirs is one. The same family as scripts/demo-vault.mts, dated
// around the day it is written: every name and amount is invented.

import Foundation

public enum DemoVault {
    /// The file that marks a folder as this generator's, so nothing real is ever written over.
    public static let marker = ".demo-vault"

    public enum WriteError: LocalizedError {
        case notADemoFolder

        public var errorDescription: String? {
            "That folder holds files the demo did not write."
        }
    }

    public struct Counts: Equatable {
        public let commitments: Int
        public let charges: Int
        public let members: Int
        public let accounts: Int
    }

    /// Writes the data file, insights and workspace into `folder` — an empty one, or one
    /// carrying the marker from an earlier write. Dates run a year back and a year ahead of
    /// `today`.
    @discardableResult
    public static func write(into folder: URL, today: Date = LB.todayMid()) throws -> Counts {
        let fm = FileManager.default
        if fm.fileExists(atPath: folder.path) {
            let present = (try? fm.contentsOfDirectory(atPath: folder.path)) ?? []
            if !present.isEmpty, !fm.fileExists(atPath: folder.appendingPathComponent(marker).path) {
                throw WriteError.notADemoFolder
            }
        }
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let made = Household(today: LB.toISO(today))
        try bytes(made.vault).write(to: folder.appendingPathComponent(VaultReader.dataFile), options: .atomic)
        try bytes(made.insights).write(to: folder.appendingPathComponent(InsightsReader.fileName), options: .atomic)
        try bytes(["homeCurrency": "INR", "commitmentsAsked": true]).write(to: folder.appendingPathComponent(WorkspaceStore.fileName), options: .atomic)
        try "Written by longbook's demo. Every name and amount is made up.\n"
            .write(to: folder.appendingPathComponent(marker), atomically: true, encoding: .utf8)
        return made.counts
    }

    private static func bytes(_ object: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
    }

    // MARK: days, as YYYY-MM-DD

    private static func day(_ iso: String) -> Date { LB.parseDate(iso) ?? LB.todayMid() }
    private static func addDays(_ iso: String, _ n: Int) -> String { LB.toISO(LB.addDays(day(iso), n)) }
    private static func addMonths(_ iso: String, _ n: Int) -> String { LB.toISO(LB.addMonths(day(iso), n)) }

    /// Day `n` of the month `iso` falls in, clamped to that month's length.
    private static func inMonth(of iso: String, day n: Int) -> String {
        let first = LB.firstOfMonth(day(iso))
        let wanted = LB.addDays(first, n - 1)
        let last = LB.addDays(LB.addMonths(first, 1), -1)
        return LB.toISO(min(wanted, last))
    }

    // MARK: the household

    private struct Spec {
        let id: String
        let name: String
        let amount: (Int) -> Double
        var currency: String? = nil
        let cycle: String
        var every: Int? = nil
        let first: String
        var until: String? = nil
        var tag: String? = nil
        var member: String? = nil
        var account: String? = nil
        var notes: String? = nil
        var direction: String? = nil
        var basis: String? = nil
        var status: String? = nil
        var ends: String? = nil
    }

    private struct Household {
        let vault: [String: Any]
        let insights: [String: Any]
        let counts: Counts

        init(today: String) {
            let yearAgo = addMonths(today, -12)
            let yearAhead = addMonths(today, 12)
            /// This month's day `n`, or last month's when that is still ahead of today.
            func recent(_ n: Int) -> String {
                let here = inMonth(of: today, day: n)
                return here <= today ? here : inMonth(of: addMonths(today, -1), day: n)
            }
            /// A monthly line's first charge, a year back on its day of the month.
            func monthly(_ n: Int) -> String { addMonths(recent(n), -12) }
            func flat(_ amount: Double) -> (Int) -> Double { { _ in amount } }
            func cycling(_ amounts: [Double]) -> (Int) -> Double { { amounts[$0 % amounts.count] } }

            let specs: [Spec] = [
                Spec(id: "c-rent", name: "House rent", amount: flat(42000), cycle: "monthly", first: monthly(1), tag: "rent",
                     member: "m-mehta", account: "a-hdfc", notes: "Landlord: Mehta Properties\nLease ends: March 2027"),
                Spec(id: "c-maint", name: "Society maintenance", amount: flat(3500), cycle: "monthly", first: monthly(5), tag: "home",
                     account: "a-hdfc", notes: "Society: Greenwood Residency"),
                Spec(id: "c-cook", name: "Sunita, cook", amount: flat(12000), cycle: "monthly", first: monthly(5), tag: "salary",
                     member: "m-sunita", account: "a-hdfc"),
                Spec(id: "c-netflix", name: "Netflix", amount: flat(649), cycle: "monthly", first: monthly(6), tag: "streaming",
                     account: "a-axis", basis: "email"),
                Spec(id: "c-spotify", name: "Spotify", amount: flat(119), cycle: "monthly", first: monthly(11), tag: "streaming",
                     member: "m-asha", account: "a-axis", basis: "email"),
                Spec(id: "c-airtel", name: "Airtel Digital TV", amount: flat(899), cycle: "monthly", first: monthly(3), tag: "telecom",
                     account: "a-hdfc"),
                Spec(id: "c-jio", name: "Jio postpaid", amount: flat(599), cycle: "monthly", first: monthly(18), tag: "telecom",
                     member: "m-asha", account: "a-axis"),
                Spec(id: "c-adobe", name: "Adobe Creative Cloud", amount: flat(1699), cycle: "monthly", first: monthly(2),
                     until: addMonths(today, 3), tag: "software", member: "m-dev", account: "a-axis", basis: "email"),
                Spec(id: "c-claude", name: "Claude Pro", amount: flat(20), currency: "USD", cycle: "monthly", first: monthly(2), tag: "ai",
                     member: "m-dev", account: "a-axis", basis: "email"),
                Spec(id: "c-school", name: "School fees, Kabir", amount: flat(15000), cycle: "monthly", first: monthly(10), tag: "education",
                     member: "m-kabir", account: "a-icici", notes: "School: Oakridge Public School\nTerm: April to March"),
                Spec(id: "c-gym", name: "Fitlane gym", amount: flat(2500), cycle: "monthly", first: monthly(15), tag: "health & fitness",
                     member: "m-asha", account: "a-icici"),
                Spec(id: "c-power", name: "Electricity",
                     amount: cycling([2140, 2310, 2890, 3420, 3180, 2760, 2230, 2080, 2450, 2960, 3310, 2870]),
                     cycle: "monthly", first: monthly(20), tag: "utility", account: "a-hdfc"),
                Spec(id: "c-prime", name: "Amazon Prime", amount: flat(1499), cycle: "yearly", first: addMonths(recent(14), -7),
                     until: addMonths(today, 24), tag: "membership", account: "a-axis"),
                Spec(id: "c-ergo", name: "HDFC ERGO health insurance", amount: flat(24500), cycle: "yearly", first: addMonths(recent(12), -10),
                     until: addMonths(today, 24), tag: "insurance", member: "m-dev", account: "a-hdfc",
                     notes: "Policy number: 88213\nCovers: Dev, Asha and Kabir\nRenews: every November"),
                Spec(id: "c-lic", name: "LIC term plan", amount: flat(18200), cycle: "yearly", first: addMonths(recent(28), -6),
                     until: addMonths(today, 24), tag: "insurance", member: "m-dev", account: "a-hdfc",
                     notes: "Policy number: 51204776\nCover: 1 crore"),
                Spec(id: "c-star", name: "Star Health, Asha", amount: flat(11800), cycle: "custom", every: 182,
                     first: addDays(recent(8), -182 * 2 + 30), until: addMonths(today, 18), tag: "insurance", member: "m-asha", account: "a-icici"),
                Spec(id: "c-domain", name: "GoDaddy domain, three years", amount: flat(2850), cycle: "custom", every: 1095,
                     first: addDays(today, -330), until: addDays(today, 800), tag: "domain & hosting", member: "m-dev", account: "a-axis"),
                Spec(id: "c-card", name: "Axis card bill",
                     amount: cycling([9830, 11240, 12450, 10610, 13980, 9960, 12870, 11420, 10350, 12050, 11730, 12450]),
                     cycle: "monthly", first: monthly(24), account: "a-hdfc", direction: "transfer"),
                Spec(id: "c-salary", name: "Salary, Vertex Labs", amount: flat(185000), cycle: "monthly", first: monthly(1),
                     member: "m-dev", account: "a-hdfc", notes: "Employer: Vertex Labs Pvt Ltd", direction: "in"),
                Spec(id: "c-swiggy", name: "Swiggy", amount: flat(1340), cycle: "once", first: addDays(today, -9), account: "a-axis"),
                Spec(id: "c-pharmacy", name: "Apollo Pharmacy", amount: flat(862), cycle: "once", first: addDays(today, -16),
                     tag: "health & fitness", account: "a-axis"),
                Spec(id: "c-train", name: "IRCTC, Pune trip", amount: flat(4380), cycle: "once", first: addDays(today, -38), tag: "travel",
                     account: "a-axis"),
                Spec(id: "c-gift", name: "Tanishq, anniversary gift", amount: flat(28500), cycle: "once", first: addDays(today, -71), tag: "gift",
                     member: "m-asha", account: "a-axis"),
                Spec(id: "c-hotstar", name: "JioHotstar", amount: flat(299), cycle: "monthly", first: addMonths(monthly(21), 2),
                     until: addMonths(recent(21), -3), tag: "streaming", account: "a-axis", status: "cancelled", ends: addMonths(recent(21), -3)),
            ]

            // Past rows are confirmed, except the one a household has not reconciled yet: this
            // month's electricity bill, which keeps the month part-covered.
            let unconfirmed: Set<String> = ["c-power:\(recent(20))"]

            var commitments: [[String: Any]] = []
            var charges: [[String: Any]] = []
            for s in specs {
                let until = s.until ?? yearAhead
                var dates: [String] = []
                var d = s.first
                var i = 0
                while d <= until, i < 400 {
                    dates.append(d)
                    if s.cycle == "once" { break }
                    switch s.cycle {
                    case "monthly": d = addMonths(s.first, i + 1)
                    case "yearly": d = addMonths(s.first, 12 * (i + 1))
                    default: d = addDays(s.first, (s.every ?? 30) * (i + 1))
                    }
                    i += 1
                }
                var row: [String: Any] = [
                    "id": s.id,
                    "name": s.name,
                    "amount": s.amount(dates.count - 1),
                    "currency": s.currency ?? "INR",
                    "billing_cycle": s.cycle,
                    "status": s.status ?? "active",
                    "created_at": "\(s.first < yearAgo ? s.first : yearAgo)T09:00:00Z",
                ]
                if let every = s.every { row["custom_cycle_days"] = every }
                if let tag = s.tag { row["tag"] = tag }
                if let notes = s.notes { row["notes"] = notes }
                if let member = s.member { row["member_id"] = member }
                if let account = s.account { row["account_id"] = account }
                if let ends = s.ends { row["ends_on"] = ends }
                if let direction = s.direction { row["direction"] = direction }
                commitments.append(row)
                for (index, date) in dates.enumerated() {
                    let past = date <= today && !unconfirmed.contains("\(s.id):\(date)")
                    var charge: [String: Any] = [
                        "commitment_id": s.id,
                        "date": date,
                        "amount": s.amount(index),
                        "paid": past,
                        "basis": past ? (s.basis ?? "statement") : "plan",
                    ]
                    if let currency = s.currency { charge["currency"] = currency }
                    if past { charge["paid_on"] = date }
                    charges.append(charge)
                }
            }
            charges.sort { ($0["date"] as? String ?? "") < ($1["date"] as? String ?? "") }

            let joined = "\(addDays(today, -115))T09:00:00Z"
            let members: [[String: Any]] = [
                ["id": "m-dev", "name": "Dev", "name_key": "dev", "tag": "family", "starred": true, "created_at": joined],
                ["id": "m-asha", "name": "Asha", "name_key": "asha", "tag": "family", "starred": true, "created_at": joined],
                ["id": "m-kabir", "name": "Kabir", "name_key": "kabir", "tag": "family", "created_at": joined],
                ["id": "m-sunita", "name": "Sunita", "name_key": "sunita", "tag": "household help", "created_at": joined],
                ["id": "m-mehta", "name": "Mehta Properties", "name_key": "mehta properties", "tag": "landlord", "created_at": joined],
            ]
            let accounts: [[String: Any]] = [
                ["id": "a-hdfc", "name": "HDFC savings", "name_key": "hdfc savings", "institution": "HDFC Bank", "last4": "5521",
                 "tag": "bank account", "member_id": "m-dev", "balance": 284512, "balance_date": addDays(today, -4), "starred": true, "created_at": joined],
                ["id": "a-axis", "name": "Axis card", "name_key": "axis card", "institution": "Axis Bank", "last4": "4402",
                 "tag": "credit card", "member_id": "m-dev", "parent_account_id": "a-hdfc", "notes": "Card name: Ruby Rewards",
                 "balance": -12450, "balance_date": recent(15), "starred": true, "created_at": joined],
                ["id": "a-icici", "name": "ICICI savings", "name_key": "icici savings", "institution": "ICICI Bank", "last4": "8130",
                 "tag": "bank account", "member_id": "m-asha", "balance": 112400, "balance_date": addDays(today, -10), "created_at": joined],
            ]

            // The library's own entries for every tag the household wears, as setup writes them.
            var worn = Set<String>()
            for c in commitments { if let tag = c["tag"] as? String { worn.insert("commitment:\(tag)") } }
            for m in members { if let tag = m["tag"] as? String { worn.insert("member:\(tag)") } }
            for a in accounts { if let tag = a["tag"] as? String { worn.insert("account:\(tag)") } }
            let tags: [[String: Any]] = TagLibrary.all.filter { worn.contains("\($0.kind):\($0.name)") }.map { entry in
                let slug = entry.nameKey.replacingOccurrences(of: "[^A-Za-z0-9_]+", with: "-", options: .regularExpression)
                var tag: [String: Any] = ["id": "t-\(entry.kind)-\(slug)", "kind": entry.kind, "name": entry.name, "name_key": entry.nameKey,
                                          "is_default": true, "sort": entry.sort, "created_at": joined]
                if let icon = entry.icon { tag["icon"] = icon }
                return tag
            }

            vault = ["app": "longbook", "version": VAULT_FORMAT_VERSION, "commitments": commitments, "members": members,
                     "accounts": accounts, "tags": tags, "charges": charges]

            let noted = addDays(today, -2)
            insights = [
                "version": 1,
                "insights": [
                    ["module": "dashboard.next_payment", "created_at": noted,
                     "text": "Rent and Sunita's pay leave HDFC savings within five days of the 1st, a little under a third of the salary that arrives the same day."],
                    ["module": "dashboard.by_category", "created_at": noted,
                     "text": "Rent is most of every month. Of the rest, the three insurance premiums fall in November, January and March, so those months run heavier."],
                    ["module": "dashboard.by_account", "created_at": noted,
                     "text": "The Axis card carries the subscriptions and the one-off spending; its bill leaves HDFC savings on the 24th."],
                    ["module": "account.a-axis", "created_at": noted,
                     "text": "Every subscription on this card renews between the 2nd and the 18th, so each month's bill on the 24th holds them all."],
                    ["module": "member.m-asha", "created_at": noted,
                     "text": "The gym and Star Health both leave ICICI savings; everything else of Asha's is on the Axis card."],
                ],
            ]
            counts = Counts(commitments: commitments.count, charges: charges.count, members: members.count, accounts: accounts.count)
        }
    }
}
