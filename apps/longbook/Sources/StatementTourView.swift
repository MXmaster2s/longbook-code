import DesignSystem
import LongbookCore
import SwiftUI

/// What the import found, one kind at a time. Everything is already saved, so this is a tour:
/// steps as data, the buttons in one place on every step, Return always the primary action.
struct StatementTourView: View {
    /// Every card, as last read from the book.
    let findings: StatementTour.Findings
    /// The people the import wrote, kept here so one taken out can be kept again.
    let people: [StatementTour.Card]
    /// Files or pieces that were not read, which the end screen must not hide.
    let troubles: [String]
    /// A refusal from Undo Import or from taking a person out.
    let problem: String?
    let photo: (String?) -> URL?
    /// How many rows would change side if this person went too.
    let flips: (String, Set<String>) -> TransferFlipWords.Flips
    /// Saves the people taken out; false when it was refused, which `problem` then says.
    let applyRemoved: (Set<String>) -> Bool
    let onUndo: () -> Void
    /// The walk is over without an undo: through its last screen or after Skip.
    let onEnd: (StatementTour.Ending) -> Void
    let onImportAnother: () -> Void
    let onOpenDashboard: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var walk: StatementTour.Walk
    /// The step whose every card is open.
    @State private var seeing: StatementTour.Step?
    /// Those taken out on See All, by id; the book holds what `applied` says.
    @State private var removed: Set<String> = []
    @State private var applied: Set<String> = []
    @State private var confirmingUndo = false
    /// Skip was used on the way, so the walk ends as skipped.
    @State private var skipped = false
    /// A removal that would change charges into Transfers or back, waiting for its Change.
    @State private var flipping: (person: String, flips: TransferFlipWords.Flips)?

    init(findings: StatementTour.Findings, people: [StatementTour.Card], troubles: [String], problem: String?,
         photo: @escaping (String?) -> URL?, flips: @escaping (String, Set<String>) -> TransferFlipWords.Flips,
         applyRemoved: @escaping (Set<String>) -> Bool, onUndo: @escaping () -> Void,
         onEnd: @escaping (StatementTour.Ending) -> Void,
         onImportAnother: @escaping () -> Void, onOpenDashboard: @escaping () -> Void) {
        self.findings = findings
        self.people = people
        self.troubles = troubles
        self.problem = problem
        self.photo = photo
        self.flips = flips
        self.applyRemoved = applyRemoved
        self.onUndo = onUndo
        self.onEnd = onEnd
        self.onImportAnother = onImportAnother
        self.onOpenDashboard = onOpenDashboard
        var withPeople = findings
        withPeople.people = people
        _walk = State(initialValue: StatementTour.Walk(steps: withPeople.steps))
    }

    var body: some View {
        Group {
            if let seeing {
                seeAll(seeing)
            } else if let step = walk.current {
                stepScreen(step)
            } else {
                endScreen
            }
        }
        .padding(.horizontal, Self.gutter)
        .padding(.top, Self.topGutter)
        .padding(.bottom, Self.gutter)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .measured("statement_import_confirming_undo", .dialog, when: confirmingUndo)
        .confirmationDialog("Undo this import", isPresented: $confirmingUndo, titleVisibility: .visible) {
            Button("Undo Import", role: .destructive) { Measure.used("undo_import_confirmed"); onUndo() }
            Button("Keep It", role: .cancel) { Measure.used("keep_import") }
        } message: {
            Text("Every card this import saved is removed.")
        }
        .measured("statement_import_person_flips", .alert, when: flipping != nil)
        .alert("Change charges?", isPresented: Binding(get: { flipping != nil }, set: { if !$0 { flipping = nil } }),
               presenting: flipping?.flips) { _ in
            Button("Change") {
                Measure.used("change")
                if let person = flipping?.person { removed.insert(person) }
                flipping = nil
            }
            Button("Cancel", role: .cancel) { Measure.used("cancel"); flipping = nil }
        } message: { flips in
            Text(TransferFlipWords.message(flips))
        }
    }

