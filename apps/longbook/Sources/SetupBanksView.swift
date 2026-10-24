import DesignSystem
import LongbookCore
import SwiftUI

/// Setup's second question, asked by bank: every bank as a mark in two sliding rows, the
/// whole list with a search and a name of one's own behind More. A chosen bank opens a
/// card where its accounts are ticked; apps and wallets stand in their own row. Names only.
struct SetupBanksView: View {
    /// Why the last Continue left a name unwritten, said above Continue.
    let refusal: String?
    let onDone: ([CommitmentPlaceholder]) -> Void
    let onSkip: () -> Void
    let onBack: (() -> Void)?

    /// A bank the reader has, and the accounts ticked under it.
    private struct Chosen: Identifiable, Equatable {
        let id: String
        let name: String
        let short: String
        let bank: Bank?
        var kinds: Set<String> = []
        var customs: [String] = []
    }

    @State private var chosen: [Chosen] = []
    @State private var apps: Set<String> = []
    @State private var query = ""
    /// The sheet with every bank, its search, and the line for a bank of one's own.
    @State private var showingAll = false
    @State private var addingBank = false
    @State private var typedBank = ""
    @State private var typingCustomIn: String?
    @State private var typedCustom = ""
    /// The cursor in whichever line was just revealed, and the name the step scrolls to.
    @FocusState private var typingCustom: Bool
    @FocusState private var typingBank: Bool
    private static let customFieldID = "lb-custom-field"

