// What comes round, decided on the device once every file's lines are named: the same line or
// the same person month after month makes a monthly commitment, and a monthly repeat whose
// last charge is old does not stand, whoever proposed it. Pure, and tested.
import Foundation

public enum StatementRepeats {
    /// The repeats as they stand, the lines they gathered under one name, and what changed.
    public struct Settled: Equatable, Sendable {
        public var candidates: [StatementCandidate]
        public var repeats: [StatementCloud.Repeat]
        /// Repeats nothing proposed, by the rule that found them.
        public var addedBySameLine = 0
        public var addedBySamePerson = 0
        /// Proposals a run gave lines they had missed.
        public var widened = 0
        /// Monthly repeats proposed whose last charge is too old.
        public var droppedAsOld = 0
        /// Runs the rules found, too old to stand.
        public var foundTooOld = 0
        /// Repeats made from what a line is, which nothing proposed.
        public var addedByNature = 0
    }

    /// How far apart one person's monthly payments may fall.
    static let daysApart = 7
    static let amountRatio = 1.2

    private enum Rule { case sameLine, samePerson }

    private struct Run {
        let rows: [StatementCandidate]
        let rule: Rule
    }

    /// The proposals with the device's rules added and the recency rule applied. A line dated
    /// after today moves nothing. `holders` are never someone paid. Lines, days and amounts stay.
    public static func settle(_ proposed: [StatementCloud.Repeat], candidates: [StatementCandidate], holders: [String] = []) -> Settled {
        // Each proposal is held to its own lines before any line is renamed.
        let pinned = proposed.map { repeated -> StatementCloud.Repeat in
            let rows = carried(repeated, in: candidates)
            return rows.isEmpty ? repeated : repeated.gathering(dates: repeated.dates, sightings: keys(rows))
        }
        var out = Settled(candidates: candidates, repeats: pinned)
        guard let newest = candidates.filter({ $0.skipReason != StatementTriage.afterToday }).map(\.line.date).max(),
              let top = month(of: newest) else {
            return out
        }
        // A month read only for its first week has not shown what it holds, so it isn't the latest.
        let latest = (day(of: newest) ?? 8) > 7 ? top : top - 1
        let ends = top == latest ? [top, top - 1] : [top, latest, latest - 1]
        let kept = candidates.filter(\.keep).sorted { $0.line.date < $1.line.date }
        let lineRuns = sameLineRuns(kept, ends: ends)
        let personRuns = samePersonRuns(left(kept, after: lineRuns), ends: ends, holders: holders)
        for run in lineRuns + personRuns { gather(run, into: &out, top: top, latest: latest) }
        // What ends too early is only counted: its lines stay one-time charges.
        let rest = left(kept, after: lineRuns + personRuns)
        let oldLines = sameLineRuns(rest, ends: nil)
        out.foundTooOld = oldLines.count + samePersonRuns(left(rest, after: oldLines), ends: nil, holders: holders).count
        addByNature(rest, into: &out)
        out.repeats = out.repeats.compactMap { repeated in
            guard repeated.cycle == BillingCycle.monthly.rawValue else { return stillRunning(repeated, top: top) }
            let months = Set(repeated.dates.compactMap(month(of:))).filter { !($0 > top) }
            guard let last = months.max() else { return repeated }
            guard !(last < latest - 1) else {
                out.droppedAsOld += 1
                return nil
            }
            return stillRunning(standing(repeated, run: runLength(endingAt: last, in: months)), top: top)
        }
        return out
    }

