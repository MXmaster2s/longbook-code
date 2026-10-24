import DesignSystem
import LongbookCore
import SwiftUI

/// A trip asked for the way setup asks: who went, which accounts paid, the days (for a trip
/// that is over), and its name. The answer is a report, narrowed to those people, accounts
/// and days. Choosing nobody, or no account, counts everyone's.
struct TripFlowView: View {
    enum Mode: String, Identifiable {
        /// From today, until the owner ends it.
        case start
        /// A trip that is over: its own first and last day.
        case past
        var id: String { rawValue }
    }

    let model: DashboardModel
    let mode: Mode
    let onCreated: (String) -> Void
    let onClose: () -> Void

    private enum Step: Int {
        case members, accounts, dates, name
    }

    @State private var step: Step = .members
    @State private var members: [String] = []
    @State private var accounts: [String] = []
    @State private var first = LB.addDays(LB.todayMid(), -7)
    @State private var last = LB.addDays(LB.todayMid(), -1)
    @State private var pickingFirst = false
    @State private var pickingLast = false
    @State private var name = ""
    @State private var adding = false
    @State private var typed = ""
    @FocusState private var typing: Bool
    @FocusState private var naming: Bool
    @State private var refusal: String?

    private var steps: [Step] { mode == .start ? [.members, .accounts, .name] : [.members, .accounts, .dates, .name] }
    private var position: Int { steps.firstIndex(of: step) ?? 0 }

    var body: some View {
        VStack(spacing: 0) {
            progress
            ScrollView {
                VStack(alignment: .leading, spacing: LBSpacing.s6) {
                    question
                    content
                }
                .padding(LBSpacing.s4)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LBColor.canvas.color)
        #if os(macOS)
        .frame(minWidth: 520, minHeight: 640)
        #endif
        .onAppear {
            #if DEBUG
            // The snapshot harness opens a step with the first people and accounts ticked.
            let env = ProcessInfo.processInfo.environment
            if let named = env["LONGBOOK_SNAPSHOT_STEP"], let wanted = steps.first(where: { "\($0)" == named }) {
                members = Array(model.memberNames.prefix(2))
                accounts = Array(model.accountNames.prefix(1))
                name = wanted == .name ? (mode == .start ? "Goa" : "Pune, Diwali") : ""
                step = wanted
            }
            #endif
        }
    }

    // MARK: the way through

    private var progress: some View {
        VStack(spacing: LBSpacing.s2) {
            HStack(alignment: .firstTextBaseline) {
                Text(mode == .start ? "Start a trip" : "Add a past trip")
                    .lbText(.screenTitle)
                    .foregroundStyle(LBColor.textPrimary.color)
                Spacer()
                Button(action: { Measure.used("close"); onClose() }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(LBColor.textSecondary.color)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
            }
            HStack(spacing: LBSpacing.s1) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, _ in
                    Capsule()
                        .fill(index <= position ? LBColor.brand.color : LBColor.hairline.color)
                        .frame(height: 3)
                }
                Text("Step \(position + 1) of \(steps.count)")
                    .lbText(.footnote)
                    .foregroundStyle(LBColor.textTertiary.color)
                    .fixedSize()
            }
            if position > 0 {
                HStack {
                    Button(action: { Measure.used("arrow_left"); back() }) {
                        Image(systemName: "arrow.left")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(LBColor.textSecondary.color)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Go back a step")
                    Spacer()
                }
            }
        }
        .padding(.horizontal, LBSpacing.s4)
        .padding(.top, LBSpacing.s3)
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity)
    }

    private func back() {
        guard position > 0 else { return }
        go(steps[position - 1])
    }

