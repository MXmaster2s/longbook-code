import DesignSystem
import LongbookCore
import SwiftUI

/// A list's Select: whether it is on and which cards are chosen. Observed apart from the list, so
/// a tap redraws the cards on show and the bar, never the list's own filtering.
@Observable
@MainActor
final class ListSelection {
    private(set) var isOn = false
    private(set) var ids: Set<String> = []
    /// Select All was the last thing pressed, so the same button now clears.
    private(set) var allChosen = false
    /// Where a ⇧-click's range starts: the card last clicked.
    @ObservationIgnored private var anchor: String?

    func begin(with chosen: Set<String> = []) {
        isOn = true
        ids = chosen
        allChosen = false
        anchor = chosen.first
    }

    func finish() {
        isOn = false
        ids = []
        allChosen = false
        anchor = nil
    }

    func toggle(_ id: String) {
        if ids.contains(id) { ids.remove(id) } else { ids.insert(id) }
        allChosen = false
        anchor = id
    }

    func choose(all shown: [String]) {
        ids = Set(shown)
        allChosen = true
    }

    func clear() {
        ids = []
        allChosen = false
        anchor = nil
    }

    func replace(with chosen: Set<String>) {
        ids = chosen
        allChosen = false
    }

    /// Narrowing the list drops what it no longer shows: an action never reaches a card out of sight.
    func keep(_ shown: [String]) {
        let left = ids.intersection(shown)
        if left.count != ids.count { replace(with: left) }
    }

    /// A click while selecting toggles; on a Mac, ⇧ adds everything from the last card clicked.
    func click(_ id: String, order: () -> [String]) {
        #if os(macOS)
        if NSEvent.modifierFlags.contains(.shift), let anchor {
            let shown = order()
            if let from = shown.firstIndex(of: anchor), let to = shown.firstIndex(of: id) {
                ids.formUnion(shown[min(from, to)...max(from, to)])
                allChosen = false
                return
            }
        }
        #endif
        toggle(id)
    }
}

/// One card while selecting: a tap toggles it, and nothing opens. Its own view, so only the cards
/// on show read the selection.
struct SelectableCard<Card: View>: View {
    let selection: ListSelection
    let id: String
    var order: () -> [String] = { [] }
    let card: (Bool) -> Card

    var body: some View {
        let chosen = selection.ids.contains(id)
        Button {
            Measure.used("select_card")
            LBHaptics.tap()
            selection.click(id, order: order)
        } label: {
            card(chosen)
        }
        .lbCardButtonStyle()
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }
}

/// Runs its content in a body of its own, so what the content reads redraws only this.
struct ObservingView<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View { content() }
}

/// Select All, in the phone's nav bar; once pressed it clears.
struct SelectAllButton: View {
    let selection: ListSelection
    let shown: () -> [String]

    var body: some View {
        Button(selection.allChosen ? "Deselect All" : "Select All") {
            Measure.used("select_all")
            if selection.allChosen { selection.clear() } else { selection.choose(all: shown()) }
        }
    }
}

/// The count and what can be done with the chosen cards, where the phone's tab bar was.
struct SelectionBar<Actions: View>: View {
    let selection: ListSelection
    var problem: String?
    @ViewBuilder let actions: (Int) -> Actions

    var body: some View {
        let count = selection.ids.count
        VStack(alignment: .leading, spacing: LBSpacing.s1) {
            if let problem {
                Text(problem)
                    .lbText(.footnote)
                    .foregroundStyle(LBColor.urgent.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: LBSpacing.s3) {
                Text("\(count) selected")
                    .lbText(.bodySM)
                    .monospacedDigit()
                    .foregroundStyle(LBColor.textSecondary.color)
                    .lineLimit(1)
                    .fixedSize()
                Spacer(minLength: LBSpacing.s2)
                actions(count)
            }
        }
        .padding(.horizontal, LBSpacing.s4)
        .padding(.vertical, LBSpacing.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LBColor.sunken.color)
        .overlay(alignment: .top) { Rectangle().fill(LBColor.hairline.color).frame(height: 1) }
    }
}

/// One word in the bar. A word that opens something more wears the Mac's ellipsis there.
struct SelectionBarButton: View {
    let title: String
    let measure: StaticString
    var destructive = false
    var enabled = true
    /// The word asks or picks before it acts; false for one that acts at once.
    var opensMore = true
    let action: () -> Void