    /// Lines nothing gathered that come round by what they are. A monthly nature gathers all its
    /// name's lines, at the latest amount, when the name has no repeat; recency then judges them.
    /// A yearly nature makes one repeat per price band, since one insurer can hold two policies.
    private static func addByNature(_ rows: [StatementCandidate], into out: inout Settled) {
        let returned = rows.filter(\.isIncome)
        let taken = Set(out.repeats.flatMap { carried($0, in: out.candidates) }.map(\.id))
        var groups: [String: (nature: StatementNature, rows: [StatementCandidate])] = [:]
        var order: [String] = []
        for row in rows where row.direction == nil && !taken.contains(row.id) {
            guard let nature = StatementNature.of(name: row.name, line: row.line.payee, tag: row.tag) else { continue }
            // A bank's small test of a mandate comes straight back, and nothing comes round after it.
            if StatementNature.hasMandateMark(row.line.payee), returned.contains(where: { $0.line.amount == row.line.amount && daysBetween($0.line.date, row.line.date).map { !($0 > testReturnDays) } == true }) { continue }
            let key = nameKey(row.name)
            if groups[key] == nil { order.append(key) }
            groups[key, default: (nature, [])].rows.append(row)
        }
        for key in order {
            guard let group = groups[key] else { continue }
            if !group.nature.isYearly, out.repeats.contains(where: { nameKey($0.name) == key }) { continue }
            for lines in group.nature.isYearly ? priceBands(group.rows) : [group.rows] {
                let dated = lines.sorted { $0.line.date < $1.line.date }
                let cycle = rhythm(dated, nature: group.nature)
                out.repeats.append(StatementCloud.Repeat(name: dated[0].name, cycle: cycle.cycle, customDays: cycle.days, amount: dated[dated.count - 1].line.amount,
                                                         dates: days(dated), category: commonTag(dated), endsOn: nil, guessed: dated.count < 3,
                                                         reason: natureReason(group.nature, sightings: dated.count), sightings: keys(dated)))
                out.addedByNature += 1
            }
        }
    }

    /// Lines whose amounts sit within the same-person ratio of the band's lowest are one band.
    private static func priceBands(_ rows: [StatementCandidate]) -> [[StatementCandidate]] {
        var bands: [[StatementCandidate]] = []
        for row in rows.sorted(by: { $0.line.amount < $1.line.amount }) {
            if let floor = bands.last?.first?.line.amount, !(row.line.amount > floor * amountRatio + 0.005) {
                bands[bands.count - 1].append(row)
            } else {
                bands.append([row])
            }
        }
        return bands
    }

    private static let testReturnDays = 14

    private static func daysBetween(_ a: String, _ b: String) -> Int? {
        guard let first = LB.parseDate(a), let second = LB.parseDate(b) else { return nil }
        return abs(Calendar(identifier: .gregorian).dateComponents([.day], from: first, to: second).day ?? Int.max)
    }

    /// The cycle a nature's lines show: their spacing when seen more than once, its own otherwise.
    private static func rhythm(_ rows: [StatementCandidate], nature: StatementNature) -> (cycle: String, days: Int?) {
        let plain = nature.isYearly ? BillingCycle.yearly.rawValue : BillingCycle.monthly.rawValue
        let months = rows.compactMap { month(of: $0.line.date) }.sorted()
        guard let first = months.first, let last = months.last, months.count > 1, last > first else { return (plain, nil) }
        switch (last - first) / (months.count - 1) {
        case 1: return (BillingCycle.monthly.rawValue, nil)
        case 3: return (BillingCycle.custom.rawValue, 91)
        case 6: return (BillingCycle.custom.rawValue, 183)
        default: return (plain, nil)
        }
    }

    private static func natureReason(_ nature: StatementNature, sightings: Int) -> String {
        let seen = sightings == 1 ? "Seen once" : "Seen \(sightings) times"
        switch nature {
        case .insurance: return "\(seen) as an insurer's payment; yearly assumed from the insurer's name."
        case .domain: return "\(seen) as a domain registration; yearly assumed."
        case .bill: return "\(seen) as a bill that repeats by nature; monthly assumed."
        case .mandate: return "\(seen) with the bank's mandate mark; monthly assumed."
        }
    }

    /// A repeat hasn't stopped while its next charge isn't due: a yearly premium read from six
    /// months of lines is still running, whatever the proposal said.
    private static func stillRunning(_ repeated: StatementCloud.Repeat, top: Int) -> StatementCloud.Repeat {
        guard let ended = repeated.endsOn, let said = month(of: ended) else { return repeated }
        // An end before its own last line is no end: judged from the later of the two.
        let last = max(said, repeated.dates.compactMap(month(of:)).max() ?? said)
        let cycleMonths = repeated.cycle == BillingCycle.yearly.rawValue ? 12 : repeated.cycle == BillingCycle.monthly.rawValue ? 1 : max(1, (repeated.customDays ?? 30) / 30)
        guard !(last + cycleMonths < top) else { return repeated }
        return StatementCloud.Repeat(name: repeated.name, cycle: repeated.cycle, customDays: repeated.customDays, amount: repeated.amount,
                                     dates: repeated.dates, category: repeated.category, endsOn: nil, guessed: repeated.guessed,
                                     reason: repeated.reason, sightings: repeated.sightings)
    }

