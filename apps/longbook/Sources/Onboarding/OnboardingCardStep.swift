import DesignSystem
import LongbookCore
import SwiftUI

/// One step of the first run: a question and its cards. The phone shows one card at a
/// time, the next peeking below; a card opens after a few seconds of reading. The Mac
/// lays every card out in two columns and holds only Continue for those seconds.
struct OnboardingCardStep: View {
    let step: Int
    let clock: OnboardingClock
    /// The step's one question; the step bar already says where the reader is.
    let title: String
    let cards: [OnboardingCard]
    let noun: (one: String, many: String)
    let continueTitle: String
    /// Picks as "card id|chip", so the same word on two cards stays two picks.
    @Binding var chosen: Set<String>
    @Binding var card: Int
    @Binding var seen: Set<Int>
    let onContinue: () -> Void
    let onNotNow: () -> Void
    /// The screen before the first card, when there is one.
    var onBackOut: (() -> Void)?
    /// Setup reopened from More: the way out.
    var onClose: (() -> Void)?

    @State private var slowDown = false
    /// The card whose "+" chip is open as a field, and the name being typed into it.
    @State private var addingOn: String?
    @State private var customName = ""
    @FocusState private var customFocused: Bool

    #if os(macOS)
    private static let paged = false
    #else
    private static let paged = true
    #endif

    private var isLast: Bool { card == cards.count - 1 }
    private var ready: Bool { seen.contains(card) }
    private var allSeen: Bool { seen.count >= cards.count }