    var body: some View {
        Button(role: destructive ? .destructive : nil) {
            Measure.used(measure)
            action()
        } label: {
            #if os(macOS)
            Text(opensMore ? title + "…" : title)
            #else
            Text(title)
                .lbText(.body)
                .foregroundStyle((destructive ? LBColor.danger : LBColor.brandText).color)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            #endif
        }
        #if os(iOS)
        .lbButtonStyle()
        #endif
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
    }
}

#if os(macOS)
/// A list's first line while selecting: how many are chosen, in the brand's ink, then what
/// works on all of them, then Done. Its own view, so a click redraws only this line.
struct HeaderSelectionBar<Actions: View>: View {
    let selection: ListSelection
    @ViewBuilder let actions: (Int) -> Actions

    var body: some View {
        let count = selection.ids.count
        HStack(alignment: .firstTextBaseline, spacing: LBSpacing.s2) {
            Text("\(count.formatted()) selected")
                .lbText(.largeTitle)
                .monospacedDigit()
                .foregroundStyle(LBColor.brandText.color)
                .lineLimit(1)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: LBSpacing.s3)
            actions(count)
            Button("Done") { Measure.used("select_done"); selection.finish() }
                .help("Done selecting")
        }
        .controlSize(.large)
    }
}
#endif

/// What a bulk change asks before it writes. `flips` first when charges would change side.
struct BulkAsk: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    /// The word that runs it; nil when there is nothing to run and the popup only says why.
    var confirm: String?
    var destructive = false
    var cancel = "Cancel"
    /// Shown as a sheet of choices rather than an alert, as deleting a person or account is.
    var asDialog = false
    var flips: TransferFlipWords.Flips = (0, 0)
    var run: () -> Void = {}
}

/// The popups a bulk change goes through: the count of charges it flips, then its confirmation.
@Observable
@MainActor
final class BulkPrompt {
    var flipping: BulkAsk?
    var confirming: BulkAsk?

    func start(_ ask: BulkAsk) {
        if TransferFlipWords.isZero(ask.flips) { confirming = ask } else { flipping = ask }
    }

    /// The flip popup has to be gone before the next one can stand up.
    func accepted(_ ask: BulkAsk) {
        flipping = nil
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            confirming = ask
        }
    }
}

private struct BulkPopups: ViewModifier {
    let prompt: BulkPrompt

    private var asksWithDialog: Bool { prompt.confirming?.asDialog == true }

    func body(content: Content) -> some View {
        content
            .measured("bulk_confirming_flip", .alert, when: prompt.flipping != nil)
            .alert("Change charges?", isPresented: Binding(get: { prompt.flipping != nil }, set: { if !$0 { prompt.flipping = nil } }),
                   presenting: prompt.flipping) { ask in
                Button("Change") { Measure.used("change"); prompt.accepted(ask) }
                Button("Cancel", role: .cancel) { Measure.used("cancel") }
            } message: { ask in
                Text(TransferFlipWords.message(ask.flips))
            }
            .measured("bulk_confirming", .alert, when: prompt.confirming != nil && !asksWithDialog)
            .alert(prompt.confirming?.title ?? "", isPresented: Binding(get: { prompt.confirming != nil && !asksWithDialog }, set: { if !$0 { prompt.confirming = nil } }),
                   presenting: prompt.confirming) { ask in
                buttons(ask)
            } message: { ask in
                Text(ask.message)
            }
            .measured("bulk_confirming_dialog", .dialog, when: prompt.confirming != nil && asksWithDialog)
            .confirmationDialog(prompt.confirming?.title ?? "", isPresented: Binding(get: { prompt.confirming != nil && asksWithDialog }, set: { if !$0 { prompt.confirming = nil } }),
                                titleVisibility: .visible, presenting: prompt.confirming) { ask in
                buttons(ask)
            } message: { ask in
                Text(ask.message)
            }
    }