    private static func left(_ rows: [StatementCandidate], after runs: [Run]) -> [StatementCandidate] {
        let used = Set(runs.flatMap(\.rows).map(\.id))
        return rows.filter { !used.contains($0.id) }
    }

    // MARK: the two rules

    /// The same amount on the same line, one sighting a month: a line seen twice in a month
    /// is not a monthly charge, so that month breaks the run.
    private static func sameLineRuns(_ rows: [StatementCandidate], ends: [Int]?) -> [Run] {
        var order: [String] = []
        var groups: [String: [StatementCandidate]] = [:]
        for row in rows {
            guard let line = lineKey(row.line.payee) else { continue }
            let key = "\(row.direction ?? "out")|\(String(format: "%.2f", row.line.amount))|\(line)"
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(row)
        }
        return order.compactMap { key in
            monthly(groups[key] ?? [], ends: ends).map { Run(rows: $0, rule: .sameLine) }
        }
    }

    /// One person's payments that fit together, longest first, each line in one run at most.
    /// The holder's own lines and transfers are no payment to anyone.
    private static func samePersonRuns(_ rows: [StatementCandidate], ends: [Int]?, holders: [String]) -> [Run] {
        var order: [String] = []
        var groups: [String: [StatementCandidate]] = [:]
        for row in rows where !row.isTransfer {
            guard let person = row.member?.trimmingCharacters(in: .whitespaces), !person.isEmpty,
                  !holders.contains(where: { StatementHolder.same(person, $0) }) else { continue }
            let key = "\(row.direction ?? "out")|\(nameKey(person))"
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(row)
        }
        var out: [Run] = []
        for key in order {
            var left = readings(groups[key] ?? [])
            while let best = closest(left, ends: ends) {
                out.append(Run(rows: best, rule: .samePerson))
                let used = Set(best.map(\.id))
                left.removeAll { used.contains($0.row.id) }
            }
        }
        return out
    }

    /// One line as the search reads it, its date parsed once.
    private struct Reading {
        let row: StatementCandidate
        let day: Int?
        let month: Int?
        var amount: Double { row.line.amount }
    }

    /// The lines cheapest first, the order the search slides over them.
    private static func readings(_ rows: [StatementCandidate]) -> [Reading] {
        rows.map { Reading(row: $0, day: day(of: $0.line.date), month: month(of: $0.line.date)) }.sorted { $0.amount < $1.amount }
    }

    static func closest(_ rows: [StatementCandidate], ends: [Int]?) -> [StatementCandidate]? {
        closest(readings(rows), ends: ends)
    }

    /// Whether a day falls in the window that opens on a floor day, a month taken as 31 days.
    private static func fits(_ day: Int, floor: Int) -> Bool {
        (day - floor + 31) % 31 <= daysApart
    }

