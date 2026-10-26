import DesignSystem
import LongbookCore
import SwiftUI

/// What the first run remembers while it is open: picks, the card in view, the cards seen
/// and the clock. Owned by the root, so a vault reload that redraws the flow loses nothing.
@Observable
final class OnboardingSession {
    var stage: OnboardingStage
    var waiting: Bool
    /// The demo longbook open over the Waiting screen.
    var showingDemo = false
    let clock = OnboardingClock()
    /// Picks as "card id|chip", so the same word on two cards stays two picks.
    var chosenCommitments: Set<String> = []
    var chosenAccounts: Set<String> = []
    var commitmentCard = 0
    var accountCard = 0
    var seenCommitments: Set<Int> = []
    var seenAccounts: Set<Int> = []

    /// What the book already holds comes back ticked, so a resumed run shows its picks.
    @MainActor
    init(start: OnboardingStage, paused: Bool, model: DashboardModel, replay: Bool = false) {
        stage = start
        waiting = paused
        let waitingNames = Set(model.placeholders.map { $0.name.lowercased() })
        for card in OnboardingCards.commitments {
            for chip in card.chips {
                let name = OnboardingCards.commitmentName(chip, on: card)
                if waitingNames.contains(name.lowercased()) || model.hasCommitment(named: name) { chosenCommitments.insert("\(card.id)|\(chip)") }
            }
        }
        // An account picked before is in the book as a hint, or as an account an older setup made.
        let accountNames = Set((model.accountNames + model.hints.filter { $0.kind == .account }.map(\.name)).map { $0.lowercased() })
        for card in OnboardingCards.accounts {
            for chip in card.chips where accountNames.contains(chip.lowercased()) { chosenAccounts.insert("\(card.id)|\(chip)") }
        }
        if case .commitments(let card) = start { commitmentCard = card; seenCommitments = Set(0..<card) }
        if case .accounts(let card) = start { accountCard = card; seenAccounts = Set(0..<card) }
        if start.step >= 2 { seenCommitments = Set(OnboardingCards.commitments.indices) }
        if start.step >= 3 { seenAccounts = Set(OnboardingCards.accounts.indices) }
        if OnboardingRounds.finished(step: 1) { seenCommitments = Set(OnboardingCards.commitments.indices) }
        if OnboardingRounds.finished(step: 2) { seenAccounts = Set(OnboardingCards.accounts.indices) }
        // Setup run again is a visit, not a first reading: every card is open at once.
        if replay {
            seenCommitments = Set(OnboardingCards.commitments.indices)
            seenAccounts = Set(OnboardingCards.accounts.indices)
        }
    }
}

/// The steps this device has finished once. A finished step opens unlocked when setup runs
/// again: the reading pace is for the first time through, not every time.
enum OnboardingRounds {
    private static func key(_ step: Int) -> String { "onboarding.finished.step\(step)" }
    static func finished(step: Int) -> Bool { UserDefaults.standard.bool(forKey: key(step)) }
    static func markFinished(step: Int) { UserDefaults.standard.set(true, forKey: key(step)) }
}

/// The first run from the first card to the dashboard: commitments, a pause, accounts, a
/// pause, then the history. Every stage is written to the vault's sidecar and the account
/// as it is reached, so a relaunch or a second device resumes from the Waiting screen.
struct OnboardingFlowView: View {
    let model: DashboardModel
    @ObservedObject var auth: AuthViewModel
    @Bindable var session: OnboardingSession
    /// Opened again from More over a book that already holds something: a way out shows.
    let replay: Bool
    let onDone: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if session.showingDemo {
                DemoLongbookView(auth: auth) {
                    withAnimation(.easeOut(duration: 0.3)) { session.showingDemo = false }
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            } else if session.waiting {
                OnboardingWaitingView(commitments: model.commitmentCount + model.placeholders.count, accounts: model.accountNames.count + model.hints.filter { $0.kind == .account }.count,
                                      onResume: { withAnimation(.easeOut(duration: 0.35)) { session.waiting = false } },
                                      onDemo: { withAnimation(.easeOut(duration: 0.3)) { session.showingDemo = true } },
                                      onClose: close)
            } else {
                stageView
                    .transition(OnboardingMotion.push(reduceMotion: reduceMotion))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LBColor.canvas.color)
        .onAppear { Telemetry.shared.send("app.onboarding_stage", ["stage": session.stage.raw, "paused": session.waiting]) }
    }