    @ViewBuilder
    private func buttons(_ ask: BulkAsk) -> some View {
        if let confirm = ask.confirm {
            Button(confirm, role: ask.destructive ? .destructive : nil) { Measure.used("bulk_confirm"); ask.run() }
            Button(ask.cancel, role: .cancel) { Measure.used("bulk_cancel") }
        } else {
            Button("OK", role: .cancel) { Measure.used("bulk_ok") }
        }
    }
}

extension View {
    func bulkPopups(_ prompt: BulkPrompt) -> some View { modifier(BulkPopups(prompt: prompt)) }
}

/// The sentences a bulk change says, so a list's two platforms cannot drift apart.
enum BulkWords {
    static func counted(_ count: Int, _ noun: (one: String, many: String)) -> String {
        "\(count.formatted()) \(count == 1 ? noun.one : noun.many)"
    }

    static let wayBack = "The version before stays in Proposals."
    static let commitment = (one: "commitment", many: "commitments")
    static let charge = (one: "charge", many: "charges")

    /// A change on the chosen cards. A card belongs to its commitment, so when the change
    /// reaches more than the cards themselves the sentence counts what it does reach.
    static func change(field: String, value: String?, noun: (one: String, many: String), reach: VaultPatch.BulkReach,
                       cardsAreCommitments: Bool, skipping: Int = 0) -> (title: String, message: String) {
        let commitments = reach.commitments - skipping
        let plain = cardsAreCommitments || (reach.commitments == reach.cards && reach.charges == reach.cards)
        let whole = plain ? counted(reach.cards - skipping, noun) : counted(commitments, commitment)
        let title = value == nil ? "Clear \(field) on \(whole)?" : "Set \(field) on \(whole)?"
        var sentences: [String] = []
        if !plain {
            let verb = reach.cards == 1 ? "belongs" : "belong"
            let whose = commitments == 1 ? "its" : "their"
            sentences.append("\(counted(reach.cards, noun).capitalizedFirst) \(verb) to \(counted(reach.commitments, commitment)), so the change reaches all \(counted(reach.charges, charge).replacingOccurrences(of: " ", with: " of \(whose) ")).")
        }
        if let value { sentences.append("\(field.capitalizedFirst) becomes \(value).") }
        if skipping > 0 {
            sentences.append("\(counted(skipping, (one: "transfer", many: "transfers")).capitalizedFirst) \(skipping == 1 ? "stays" : "stay") as \(skipping == 1 ? "it is" : "they are"): a transfer's people come from its accounts' owners.")
        }
        sentences.append(wayBack)
        return (title, sentences.joined(separator: " "))
    }

    static func merge(_ kind: VaultPatch.EntityKind, count: Int, into kept: String) -> (title: String, message: String) {
        let noun = kind == .paymentMethod ? (one: "account", many: "accounts") : (one: "person", many: "people")
        return ("Merge \(counted(count, noun)) into \(kept)?",
                "Everything that names them moves to \(kept). Details already filled in on \(kept) stay, and empty ones are taken from the others. Later statements printing those names go to \(kept). \(wayBack)")
    }
}

#if os(macOS)
/// ⌘A on a list: selects everything shown, unless a text field holds the cursor, where it
/// selects the words as ever. Only for the window this view is in.
struct SelectAllKey: NSViewRepresentable {
    let action: () -> Void

    func makeNSView(context: Context) -> Catcher { Catcher() }

    func updateNSView(_ view: Catcher, context: Context) { view.action = action }

    static func dismantleNSView(_ view: Catcher, coordinator: ()) { view.stop() }

    final class Catcher: NSView {
        var action: () -> Void = {}
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stop()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, let window = self.window, event.window === window,
                      KeyShortcut.selectAll.matches(event), !(window.firstResponder is NSText) else { return event }
                self.action()
                return nil
            }
        }

        func stop() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }
    }
}
#endif

#if os(iOS)
/// A screen asking the tab bar to step aside while its selection bar stands in that place.
struct HidesTabBarKey: PreferenceKey {
    static let defaultValue = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) { value = value || nextValue() }
}
#endif