    /// The longest, then latest, monthly run among one person's lines, within what is allowed.
    /// Every lowest day and lowest amount is a floor. The amounts in reach of a floor slide as
    /// it rises, so each day costs one pass over its lines and a look at each change.
    private static func closest(_ lines: [Reading], ends: [Int]?) -> [StatementCandidate]? {
        let amounts = lines.map(\.amount), days = lines.map(\.day), months = lines.map(\.month)
        guard let first = months.compactMap({ $0 }).min(), let last = months.compactMap({ $0 }).max() else { return nil }
        let floors = amounts.reduce(into: [Double]()) { if $0.last != $1 { $0.append($1) } }
        let span = last - first + 1
        let allowed = ends?.map { $0 - first }
        var best: (count: Int, date: String, day: Int, amount: Double)?
        for floorDay in Set(days.compactMap { $0 }).sorted() {
            let onDays = days.indices.filter { days[$0].map { fits($0, floor: floorDay) } ?? false }
            // Per month: how many lines are in reach, and the sum of their places, which is the
            // place of the one line when one is all it holds.
            var counts = [Int](repeating: 0, count: span)
            var places = [Int](repeating: 0, count: span)
            var once = MonthBits(span: span)
            func change(_ place: Int, by step: Int) {
                guard let month = months[place] else { return }
                counts[month - first] += step
                places[month - first] += step * place
                once.set(month - first, to: counts[month - first] == 1)
            }
            var low = 0, high = 0
            for floorAmount in floors {
                var moved = false
                while high < onDays.count, !(amounts[onDays[high]] > floorAmount * amountRatio + 0.005) {
                    change(onDays[high], by: 1)
                    high += 1
                    moved = true
                }
                while low < high, amounts[onDays[low]] < floorAmount {
                    change(onDays[low], by: -1)
                    low += 1
                    moved = true
                }
                guard moved, let run = once.bestRun(ends: allowed), run.length >= 2, run.length >= best?.count ?? 0 else { continue }
                let date = lines[places[run.end]].row.line.date
                if run.length > best?.count ?? 0 || date > best?.date ?? "" {
                    best = (run.length, date, floorDay, floorAmount)
                }
            }
        }
        guard let best else { return nil }
        let chosen = lines.filter { line in
            guard let day = line.day, fits(day, floor: best.day) else { return false }
            return !(line.amount < best.amount) && !(line.amount > best.amount * amountRatio + 0.005)
        }
        return monthly(chosen.map(\.row), ends: ends)
    }

    /// Which months of a span hold one line, as bits, so a run is found in a few steps. Past
    /// what one word holds it reads them one by one.
    private struct MonthBits {
        private var word: UInt64 = 0
        private var long: Set<Int>?

        init(span: Int) {
            if span > 64 { long = [] }
        }

        mutating func set(_ month: Int, to on: Bool) {
            if long != nil {
                if on { long?.insert(month) } else { long?.remove(month) }
            } else if on {
                word |= 1 << UInt64(month)
            } else {
                word &= ~(1 << UInt64(month))
            }
        }

        /// The longest run allowed. Among `ends` the first of the longest; with none, the latest.
        func bestRun(ends: [Int]?) -> (end: Int, length: Int)? {
            if let long {
                return StatementRepeats.bestEnd(in: long, ends: ends).map { ($0, StatementRepeats.runLength(endingAt: $0, in: long)) }
            }
            if let ends {
                var best: (end: Int, length: Int)?
                for end in ends where (0..<64).contains(end) && word & (1 << UInt64(end)) != 0 {
                    let length = (~(word << UInt64(63 - end))).leadingZeroBitCount
                    if length > (best?.length ?? 0) { best = (end, length) }
                }
                return best
            }
            guard word != 0 else { return nil }
            // Each step keeps a month only if the month before it is kept: what is kept last
            // are the ends of the longest runs.
            var kept = word, length = 0, ends = word
            while kept != 0 {
                ends = kept
                kept &= kept << 1
                length += 1
            }
            return (63 - ends.leadingZeroBitCount, length)
        }
    }

    /// The months these lines hold once each, as the longest consecutive run of two or more.
    /// With `ends`, only a run ending in one of those months counts.
    static func monthly(_ rows: [StatementCandidate], ends: [Int]?) -> [StatementCandidate]? {
        let byMonth = Dictionary(grouping: rows) { month(of: $0.line.date) ?? 0 }.filter { $0.key != 0 && $0.value.count == 1 }
        let months = Set(byMonth.keys)
        guard let end = bestEnd(in: months, ends: ends) else { return nil }
        let length = runLength(endingAt: end, in: months)
        guard length >= 2 else { return nil }
        return ((end - length + 1)...end).compactMap { byMonth[$0]?.first }
    }

    /// The month a longest run ends in: the first of `ends` that has one, or the latest.
    private static func bestEnd(in months: Set<Int>, ends: [Int]?) -> Int? {
        let ends = ends ?? months.filter { !months.contains($0 + 1) }.sorted(by: >)
        return ends.filter({ months.contains($0) }).max(by: { runLength(endingAt: $0, in: months) < runLength(endingAt: $1, in: months) })
    }