    var body: some View {
        VStack(spacing: 0) {
            OnboardingHeader(step: step, clock: clock, onClose: onClose)
            ScrollView {
                VStack(spacing: LBSpacing.s6) {
                    heading
                    if Self.paged {
                        cardView(cards[card])
                            .id(card)
                            .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity),
                                                    removal: .move(edge: .top).combined(with: .opacity)))
                    } else {
                        grid
                    }
                    Text("You can always edit your longbook later.")
                        .lbText(.bodySM)
                        .foregroundStyle(LBColor.textSecondary.color)
                    if Self.paged, !isLast {
                        peek(cards[card + 1])
                    }
                }
                .padding(LBSpacing.s4)
            }
            footer
        }
        .onboardingColumn(width: OnboardingWidth.wide)
        .contentShape(Rectangle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 40).onEnded { drag in
                guard Self.paged, abs(drag.translation.height) > abs(drag.translation.width) * 1.5 else { return }
                if drag.translation.height < 0 { if !isLast { next() } } else { back() }
            }
        )
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(.downArrow) { if !isLast { next() }; return .handled }
        .onKeyPress(.rightArrow) { if !isLast { next() }; return .handled }
        .onKeyPress(.space) { if !isLast { next() }; return .handled }
        .onKeyPress(.upArrow) { back(); return .handled }
        .onKeyPress(.leftArrow) { back(); return .handled }
        .task(id: card) { await arm() }
        .measured("onboarding_card_step_slow_down", .alert, when: slowDown)
        .alert("Slow down", isPresented: $slowDown) {
            Button("Got it") {}
        } message: {
            Text("Please read before continuing. This one-time setup of your longbook requires your attention.")
        }
    }

    // MARK: the words

    private var heading: some View {
        Text(title)
            .lbText(.displayLG)
            .foregroundStyle(LBColor.textPrimary.color)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, LBSpacing.s4)
            .frame(maxWidth: .infinity)
    }

    // MARK: the cards

    /// The Mac's two columns: every question at once, ticked with the mouse. Each column
    /// stacks its own cards, so a short card leaves no hole beside a tall one.
    private var grid: some View {
        HStack(alignment: .top, spacing: LBSpacing.s3) {
            ForEach(0..<2, id: \.self) { side in
                VStack(spacing: LBSpacing.s3) {
                    ForEach(cards.indices.filter { $0 % 2 == side }, id: \.self) { index in
                        cardView(cards[index])
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func cardView(_ current: OnboardingCard) -> some View {
        VStack(alignment: .leading, spacing: LBSpacing.s3) {
            questionRow(current)
            LBFlow {
                ForEach(OnboardingRegion.chips(of: current) + customChips(current), id: \.self) { chip in
                    let key = "\(current.id)|\(chip)"
                    LBChip(chip, style: .choice(selected: chosen.contains(key))) {
                        LBHaptics.tap()
                        if chosen.contains(key) { chosen.remove(key) } else { chosen.insert(key) }
                    }
                    .accessibilityAddTraits(chosen.contains(key) ? [.isSelected] : [])
                }
                // One the card did not think of: typed where it will sit, picked as it is added.
                if addingOn == current.id {
                    LBChipField("Your own", text: $customName, width: 150, focus: $customFocused) { addCustom(to: current) }
                } else {
                    LBChip("Add", symbol: "plus", style: .accent) {
                        LBHaptics.tap()
                        customName = ""
                        addingOn = current.id
                        customFocused = true
                    }
                    .accessibilityLabel("Add your own")
                }
            }
        }
        .padding(LBSpacing.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LBColor.card.color, in: RoundedRectangle(cornerRadius: LBRadius.md, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: LBRadius.md, style: .continuous).strokeBorder(LBColor.hairline.color, lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Self.paged ? "\(current.question) Card \(card + 1) of \(cards.count)" : current.question)
    }

    /// The names typed onto a card: its picks that are not among its own chips. Held in
    /// the picks themselves, so a step back and forth keeps them.
    private func customChips(_ card: OnboardingCard) -> [String] {
        let own = Set(OnboardingRegion.chips(of: card))
        let prefix = "\(card.id)|"
        return chosen.filter { $0.hasPrefix(prefix) }
            .map { String($0.dropFirst(prefix.count)) }
            .filter { !own.contains($0) }
            .sorted()
    }

    private func addCustom(to card: OnboardingCard) {
        let clean = customName.trimmingCharacters(in: .whitespacesAndNewlines)
        addingOn = nil
        customName = ""
        guard !clean.isEmpty else { return }
        LBHaptics.tap()
        chosen.insert("\(card.id)|\(clean)")
    }

    private func questionRow(_ current: OnboardingCard) -> some View {
        HStack(spacing: LBSpacing.s3) {
            Image(systemName: current.symbol)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(LBColor.textSecondary.color)
                .frame(width: 24)
            Text(current.question)
                .lbText(.headline)
                .foregroundStyle(LBColor.textPrimary.color)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The next card's question, dimmed under the open one: a tap brings it up once the
    /// open card has been read.
    private func peek(_ following: OnboardingCard) -> some View {
        Button(action: next) {
            HStack(spacing: LBSpacing.s3) {
                questionRow(following)
                Spacer(minLength: LBSpacing.s2)
                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(LBColor.textTertiary.color)
            }
            .padding(LBSpacing.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(LBColor.card.color, in: RoundedRectangle(cornerRadius: LBRadius.md, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: LBRadius.md, style: .continuous).strokeBorder(LBColor.hairline.color, lineWidth: 1))
            .opacity(ready ? 0.85 : 0.5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.2), value: ready)
        .accessibilityLabel("Next card")
    }

    // MARK: the tally

    private var footer: some View {
        VStack(spacing: LBSpacing.s3) {
            Rectangle().fill(LBColor.hairline.color).frame(height: 1)
            HStack(alignment: .lastTextBaseline, spacing: LBSpacing.s2) {
                // A zero keeps to the label's size; the number grows once something is picked.
                Text("\(chosen.count)")
                    .lbText(chosen.isEmpty ? .bodySM : .displayLG)
                    .foregroundStyle(chosen.isEmpty ? LBColor.textSecondary.color : LBColor.textPrimary.color)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.easeOut(duration: 0.2), value: chosen.count)
                Text(chosen.count == 1 ? noun.one : noun.many)
                    .lbText(.bodySM)
                    .foregroundStyle(LBColor.textSecondary.color)
                Spacer(minLength: LBSpacing.s3)
                OnboardingThemeButton()
                OnboardingTextButton(title: "Skip", action: onNotNow)
            }
            HStack(spacing: LBSpacing.s3) {
                #if os(macOS)
                OnboardingCancelButton(action: onClose)
                #endif
                OnboardingPrimaryButton(title: continueTitle, enabled: allSeen, hint: "Read each card to continue", action: onContinue)
            }
        }
        .padding(.horizontal, LBSpacing.s4)
        .padding(.bottom, LBSpacing.s4)
        .background(LBColor.canvas.color)
    }

    // MARK: the pace

    /// The first card of the first step gives eight seconds, every other card five. A card
    /// already seen is open the moment it returns. The Mac, showing every card at once,
    /// waits that long once and then opens them all.
    private func arm() async {
        guard !seen.contains(card) else { return }
        let seconds: Double = step == 1 && card == 0 ? 8 : 5
        try? await Task.sleep(for: .seconds(seconds))
        guard !Task.isCancelled else { return }
        withAnimation(.easeOut(duration: 0.2)) {
            if Self.paged { _ = seen.insert(card) } else { seen.formUnion(cards.indices) }
        }
    }

    private func next() {
        guard Self.paged else { return }
        guard ready else {
            LBHaptics.warn()
            slowDown = true
            return
        }
        show(card + 1)
    }

    private func back() {
        if Self.paged, card > 0 { show(card - 1) } else { onBackOut?() }
    }

    private func show(_ index: Int) {
        guard cards.indices.contains(index) else { return }
        withAnimation(.easeOut(duration: 0.35)) { card = index }
    }
}