    /// The way out of a reopened setup; a first run has none.
    private var close: (() -> Void)? { replay ? onDone : nil }

    @ViewBuilder
    private var stageView: some View {
        switch session.stage {
        case .commitments:
            OnboardingCardStep(step: 1, clock: session.clock, title: replay ? "Add more commitments" : "What do you want to remember?",
                               cards: OnboardingCards.commitments, noun: ("commitment", "commitments"),
                               continueTitle: "Continue", chosen: $session.chosenCommitments, card: $session.commitmentCard,
                               seen: $session.seenCommitments, onContinue: finishCommitments,
                               onNotNow: { writeCommitments(); pause(.commitments(card: session.commitmentCard)) }, onClose: close)
                .onChange(of: session.commitmentCard) { _, card in go(.commitments(card: card)) }
                .id("step1")
        case .commitmentsDone:
            OnboardingMilestoneView(step: 1, clock: session.clock, heading: added(commitmentRows.count, "commitment", "commitments"),
                                    summary: commitmentRows.isEmpty ? Self.addLater : nil, rows: commitmentRows,
                                    buttonTitle: "Continue", onContinue: { go(.accounts(card: session.accountCard)) },
                                    onBack: { go(.commitments(card: OnboardingCards.commitments.count - 1)) }, onClose: close)
        case .accounts:
            OnboardingCardStep(step: 2, clock: session.clock, title: replay ? "Add more accounts" : "Which accounts do you pay from?",
                               cards: OnboardingCards.accounts, noun: ("account", "accounts"),
                               continueTitle: "Continue", chosen: $session.chosenAccounts, card: $session.accountCard,
                               seen: $session.seenAccounts, onContinue: finishAccounts,
                               onNotNow: { writeAccounts(); pause(.accounts(card: session.accountCard)) },
                               onBackOut: { go(.commitmentsDone) }, onClose: close)
                .onChange(of: session.accountCard) { _, card in go(.accounts(card: card)) }
                .id("step2")
        case .accountsDone(true):
            // Nothing picked: the way back to the first account card is the main button, the
            // way on to step 3 the quieter one.
            OnboardingMilestoneView(step: 2, clock: session.clock, heading: "No accounts added? That’s fine",
                                    summary: "You can add your accounts to your longbook later.", rows: [],
                                    note: "Your AI sorts your statements better when it knows your accounts.",
                                    buttonTitle: "Add Accounts",
                                    onContinue: { session.accountCard = 0; go(.accounts(card: 0)) },
                                    onBack: { go(.accounts(card: OnboardingCards.accounts.count - 1)) },
                                    secondary: ("Continue", { go(.finish) }), onClose: close)
        case .accountsDone:
            // The picks are hints, not rows: Done goes on, and the cards stay a tap away.
            OnboardingMilestoneView(step: 2, clock: session.clock, heading: "Hints added",
                                    summary: Self.hintsLine, rows: hintRows,
                                    buttonTitle: replay ? "Done" : "Continue",
                                    onContinue: { replay ? finish() : go(.finish) },
                                    onBack: { go(.accounts(card: OnboardingCards.accounts.count - 1)) },
                                    secondary: ("Add more hints", { session.accountCard = 0; go(.accounts(card: 0)) }),
                                    secondaryGoesBack: true, onClose: close)
        case .finish, .done:
            OnboardingFinishView(model: model, auth: auth, clock: session.clock, onDone: finish, onNotNow: finish,
                                 onBack: { go(.accountsDone(empty: session.chosenAccounts.isEmpty)) }, onClose: close,
                                 onDemo: { withAnimation(.easeOut(duration: 0.3)) { session.showingDemo = true } })
        }
    }