    // MARK: gathering

    /// A run over the proposals. A monthly proposal holding it all stands. One whose lines are
    /// all in the run takes the rest, a monthly one first. With neither it is a new repeat. A
    /// proposal holding part of it keeps what still stands.
    private static func gather(_ run: Run, into out: inout Settled, top: Int, latest: Int) {
        let monthlyCycle = BillingCycle.monthly.rawValue
        let ids = Set(run.rows.map(\.id))
        let runDays = Set(run.rows.map(\.line.date))
        let holding = out.repeats.indices.filter { out.repeats[$0].dates.contains(where: runDays.contains) }
            .map { (at: $0, rows: carried(out.repeats[$0], in: out.candidates)) }
            .filter { $0.rows.contains { ids.contains($0.id) } }
        if holding.contains(where: { held in
            out.repeats[held.at].cycle == monthlyCycle && ids.isSubset(of: Set(held.rows.map(\.id)))
        }) { return }
        let within = holding.filter { held in held.rows.allSatisfy { ids.contains($0.id) } }.map(\.at)
        let keep = within.first { out.repeats[$0].cycle == monthlyCycle } ?? within.first
        if let keep {
            let held = out.repeats[keep]
            let same = held.cycle == monthlyCycle
            rename(ids, to: held.name, in: &out.candidates)
            out.repeats[keep] = StatementCloud.Repeat(name: held.name, cycle: monthlyCycle, customDays: nil, amount: same ? held.amount : commonAmount(run.rows),
                                                      dates: days(run.rows), category: held.category ?? commonTag(run.rows), endsOn: held.endsOn,
                                                      guessed: same ? held.guessed : true, reason: same ? held.reason : reason(run.rule), sightings: keys(run.rows))
            out.widened += 1
        }
        for held in holding.reversed() where held.at != keep {
            let rest = held.rows.filter { !ids.contains($0.id) }
            if rest.isEmpty || (out.repeats[held.at].cycle == monthlyCycle && !standsMonthly(rest, top: top, latest: latest)) {
                out.repeats.remove(at: held.at)
            } else {
                out.repeats[held.at] = out.repeats[held.at].gathering(dates: days(rest), sightings: keys(rest))
            }
        }
        if keep == nil {
            let name = commonName(run.rows)
            rename(ids, to: name, in: &out.candidates)
            out.repeats.append(StatementCloud.Repeat(name: name, cycle: monthlyCycle, customDays: nil, amount: commonAmount(run.rows),
                                                     dates: days(run.rows), category: commonTag(run.rows), endsOn: nil,
                                                     guessed: true, reason: reason(run.rule), sightings: keys(run.rows)))
            if run.rule == .sameLine { out.addedBySameLine += 1 } else { out.addedBySamePerson += 1 }
        }
    }

    /// Whether lines left over from a monthly proposal are monthly by themselves: two or more
    /// consecutive months, ending in the latest month read or the month before. If not, they
    /// stay one-time charges.
    private static func standsMonthly(_ rows: [StatementCandidate], top: Int, latest: Int) -> Bool {
        let months = Set(rows.compactMap { month(of: $0.line.date) }).filter { !($0 > top) }
        guard let last = months.max(), !(last < latest - 1) else { return false }
        return runLength(endingAt: last, in: months) >= 2
    }

    /// The kept lines a repeat will gather when written.
    private static func carried(_ repeated: StatementCloud.Repeat, in candidates: [StatementCandidate]) -> [StatementCandidate] {
        candidates.filter { row in
            row.keep && nameKey(row.name) == nameKey(repeated.name) && repeated.dates.contains(row.line.date)
                && (repeated.sightings.isEmpty || repeated.sightings.contains(StatementCompleteness.key(row.line.date, row.line.amount)))
        }
    }

    private static func days(_ rows: [StatementCandidate]) -> [String] {
        Array(Set(rows.map(\.line.date))).sorted()
    }