    init(initial: [CommitmentPlaceholder] = [], refusal: String? = nil, onDone: @escaping ([CommitmentPlaceholder]) -> Void,
         onSkip: @escaping () -> Void, onBack: (() -> Void)? = nil) {
        self.refusal = refusal
        self.onDone = onDone
        self.onSkip = onSkip
        self.onBack = onBack
        _chosen = State(initialValue: Self.chosen(from: initial))
        _apps = State(initialValue: Set(initial.map(\.name).filter { name in BankDirectory.apps.contains { $0.name == name } }))
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: LBSpacing.s4) {
                        VStack(alignment: .leading, spacing: LBSpacing.s2) {
                            Text("Quick select")
                                .lbText(.label)
                                .foregroundStyle(LBColor.brandText.color)
                            Text("Your banks & accounts in longbook")
                                .lbText(.displayLG)
                                .foregroundStyle(LBColor.textPrimary.color)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("Select all which are relevant for you.")
                                .lbText(.bodySM)
                                .foregroundStyle(LBColor.textSecondary.color)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        bankRows
                        moreButton
                        ForEach(chosen) { bank in
                            bankCard(bank)
                        }
                        appsRow
                    }
                    .padding(LBSpacing.s4)
                    .frame(maxWidth: 560)
                    .frame(maxWidth: .infinity)
                }
                // A line opened on a card far down the step sits below the keyboard. The
                // sleep lets it exist before it is scrolled to.
                .onChange(of: typingCustomIn) { _, bank in
                    guard bank != nil else { return }
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(60))
                        proxy.scrollTo(Self.customFieldID, anchor: .center)
                    }
                }
            }
            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LBColor.canvas.color)
        .onAppear {
            #if DEBUG
            // The snapshot harness picks a bank and two of its accounts, or opens the sheet.
            if let id = ProcessInfo.processInfo.environment["LONGBOOK_SNAPSHOT_OPEN"], let bank = BankDirectory.bank(id: id) {
                add(bank)
                if let at = chosen.firstIndex(where: { $0.id == bank.id }) {
                    chosen[at].kinds = [BankAccountKind.savings.rawValue, BankAccountKind.credit.rawValue]
                }
            }
            if ProcessInfo.processInfo.environment["LONGBOOK_SNAPSHOT_MORE"] != nil { showingAll = true }
            #endif
        }
        .measured("setup_banks_showing_all", .sheet, when: showingAll)
        .sheet(isPresented: $showingAll, onDismiss: { query = ""; addingBank = false; typedBank = "" }) {
            allBanks
                #if os(macOS)
                .frame(minWidth: 480, minHeight: 560)
                #endif
        }
    }

    // MARK: every bank in two rows

    /// The whole directory as marks: the even indices in the first row, the odd in the
    /// second, each row sliding on its own and running to the column's edge.
    private var bankRows: some View {
        let banks = BankDirectory.banks
        let rows = [
            banks.indices.filter { $0.isMultiple(of: 2) }.map { banks[$0] },
            banks.indices.filter { !$0.isMultiple(of: 2) }.map { banks[$0] },
        ]
        return VStack(alignment: .leading, spacing: LBSpacing.s2) {
            ForEach(rows.indices, id: \.self) { index in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: LBSpacing.s2) {
                        ForEach(rows[index]) { bank in
                            bankTile(bank)
                                .frame(width: 88)
                        }
                    }
                    .padding(.horizontal, LBSpacing.s4)
                }
                .padding(.horizontal, -LBSpacing.s4)
            }
        }
    }

    private func bankTile(_ bank: Bank) -> some View {
        let picked = chosen.contains { $0.id == bank.id }
        return Button { toggle(bank) } label: {
            VStack(spacing: LBSpacing.s2) {
                BankMark(bank: bank, size: 40)
                Text(bank.short)
                    .lbText(.footnote)
                    .foregroundStyle(picked ? LBColor.textPrimary.color : LBColor.textSecondary.color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, LBSpacing.s3)
            .background(LBColor.card.color, in: RoundedRectangle(cornerRadius: LBRadius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: LBRadius.md, style: .continuous)
                    .strokeBorder(picked ? LBColor.brand.color : LBColor.hairline.color, lineWidth: picked ? 1.5 : 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(bank.name)
        .accessibilityAddTraits(picked ? [.isSelected] : [])
    }

    /// The whole list, the search and a name of one's own, behind one full-width button.
    private var moreButton: some View {
        Button { showingAll = true } label: {
            HStack(spacing: LBSpacing.s3) {
                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(LBColor.brandText.color)
                    .frame(width: 32, height: 32)
                    .background(LBColor.brand.color.opacity(0.16), in: RoundedRectangle(cornerRadius: LBRadius.xs, style: .continuous))
                Text("More")
                    .lbText(.label)
                    .foregroundStyle(LBColor.brandText.color)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(LBColor.textTertiary.color)
            }
            .padding(LBSpacing.s3)
            .frame(maxWidth: .infinity)
            .background(LBColor.card.color, in: RoundedRectangle(cornerRadius: LBRadius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: LBRadius.md, style: .continuous)
                    .strokeBorder(LBColor.hairline.color, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("More banks")
    }

    // MARK: the sheet with every bank

    /// The search at the top, the line for a bank the list does not carry, then every
    /// bank that matches — the reader's own first — each ticked or not.
    private var allBanks: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: LBSpacing.s2) {
                    searchField
                    addCustomRow
                    ForEach(listedCustoms) { bank in
                        customRow(bank)
                    }
                    ForEach(listedBanks) { bank in
                        bankRow(bank)
                    }
                }
                .padding(LBSpacing.s4)
            }
            #if os(macOS)
            VStack(spacing: LBSpacing.s3) {
                Rectangle().fill(LBColor.hairline.color).frame(height: 1)
                Button { showingAll = false } label: {
                    Text("Done")
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
            #endif
        }
        .background(LBColor.canvas.color)
        #if os(iOS)
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack {
                Spacer()
                Button { showingAll = false } label: {
                    Text("Done")
                        .lbText(.label)
                        .foregroundStyle(LBColor.brandText.color)
                        .frame(minHeight: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, LBSpacing.s4)
            .padding(.top, LBSpacing.s2)
            .background(LBColor.canvas.color)
        }
        #endif
    }

    private var listedBanks: [Bank] {
        let typed = query.trimmingCharacters(in: .whitespaces)
        return typed.isEmpty ? BankDirectory.banks : BankDirectory.search(typed)
    }

    /// The banks named by hand, so the sheet shows what Other Bank… made.
    private var listedCustoms: [Chosen] {
        let typed = query.trimmingCharacters(in: .whitespaces).lowercased()
        return chosen.filter { $0.bank == nil && (typed.isEmpty || $0.name.lowercased().contains(typed)) }
    }

    private var searchField: some View {
        HStack(spacing: LBSpacing.s2) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(LBColor.textTertiary.color)
            TextField("", text: $query, prompt: Text("Search for your bank").foregroundStyle(LBColor.textTertiary.color))
                .textFieldStyle(.plain)
                .lbText(.body)
                .foregroundStyle(LBColor.textPrimary.color)
                .submitLabel(.done)
                .onSubmit { addFirstResult() }
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(LBColor.textQuaternary.color)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear the search")
            }
        }
        .padding(.horizontal, LBSpacing.s3)
        .padding(.vertical, LBSpacing.s3)
        .background(LBColor.card.color, in: RoundedRectangle(cornerRadius: LBRadius.sm, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: LBRadius.sm, style: .continuous)
                .strokeBorder(LBColor.hairline.color, lineWidth: 1)
        )
    }

    /// One row that opens into a line for a bank name of the reader's own.
    @ViewBuilder
    private var addCustomRow: some View {
        if addingBank {
            HStack(spacing: LBSpacing.s3) {
                Image(systemName: "building.columns")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(LBColor.brandText.color)
                    .frame(width: 32, height: 32)
                    .background(LBColor.brand.color.opacity(0.16), in: RoundedRectangle(cornerRadius: LBRadius.xs, style: .continuous))
                TextField("", text: $typedBank, prompt: Text("Bank name").foregroundStyle(LBColor.textTertiary.color))
                    .textFieldStyle(.plain)
                    .lbText(.body)
                    .foregroundStyle(LBColor.textPrimary.color)
                    .focused($typingBank)
                    // The field takes the cursor once it exists; before that there is
                    // nothing to focus.
                    .onAppear { typingBank = true }
                    .submitLabel(.done)
                    .onSubmit(addTypedBank)
                    .accessibilityLabel("Bank name")
                Button(action: addTypedBank) {
                    Text("Add")
                        .lbText(.label)
                        .foregroundStyle(LBColor.brandText.color)
                        .frame(minHeight: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(LBSpacing.s3)
            .background(LBColor.card.color, in: RoundedRectangle(cornerRadius: LBRadius.sm, style: .continuous))
        } else {
            Button {
                typedBank = ""
                addingBank = true
            } label: {
                HStack(spacing: LBSpacing.s3) {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(LBColor.brandText.color)
                        .frame(width: 32, height: 32)
                        .background(LBColor.brand.color.opacity(0.16), in: RoundedRectangle(cornerRadius: LBRadius.xs, style: .continuous))
                    Text("Other Bank…")
                        .lbText(.body)
                        .foregroundStyle(LBColor.brandText.color)
                    Spacer(minLength: 0)
                }
                .padding(LBSpacing.s3)
                .frame(maxWidth: .infinity)
                .background(LBColor.card.color, in: RoundedRectangle(cornerRadius: LBRadius.sm, style: .continuous))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add a bank by name")
        }
    }

    private func bankRow(_ bank: Bank) -> some View {
        let picked = chosen.contains { $0.id == bank.id }
        return Button { toggle(bank) } label: {
            HStack(spacing: LBSpacing.s3) {
                BankMark(bank: bank, size: 32)
                Text(bank.name)
                    .lbText(.body)
                    .foregroundStyle(LBColor.textPrimary.color)
                Spacer(minLength: 0)
                Image(systemName: picked ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(picked ? LBColor.brandText.color : LBColor.textTertiary.color)
            }
            .padding(LBSpacing.s3)
            .background(LBColor.card.color, in: RoundedRectangle(cornerRadius: LBRadius.sm, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(bank.name)
        .accessibilityAddTraits(picked ? [.isSelected] : [])
    }

    private func customRow(_ bank: Chosen) -> some View {
        Button {
            LBHaptics.tap()
            chosen.removeAll { $0.id == bank.id }
        } label: {
            HStack(spacing: LBSpacing.s3) {
                Image(systemName: "building.columns")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(LBColor.brandText.color)
                    .frame(width: 32, height: 32)
                    .background(LBColor.brand.color.opacity(0.16), in: RoundedRectangle(cornerRadius: LBRadius.xs, style: .continuous))
                Text(bank.name)
                    .lbText(.body)
                    .foregroundStyle(LBColor.textPrimary.color)
                Spacer(minLength: 0)
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(LBColor.brandText.color)
            }
            .padding(LBSpacing.s3)
            .background(LBColor.card.color, in: RoundedRectangle(cornerRadius: LBRadius.sm, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(bank.name)
        .accessibilityAddTraits([.isSelected])
    }

    private func addTypedBank() {
        addCustom(typedBank)
        typedBank = ""
        addingBank = false
    }

    // MARK: a chosen bank

    private func bankCard(_ bank: Chosen) -> some View {
        VStack(alignment: .leading, spacing: LBSpacing.s3) {
            HStack(spacing: LBSpacing.s3) {
                if let real = bank.bank {
                    BankMark(bank: real, size: 32)
                } else {
                    Image(systemName: "building.columns")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(LBColor.brandText.color)
                        .frame(width: 32, height: 32)
                        .background(LBColor.brand.color.opacity(0.16), in: RoundedRectangle(cornerRadius: LBRadius.xs, style: .continuous))
                }
                Text(bank.name)
                    .lbText(.body)
                    .foregroundStyle(LBColor.textPrimary.color)
                    .lineLimit(1)
                Spacer(minLength: LBSpacing.s2)
                Button {
                    LBHaptics.tap()
                    chosen.removeAll { $0.id == bank.id }
                } label: {
                    Text("Remove")
                        .lbText(.label)
                        .foregroundStyle(LBColor.brandText.color)
                        .frame(minHeight: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Rectangle().fill(LBColor.hairline.color).frame(height: 1)
            Text("Which accounts do you have with \(bank.short)?")
                .lbText(.bodySM)
                .foregroundStyle(LBColor.textPrimary.color)
                .fixedSize(horizontal: false, vertical: true)
            LBFlow {
                ForEach(BankAccountKind.allCases, id: \.rawValue) { kind in
                    let on = bank.kinds.contains(kind.rawValue)
                    LBChip(kind.rawValue, symbol: on ? "checkmark.circle.fill" : "circle", style: .choice(selected: on)) {
                        LBHaptics.tap()
                        guard let at = chosen.firstIndex(where: { $0.id == bank.id }) else { return }
                        if on { chosen[at].kinds.remove(kind.rawValue) } else { chosen[at].kinds.insert(kind.rawValue) }
                    }
                }
                ForEach(bank.customs, id: \.self) { custom in
                    LBChip(custom, symbol: "checkmark.circle.fill", style: .choice(selected: true)) {
                        guard let at = chosen.firstIndex(where: { $0.id == bank.id }) else { return }
                        chosen[at].customs.removeAll { $0 == custom }
                    }
                }
                if typingCustomIn == bank.id {
                    customField(bank)
                } else {
                    LBChip("Other", symbol: "plus", style: .accent) {
                        typedCustom = ""
                        typingCustomIn = bank.id
                        // Moving the line from one card to another reuses the same field,
                        // which does not appear again, so the cursor is set here too.
                        typingCustom = true
                    }
                    .accessibilityLabel("Add another kind of account at \(bank.short)")
                }
            }
        }
        .padding(LBSpacing.s4)
        .background(LBColor.card.color, in: RoundedRectangle(cornerRadius: LBRadius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: LBRadius.lg, style: .continuous)
                .strokeBorder(LBColor.hairline.color, lineWidth: 1)
        )
    }

    private func customField(_ bank: Chosen) -> some View {
        LBChipField("What kind", text: $typedCustom, width: 140, height: .floor(34),
                    focus: $typingCustom, onSubmit: { addCustom(to: bank) })
            .id(Self.customFieldID)
    }

    private func addCustom(to bank: Chosen) {
        let clean = typedCustom.trimmingCharacters(in: .whitespaces)
        if !clean.isEmpty, let at = chosen.firstIndex(where: { $0.id == bank.id }), !chosen[at].customs.contains(clean) {
            chosen[at].customs.append(clean)
        }
        typedCustom = ""
        typingCustomIn = nil
    }

    private var appsRow: some View {
        VStack(alignment: .leading, spacing: LBSpacing.s2) {
            Text("Apps and wallets")
                .lbText(.label)
                .foregroundStyle(LBColor.textPrimary.color)
            LBFlow {
                ForEach(BankDirectory.apps, id: \.name) { app in
                    LBChip(app.name, style: .choice(selected: apps.contains(app.name))) {
                        LBHaptics.tap()
                        if apps.contains(app.name) { apps.remove(app.name) } else { apps.insert(app.name) }
                    }
                }
            }
        }
    }

    // MARK: the tally

    private var footer: some View {
        VStack(spacing: LBSpacing.s3) {
            Rectangle().fill(LBColor.hairline.color).frame(height: 1)
            HStack(alignment: .firstTextBaseline, spacing: LBSpacing.s2) {
                Text("\(count)")
                    .lbText(.displayLG)
                    .foregroundStyle(LBColor.textPrimary.color)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.easeOut(duration: 0.2), value: count)
                Text(count == 1 ? "account" : "accounts")
                    .lbText(.bodySM)
                    .foregroundStyle(LBColor.textSecondary.color)
                Spacer()
                Button(action: onSkip) {
                    Text("Skip")
                        .lbText(.label)
                        .foregroundStyle(LBColor.textTertiary.color)
                        .frame(minHeight: 32)
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
                onDone(placeholders)
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
    }

    // MARK: what it makes

    private var count: Int { placeholders.count }

    /// One account per ticked kind, named as the book names them, wearing the kind's tag.
    private var placeholders: [CommitmentPlaceholder] {
        var out: [CommitmentPlaceholder] = []
        for bank in chosen {
            for kind in BankAccountKind.allCases where bank.kinds.contains(kind.rawValue) {
                out.append(CommitmentPlaceholder(name: "\(bank.short) \(kind.word)", group: bank.name, tag: kind.tag))
            }
            for custom in bank.customs {
                out.append(CommitmentPlaceholder(name: "\(bank.short) \(custom)", group: bank.name, tag: "bank account"))
            }
        }
        for app in BankDirectory.apps where apps.contains(app.name) {
            out.append(CommitmentPlaceholder(name: app.name, group: "Apps and wallets", tag: app.tag))
        }
        return out
    }

    private func toggle(_ bank: Bank) {
        LBHaptics.tap()
        if chosen.contains(where: { $0.id == bank.id }) {
            chosen.removeAll { $0.id == bank.id }
        } else {
            add(bank)
        }
    }

    private func add(_ bank: Bank) {
        guard !chosen.contains(where: { $0.id == bank.id }) else { return }
        chosen.append(Chosen(id: bank.id, name: bank.name, short: bank.short, bank: bank, kinds: [BankAccountKind.savings.rawValue]))
    }

    private func addCustom(_ name: String) {
        let clean = name.trimmingCharacters(in: .whitespaces)
        guard !clean.isEmpty, !chosen.contains(where: { $0.name.caseInsensitiveCompare(clean) == .orderedSame }) else { return }
        chosen.append(Chosen(id: "custom:" + clean.lowercased(), name: clean, short: clean, bank: nil, kinds: [BankAccountKind.savings.rawValue]))
    }

    /// Return in the search: the first bank not yet chosen, or, when the directory has no
    /// match at all, the typed name as a bank of one's own.
    private func addFirstResult() {
        let hits = BankDirectory.search(query)
        if let first = hits.first(where: { hit in !chosen.contains { $0.id == hit.id } }) {
            add(first)
        } else if hits.isEmpty {
            addCustom(query)
        }
        query = ""
    }

    /// The accounts already in the book, read back into banks and kinds.
    private static func chosen(from initial: [CommitmentPlaceholder]) -> [Chosen] {
        var out: [Chosen] = []
        for account in initial where !BankDirectory.apps.contains(where: { $0.name == account.name }) {
            if let (bank, rest) = BankDirectory.split(accountName: account.name) {
                let kind = BankAccountKind.allCases.first { $0.word == rest.lowercased() }
                if let at = out.firstIndex(where: { $0.id == bank.id }) {
                    if let kind { out[at].kinds.insert(kind.rawValue) } else if !rest.isEmpty { out[at].customs.append(rest) }
                } else {
                    var entry = Chosen(id: bank.id, name: bank.name, short: bank.short, bank: bank)
                    if let kind { entry.kinds = [kind.rawValue] } else if !rest.isEmpty { entry.customs = [rest] }
                    out.append(entry)
                }
            }
        }
        return out
    }
}

/// A bank's mark: its letters on its colour, the size the place asks for.
struct BankMark: View {
    let bank: Bank
    let size: CGFloat

    var body: some View {
        // One glyph for every bank: initials in a brand colour read as a logo that is not one.
        Image(systemName: "building.columns")
            .font(.system(size: size * 0.44, weight: .medium))
            .foregroundStyle(bank.darkInk ? Color.black.opacity(0.85) : .white)
            .frame(width: size, height: size)
            .background(Color(hexString: bank.colour), in: RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
            .accessibilityHidden(true)
    }
}

extension Color {
    /// "#004C8F" as a colour; anything unreadable is the brand's own.
    init(hexString: String) {
        var digits = hexString.trimmingCharacters(in: .whitespaces)
        if digits.hasPrefix("#") { digits.removeFirst() }
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else {
            self = LBColor.brand.color
            return
        }
        self.init(red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255, blue: Double(value & 0xFF) / 255)
    }
}
