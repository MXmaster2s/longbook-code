import DesignSystem
import LongbookCore
import SwiftUI
#if os(macOS)
import AppKit
#endif

/// One field of an Edit form, by what it edits: the field a Preview's row opens Edit on, and
/// the field the picture harness names.
enum EditFocus: String, Hashable {
    case repeats, status, ends, category, currency, tag, owner
    case fromAccount = "from_account"
    case fromPerson = "from_person"
    case toAccount = "to_account"
    case toPerson = "to_person"
    case linkedAccount = "linked_account"
    case date, planned, paid, notes, balance, email
    case freeTrial = "free_trial"
    case statementLine = "statement_line"
    case chargeNote = "charge_note"
    case chargeStatementLine = "charge_statement_line"
    case asOn = "as_on"

    /// A field typed into, which takes the cursor; every other one is shown, or its list opened.
    var isTyped: Bool {
        switch self {
        case .notes, .balance, .email, .statementLine, .chargeNote, .chargeStatementLine: true
        default: false
        }
    }

    #if DEBUG
    /// The field LONGBOOK_SNAPSHOT_PICKER names, so the harness pictures its list open.
    static var snapshotPicker: EditFocus? {
        ProcessInfo.processInfo.environment["LONGBOOK_SNAPSHOT_PICKER"].flatMap(EditFocus.init(rawValue:))
    }

    /// The field LONGBOOK_SNAPSHOT_FOCUS names: a Preview opens Edit on it, as a click on its row does.
    static var snapshotFocus: EditFocus? {
        ProcessInfo.processInfo.environment["LONGBOOK_SNAPSHOT_FOCUS"].flatMap(EditFocus.init(rawValue:))
    }
    #endif
}

/// The add row's words for a typed name, and the write behind it: nil once the name is written
/// and picked, else why it was not.
struct ChoiceAdding {
    var label: (String) -> String = { "Add “\($0)”" }
    let create: (String) -> String?

    /// An account or a person is named as one: "New Account “HDFC”".
    static func named(_ noun: String, create: @escaping (String) -> String?) -> ChoiceAdding {
        ChoiceAdding(label: { "New \(noun) “\($0)”" }, create: create)
    }
}

/// A choice as a form's field: its face, and a tap opens the one list every choice shares. On
/// the Mac it drops from the field as a popover; on a phone it is pushed inside the form's own
/// sheet, and a pick comes back to the form.
struct ChoiceField<Face: View>: View {
    let title: String
    /// What the face says, read to a screen reader.
    let value: String
    let choices: [ChoicePickerView.Choice]
    /// The chosen id; nil is None.
    let selected: String?
    var allowsNone = true
    var searchable = true
    var adding: ChoiceAdding?
    /// The list opens as the field first appears: a Preview's row asked for this field.
    var opensOnAppear = false
    let onPick: (String?) -> Void
    let face: () -> Face

    @State private var open = false
    @State private var openedOnce = false

    init(title: String, value: String, choices: [ChoicePickerView.Choice], selected: String?,
         allowsNone: Bool = true, searchable: Bool = true, adding: ChoiceAdding? = nil,
         opensOnAppear: Bool = false, onPick: @escaping (String?) -> Void, @ViewBuilder face: @escaping () -> Face) {
        self.title = title
        self.value = value
        self.choices = choices
        self.selected = selected
        self.allowsNone = allowsNone
        self.searchable = searchable
        self.adding = adding
        self.opensOnAppear = opensOnAppear
        self.onPick = onPick
        self.face = face
    }

    var body: some View {
        Button { Measure.used("open_choice"); open = true } label: { face() }
            .lbButtonStyle()
            .accessibilityLabel(title)
            .accessibilityValue(value)
            #if os(macOS)
            .measured("choice_field_list", .popover, when: open)
            .popover(isPresented: $open, arrowEdge: .bottom) { list.lbKeyboardFocusEffects() }
            #else
            .navigationDestination(isPresented: $open) { pushed }
            #endif
            .onAppear(perform: openIfAsked)
    }

    private var list: ChoiceList {
        ChoiceList(title: title, choices: choices, selected: selected, allowsNone: allowsNone,
                   searchable: searchable, adding: adding, onPick: onPick, onDone: { open = false })
    }