    private func advance() {
        // A name typed into the plus and not yet submitted is still the owner's answer.
        if adding, !typed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if step == .members { add(.familyMember, into: $members) }
            if step == .accounts { add(.paymentMethod, into: $accounts) }
            if refusal != nil { return }
        }
        guard position + 1 < steps.count else { return create() }
        go(steps[position + 1])
    }

    private func go(_ next: Step) {
        refusal = nil
        adding = false
        withAnimation(.easeOut(duration: 0.2)) { step = next }
    }

    // MARK: the question

    private var question: some View {
        VStack(alignment: .leading, spacing: LBSpacing.s2) {
            Text(mode == .start ? "Trip mode" : "Past trip")
                .lbText(.label)
                .foregroundStyle(LBColor.brandText.color)
            Text(title)
                .lbText(.displayLG)
                .foregroundStyle(LBColor.textPrimary.color)
                .fixedSize(horizontal: false, vertical: true)
            Text(blurb)
                .lbText(.bodySM)
                .foregroundStyle(LBColor.textSecondary.color)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, LBSpacing.s2)
    }

    private var title: String {
        switch step {
        case .members: "Trip people"
        case .accounts: "Trip accounts"
        case .dates: "Trip dates"
        case .name: "Trip name"
        }
    }

    private var blurb: String {
        switch step {
        case .members:
            (mode == .start ? "The people travelling." : "The people on the trip.")
                + " Only charges written for them are counted; choose nobody to count every charge."
        case .accounts: "The cards and accounts the trip is paid from. Choose none to count every account."
        case .dates: "The first and last day of the trip. Confirmed charges on those days are counted."
        case .name:
            mode == .start
                ? "What the trip’s report is called. It counts from today until the trip is ended."
                : "What the trip’s report is called, in Reports and in Trips."
        }
    }

    // MARK: the answers

    @ViewBuilder
    private var content: some View {
        switch step {
        case .members: chips(model.memberNames, chosen: $members, kind: .familyMember)
        case .accounts: chips(model.accountNames, chosen: $accounts, kind: .paymentMethod)
        case .dates: dates
        case .name: nameField
        }
    }

    /// The names the book holds as pills, and a plus for one it does not: typed names are
    /// made real, as setup makes them, so the report's scope names a real person or account.
    private func chips(_ names: [String], chosen: Binding<[String]>, kind: VaultPatch.EntityKind) -> some View {
        LBFlow {
            ForEach(names, id: \.self) { item in
                let picked = chosen.wrappedValue.contains(item)
                LBChip(item, style: .choice(selected: picked)) {
                    LBHaptics.tap()
                    if picked { chosen.wrappedValue.removeAll { $0 == item } } else { chosen.wrappedValue.append(item) }
                }
                .accessibilityAddTraits(picked ? [.isSelected] : [])
            }
            if adding {
                LBChipField(kind == .familyMember ? "Name" : "Account", text: $typed, width: 160, focus: $typing) {
                    add(kind, into: chosen)
                }
            } else {
                LBChip("Add", symbol: "plus", style: .accent) {
                    typed = ""
                    adding = true
                    typing = true
                }
                .accessibilityLabel(kind == .familyMember ? "Add a person" : "Add an account")
            }
        }
    }

    private func add(_ kind: VaultPatch.EntityKind, into chosen: Binding<[String]>) {
        let wanted = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        adding = false
        typed = ""
        guard !wanted.isEmpty else { return }
        // Matched as the book matches names, so "HDFC  Regalia" is the HDFC Regalia already there.
        let names = { kind == .familyMember ? model.memberNames : model.accountNames }
        if let existing = names().first(where: { nameKey($0) == nameKey(wanted) }) {
            if !chosen.wrappedValue.contains(existing) { chosen.wrappedValue.append(existing) }
            return
        }
        guard model.addEntity(kind, named: wanted) != nil else {
            refusal = model.saveError ?? "That name could not be added."
            return
        }
        let stored = names().first { nameKey($0) == nameKey(wanted) } ?? wanted
        if !chosen.wrappedValue.contains(stored) { chosen.wrappedValue.append(stored) }
    }

    private var dates: some View {
        let today = LB.todayMid()
        return VStack(alignment: .leading, spacing: LBSpacing.s4) {
            FormDateControl(title: "First day", date: $first, picking: $pickingFirst, latest: min(last, today))
            FormDateControl(title: "Last day", date: $last, picking: $pickingLast, earliest: first, latest: today)
        }
    }

    private var nameField: some View {
        FormField {
            TextField("", text: $name, prompt: Text("Goa, Diwali at home, Mum’s visit").foregroundStyle(LBColor.textTertiary.color))
                .textFieldStyle(.plain)
                .lbText(.body)
                .foregroundStyle(LBColor.textPrimary.color)
                .focused($naming)
                .onSubmit { if canFinish { create() } }
        }
        .onAppear { naming = true }
    }

    // MARK: the tally

    private var canFinish: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var footer: some View {
        VStack(spacing: LBSpacing.s3) {
            Rectangle().fill(LBColor.hairline.color).frame(height: 1)
            tally
            if let refusal {
                Text(refusal)
                    .lbText(.footnote)
                    .foregroundStyle(LBColor.urgent.color)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            let finishing = step == .name
            Button {
                Measure.used("start_trip")
                advance()
            } label: {
                Text(finishing ? (mode == .start ? "Start Trip" : "Add Trip") : "Continue")
                    .lbText(.body)
                    .foregroundStyle((finishing && !canFinish) ? LBColor.textTertiary.color : LBColor.onBrand.color)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, LBSpacing.s3)
                    .background((finishing && !canFinish) ? LBColor.chrome.color : LBColor.brand.color,
                                in: RoundedRectangle(cornerRadius: LBRadius.sm, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(finishing && !canFinish)
        }
        .padding(.horizontal, LBSpacing.s4)
        .padding(.bottom, LBSpacing.s4)
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity)
        .background(LBColor.canvas.color)
    }

    /// What the step has chosen, counted the way setup counts: "2 members", "All accounts".
    @ViewBuilder
    private var tally: some View {
        switch step {
        case .members: count(members.count, one: "member", many: "members")
        case .accounts: count(accounts.count, one: "account", many: "accounts")
        case .dates:
            count((LB.calendar.dateComponents([.day], from: first, to: last).day ?? 0) + 1, one: "day", many: "days", allWhenZero: false)
        case .name:
            Text(summary)
                .lbText(.footnote)
                .foregroundStyle(LBColor.textSecondary.color)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func count(_ n: Int, one: String, many: String, allWhenZero: Bool = true) -> some View {
        HStack(alignment: .lastTextBaseline, spacing: LBSpacing.s2) {
            Text(n == 0 && allWhenZero ? "All" : "\(n)")
                .lbText(.displayLG)
                .foregroundStyle(LBColor.textPrimary.color)
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(.easeOut(duration: 0.2), value: n)
            Text(n == 1 ? one : many)
                .lbText(.bodySM)
                .foregroundStyle(LBColor.textSecondary.color)
            Spacer()
        }
    }

    /// "Rohit, Anita · Amex 1007 · 9–14 October 2026", or "everyone" and "every account".
    private var summary: String {
        let who = members.isEmpty ? "Everyone" : members.joined(separator: ", ")
        let paid = accounts.isEmpty ? "every account" : accounts.joined(separator: ", ")
        let when = mode == .start ? "from today" : Report.rangeWords(start: first, end: last)
        return "\(who) · \(paid) · \(when)"
    }

    // MARK: making it

    private func create() {
        let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        let id = mode == .start
            ? model.startTrip(name: title, members: members, accounts: accounts)
            : model.addPastTrip(name: title, members: members, accounts: accounts, start: first, end: last)
        guard let id else {
            refusal = "The trip could not be saved, because no folder is open."
            LBHaptics.warn()
            return
        }
        LBHaptics.tap()
        onCreated(id)
    }
}