    // MARK: what the picks become

    /// The milestone's title: the count added, or that nothing was.
    private func added(_ count: Int, _ one: String, _ many: String) -> String {
        count == 0 ? "Nothing added yet" : "\(count) \(count == 1 ? one : many) added"
    }

    /// Where a commitment is added once the book is open: the phone’s Add tab, the Mac’s sidebar.
    #if os(macOS)
    private static let addLater = "You can add them any time with Add commitment in the sidebar."
    #else
    private static let addLater = "You can add them any time with the Add button."
    #endif

    private var commitmentRows: [OnboardingMilestoneView.Row] {
        picks(in: OnboardingCards.commitments, from: session.chosenCommitments).map { card, chip in
            OnboardingMilestoneView.Row(name: OnboardingCards.commitmentName(chip, on: card), badge: "Add amount later",
                                        tag: OnboardingCards.memberRole(chip, on: card))
        }
    }

    /// What the last step says of the hints: what reads them, and where they are not.
    private static let hintsLine = "Your AI reads these when it sorts your statements. They aren’t added to Accounts or People, so those lists hold only what your statements show."

    /// Every account picked, then every person, each tagged a hint.
    private var hintRows: [OnboardingMilestoneView.Row] {
        let accounts = picks(in: OnboardingCards.accounts, from: session.chosenAccounts).map { $1 }
        let people = picks(in: OnboardingCards.commitments, from: session.chosenCommitments).compactMap { OnboardingCards.memberRole($1, on: $0) }
        return (accounts + people).map { OnboardingMilestoneView.Row(name: $0, badge: "Hint", tag: nil, isHint: true) }
    }

    private func picks(in cards: [OnboardingCard], from chosen: Set<String>) -> [(OnboardingCard, String)] {
        cards.flatMap { card in card.chips.filter { chosen.contains("\(card.id)|\($0)") }.map { (card, $0) } }
    }

    /// The picks become to-fill-in commitments; a person picked becomes a hint wearing the
    /// role, never a member; the owner is the first member.
    private func writeCommitments() {
        let picked = picks(in: OnboardingCards.commitments, from: session.chosenCommitments)
        let placeholders = picked.map { OnboardingCards.placeholder($1, on: $0) }.filter { !model.hasCommitment(named: $0.name) }
        model.setPlaceholders(placeholders)
        model.ensureMember("Self", role: "Self")
        let roles = picked.compactMap { card, chip in OnboardingCards.memberRole(chip, on: card) }
        model.setHints(.member, roles.map { (name: $0, tag: $0) })
        model.markCommitmentsAsked()
    }

    /// Accounts picked by kind are hints for reading statements; a statement adds the real one.
    private func writeAccounts() {
        let picked = picks(in: OnboardingCards.accounts, from: session.chosenAccounts)
        model.setHints(.account, picked.map { card, chip in (name: chip, tag: OnboardingCards.accountTag(chip, on: card)) })
    }

    private func finishCommitments() {
        OnboardingRounds.markFinished(step: 1)
        writeCommitments()
        go(.commitmentsDone)
    }

    private func finishAccounts() {
        OnboardingRounds.markFinished(step: 2)
        writeAccounts()
        go(.accountsDone(empty: session.chosenAccounts.isEmpty))
    }

    private func finish() {
        model.setOnboardingStage(.done)
        Telemetry.shared.send("app.onboarding_done", ["seconds": Int(Date().timeIntervalSince(session.clock.startedAt))])
        onDone()
    }

    // MARK: moving

    private func go(_ next: OnboardingStage) {
        model.setOnboardingStage(next)
        withAnimation(OnboardingMotion.step) { session.stage = next }
    }

    private func pause(_ at: OnboardingStage) {
        model.setOnboardingStage(at)
        withAnimation(.easeOut(duration: 0.3)) { session.stage = at; session.waiting = true }
    }
}