    #if os(iOS)
    /// The list on its own screen, Back to the form beside its title.
    private var pushed: some View {
        list
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.visible, for: .navigationBar)
            .measured("choice_field_list", .page, when: open)
    }
    #endif

    /// Once only: Back from the list, or the form drawn again, leaves it closed.
    private func openIfAsked() {
        guard opensOnAppear, !openedOnce else { return }
        openedOnce = true
        Task { @MainActor in
            #if os(macOS)
            // A popover from a field still sliding in with its panel lands astray.
            try? await Task.sleep(for: .milliseconds(350))
            open = true
            #else
            var quiet = Transaction()
            quiet.disablesAnimations = true
            withTransaction(quiet) { open = true }
            #endif
        }
    }
}

extension ChoiceField where Face == FormChoiceFace {
    /// The form's usual face: the value, quieter while nothing is chosen, and the chevron.
    init(_ title: String, value: String, empty: Bool = false, symbol: String? = nil,
         choices: [ChoicePickerView.Choice], selected: String?, allowsNone: Bool = true,
         searchable: Bool = true, adding: ChoiceAdding? = nil, opensOnAppear: Bool = false,
         onPick: @escaping (String?) -> Void) {
        self.init(title: title, value: value, choices: choices, selected: selected, allowsNone: allowsNone,
                  searchable: searchable, adding: adding, opensOnAppear: opensOnAppear, onPick: onPick) {
            FormChoiceFace(value: value, empty: empty, symbol: symbol)
        }
    }
}

/// One choice field's list, the same on every form: the search on top where the list can grow,
/// None first where the field can be empty, the chosen row ticked, and a typed name nothing
/// carries offered last. On the Mac ↑ and ↓ move the highlight, Return picks, Escape closes.
struct ChoiceList: View {
    typealias Choice = ChoicePickerView.Choice

    let title: String
    let choices: [Choice]
    /// The chosen id; nil is None.
    let selected: String?
    var allowsNone = true
    var searchable = true
    var adding: ChoiceAdding?
    let onPick: (String?) -> Void
    let onDone: () -> Void

    @State private var typed = ""
    /// The row the keyboard or the pointer last moved to; nil follows what is typed.
    @State private var highlighted: String?
    /// Why the typed name was not written, said above the list until the name changes.
    @State private var refusal: String?
    @FocusState private var searching: Bool

    private enum Line: Identifiable {
        case none
        case choice(Choice)
        case add(String)

        var id: String {
            switch self {
            case .none: "\u{0}none"
            case .choice(let choice): "c\u{0}" + choice.id
            case .add: "\u{0}add"
            }
        }
    }

    private var needle: String { typed.trimmingCharacters(in: .whitespaces) }

    private var lines: [Line] {
        let key = needle.lowercased()
        var lines: [Line] = allowsNone && key.isEmpty ? [.none] : []
        lines += choices.filter {
            key.isEmpty || $0.name.lowercased().contains(key) || ($0.detail?.lowercased().contains(key) ?? false)
        }.map(Line.choice)
        if adding != nil, !key.isEmpty,
           !choices.contains(where: { $0.name.caseInsensitiveCompare(needle) == .orderedSame }) {
            lines.append(.add(needle))
        }
        return lines
    }

    /// Where Return lands: the row moved to; else the first match of what is typed, the add row
    /// when nothing matches; else the chosen row.
    private func current(_ lines: [Line]) -> String? {
        if let highlighted, lines.contains(where: { $0.id == highlighted }) { return highlighted }
        if !needle.isEmpty {
            let match = lines.first { if case .choice = $0 { true } else { false } }
            return match?.id ?? lines.last?.id
        }
        let chosen = selected.map { "c\u{0}" + $0 } ?? Line.none.id
        return lines.contains { $0.id == chosen } ? chosen : lines.first?.id
    }

    private var hasGlyphs: Bool { choices.contains { $0.symbol != nil } }

