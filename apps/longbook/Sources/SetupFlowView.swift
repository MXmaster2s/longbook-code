import DesignSystem
import LongbookCore
import SwiftUI

/// Setup for a book: five screens, each one question. Commitments by name, the accounts
/// the money sits in, the people it is for, a count of what is there, and last the
/// statement that fills the history. Every screen can be passed over; More reopens it.
struct SetupFlowView: View {
    enum Step: Int, CaseIterable {
        case commitments, accounts, members, summary, statement
    }

    let model: DashboardModel
    @ObservedObject var auth: AuthViewModel
    /// Opened again from More: a close control shows, and what the book holds is ticked.
    let replay: Bool
    let onDone: () -> Void

    @State private var step: Step
    /// What the commitments screen chose, so the people screen can tick who they imply.
    @State private var named: [String] = []
    /// Why Continue wrote no account or person for a name: the step stays, saying so above
    /// its Continue. The names it did write stay written, and a second Continue skips them.
    @State private var refusal: String?
    /// The seconds shown in the header run from the first screen and freeze on the first
    /// arrival at the count, on a first run and on a replay alike. A flow opened at the
    /// count or later shows none.
    private let timed: Bool
    @State private var startedAt = Date()
    @State private var stoppedAt: Date?

    init(model: DashboardModel, auth: AuthViewModel, step: Step = .commitments, replay: Bool = false, onDone: @escaping () -> Void) {
        self.model = model
        self.auth = auth
        self.replay = replay
        self.onDone = onDone
        self.timed = step.rawValue < Step.summary.rawValue
        _step = State(initialValue: step)
    }

