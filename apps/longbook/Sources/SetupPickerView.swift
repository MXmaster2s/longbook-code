import DesignSystem
import LongbookCore
import SwiftUI

/// One setup question answered by ticking pills: every group's usual entries in view at
/// once, a plus for one the list does not name. Names only — the details come later. The
/// same screen asks for commitments, accounts and people; the groups make it which.
struct SetupPickerView: View {
    /// The short line above the title: what kind of step this is.
    let kicker: String
    let title: String
    let blurb: String
    let groups: [CommitmentSuggestions.Group]
    /// The word the tally counts: "commitment", "account", "person".
    let noun: (one: String, many: String)
    /// Why the last Continue left a name unwritten, said above Continue.
    let refusal: String?
    let onDone: ([CommitmentPlaceholder]) -> Void
    let onSkip: () -> Void
    /// The step before, when there is one: a swipe to the right goes there.
    let onBack: (() -> Void)?

    @State private var chosen: [CommitmentPlaceholder]
    /// The group whose plus is open, and what is being typed into it.
    @State private var typingIn: String?
    @State private var typed = ""
    @FocusState private var typing: Bool
    /// The name the open line answers to: only one is ever open, whichever group holds it.
    private static let typeLineID = "lb-type-line"

    /// `initial` is ticked from the start: what setup chose before, or what the book holds.
    init(kicker: String, title: String, blurb: String, groups: [CommitmentSuggestions.Group], noun: (one: String, many: String),
         initial: [CommitmentPlaceholder] = [], refusal: String? = nil, onDone: @escaping ([CommitmentPlaceholder]) -> Void,
         onSkip: @escaping () -> Void, onBack: (() -> Void)? = nil) {
        self.kicker = kicker
        self.title = title
        self.blurb = blurb
        self.groups = groups
        self.noun = noun
        self.refusal = refusal
        self.onDone = onDone
        self.onSkip = onSkip
        self.onBack = onBack
        _chosen = State(initialValue: initial)
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: LBSpacing.s6) {
                        question
                        VStack(alignment: .leading, spacing: LBSpacing.s4) {
                            ForEach(groups) { group in
                                groupSection(group)
                            }
                        }
                    }
                    .padding(LBSpacing.s4)
                    .frame(maxWidth: 560)
                    .frame(maxWidth: .infinity)
                }
                // A line opened in a group far down the step sits below the keyboard. The
                // sleep lets it exist before it is scrolled to.
                .onChange(of: typingIn) { _, group in
                    guard group != nil else { return }
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(60))
                        proxy.scrollTo(Self.typeLineID, anchor: .center)
                    }
                }
            }
            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LBColor.canvas.color)
        .contentShape(Rectangle())
        // A swipe to the left anywhere on the step is Continue, with what is ticked; to
        // the right, back. On the whole step, so a short list leaves no dead ground.
        .simultaneousGesture(
            DragGesture(minimumDistance: 40).onEnded { drag in
                guard abs(drag.translation.width) > abs(drag.translation.height) * 1.5 else { return }
                if drag.translation.width < 0 { onDone(chosen) } else { onBack?() }
            }
        )
        .onAppear {
            #if DEBUG
            // The snapshot harness names a group whose first two to tick.
            if let name = ProcessInfo.processInfo.environment["LONGBOOK_SNAPSHOT_OPEN"],
               let group = groups.first(where: { $0.name == name }) {
                chosen = group.suggestions.prefix(2).compactMap { CommitmentSuggestions.placeholder($0, in: group) }
            }
            #endif
        }
        .onChange(of: typing) { _, focused in
            // The line closes when the keyboard goes with nothing typed.
            if !focused, typed.trimmingCharacters(in: .whitespaces).isEmpty { typingIn = nil }
        }
    }

    // MARK: the question

    private var question: some View {
        VStack(alignment: .leading, spacing: LBSpacing.s2) {
            Text(kicker)
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

    // MARK: groups

    /// A group is its name and a row of pills: the usual ones, the ones typed in, and the plus.
    private func groupSection(_ group: CommitmentSuggestions.Group) -> some View {
        let extras = chosen.filter { $0.group == group.name && !group.suggestions.contains($0.name) }
        return VStack(alignment: .leading, spacing: LBSpacing.s2) {
            if groups.count > 1 {
                Text(group.name)
                    .lbText(.label)
                    .foregroundStyle(LBColor.textPrimary.color)
            }
            LBFlow {
                ForEach(group.suggestions, id: \.self) { name in
                    LBChip(name, style: .choice(selected: isChosen(name, in: group))) {
                        toggle(name, in: group)
                    }
                    .accessibilityAddTraits(isChosen(name, in: group) ? [.isSelected] : [])
                }
                ForEach(extras) { placeholder in
                    LBChip(placeholder.name, style: .choice(selected: true)) {
                        LBHaptics.tap()
                        chosen.removeAll { $0.id == placeholder.id }
                    }
                    .accessibilityAddTraits([.isSelected])
                }
                if typingIn == group.name {
                    typeLine(group)
                } else {
                    LBChip("Add", symbol: "plus", style: .accent) {
                        typed = ""
                        typingIn = group.name
                        typing = true
                    }
                    .accessibilityLabel("Add another \(noun.one) under \(group.name)")
                }
            }
        }
    }

    /// The line for a name the list does not carry, shaped like a pill so the row keeps
    /// its shape while the word is typed. Return adds it; the pill stays ticked.
    private func typeLine(_ group: CommitmentSuggestions.Group) -> some View {
        LBChipField("Something else", text: $typed, width: 160,
                    focus: $typing, onSubmit: { addTyped(group) })
            .id(Self.typeLineID)
    }

    // MARK: the tally

    private var footer: some View {
        VStack(spacing: LBSpacing.s3) {
            Rectangle().fill(LBColor.hairline.color).frame(height: 1)
            HStack(alignment: .lastTextBaseline, spacing: LBSpacing.s2) {
                Text("\(chosen.count)")
                    .lbText(.displayLG)
                    .foregroundStyle(LBColor.textPrimary.color)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.easeOut(duration: 0.2), value: chosen.count)
                Text(chosen.count == 1 ? noun.one : noun.many)
                    .lbText(.bodySM)
                    .foregroundStyle(LBColor.textSecondary.color)
                Spacer(minLength: LBSpacing.s3)
                Button(action: onSkip) {
                    Text("Skip")
                        .lbText(.label)
                        .foregroundStyle(LBColor.textTertiary.color)
                        .padding(.vertical, LBSpacing.s2)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            if let refusal {
                Text(refusal)
                    .lbText(.footnote)
                    .foregroundStyle(LBColor.urgent.color)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Button {
                onDone(chosen)
            } label: {
                Text("Continue")
                    .lbText(.body)
                    .foregroundStyle(LBColor.onBrand.color)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, LBSpacing.s3)
                    .background(LBColor.brand.color, in: RoundedRectangle(cornerRadius: LBRadius.sm, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, LBSpacing.s4)
        .padding(.bottom, LBSpacing.s4)
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity)
        .background(LBColor.canvas.color)
    }

    // MARK: choosing

    private func isChosen(_ name: String, in group: CommitmentSuggestions.Group) -> Bool {
        chosen.contains { $0.group == group.name && $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    private func toggle(_ name: String, in group: CommitmentSuggestions.Group) {
        LBHaptics.tap()
        if isChosen(name, in: group) {
            chosen.removeAll { $0.group == group.name && $0.name.caseInsensitiveCompare(name) == .orderedSame }
        } else if let placeholder = CommitmentSuggestions.placeholder(name, in: group) {
            chosen.append(placeholder)
        }
    }

    private func addTyped(_ group: CommitmentSuggestions.Group) {
        guard let placeholder = CommitmentSuggestions.placeholder(typed, in: group) else {
            typingIn = nil
            return
        }
        if !isChosen(placeholder.name, in: group) { chosen.append(placeholder) }
        typed = ""
        typingIn = nil
    }
}