    private static func keys(_ rows: [StatementCandidate]) -> Set<String> {
        Set(rows.map { StatementCompleteness.key($0.line.date, $0.line.amount) })
    }

    private static func rename(_ ids: Set<String>, to name: String, in candidates: inout [StatementCandidate]) {
        for at in candidates.indices where ids.contains(candidates[at].id) { candidates[at].name = name }
    }

    /// The name most of the lines carry; on a tie, the latest line's.
    private static func commonName(_ rows: [StatementCandidate]) -> String {
        var counts: [String: Int] = [:]
        for row in rows { counts[row.name, default: 0] += 1 }
        return rows.reversed().max { (counts[$0.name] ?? 0) < (counts[$1.name] ?? 0) }?.name ?? ""
    }

    private static func commonAmount(_ rows: [StatementCandidate]) -> Double {
        Dictionary(rows.map { ($0.line.amount, 1) }, uniquingKeysWith: +).max { ($0.value, $0.key) < ($1.value, $1.key) }?.key ?? 0
    }

    private static func commonTag(_ rows: [StatementCandidate]) -> String? {
        Dictionary(rows.compactMap(\.tag).map { ($0, 1) }, uniquingKeysWith: +).max { ($0.value, $0.key) < ($1.value, $1.key) }?.key
    }

    // MARK: guessed or plain

    /// Three months or more in a row stand plain; anything less is a guess, with its reason.
    private static func standing(_ repeated: StatementCloud.Repeat, run: Int) -> StatementCloud.Repeat {
        let said = repeated.guessed ? repeated.reason : ""
        let fallback = run == 2 ? "Seen in two consecutive months; monthly assumed." : "Seen in one recent month; monthly assumed."
        return StatementCloud.Repeat(name: repeated.name, cycle: repeated.cycle, customDays: repeated.customDays, amount: repeated.amount,
                                     dates: repeated.dates, category: repeated.category, endsOn: repeated.endsOn, guessed: run < 3,
                                     reason: said.isEmpty ? fallback : said, sightings: repeated.sightings)
    }

    private static func reason(_ rule: Rule) -> String {
        switch rule {
        case .sameLine: return "The same amount on the same line in two consecutive months; monthly assumed."
        case .samePerson: return "The same person paid in two consecutive months, within 7 days and 20% of each other; monthly assumed."
        }
    }

    private static func runLength(endingAt end: Int, in months: Set<Int>) -> Int {
        var length = 0
        while months.contains(end - length) { length += 1 }
        return length
    }

    // MARK: reading a day and a line

    /// A day's month as one count, so consecutive months differ by one across a year's end.
    static func month(of date: String) -> Int? {
        let parts = date.split(separator: "-")
        guard parts.count == 3, let year = Int(parts[0]), let month = Int(parts[1]) else { return nil }
        return year * 12 + month
    }

    private static func day(of date: String) -> Int? {
        let parts = date.split(separator: "-")
        return parts.count == 3 ? Int(parts[2]) : nil
    }

    /// Month words a bank prints as a reference: "SALARY OCT" and "SALARY NOV" are one line.
    private static let monthWords: Set<String> = [
        "jan", "january", "feb", "february", "mar", "march", "apr", "april", "may", "jun", "june", "jul", "july",
        "aug", "august", "sep", "sept", "september", "oct", "october", "nov", "november", "dec", "december",
    ]

    /// The most of a line compared: a narration is cut to length after its numbers go, so the
    /// same line can end a few letters apart.
    private static let lineKeyLimit = 60

    /// A line as it is compared: any word with a digit is a reference and goes, month words too.
    /// Nil when only a bank's own words are left, which names no one.
    static func lineKey(_ payee: String) -> String? {
        let words = payee.lowercased().split(whereSeparator: { !($0.isLetter || $0.isNumber || $0 == "@" || $0 == ".") }).map(String.init)
        let kept = words.filter { !$0.contains(where: \.isNumber) && !monthWords.contains($0) }
        guard kept.contains(where: { $0.count >= 3 && !StatementNaming.noise.contains($0.uppercased()) }) else { return nil }
        return String(kept.joined(separator: " ").prefix(lineKeyLimit))
    }
}