    var body: some View {
        VStack(spacing: 0) {
            progress
            switch step {
            case .commitments:
                SetupPickerView(
                    kicker: "Quick select",
                    title: "Your commitments in longbook",
                    blurb: "Select all which are relevant for you.",
                    groups: CommitmentSuggestions.groups,
                    noun: ("commitment", "commitments"),
                    initial: initialCommitments,
                    onDone: { chosen in
                        named = chosen.map(\.name)
                        model.setPlaceholders(chosen.filter { !model.hasCommitment(named: $0.name) })
                        model.markCommitmentsAsked()
                        advance()
                    },
                    onSkip: {
                        model.markCommitmentsAsked()
                        advance()
                    },
                    onBack: replay ? onDone : nil
                )
                .id(Step.commitments)
            case .accounts:
                SetupBanksView(
                    initial: initialAccounts,
                    refusal: refusal,
                    onDone: { chosen in
                        var refused: String?
                        for account in chosen where !Self.has(account.name, in: model.accountNames) {
                            guard let id = model.addEntity(.paymentMethod, named: account.name) else {
                                refused = model.saveError ?? "That didn’t save."
                                continue
                            }
                            model.setEntityDetails(.paymentMethod, id: id, accountTag: .some(account.tag))
                        }
                        stayOrAdvance(refused)
                    },
                    onSkip: advance,
                    onBack: back
                )
                .id(Step.accounts)
            case .members:
                SetupPickerView(
                    kicker: "Quick select",
                    title: "Who do you pay for?",
                    blurb: "Tap everyone that applies.",
                    groups: CommitmentSuggestions.memberGroups,
                    noun: ("person", "people"),
                    initial: initialMembers,
                    refusal: refusal,
                    onDone: { chosen in
                        // A pick here is a role. The person wears it as their tag, so a later
                        // rename to their own name keeps "Wife" or "Landlord" beside it.
                        var refused: String?
                        for person in chosen where !Self.has(person.name, in: model.memberNames) {
                            guard let id = model.addEntity(.familyMember, named: person.name) else {
                                refused = model.saveError ?? "That didn’t save."
                                continue
                            }
                            guard Self.isRole(person.name) else { continue }
                            model.setEntityDetails(.familyMember, id: id, memberTag: .some(person.name))
                        }
                        stayOrAdvance(refused)
                    },
                    onSkip: advance,
                    onBack: back
                )
                .id(Step.members)
            case .summary:
                summary
                    .id(Step.summary)
            case .statement:
                StatementImportView(model: model, auth: auth, setup: true, onBack: back, onDone: onDone)
                    .id(Step.statement)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LBColor.canvas.color)
    }

    // MARK: what is ticked from the start

    /// Setup's earlier answer, plus any suggestion the book already holds as a commitment.
    private var initialCommitments: [CommitmentPlaceholder] {
        var out = model.placeholders
        for group in CommitmentSuggestions.groups {
            for name in group.suggestions where model.hasCommitment(named: name) && !out.contains(where: { Self.same($0.name, name) }) {
                if let placeholder = CommitmentSuggestions.placeholder(name, in: group) { out.append(placeholder) }
            }
        }
        return out
    }

    /// The book's accounts, each under the group its kind names — a suggestion when one
    /// matches, otherwise as its own pill.
    private var initialAccounts: [CommitmentPlaceholder] {
        let groups = CommitmentSuggestions.accountGroups
        return model.editChoices.methods.compactMap { method in
            if let group = groups.first(where: { $0.suggestions.contains { Self.same($0, method.name) } }) {
                return CommitmentSuggestions.placeholder(method.name, in: group)
            }
            let tag = model.entityDetails(.paymentMethod, id: method.id).accountTag
            let group = groups.first { $0.tag == tag } ?? groups[0]
            return CommitmentSuggestions.placeholder(method.name, in: group)
        }
    }

    /// The book's people, then whoever the chosen commitments say is there — a wife's
    /// insurance means a wife, a cook's salary a cook — ticked, editable, and easily untucked.
    private var initialMembers: [CommitmentPlaceholder] {
        guard let group = CommitmentSuggestions.memberGroups.first else { return [] }
        var out: [CommitmentPlaceholder] = []
        func add(_ name: String) {
            guard !out.contains(where: { Self.same($0.name, name) }),
                  let placeholder = CommitmentSuggestions.placeholder(name, in: group) else { return }
            out.append(placeholder)
        }
        model.memberNames.forEach(add)
        let commitments = named.isEmpty ? model.placeholders.map(\.name) + model.editChoices.names : named
        Self.impliedMembers(from: commitments).forEach(add)
        return out
    }

    /// True for a word setup itself offers — "Wife", "Cook" — and false for a name the owner
    /// typed, which is a person and never a role.
    static func isRole(_ name: String) -> Bool {
        let offered = CommitmentSuggestions.memberGroups.flatMap(\.suggestions)
            + ["Maid", "Cook", "Nanny", "Driver", "Gardener", "Tutor", "Car washer"]
        return offered.contains { same($0, name) }
    }

    /// Who a commitment's name says is in the owner's life. Relations by their word; staff
    /// by their role, since the app names household help that way until a name is given.
    static func impliedMembers(from names: [String]) -> [String] {
        var out: [String] = []
        func add(_ name: String) {
            if !out.contains(where: { same($0, name) }) { out.append(name) }
        }
        for name in names {
            let lower = name.lowercased()
            let words = Set(lower.split(whereSeparator: { !$0.isLetter }).map(String.init))
            if words.contains("self") { add("Self") }
            if words.contains("wife") { add("Wife") }
            if words.contains("husband") { add("Husband") }
            if words.contains("parents") { add("Mother"); add("Father") }
            for relation in ["mother", "father", "brother", "sister", "son", "daughter"] where words.contains(relation) {
                add(relation.capitalized)
            }
            for role in ["maid", "cook", "nanny", "driver", "gardener", "tutor"] where words.contains(role) {
                add(role.capitalized)
            }
            if lower.contains("car washer") { add("Car washer") }
        }
        return out
    }

    private static func same(_ a: String, _ b: String) -> Bool {
        a.trimmingCharacters(in: .whitespaces).caseInsensitiveCompare(b.trimmingCharacters(in: .whitespaces)) == .orderedSame
    }

    private static func has(_ name: String, in list: [String]) -> Bool {
        list.contains { same($0, name) }
    }

    // MARK: the count

    /// What the book holds after three screens, and the way back to any of them.
    private var summary: some View {
        let commitments = model.commitmentCount + model.placeholders.count
        let accounts = model.accountNames.count
        let members = model.memberNames.count
        return VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: LBSpacing.s6) {
                    VStack(alignment: .leading, spacing: LBSpacing.s2) {
                        Text("Confirm details")
                            .lbText(.label)
                            .foregroundStyle(LBColor.brandText.color)
                        Text("Your commitments, accounts & people in longbook")
                            .lbText(.displayLG)
                            .foregroundStyle(LBColor.textPrimary.color)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("You can add or edit more details later.")
                            .lbText(.bodySM)
                            .foregroundStyle(LBColor.textSecondary.color)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, LBSpacing.s2)
                    HStack(spacing: LBSpacing.s3) {
                        count(commitments, "commitments")
                        count(accounts, "accounts")
                        count(members, "members")
                    }
                    VStack(alignment: .leading, spacing: LBSpacing.s2) {
                        Text("Missed something? Add more.")
                            .lbText(.body)
                            .foregroundStyle(LBColor.textPrimary.color)
                        LBFlow {
                            LBChip("Commitments", symbol: "plus", style: .accent) { go(.commitments) }
                            LBChip("Accounts", symbol: "plus", style: .accent) { go(.accounts) }
                            LBChip("People", symbol: "plus", style: .accent) { go(.members) }
                        }
                    }
                }
                .padding(LBSpacing.s4)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            VStack(spacing: LBSpacing.s3) {
                Rectangle().fill(LBColor.hairline.color).frame(height: 1)
                Button(action: { Measure.used("continue"); advance() }) {
                    Text("Continue")
                        .lbText(.body)
                        .foregroundStyle(LBColor.onBrand.color)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, LBSpacing.s3)
                        .background(LBColor.brand.color, in: RoundedRectangle(cornerRadius: LBRadius.sm, style: .continuous))
                }
                .lbButtonStyle(shape: RoundedRectangle(cornerRadius: LBRadius.sm, style: .continuous))
            }
            .padding(.horizontal, LBSpacing.s4)
            .padding(.bottom, LBSpacing.s4)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .contentShape(Rectangle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 40).onEnded { drag in
                guard abs(drag.translation.width) > abs(drag.translation.height) * 1.5 else { return }
                if drag.translation.width < 0 { advance() } else { back() }
            }
        )
    }

    private func count(_ number: Int, _ word: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(number)")
                .lbText(.displayLG)
                .foregroundStyle(LBColor.textPrimary.color)
                .monospacedDigit()
            Text(word)
                .lbText(.footnote)
                .foregroundStyle(LBColor.textTertiary.color)
        }
        .frame(maxWidth: .infinity)
        .padding(LBSpacing.s3)
        .background(LBColor.card.color, in: RoundedRectangle(cornerRadius: LBRadius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: LBRadius.md, style: .continuous)
                .strokeBorder(LBColor.hairline.color, lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }

    // MARK: the way through

    /// The flow's one heading, five marks with the ones passed filled, a position in words
    /// and the seconds; a way back a step, and out altogether when setup was reopened.
    private var progress: some View {
        let steps = Step.allCases
        return VStack(spacing: LBSpacing.s2) {
            Text("Set up your longbook in 60 seconds")
                .lbText(.screenTitle)
                .foregroundStyle(LBColor.textPrimary.color)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: LBSpacing.s1) {
                ForEach(steps, id: \.rawValue) { mark in
                    Capsule()
                        .fill(mark.rawValue <= step.rawValue ? LBColor.brand.color : LBColor.hairline.color)
                        .frame(height: 3)
                }
                Text("Step \(step.rawValue + 1) of \(steps.count)")
                    .lbText(.footnote)
                    .foregroundStyle(LBColor.textTertiary.color)
                    .fixedSize()
                timer
            }
            if step != .commitments || replay {
                HStack {
                    if step != .commitments {
                        Button(action: { Measure.used("arrow_left"); back() }) {
                            Image(systemName: "arrow.left")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(LBColor.textSecondary.color)
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .lbButtonStyle()
                        .accessibilityLabel("Go back a step")
                    }
                    Spacer()
                    if replay {
                        Button(action: { Measure.used("close"); onDone() }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(LBColor.textSecondary.color)
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .lbButtonStyle()
                        .accessibilityLabel("Close setup")
                    }
                }
            }
        }
        .padding(.horizontal, LBSpacing.s4)
        .padding(.top, LBSpacing.s3)
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
    }

    private func advance() {
        guard let next = Step(rawValue: step.rawValue + 1) else {
            onDone()
            return
        }
        go(next)
    }

    private func back() {
        guard let previous = Step(rawValue: step.rawValue - 1) else { return }
        go(previous)
    }

    private func go(_ next: Step) {
        refusal = nil
        if next == .summary, stoppedAt == nil { stoppedAt = Date() }
        withAnimation(.easeOut(duration: 0.2)) { step = next }
    }

    /// A Continue whose every name was written moves on. One refused keeps the step, its
    /// refusal above Continue, felt and announced as a form's refused name is.
    private func stayOrAdvance(_ refused: String?) {
        guard let refused else {
            advance()
            return
        }
        refusal = refused
        LBHaptics.warn()
        AccessibilityNotification.Announcement(refused).post()
    }

    // MARK: the seconds

    /// Counts down from 60, then up to a ceiling of 500; frozen with a mark once the count
    /// screen has been reached.
    @ViewBuilder
    private var timer: some View {
        if let stoppedAt {
            clock(seconds(at: stoppedAt), frozen: true)
        } else if timed {
            TimelineView(.periodic(from: startedAt, by: 1)) { context in
                clock(seconds(at: context.date), frozen: false)
            }
        }
    }

    private func clock(_ seconds: Int, frozen: Bool) -> some View {
        HStack(spacing: 2) {
            if frozen {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .semibold))
            }
            Text("\(seconds)s")
                .lbText(.footnote)
                .monospacedDigit()
                .fixedSize()
        }
        .foregroundStyle(frozen ? LBColor.mintTint.color : LBColor.textTertiary.color)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(seconds) seconds")
    }

    private func seconds(at date: Date) -> Int {
        let elapsed = max(0, Int(date.timeIntervalSince(startedAt)))
        return elapsed <= 60 ? 60 - elapsed : min(elapsed, 500)
    }
}