    var body: some View {
        let lines = lines
        let current = current(lines)
        VStack(alignment: .leading, spacing: 0) {
            if searchable {
                search
                    .padding(.horizontal, Self.edge)
                    .padding(.top, Self.edge)
                    .padding(.bottom, LBSpacing.s2)
            }
            if let refusal {
                Text(refusal)
                    .lbText(.footnote)
                    .foregroundStyle(LBColor.urgent.color)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Self.edge)
                    .padding(.bottom, LBSpacing.s2)
            }
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(lines) { line in
                            row(line, lit: line.id == current).id(line.id)
                        }
                        if !lines.contains(where: { if case .none = $0 { false } else { true } }) {
                            Text(emptyWord)
                                .lbText(.footnote)
                                .foregroundStyle(LBColor.textTertiary.color)
                                .padding(.horizontal, LBSpacing.s2)
                                .frame(minHeight: Self.rowHeight, alignment: .leading)
                        }
                    }
                    .padding(Self.inset)
                    #if os(iOS)
                    .background(LBColor.card.color, in: RoundedRectangle(cornerRadius: LBRadius.sm, style: .continuous))
                    .padding(.horizontal, Self.edge)
                    .padding(.top, searchable ? 0 : Self.edge)
                    #endif
                }
                .onAppear { if let current { proxy.scrollTo(current, anchor: .center) } }
                .onChange(of: current) { _, id in if let id { proxy.scrollTo(id) } }
            }
            #if os(macOS)
            .frame(height: Self.listHeight(rows: lines.count + (lines.contains { if case .none = $0 { false } else { true } } ? 0 : 1)))
            #endif
        }
        #if os(macOS)
        .frame(width: 300)
        .background(ChoiceKeys(handle: key))
        #else
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(LBColor.canvas.color)
        #endif
        .onChange(of: typed) { _, _ in
            highlighted = nil
            refusal = nil
        }
        .onAppear {
            #if os(macOS)
            if searchable { DispatchQueue.main.async { searching = true } }
            #endif
            #if DEBUG
            // Snapshot harness: LONGBOOK_SNAPSHOT_NAMING=1 pictures a new name typed into the search.
            if adding != nil, ProcessInfo.processInfo.environment["LONGBOOK_SNAPSHOT_NAMING"] == "1" { typed = "Pets" }
            #endif
        }
    }

    private static var edge: CGFloat {
        #if os(macOS)
        LBSpacing.s2
        #else
        LBSpacing.s4
        #endif
    }

    private static var inset: CGFloat {
        #if os(macOS)
        4
        #else
        0
        #endif
    }

    private static var rowHeight: CGFloat {
        #if os(macOS)
        26
        #else
        44
        #endif
    }

    /// Every row in view up to twelve; past that the list scrolls.
    private static func listHeight(rows: Int) -> CGFloat {
        CGFloat(min(max(rows, 1), 12)) * rowHeight + inset * 2
    }

    private var search: some View {
        HStack(spacing: LBSpacing.s2) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(LBColor.textTertiary.color)
                .accessibilityHidden(true)
            TextField("", text: $typed,
                      prompt: Text(adding == nil ? "Search" : "Search or add").foregroundStyle(LBColor.textTertiary.color))
                .textFieldStyle(.plain)
                .lbText(.body)
                .foregroundStyle(LBColor.textPrimary.color)
                .focused($searching)
                .accessibilityLabel("Search \(title.lowercased())")
                #if os(iOS)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .onSubmit { pickCurrent() }
                #endif
        }
        .padding(.horizontal, LBSpacing.s2)
        .padding(.vertical, Self.searchPadding)
        .background(LBColor.chrome.color, in: RoundedRectangle(cornerRadius: LBRadius.xs, style: .continuous))
    }

    private static var searchPadding: CGFloat {
        #if os(macOS)
        5
        #else
        LBSpacing.s2
        #endif
    }

    /// Nothing to list is a different fact from nothing matching what was typed, and the first
    /// one says where new ones come from.
    private var emptyWord: String {
        guard choices.isEmpty else { return "Nothing matches." }
        return adding == nil ? "None yet." : "None yet. Type a name above to add one."
    }

    private func row(_ line: Line, lit: Bool) -> some View {
        let words: String
        var symbol: String?
        var detail: String?
        var chosen = false
        switch line {
        case .none:
            words = "None"
            chosen = selected == nil
        case .choice(let choice):
            words = choice.name
            symbol = choice.symbol
            detail = choice.detail
            chosen = selected == choice.id
        case .add(let name):
            words = (adding?.label ?? { "Add “\($0)”" })(name)
            symbol = "plus.circle.fill"
        }
        let isAdd = { if case .add = line { true } else { false } }()
        return Button { Measure.used("pick_choice"); pick(line) } label: {
            HStack(spacing: LBSpacing.s2) {
                if hasGlyphs || isAdd {
                    Image(systemName: symbol ?? "circle")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle((isAdd ? LBColor.brandText : LBColor.textSecondary).color)
                        .opacity(symbol == nil ? 0 : 1)
                        .frame(width: 18)
                        .accessibilityHidden(true)
                }
                Text(words)
                    .lbText(.body)
                    .foregroundStyle((isAdd ? LBColor.brandText : LBColor.textPrimary).color)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: LBSpacing.s2)
                if let detail {
                    Text(detail)
                        .lbText(.footnote)
                        .foregroundStyle(LBColor.textTertiary.color)
                        .lineLimit(1)
                }
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(LBColor.brandText.color)
                    .opacity(chosen ? 1 : 0)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, LBSpacing.s2)
            .frame(maxWidth: .infinity, minHeight: Self.rowHeight, alignment: .leading)
            #if os(macOS)
            .background(lit ? LBColor.brand.color.opacity(0.16) : Color.clear,
                        in: RoundedRectangle(cornerRadius: LBRadius.xs, style: .continuous))
            #endif
            .contentShape(Rectangle())
        }
        .lbButtonStyle(hovers: false)
        #if os(macOS)
        .onHover { inside in if inside { highlighted = line.id } }
        #endif
        .accessibilityLabel(words)
        .accessibilityAddTraits(chosen ? [.isSelected] : [])
    }

    /// None clears, a row picks, the add row writes the typed name first. A refused name stays
    /// in the search, its reason above the list, and the list stays open.
    private func pick(_ line: Line) {
        switch line {
        case .none: onPick(nil)
        case .choice(let choice): onPick(choice.id)
        case .add(let name):
            if let refused = adding?.create(name) {
                refusal = refused
                LBHaptics.warn()
                return
            }
        }
        LBHaptics.tap()
        onDone()
    }

    private func pickCurrent() {
        let lines = lines
        guard let id = current(lines), let line = lines.first(where: { $0.id == id }) else { return }
        pick(line)
    }

    private func move(_ step: Int) {
        let lines = lines
        guard !lines.isEmpty else { return }
        let at = current(lines).flatMap { id in lines.firstIndex { $0.id == id } }
        let next = at.map { $0 + step } ?? (step > 0 ? 0 : lines.count - 1)
        highlighted = lines[min(max(next, 0), lines.count - 1)].id
    }

    /// The Mac's keys, by key code: ↑ 126, ↓ 125, Return 36 or 76, Escape 53.
    private func key(_ code: UInt16) -> Bool {
        switch code {
        case 126: move(-1)
        case 125: move(1)
        case 36, 76:
            Measure.used("pick_choice", .shortcut)
            pickCurrent()
        case 53:
            Measure.used("close", .shortcut)
            onDone()
        default: return false
        }
        return true
    }
}

#if os(macOS)
/// The list's keys while it is up, taken before the search field reads them, so typing and
/// moving happen in one place. A key with Command, Option or Control passes by.
private struct ChoiceKeys: NSViewRepresentable {
    let handle: (UInt16) -> Bool

    func makeNSView(context: Context) -> Catcher { Catcher(handle: handle) }

    func updateNSView(_ view: Catcher, context: Context) { view.handle = handle }

    static func dismantleNSView(_ view: Catcher, coordinator: ()) { view.stop() }

    final class Catcher: NSView {
        var handle: (UInt16) -> Bool
        private var monitor: Any?

        init(handle: @escaping (UInt16) -> Bool) {
            self.handle = handle
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { nil }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stop()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, self.window != nil,
                      event.modifierFlags.intersection([.command, .option, .control]).isEmpty else { return event }
                return self.handle(event.keyCode) ? nil : event
            }
        }

        func stop() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }
    }
}
#endif