    #if os(macOS)
    private static let gutter = LBSpacing.s6
    private static let topGutter = LBSpacing.s6
    #else
    private static let gutter = LBSpacing.s4
    private static let topGutter = LBSpacing.s2
    #endif

    // MARK: a step

    private func stepScreen(_ step: StatementTour.Step) -> some View {
        VStack(alignment: .leading, spacing: LBSpacing.s3) {
            #if os(macOS)
            HStack(spacing: LBSpacing.s3) {
                stepControl(step).frame(maxWidth: CGFloat(walk.steps.count) * 48)
                Spacer(minLength: LBSpacing.s2)
                skipButton
            }
            #else
            HStack {
                leadingButton
                Spacer(minLength: LBSpacing.s2)
                skipButton
            }
            stepControl(step)
            #endif
            ScrollView {
                VStack(alignment: .leading, spacing: LBSpacing.s3) {
                    heading(step.heading, line: step.line)
                    VStack(spacing: LBSpacing.s2) {
                        ForEach(stepCards(step.kind).prefix(StatementTour.cardsOnAStep)) { card($0) }
                    }
                    if let word = step.seeAll {
                        quiet(word, measure: "see_all") {
                            withAnimation(LBMotion.rise(reduceMotion: reduceMotion)) { seeing = step }
                        }
                    }
                    problemLine
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.automatic)
            .id(step.kind)
            .transition(rising)
            footer(primary: "Continue", measure: "continue_step", action: forward) {
                #if os(macOS)
                leadingButton
                #else
                EmptyView()
                #endif
            }
        }
    }

    private var rising: AnyTransition {
        .asymmetric(insertion: .opacity.combined(with: .offset(y: LBSpacing.s2)), removal: .opacity)
    }

    private func move(_ change: () -> Void) {
        withAnimation(LBMotion.rise(reduceMotion: reduceMotion), change)
    }

    private func forward() {
        move { walk.forward() }
    }

    private func stepControl(_ step: StatementTour.Step) -> some View {
        LBCardsControl(items: walk.steps.map { LBCardsControlItem(id: $0.kind, title: StatementTour.listLabel($0.kind), symbol: $0.kind.symbol) },
                      current: step.kind) { kind in
            Measure.used("step_control")
            move { walk.jump(to: kind) }
        }
    }

    /// Undo Import on the first step, where it takes the whole import back; Back after it.
    @ViewBuilder
    private var leadingButton: some View {
        if walk.isFirst {
            Button {
                Measure.used("undo_import")
                confirmingUndo = true
            } label: {
                barWord("Undo Import", ink: LBColor.danger)
            }
            .lbButtonStyle()
        } else {
            Button {
                Measure.used("back")
                move { walk.back() }
            } label: {
                barWord("Back", ink: LBColor.textSecondary)
            }
            .lbButtonStyle()
        }
    }

    private var skipButton: some View {
        Button {
            Measure.used("skip")
            skipped = true
            move { walk.skip() }
        } label: {
            barWord("Skip", ink: LBColor.brandText)
        }
        .lbButtonStyle()
    }

    private func barWord(_ word: String, ink: LBColorValue) -> some View {
        Text(word)
            .lbText(.body)
            .foregroundStyle(ink.color)
            #if os(iOS)
            .frame(minHeight: 44)
            #else
            .frame(minHeight: 32)
            #endif
            .contentShape(Rectangle())
    }

    // MARK: See All

    /// A step shows only who is still kept; See All shows everyone, to keep one again.
    private func stepCards(_ kind: StatementTour.Kind) -> [StatementTour.Card] {
        kind == .people ? people.filter { !applied.contains($0.id) } : findings.cards(kind)
    }

    private func cards(_ kind: StatementTour.Kind) -> [StatementTour.Card] {
        kind == .people ? people : findings.cards(kind)
    }

    private func seeAll(_ step: StatementTour.Step) -> some View {
        VStack(alignment: .leading, spacing: LBSpacing.s3) {
            #if os(iOS)
            HStack {
                backFromList
                Spacer()
            }
            #endif
            if step.kind == .people {
                heading(step.listTitle, line: StatementTour.peopleLine(kept: people.count - removed.count))
            } else {
                heading(step.listTitle, line: nil)
            }
            // Lazy: the step opens at once, and the rest load behind as they are reached.
            ScrollView {
                LazyVStack(spacing: LBSpacing.s2) {
                    ForEach(cards(step.kind)) { card in
                        if step.kind == .people {
                            Button { Measure.used("person_card"); toggle(card.id) } label: { self.card(card, state: removed.contains(card.id) ? .removed : .kept) }
                                .lbButtonStyle(.rounded(LBKindCard.radius))
                                .accessibilityHint(removed.contains(card.id) ? "Keeps this person." : "Removes this person.")
                        } else {
                            self.card(card)
                        }
                    }
                }
            }
            problemLine
            footer(primary: "Done", measure: "done", action: leaveList) {
                #if os(macOS)
                backFromList
                #else
                EmptyView()
                #endif
            }
        }
        .transition(rising)
    }

    private var backFromList: some View {
        Button {
            Measure.used("back")
            leaveList()
        } label: {
            barWord("Back", ink: LBColor.textSecondary)
        }
        .lbButtonStyle()
        .keyboardShortcut(.cancelAction)
    }

    /// A tap takes a person out or keeps them again; a removal that would move charges and
    /// Transfers asks first, as every such change does.
    private func toggle(_ id: String) {
        if removed.contains(id) {
            removed.remove(id)
            return
        }
        let change = flips(id, removed)
        if TransferFlipWords.isZero(change) { removed.insert(id) } else { flipping = (id, change) }
    }

    /// Back and Done both return, with the removals saved as one change. A refusal stays here.
    private func leaveList() {
        if removed != applied {
            guard applyRemoved(removed) else { return }
            applied = removed
        }
        move { seeing = nil }
    }

    // MARK: the end

    private var endScreen: some View {
        VStack(alignment: .leading, spacing: LBSpacing.s3) {
            ScrollView {
                VStack(alignment: .leading, spacing: LBSpacing.s3) {
                    seal
                    heading("Your longbook is ready", line: walk.steps.isEmpty ? "Nothing new on this statement" : "All your cards are saved")
                    if !walk.steps.isEmpty { endList }
                    ForEach(troubles, id: \.self) { trouble in
                        Text(trouble)
                            .lbText(.footnote)
                            .foregroundStyle(LBColor.urgent.color)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    quiet("Import Another Statement", measure: "import_another_statement") { finish(onImportAnother) }
                    Text(StatementTour.nextMonthLine)
                        .lbText(.bodySM)
                        .foregroundStyle(LBColor.textSecondary.color)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .transition(rising)
            footer(primary: "Open Dashboard", measure: "open_dashboard", action: { finish(onOpenDashboard) }) { EmptyView() }
        }
    }

    private func finish(_ leave: () -> Void) {
        onEnd(skipped ? .skipped : .done)
        leave()
    }

    private var seal: some View {
        Image(systemName: "checkmark.seal.fill")
            .lbText(.title)
            .foregroundStyle(LBColor.mintTint.color)
            .frame(width: Self.sealSize, height: Self.sealSize)
            .background(LBColor.mintFill.color, in: RoundedRectangle(cornerRadius: LBRadius.sm, style: .continuous))
            .accessibilityHidden(true)
    }

    #if os(macOS)
    private static let sealSize: CGFloat = 48
    private static let endRowHeight: CGFloat = 44
    #else
    private static let sealSize: CGFloat = 56
    private static let endRowHeight: CGFloat = 52
    #endif

    /// Each kind's symbol and how many are saved: a person taken out no longer counts.
    private var endList: some View {
        VStack(spacing: 0) {
            ForEach(Array(walk.steps.enumerated()), id: \.element.id) { index, step in
                let count = step.kind == .people ? people.count - applied.count : findings.cards(step.kind).count
                HStack(spacing: LBSpacing.s3) {
                    Label(StatementTour.listLabel(step.kind), systemImage: step.kind.symbol)
                        .labelStyle(.titleAndIcon)
                        .lbText(.body)
                        .foregroundStyle(LBColor.textPrimary.color)
                    Spacer(minLength: LBSpacing.s2)
                    Text("\(count)")
                        .lbText(.body)
                        .monospacedDigit()
                        .foregroundStyle(LBColor.textSecondary.color)
                }
                .padding(.horizontal, LBSpacing.s4)
                .frame(minHeight: Self.endRowHeight)
                .accessibilityElement(children: .combine)
                if index < walk.steps.count - 1 {
                    Rectangle()
                        .fill(LBColor.hairline.color)
                        .frame(height: 1)
                        .padding(.horizontal, LBSpacing.s4)
                        .accessibilityHidden(true)
                }
            }
        }
        .background(LBColor.card.color, in: RoundedRectangle(cornerRadius: LBKindCard.radius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: LBKindCard.radius, style: .continuous)
                .strokeBorder(LBColor.hairline.color, lineWidth: 1)
        )
    }

    // MARK: pieces

    private func heading(_ title: String, line: String?) -> some View {
        VStack(alignment: .leading, spacing: LBSpacing.s1) {
            Text(title)
                #if os(macOS)
                .lbText(.largeTitle)
                #else
                .lbText(.screenTitle)
                #endif
                .foregroundStyle(LBColor.textPrimary.color)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if let line {
                Text(line)
                    #if os(macOS)
                    .lbText(.body)
                    #else
                    .lbText(.bodySM)
                    #endif
                    .foregroundStyle(LBColor.textSecondary.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func quiet(_ word: String, measure: StaticString, action: @escaping () -> Void) -> some View {
        Button {
            Measure.used(measure)
            action()
        } label: {
            barWord(word, ink: LBColor.textSecondary)
        }
        .lbButtonStyle()
    }

    @ViewBuilder
    private var problemLine: some View {
        if let problem {
            Text(problem)
                .lbText(.footnote)
                .foregroundStyle(LBColor.urgent.color)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The primary button in the same place on every screen, Return's default. The phone gives
    /// it the width; the Mac keeps its quiet action to the left of it.
    private func footer<Leading: View>(primary: String, measure: StaticString, action: @escaping () -> Void, @ViewBuilder leading: () -> Leading) -> some View {
        #if os(macOS)
        HStack(spacing: LBSpacing.s3) {
            leading()
            Spacer(minLength: LBSpacing.s2)
            ImportPrimaryButton(title: primary, measure: measure, fills: false, action: action)
                .keyboardShortcut(.defaultAction)
        }
        #else
        ImportPrimaryButton(title: primary, measure: measure, action: action)
            .keyboardShortcut(.defaultAction)
        #endif
    }

    /// Laid out as KindCards lays the same kind in a list: a money card's day, category and cycle
    /// share the first line, and From and To the second.
    private func card(_ card: StatementTour.Card, state: LBCardState = .plain) -> some View {
        let lead = [.people, .account].contains(card.kind) ? 2
            : max(card.details.prefix { [.date, .category, .cycle].contains($0.fact) }.count, 1)
        return LBKindCard(kind: card.kind.cardKind, title: card.title, pill: card.pill, amount: card.amount,
                          details: card.details.map { LBMetaFact(symbol: $0.fact.symbol, text: $0.text) },
                          lead: lead, image: photo(card.photo), state: state)
    }
}

private extension StatementTour.Fact {
    var symbol: String {
        switch self {
        case .date: LBGlyph.date
        case .category: LBGlyph.category
        case .person: LBGlyph.member
        case .account: LBGlyph.account
        case .cycle: LBGlyph.cycle
        case .charges: LBGlyph.charge
        case .commitments: LBGlyph.commitment
        }
    }
}
