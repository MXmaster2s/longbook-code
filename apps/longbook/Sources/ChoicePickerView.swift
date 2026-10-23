import DesignSystem
import LongbookCore
import SwiftUI

/// The whole of one rack as a plain list, the chosen row ticked. One search field: a name
/// it does not find is offered first, to add. A tap picks or clears, as the chips do.
struct ChoicePickerView: View {
    struct Choice: Identifiable, Equatable {
        let id: String
        let name: String
        let symbol: String?
    }

    let title: String
    let glyph: String
    let choices: [Choice]
    let selected: String?
    let onPick: (String) -> Void
    /// Naming a new one from here: nil once it is written and picked, else why it was not.
    /// Absent means this list can only be picked from.
    var onCreate: ((String) -> String?)? = nil
    var createPrompt = "Name it"
    let onDone: () -> Void

    @State private var typed = ""
    /// Whether the name question the plus opens is up, and what is typed into it.
    @State private var naming = false
    @State private var typedNew = ""
    /// Why the last name was not written, said above the list until another is tried.
    @State private var refusal: String?

    private var needle: String { typed.trimmingCharacters(in: .whitespaces) }

    private var shown: [Choice] {
        guard !needle.isEmpty else { return choices }
        return choices.filter { $0.name.lowercased().contains(needle.lowercased()) }
    }

    /// The typed name, offered to add while nothing listed carries it exactly.
    private var addable: String? {
        guard onCreate != nil, !needle.isEmpty,
              !choices.contains(where: { $0.name.caseInsensitiveCompare(needle) == .orderedSame }) else { return nil }
        return needle
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            search
                .padding(.horizontal, LBSpacing.s4)
                .padding(.bottom, LBSpacing.s2)
            if let refusal {
                Text(refusal)
                    .lbText(.footnote)
                    .foregroundStyle(LBColor.urgent.color)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, LBSpacing.s4)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            List {
                Section {
                    if let addable {
                        Button { create(addable) } label: {
                            Label("Add “\(addable)”", systemImage: "plus.circle.fill")
                                .lbText(.body)
                                .foregroundStyle(LBColor.brandText.color)
                                .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .lbListRowBackground()
                    }
                    ForEach(shown) { choice in
                        row(choice).lbListRowBackground()
                    }
                    if shown.isEmpty, addable == nil {
                        Text(emptyWord)
                            .lbText(.footnote)
                            .foregroundStyle(LBColor.textTertiary.color)
                            .lbListRowBackground()
                    }
                }
            }
            .lbGroupedList()
        }
        #if DEBUG
        // Snapshot harness: LONGBOOK_SNAPSHOT_NAMING=1 pictures a new name typed into the search.
        .onAppear {
            if onCreate != nil, ProcessInfo.processInfo.environment["LONGBOOK_SNAPSHOT_NAMING"] == "1" {
                typed = "Pets"
            }
        }
        #endif
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        #if os(macOS)
        .frame(minWidth: 380, minHeight: 460)
        #endif
        .background(LBColor.canvas.color)
        .lbClosesOnOutsideClick(onDone)
        .alert("New \(title.lowercased())", isPresented: $naming) {
            TextField(createPrompt, text: $typedNew)
            Button("Add") { create(typedNew.trimmingCharacters(in: .whitespaces)) }
            Button("Cancel", role: .cancel) {}
        }
    }

    /// Cancel at the leading end, the name in the middle, the plus at the trailing end.
    private var header: some View {
        ZStack {
            Text(title)
                .lbText(.headline)
                .foregroundStyle(LBColor.textPrimary.color)
                .lineLimit(1)
            HStack {
                Button("Cancel", action: onDone)
                    .buttonStyle(.plain)
                    .lbText(.body)
                    .foregroundStyle(LBColor.brandText.color)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                if onCreate != nil {
                    Button {
                        LBHaptics.tap()
                        typedNew = needle
                        refusal = nil
                        naming = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(LBColor.brandText.color)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Add \(title.lowercased())")
                }
            }
        }
        .padding(.horizontal, LBSpacing.s4)
        .frame(minHeight: 52)
    }

    private var search: some View {
        HStack(spacing: LBSpacing.s2) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(LBColor.textTertiary.color)
            TextField("", text: $typed,
                      prompt: Text(onCreate == nil ? "Search" : "Search or add").foregroundStyle(LBColor.textTertiary.color))
                .textFieldStyle(.plain)
                .lbText(.body)
                .foregroundStyle(LBColor.textPrimary.color)
                .submitLabel(.done)
                .onSubmit { if let addable { create(addable) } }
                .onChange(of: typed) { _, _ in refusal = nil }
                #if os(iOS)
                .autocorrectionDisabled()
                #endif
        }
        .padding(.horizontal, LBSpacing.s3)
        .padding(.vertical, LBSpacing.s2)
        .background(LBColor.chrome.color, in: RoundedRectangle(cornerRadius: LBRadius.sm, style: .continuous))
    }

    /// Nothing typed writes nothing. A name already listed is picked instead of written a
    /// second time; the writers behind this match on the name too. A refused name stays
    /// in the search with the reason above the list, and the list stays open.
    private func create(_ name: String) {
        guard !name.isEmpty else { return }
        if let already = choices.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            if already.id != selected { onPick(already.id) }
        } else if let refused = onCreate?(name) {
            refusal = refused
            typed = name
            return
        }
        LBHaptics.tap()
        typed = ""
        typedNew = ""
        onDone()
    }

    /// Nothing to list is a different fact from nothing matching what was typed, and the
    /// first one needs to say where new ones come from.
    private var emptyWord: String {
        guard choices.isEmpty else { return "Nothing matches." }
        return onCreate == nil ? "None yet." : "None yet. Type a name above to add one."
    }

    private func row(_ choice: Choice) -> some View {
        let isOn = selected == choice.id
        return Button {
            LBHaptics.tap()
            onPick(choice.id)
            onDone()
        } label: {
            HStack(spacing: LBSpacing.s3) {
                if let symbol = choice.symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(LBColor.textSecondary.color)
                        .frame(width: 22)
                        .accessibilityHidden(true)
                }
                Text(choice.name)
                    .lbText(.body)
                    .foregroundStyle(LBColor.textPrimary.color)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: LBSpacing.s2)
                if isOn {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(LBColor.brandText.color)
                        .accessibilityHidden(true)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(choice.name)
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }
}
