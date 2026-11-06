import DesignSystem
import LongbookCore
import SwiftUI

// MARK: - layout

/// Where a grouped form's labels stand on the Mac: a column of their own, this wide.
enum FormLayout {
    static let labelWidth: CGFloat = 150
    /// The Edit forms' narrower column, which a side panel's width has room for.
    static let denseLabelWidth: CGFloat = 100
}

private struct FormDenseKey: EnvironmentKey {
    static let defaultValue = false
}

private struct FormGroupedKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// An Edit form on the Mac: the narrower label column and fields a side panel holds.
    var lbFormDense: Bool {
        get { self[FormDenseKey.self] }
        set { self[FormDenseKey.self] = newValue }
    }

    /// A grouped form: quiet 13 pt labels over each field on a phone, and labels in their
    /// own right-aligned column on the Mac. Off, a form keeps the plain stack.
    var lbFormGrouped: Bool {
        get { self[FormGroupedKey.self] }
        set { self[FormGroupedKey.self] = newValue }
    }
}

/// A question and its answer: stacked, or on the grouped Mac form side by side, the label
/// right-aligned in its column.
struct FormRow<Label: View, Content: View>: View {
    @Environment(\.lbFormGrouped) private var grouped
    @Environment(\.lbFormDense) private var dense
    private let alignment: VerticalAlignment
    private let label: Label
    private let content: Content

    /// `alignment` centres the label on content with no text baseline, such as a rack.
    init(alignment: VerticalAlignment = .firstTextBaseline,
         @ViewBuilder label: () -> Label, @ViewBuilder content: () -> Content) {
        self.alignment = alignment
        self.label = label()
        self.content = content()
    }

    var body: some View {
        #if os(macOS)
        if grouped {
            HStack(alignment: alignment, spacing: dense ? LBSpacing.s2 : LBSpacing.s3) {
                label.frame(width: dense ? FormLayout.denseLabelWidth : FormLayout.labelWidth, alignment: .trailing)
                VStack(alignment: .leading, spacing: LBSpacing.s2) { content }
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            stacked
        }
        #else
        stacked
        #endif
    }

    private var stacked: some View {
        VStack(alignment: .leading, spacing: LBSpacing.s2) {
            label
            content
        }
    }
}

// MARK: - the question row

/// Every section's name sits on a row of the same height, whether or not it carries a
/// plus, so the sections with one stand no further from their fields than those without.
/// `trailing` is a chip that belongs on the label row, after its buttons.
struct FormQuestion<Trailing: View>: View {
    @Environment(\.lbFormGrouped) private var grouped
    private let text: String
    /// The field a Save cannot go without, marked so; every other field may stay empty.
    private let required: Bool
    private let noun: String?
    private let money: MoneyButton?
    private let add: (() -> Void)?
    private let browse: (() -> Void)?
    private let trailing: () -> Trailing

    init(_ text: String, required: Bool = false, adding noun: String? = nil, money: MoneyButton? = nil,
         add: (() -> Void)? = nil, browse: (() -> Void)? = nil, @ViewBuilder trailing: @escaping () -> Trailing) {
        self.text = text
        self.required = required
        self.noun = noun
        self.money = money
        self.add = add
        self.browse = browse
        self.trailing = trailing
    }

    /// 13 pt on both: the phone's footnote, the Mac's body.
    static var groupedRole: LBTextStyle {
        #if os(macOS)
        .body
        #else
        .footnote
        #endif
    }

    var body: some View {
        HStack(spacing: LBSpacing.s2) {
            HStack(alignment: .firstTextBaseline, spacing: LBSpacing.s1) {
                // Grouped, the label is a quiet heading over its field, so the answers are louder.
                Text(text)
                    .lbText(grouped ? Self.groupedRole : .body)
                    .foregroundStyle((grouped ? LBColor.textSecondary : LBColor.textPrimary).color)
                if required {
                    Text("Required")
                        .lbText(.footnote)
                        .foregroundStyle(LBColor.textTertiary.color)
                }
            }
            if let noun, let add {
                addButton(noun, action: add)
            }
            if let noun, let browse {
                browseButton(noun, action: browse)
            }
            if let money { money }
            // A chip beside the buttons keeps its words: the row has room, the rail none.
            trailing().fixedSize()
        }
        .frame(minHeight: 26, alignment: .leading)
    }

    /// The way to make a new one. A word beside the plus only repeated the section's name.
    private func addButton(_ noun: String, action: @escaping () -> Void) -> some View {
        Button(action: { Measure.used("add_new"); action() }) {
            Image(systemName: "plus")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(LBColor.brandText.color)
                .frame(width: 26, height: 26)
                .background(LBColor.brand.color.opacity(0.16), in: Circle())
                // A finger's worth of target without a finger's worth of row. The plain
                // 44pt frame made every label row carrying a plus 44pt tall, so those
                // sections stood further from their fields than the ones without one —
                // which is what made the form's rhythm read as uneven.
                .padding(9)
                .contentShape(Rectangle())
                .padding(-9)
        }
        .lbButtonStyle()
        .help("Add a \(noun)")
        .accessibilityLabel("Add a \(noun)")
    }

    /// The rest of the rack. The rail carries one row, so the list behind this is the
    /// only place a name past its edge can be read rather than scrolled to blindly.
    private func browseButton(_ noun: String, action: @escaping () -> Void) -> some View {
        Button(action: { Measure.used("list_bullet"); action() }) {
            Image(systemName: "list.bullet")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(LBColor.textSecondary.color)
                .frame(width: 26, height: 26)
                .background(LBColor.chrome.color, in: Circle())
                .padding(9)
                .contentShape(Rectangle())
                .padding(-9)
        }
        .lbButtonStyle()
        .help("See every \(noun)")
        .accessibilityLabel("See every \(noun)")
    }
}

extension FormQuestion where Trailing == EmptyView {
    /// A label row with nothing after its buttons.
    init(_ text: String, required: Bool = false, adding noun: String? = nil, money: MoneyButton? = nil,
         add: (() -> Void)? = nil, browse: (() -> Void)? = nil) {
        self.init(text, required: required, adding: noun, money: money, add: add, browse: browse) { EmptyView() }
    }
}

/// Which way the money moves, beside the plus: out is the quiet default; money in and a
/// transfer are marked, each with its own glyph. A transfer is its accounts' doing, so it opens
/// on that rather than on a choice.
struct MoneyButton: View {
    let direction: String?
    let action: () -> Void

    var body: some View {
        let income = direction == "in"
        let transfer = direction == "transfer"
        let marked = income || transfer
        return Button(action: { Measure.used("pick_direction"); action() }) {
            Image(systemName: income ? LBGlyph.income : (transfer ? LBGlyph.transfer : LBGlyph.expense))
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(marked ? LBColor.onBrandTint.color : LBColor.textSecondary.color)
                .frame(width: 26, height: 26)
                .background(marked ? LBColor.brand.color.opacity(0.16) : LBColor.chrome.color, in: Circle())
                .padding(9)
                .contentShape(Rectangle())
                .padding(-9)
        }
        .lbButtonStyle()
        .help(transfer ? "Why it is a transfer" : "Change which way it moves")
        .accessibilityLabel(transfer ? "Transfer. Tap to read why." : (income ? "Money in" : "Money out") + ". Tap to change which way it moves.")
    }
}

extension View {
    /// Lines up with the answers of a grouped Mac form, past its label column.
    func formContentColumn() -> some View {
        modifier(FormContentColumn())
    }
}

extension View {
    /// On a phone a form stands at the root of its own stack, so a choice's list is pushed
    /// inside the sheet and Back reads the form's title. The form draws its own header, so the
    /// stack's bar shows only over what is pushed.
    @ViewBuilder
    func lbFormStack(_ title: String) -> some View {
        #if os(iOS)
        NavigationStack {
            navigationTitle(title)
                .toolbar(.hidden, for: .navigationBar)
        }
        #else
        self
        #endif
    }
}

private struct FormContentColumn: ViewModifier {
    @Environment(\.lbFormGrouped) private var grouped
    @Environment(\.lbFormDense) private var dense

    func body(content: Content) -> some View {
        #if os(macOS)
        content.padding(.leading, !grouped ? 0 : dense ? FormLayout.denseLabelWidth + LBSpacing.s2 : FormLayout.labelWidth + LBSpacing.s3)
        #else
        content
        #endif
    }
}

// MARK: - fields

/// A field's card: what is typed or picked sits on the card colour, inside a hairline.
struct FormField<Content: View>: View {
    @Environment(\.lbFormDense) private var dense
    private let content: Content

    init(@ViewBuilder _ content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(.horizontal, LBSpacing.s3)
            .padding(.vertical, dense ? 7 : LBSpacing.s3)
            .background(LBColor.card.color, in: RoundedRectangle(cornerRadius: LBRadius.xs, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: LBRadius.xs, style: .continuous)
                    .strokeBorder(LBColor.hairline.color, lineWidth: 1)
            )
    }
}

/// One choice as a row that opens a menu: the value it holds, and the up-down chevron
/// that says a tap lists the rest.
struct FormMenuField<Items: View>: View {
    let value: String
    var symbol: String?
    /// Nothing is chosen, so the value reads quieter.
    var empty = false
    @ViewBuilder let items: () -> Items

    var body: some View {
        Menu {
            items()
        } label: {
            FormField {
                HStack(spacing: LBSpacing.s2) {
                    if let symbol {
                        Image(systemName: symbol)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(LBColor.textTertiary.color)
                            .accessibilityHidden(true)
                    }
                    Text(value)
                        .lbText(.body)
                        .foregroundStyle((empty ? LBColor.textTertiary : LBColor.textPrimary).color)
                        .lineLimit(1)
                    Spacer(minLength: LBSpacing.s2)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(LBColor.textTertiary.color)
                        .accessibilityHidden(true)
                }
                .contentShape(Rectangle())
            }
        }
        .menuStyle(.button)
        .lbButtonStyle()
        .menuIndicator(.hidden)
        .accessibilityValue(value)
    }
}

/// The face of a choice that opens more than a menu: a calendar, a list, a sheet.
struct FormChoiceFace: View {
    let value: String
    var empty = false
    var symbol: String?

    var body: some View {
        FormField {
            HStack(spacing: LBSpacing.s2) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(LBColor.textTertiary.color)
                        .accessibilityHidden(true)
                }
                Text(value)
                    .lbText(.body)
                    .foregroundStyle((empty ? LBColor.textTertiary : LBColor.textPrimary).color)
                    .lineLimit(1)
                Spacer(minLength: LBSpacing.s2)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(LBColor.textTertiary.color)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
    }
}

/// A fact the form shows and does not ask, such as the person an account belongs to.
struct FormFactRow: View {
    let title: String
    let value: String

    var body: some View {
        FormRow {
            FormQuestion(title)
        } content: {
            Text(value)
                .lbText(.body)
                .foregroundStyle(LBColor.textTertiary.color)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .accessibilityElement(children: .combine)
    }
}

/// A day as an Edit form's field: the date, and a tap opens the calendar, off the field on
/// the Mac and as a sheet on a phone. A pick lands at midnight of the day.
struct FormDayButton: View {
    let title: String
    @Binding var date: Date
    /// Said in place of the date while there is no day to show.
    var unset: String?
    @State private var picking = false

    var body: some View {
        Button {
            Measure.used("open_picker")
            picking.toggle()
        } label: {
            FormChoiceFace(value: unset ?? LB.longDate(date), empty: unset != nil)
        }
        .lbButtonStyle()
        .accessibilityLabel(title)
        .accessibilityValue(unset ?? LB.longDate(date))
        #if os(macOS)
        .measured("form_parts_day_button", .popover, when: picking)
        .popover(isPresented: $picking, arrowEdge: .bottom) { calendar.lbKeyboardFocusEffects() }
        #else
        .measured("form_parts_day_button", .sheet, when: picking)
        .sheet(isPresented: $picking) { calendar.lbDaySheet().lbKeyboardFocusEffects() }
        #endif
    }

    private var calendar: some View {
        DayPickerView(title: title, selected: date, onPick: { date = $0 }, onDone: { picking = false })
    }
}

/// A yes or no as a switch row: its name inside the field on a phone; on the grouped Mac
/// form the name in the label column and the switch beside it.
struct FormToggleRow: View {
    @Environment(\.lbFormGrouped) private var grouped
    @Environment(\.lbFormDense) private var dense
    let title: String
    @Binding var isOn: Bool
    /// The switch's fixed name in usage counts.
    let measure: StaticString

    var body: some View {
        #if os(macOS)
        if grouped {
            FormRow {
                FormQuestion(title)
            } content: {
                Toggle(title, isOn: $isOn.measured(measure))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(dense ? .small : .regular)
                    .tint(LBColor.brand.color)
            }
        } else {
            field
        }
        #else
        field
        #endif
    }

    private var field: some View {
        FormField {
            Toggle(isOn: $isOn.measured(measure)) {
                Text(title)
                    .lbText(.body)
                    .foregroundStyle(LBColor.textPrimary.color)
            }
            .tint(LBColor.brand.color)
        }
    }
}

/// A commitment's name, typed on its card.
struct FormNameField: View {
    @Binding var text: String

    var body: some View {
        FormField {
            TextField("", text: $text, prompt: Text("Netflix, rent, school fees…").foregroundStyle(LBColor.textTertiary.color))
                .textFieldStyle(.plain)
                .lbText(.body)
                .foregroundStyle(LBColor.textPrimary.color)
        }
    }
}

/// An amount, typed on its card with the decimal pad; the currency sits inside the field,
/// at its end, as Wallet keeps it.
struct FormAmountField<Accessory: View>: View {
    @Binding var text: String
    @ViewBuilder var accessory: () -> Accessory

    var body: some View {
        FormField {
            HStack(spacing: LBSpacing.s2) {
                TextField("", text: $text, prompt: Text("0.00").foregroundStyle(LBColor.textTertiary.color))
                    .textFieldStyle(.plain)
                    .lbText(.body)
                    .foregroundStyle(LBColor.textPrimary.color)
                    #if os(iOS)
                    .keyboardType(.decimalPad)
                    #endif
                accessory()
            }
        }
    }
}

extension FormAmountField where Accessory == EmptyView {
    init(text: Binding<String>) {
        self.init(text: text) { EmptyView() }
    }
}

/// The currency as one capsule inside the amount field. A tap lists the quick selector's codes,
/// then every other code the system knows, each named; picking one of those puts it on the
/// selector. Held down, a code no commitment counts can be taken off the selector.
struct FormCurrencyMenu: View {
    @Environment(\.lbFormDense) private var dense
    let model: DashboardModel
    @Binding var currency: String
    /// The list opens as the field first appears.
    var opensOnAppear = false
    @State private var deleting: String?

    var body: some View {
        let codes = model.editChoices.currencies
        ChoiceField(title: "Currency", value: currency, choices: choices(quick: codes), selected: currency,
                    allowsNone: false, opensOnAppear: opensOnAppear, onPick: { code in
            guard let code else { return }
            if !codes.contains(code) { model.keepCurrency(code) }
            currency = code
        }) {
            HStack(spacing: 4) {
                Text(currency)
                    .lbText(.label)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
            }
            .foregroundStyle(LBColor.onBrandTint.color)
            .padding(.horizontal, LBSpacing.s2)
            .frame(minHeight: dense ? 18 : 28)
            .background(LBColor.brand.color.opacity(0.12), in: Capsule())
            .contentShape(Capsule())
        }
        .fixedSize()
        .contextMenu {
            let removable = codes.filter { model.commitmentsIn(currency: $0).isEmpty && $0 != currency }
            if !removable.isEmpty {
                Menu("Remove From Quick Selector") {
                    ForEach(removable, id: \.self) { code in
                        Button(code, role: .destructive) { Measure.used("deleting", .contextMenu); deleting = code }
                    }
                }
            }
        }
        .measured("form_parts_deleting", .alert, when: deleting != nil)
        .alert(refusal.title,
               isPresented: Binding(get: { deleting != nil },
                                    set: { if !$0 { deleting = nil } })) {
            if refusal.removable {
                Button("Delete", role: .destructive) {
                    Measure.used("delete")
                    if let code = deleting, model.forgetCurrency(code), currency == code {
                        currency = model.editChoices.currencies.first ?? "INR"
                    }
                    deleting = nil
                }
                Button("Cancel", role: .cancel) { Measure.used("cancel"); deleting = nil }
            } else {
                Button("Close", role: .cancel) { Measure.used("close"); deleting = nil }
            }
        } message: {
            Text(refusal.message)
        }
    }

    /// The quick selector's codes lead, then the rest of the world's, each with its name.
    private func choices(quick: [String]) -> [ChoicePickerView.Choice] {
        let locale = Locale.current
        let rest = Locale.commonISOCurrencyCodes.filter { !quick.contains($0) }
        return (quick + rest).map {
            ChoicePickerView.Choice(id: $0, name: $0, symbol: nil, detail: locale.localizedString(forCurrencyCode: $0))
        }
    }

    /// A code no commitment counts is only a selector entry, and can be put away. A code
    /// in use is listed from the vault itself, so taking it off would change nothing.
    private var refusal: (title: String, message: String, removable: Bool) {
        let code = deleting ?? ""
        let used = model.commitmentsIn(currency: code).count
        guard used > 0 else {
            return ("Delete \(code) from Quick Selector?",
                    "The quick selector loses the code. No commitment changes.", true)
        }
        return ("\(code) stays in the Quick Selector",
                "\(used) commitment\(used == 1 ? "" : "s") count\(used == 1 ? "s" : "") in \(code), so the code is listed from the vault itself.",
                false)
    }
}

/// Notes on their card: three lines open, growing to six before the text scrolls.
struct FormNotesField: View {
    let prompt: String
    @Binding var text: String
    /// The longest the text grows by typing. An edit longer than both this and the text it
    /// replaces keeps only as much of what it inserted as fits, so the notes are never cut.
    let cap: Int

    var body: some View {
        FormField {
            TextField("", text: Binding(
                get: { text },
                set: { text = TextFit.fitted($0, replacing: text, cap: cap) }
            ), prompt: Text(prompt).foregroundStyle(LBColor.textTertiary.color), axis: .vertical)
                .textFieldStyle(.plain)
                .lbText(.bodySM)
                .foregroundStyle(LBColor.textPrimary.color)
                .lineLimit(3...6)
        }
    }
}

/// A statement line as the bank printed it or the owner corrected it: one line of words that
/// wraps as it grows, a Return adding no line.
struct FormStatementLineField: View {
    @Binding var text: String

    var body: some View {
        FormField {
            TextField("", text: Binding(
                get: { text },
                set: { text = $0.replacingOccurrences(of: "\n", with: " ") }
            ), prompt: Text("As printed on the statement").foregroundStyle(LBColor.textTertiary.color), axis: .vertical)
                .textFieldStyle(.plain)
                .lbText(.bodySM)
                .foregroundStyle(LBColor.textPrimary.color)
                .lineLimit(1...4)
                .accessibilityLabel("Statement line")
        }
    }
}

// MARK: - the date control

/// A day on its card, said as the date and what it means; a tap opens the day sheet. The
/// label row takes a trailing chip, as `FormQuestion` does.
struct FormDateControl<Trailing: View>: View {
    let title: String
    @Binding var date: Date
    /// The host holds whether the sheet is up, so it can open or close it too.
    @Binding var picking: Bool
    /// The first and last days the sheet takes.
    var earliest: Date?
    var latest: Date?
    /// Said in place of the date while there is no day to show.
    var unset: String?
    @ViewBuilder var trailing: () -> Trailing

    @Environment(\.lbFormGrouped) private var grouped

    /// On the grouped Mac form the label column holds the name alone; the chip goes beside the field.
    private var chipBesideField: Bool {
        #if os(macOS)
        grouped
        #else
        false
        #endif
    }

    var body: some View {
        FormRow {
            if chipBesideField { FormQuestion(title) } else { FormQuestion(title, trailing: trailing) }
        } content: {
            HStack(spacing: LBSpacing.s2) {
                dayButton
                if chipBesideField { trailing().fixedSize() }
            }
        }
        #if os(macOS)
        // The Mac's calendar hangs off the field, as Calendar and Reminders do; no sheet.
        .measured("form_parts_picking", .popover, when: picking)
        .popover(isPresented: $picking, arrowEdge: .bottom) {
            DayPickerView(
                title: title,
                selected: date,
                earliest: earliest,
                latest: latest,
                onPick: { date = $0 },
                onDone: { picking = false }
            )
                .lbKeyboardFocusEffects()
        }
        #else
        .measured("form_parts_picking", .sheet, when: picking)
        .sheet(isPresented: $picking) {
            DayPickerView(
                title: title,
                selected: date,
                earliest: earliest,
                latest: latest,
                onPick: { date = $0 },
                onDone: { picking = false }
            )
            .lbDaySheet()
            .lbKeyboardFocusEffects()
        }
        #endif
    }

    private var dayButton: some View {
            Button {
                Measure.used("open_picker")
                picking.toggle()
            } label: {
                FormField {
                    HStack(spacing: LBSpacing.s2) {
                        Image(systemName: LBGlyph.date)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(LBColor.textTertiary.color)
                        Text(unset ?? Self.word(date))
                            .lbText(.body)
                            .foregroundStyle(unset == nil ? LBColor.textPrimary.color : LBColor.textTertiary.color)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(LBColor.textTertiary.color)
                    }
                }
            }
            .lbButtonStyle()
    }

    /// "6 Aug 2026 (in 8 days)" — the date and what it means. A date in a form is a fact,
    /// not a status: a past one reads "(42 days ago)", never overdue. Lowercased here: the
    /// same words head a rail card, where they are set in capitals.
    static func word(_ date: Date) -> String {
        let days = LB.daysBetween(LB.todayMid(), date)
        guard days != 0 else { return LB.longDate(date) }
        let word = days < 0 ? LB.agoWord(days) : LB.dayWord(days)
        return "\(LB.longDate(date)) (\(word.prefix(1).lowercased() + word.dropFirst()))"
    }
}

extension FormDateControl where Trailing == EmptyView {
    init(title: String, date: Binding<Date>, picking: Binding<Bool>, earliest: Date? = nil, latest: Date? = nil, unset: String? = nil) {
        self.init(title: title, date: date, picking: picking, earliest: earliest, latest: latest, unset: unset) { EmptyView() }
    }
}

/// A day in a form row, picked in place with the system's own date picker, with what the
/// day means beside it ("in 8 days").
struct FormDayPicker: View {
    let title: String
    @Binding var date: Date
    var earliest: Date?
    var latest: Date?

    var body: some View {
        FormRow {
            FormQuestion(title)
        } content: {
            HStack(spacing: LBSpacing.s2) {
                FormDayField(title: title, date: $date, earliest: earliest, latest: latest)
                if let word = Self.relative(date) {
                    Text(word)
                        .lbText(.footnote)
                        .foregroundStyle(LBColor.textTertiary.color)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .frame(minHeight: 34)
        }
    }

    /// "in 8 days", "42 days ago"; nothing for today. A date in a form is a fact, never overdue.
    static func relative(_ date: Date) -> String? {
        let days = LB.daysBetween(LB.todayMid(), date)
        guard days != 0 else { return nil }
        let word = days < 0 ? LB.agoWord(days) : LB.dayWord(days)
        return word.prefix(1).lowercased() + word.dropFirst()
    }
}

/// The system date picker as Apple sets it in a form: compact on iPhone (a tap opens the
/// system calendar), the date field with its calendar on the Mac. A pick lands at midnight
/// of the day; the bounds say which days can be taken.
struct FormDayField: View {
    let title: String
    @Binding var date: Date
    var earliest: Date?
    var latest: Date?

    var body: some View {
        picker
            .datePickerStyle(.compact)
            .labelsHidden()
            .tint(LBColor.brand.color)
            .fixedSize()
            .accessibilityLabel(title)
    }

    private var day: Binding<Date> {
        Binding(get: { date }, set: { picked in
            let picked = LB.dayOf(picked)
            guard picked != LB.dayOf(date) else { return }
            Measure.used("pick_date")
            LBHaptics.tap()
            date = picked
        })
    }

    @ViewBuilder
    private var picker: some View {
        switch (earliest.map(LB.dayOf), latest.map(LB.dayOf)) {
        case let (first?, last?) where !(first > last):
            DatePicker(title, selection: day, in: first...last, displayedComponents: .date)
        case let (first?, _):
            DatePicker(title, selection: day, in: first..., displayedComponents: .date)
        case let (nil, last?):
            DatePicker(title, selection: day, in: ...last, displayedComponents: .date)
        default:
            DatePicker(title, selection: day, displayedComponents: .date)
        }
    }
}

// MARK: - racks

/// One rack of choices: a single row scrolled sideways, with the way to make a new one
/// pinned beside the section's name, where it stays however far the list runs.
struct FormRack<Editor: View, Chips: View>: View {
    private let label: String
    private let noun: String
    private let money: MoneyButton?
    private let chosen: String?
    private let focusID: String?
    @Binding private var railWidth: CGFloat?
    private let add: () -> Void
    private let browse: (() -> Void)?
    private let editor: () -> Editor
    private let chips: () -> Chips

    init(_ label: String, adding noun: String, money: MoneyButton? = nil,
         chosen: String? = nil, focusID: String? = nil, railWidth: Binding<CGFloat?>,
         add: @escaping () -> Void, browse: (() -> Void)? = nil,
         @ViewBuilder editor: @escaping () -> Editor, @ViewBuilder chips: @escaping () -> Chips) {
        self.label = label
        self.noun = noun
        self.money = money
        self.chosen = chosen
        self.focusID = focusID
        _railWidth = railWidth
        self.add = add
        self.browse = browse
        self.editor = editor
        self.chips = chips
    }

    var body: some View {
        FormRow(alignment: .center) {
            FormQuestion(label, adding: noun, money: money, add: add, browse: browse)
        } content: {
            RackStrip(chosen: chosen, focusID: focusID, railWidth: $railWidth) {
                editor()
                chips()
            }
        }
    }
}

/// One rack's scroller: a row of chips pulled sideways by finger or pointer, opened on the
/// chip already chosen. Each rack holds its own pointer, so dragging one never moves another.
struct RackStrip<Content: View>: View {
    let chosen: String?
    /// The id of a field just revealed at the rail's leading edge, so the rack scrolls back
    /// to it. The chosen chip may sit anywhere, and the field is off-screen behind it.
    var focusID: String? = nil
    @Binding var railWidth: CGFloat?
    @ViewBuilder let content: () -> Content
    @State private var pointer = LBPointerScroll()

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LBRail(rows: 1, fitting: railWidth, spacing: LBSpacing.s2, lineSpacing: LBSpacing.s2) {
                    content()
                }
                .lbPointerScrollTarget(pointer)
            }
            .lbPointerDrag(pointer)
            // The width the rail is read through. Inside a horizontal scroller the rail is
            // offered infinity, so a short set was split by its item count rather than by
            // whether it actually needed a second line.
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .onAppear { railWidth = proxy.size.width }
                        .onChange(of: proxy.size.width) { _, width in railWidth = width }
                }
            )
            // Editing opens on the chip already chosen, wherever along the rack it is.
            .onAppear {
                guard let chosen else { return }
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(60))
                    proxy.scrollTo(chosen, anchor: .center)
                }
            }
            // A field just revealed sits at the leading edge, which is behind the rack
            // wherever a chosen chip pulled it. The sleep lets the field exist first.
            .onChange(of: focusID) { _, id in
                guard let id else { return }
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(60))
                    proxy.scrollTo(id, anchor: .leading)
                }
            }
        }
    }
}

/// How a form's Save reaches the names typed into the account and member pills: the racks
/// fill it in, and the host submits it before saving, so a name typed without return is kept.
final class RackTyping {
    fileprivate var submitTyped: () -> Bool = { true }
    /// The accounts and members the racks wrote while the form was open, by id. Each is
    /// written the moment it is named, so a discarded form leaves them in the file.
    fileprivate var added: [String] = []

    /// Writes and chooses each typed name, as return does. False when one was refused.
    func submit() -> Bool { submitTyped() }

    /// An account the form wrote outside the racks, named by the discard question all the same.
    func noteAdded(_ id: String) { added.append(id) }

    /// A saved form's names are part of what it saved; the discard question forgets them.
    func forgetAdded() { added = [] }

    /// What the discard question says stays — "HDFC is already in Accounts, and stays
    /// there." — by the names the file holds now, or nil when the racks wrote nothing.
    @MainActor
    func keptOnDiscard(_ model: DashboardModel) -> String? {
        let choices = model.editChoices
        let lines = [(choices.methods, "Accounts"), (choices.members, "People")].compactMap { rows, screen -> String? in
            let names = rows.filter { added.contains($0.id) }.map(\.name)
            guard let last = names.last else { return nil }
            guard names.count > 1 else { return "\(last) is already in \(screen), and stays there." }
            return "\(names.dropLast().joined(separator: ", ")) and \(last) are already in \(screen), and stay there."
        }
        return lines.isEmpty ? nil : lines.joined(separator: " ")
    }
}

/// The three racks a commitment is filed under. A tap picks; the plus types a new one; the
/// list opens the whole set; a press and hold edits or deletes. An Edit form asks for one at
/// a time, as a choice field whose face, held, edits or deletes.
struct CommitmentRacks: View {
    /// One rack as an Edit form's row, under the label its side of the money gives it.
    enum Row {
        case category
        case account(String)
        case member(String)
    }

    var row: Row?
    let model: DashboardModel
    @Binding var tag: String?
    @Binding var accountId: String?
    @Binding var memberId: String?
    /// What was set when the form opened: those chips lead their racks, and stay put
    /// while the reader is choosing, so a tap never moves the chip out from under it.
    var openedWith: (tag: String?, method: String?, member: String?) = (nil, nil, nil)
    /// Raised by the host each time it blanks the form for another; an open tag field
    /// closes, since the tag it was typing into has just been cleared.
    var blankings = 0
    /// One rack as a row opens its list as it first appears.
    var opensOnAppear = false
    /// Whether a sheet opened from a rack is up, so the host can soften itself behind it.
    @Binding var detourOpen: Bool
    let typing: RackTyping

    @State private var addingCategory = false
    @State private var addingMethod = false
    @State private var typedMethod = ""
    @State private var addingMember = false
    @State private var typedMember = ""
    /// Why the name in the account pill, or the member pill, was not written: said under
    /// that rack until the name changes or the pill closes.
    @State private var methodRefusal: String?
    @State private var memberRefusal: String?
    /// The cursor in whichever rail field was just revealed, and the name its rack scrolls
    /// to. One of each, because all three racks can be open at once.
    @FocusState private var tagFocused: Bool
    @FocusState private var methodFocused: Bool
    @FocusState private var memberFocused: Bool
    private static let tagFieldID = "lb-tag-field"
    private static let methodFieldID = "lb-account-field"
    private static let memberFieldID = "lb-member-field"
    /// The width the chip rails are read through, measured from the rail itself.
    @State private var railWidth: CGFloat?
    @State private var browsing: BrowseTarget?
    /// The tag held down on its chip, and the account or member held down on theirs.
    @State private var editingTag: TagTarget?
    @State private var editingEntity: EntityTarget?
    @State private var deletingTag: TagTarget?
    @State private var deletingEntity: EntityTarget?

    struct TagTarget: Identifiable, Equatable {
        let name: String
        var id: String { name }
    }

    /// An account or a member, named by the chip that was held down.
    struct EntityTarget: Identifiable, Equatable {
        let kind: VaultPatch.EntityKind
        let entityId: String
        let name: String
        var id: String { entityId }
    }

    /// Which rack has its full list open. The rail shows one row; the rest is listed.
    enum BrowseTarget: String, Identifiable {
        case tag, account, member
        var id: String { rawValue }

        var title: String {
            switch self {
            case .tag: return "Category"
            case .account: return "Account"
            case .member: return "Person"
            }
        }

        var glyph: String {
            switch self {
            case .tag: return LBGlyph.category
            case .account: return LBGlyph.account
            case .member: return LBGlyph.member
            }
        }

        /// The same words the rail's own field asks with, so naming one reads the same
        /// wherever it is named.
        var prompt: String {
            switch self {
            case .tag: return "New category"
            case .account: return "New account"
            case .member: return "Their name"
            }
        }
    }

    /// A sheet opened from a rack, rather than a question asked over it. The full list drops
    /// from its rack, or is pushed, so it softens nothing.
    private var detour: Bool { editingTag != nil || editingEntity != nil }

    @ViewBuilder
    private var shown: some View {
        switch row {
        case .category: categoryRow
        case .account(let label): accountRow(label)
        case .member(let label): memberRow(label)
        case nil:
            VStack(alignment: .leading, spacing: LBSpacing.s4) {
                categories
                howPaid
                whoFor
            }
        }
    }

    var body: some View {
        shown
        .onChange(of: detour) { _, open in detourOpen = open }
        .onChange(of: blankings) { _, _ in addingCategory = false }
        .onAppear { if row == nil { typing.submitTyped = submitTyped } }
        // The closure holds these racks, and they hold the typing: let go when they leave.
        .onDisappear { if row == nil { typing.submitTyped = { true } } }
        #if os(iOS)
        .navigationDestination(item: $browsing) { target in
            browseList(target)
                .navigationTitle(target.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar(.visible, for: .navigationBar)
                .measured("form_parts_browsing", .page, when: browsing != nil)
        }
        #endif
        .measured("form_parts_editing_tag", .sheet, when: editingTag != nil)
        .sheet(item: $editingTag) { target in
            CategoryEditView(
                model: model,
                name: target.name,
                onDone: { editingTag = nil },
                // The vault's rows already moved; the open form must say the same word.
                onRenamed: { newName in
                    if tag == target.name { tag = newName }
                },
                onDeleted: {
                    if tag == target.name { tag = nil }
                }
            )
            .lbThreeQuarterSheet()
            .lbKeyboardFocusEffects()
        }
        .measured("form_parts_editing_entity", .sheet, when: editingEntity != nil)
        .sheet(item: $editingEntity) { target in
            EntityEditView(model: model, kind: target.kind, id: target.entityId,
                           currentName: target.name, onDone: { editingEntity = nil },
                           onDeleted: { forget(target) })
                .lbThreeQuarterSheet()
                .lbKeyboardFocusEffects()
        }
        .measured("form_parts_deleting_tag", .dialog, when: deletingTag != nil)
        .confirmationDialog("Delete the tag \(deletingTag?.name ?? "")?",
                            isPresented: Binding(get: { deletingTag != nil },
                                                 set: { if !$0 { deletingTag = nil } }),
                            titleVisibility: .visible) {
            Button("Delete Tag", role: .destructive) {
                Measure.used("delete_tag")
                guard let target = deletingTag else { return }
                if model.deleteTag(kind: "commitment", name: target.name), tag == target.name {
                    tag = nil
                }
                deletingTag = nil
            }
            Button("Keep It", role: .cancel) { Measure.used("keep_it"); deletingTag = nil }
        } message: {
            Text("Commitments wearing it keep everything else; they just lose the tag.")
        }
        .measured("form_parts_deleting_entity", .dialog, when: deletingEntity != nil)
        .confirmationDialog("Delete \(deletingEntity?.name ?? "")?",
                            isPresented: Binding(get: { deletingEntity != nil },
                                                 set: { if !$0 { deletingEntity = nil } }),
                            titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                Measure.used("delete")
                guard let target = deletingEntity else { return }
                if model.deleteEntity(target.kind, id: target.entityId) { forget(target) }
                deletingEntity = nil
            }
            Button("Keep It", role: .cancel) { Measure.used("keep_it"); deletingEntity = nil }
        } message: {
            Text("Commitments paid from it stay; they simply stop naming it.")
        }
        #if DEBUG
        .onAppear {
            guard row == nil else { return }
            switch ProcessInfo.processInfo.environment["LONGBOOK_SNAPSHOT_OPEN"] {
            case "categories": browsing = .tag
            case "accounts": browsing = .account
            case "members": browsing = .member
            default: break
            }
        }
        #endif
    }

    // MARK: one rack as a row

    private var categoryRow: some View {
        FormRow {
            FormQuestion("Category")
        } content: {
            ChoiceField("Category", value: tag.map(categoryWord) ?? "None", empty: tag == nil,
                        choices: browseChoices(.tag), selected: tag, adding: browseAdding(.tag),
                        opensOnAppear: opensOnAppear, onPick: { pickBrowsed(.tag, $0) })
            .contextMenu {
                if let tag {
                    Button("Edit Tag…") { Measure.used("edit_tag", .contextMenu); editingTag = TagTarget(name: tag) }
                    if model.customTags(kind: "commitment").contains(tag) {
                        Button("Delete Tag…", role: .destructive) { Measure.used("delete_tag", .contextMenu); deletingTag = TagTarget(name: tag) }
                    }
                }
            }
        }
    }

    private func accountRow(_ label: String) -> some View {
        let chosen = model.editChoices.methods.first { $0.id == accountId }
        return VStack(alignment: .leading, spacing: LBSpacing.s2) {
            FormRow {
                FormQuestion(label)
            } content: {
                ChoiceField(label, value: chosen?.name ?? "None", empty: chosen == nil,
                            choices: browseChoices(.account), selected: accountId, adding: browseAdding(.account),
                            opensOnAppear: opensOnAppear, onPick: { pickBrowsed(.account, $0) })
                .contextMenu {
                    if let chosen {
                        Button("Edit Account…") {
                            Measure.used("edit_account", .contextMenu)
                            editingEntity = EntityTarget(kind: .paymentMethod, entityId: chosen.id, name: chosen.name)
                        }
                        Button("Delete Account…", role: .destructive) {
                            Measure.used("delete_account", .contextMenu)
                            deletingEntity = EntityTarget(kind: .paymentMethod, entityId: chosen.id, name: chosen.name)
                        }
                    }
                }
            }
            if let methodRefusal { refusalLine(methodRefusal).formContentColumn() }
        }
    }

    /// Only someone in People, or None: a person is never a name the row makes up.
    private func memberRow(_ label: String) -> some View {
        let chosen = model.editChoices.members.first { $0.id == memberId }
        return VStack(alignment: .leading, spacing: LBSpacing.s2) {
            FormRow {
                FormQuestion(label)
            } content: {
                ChoiceField(label, value: chosen?.name ?? "None", empty: chosen == nil,
                            choices: browseChoices(.member), selected: memberId, adding: browseAdding(.member),
                            opensOnAppear: opensOnAppear, onPick: { pickBrowsed(.member, $0) })
                .contextMenu {
                    if let chosen {
                        Button("Edit Person…") {
                            Measure.used("edit_person", .contextMenu)
                            editingEntity = EntityTarget(kind: .familyMember, entityId: chosen.id, name: chosen.name)
                        }
                        Button("Delete Person…", role: .destructive) {
                            Measure.used("delete_person", .contextMenu)
                            deletingEntity = EntityTarget(kind: .familyMember, entityId: chosen.id, name: chosen.name)
                        }
                    }
                }
            }
            if let memberRefusal { refusalLine(memberRefusal).formContentColumn() }
        }
    }

    /// A rack's full list, dropping from the rack on the Mac. A phone pushes it instead.
    private func browsed(_ target: BrowseTarget) -> BrowsePopover {
        BrowsePopover(open: Binding(get: { browsing == target },
                                    set: { if !$0, browsing == target { browsing = nil } })) {
            browseList(target)
        }
    }

    /// The whole rack as the list every choice field opens, its None first.
    private func browseList(_ target: BrowseTarget) -> ChoiceList {
        ChoiceList(title: target.title, choices: browseChoices(target), selected: browseSelection(target),
                   adding: browseAdding(target), onPick: { pickBrowsed(target, $0) }, onDone: { browsing = nil })
    }

    /// A typed category is set as the rack's field sets it; an account or a person is written,
    /// then chosen.
    private func browseAdding(_ target: BrowseTarget) -> ChoiceAdding {
        switch target {
        case .tag: ChoiceAdding { createBrowsed(.tag, $0) }
        case .account: .named("Account") { createBrowsed(.account, $0) }
        case .member: .named("Person") { createBrowsed(.member, $0) }
        }
    }

    private var categories: some View {
        // The library's vocabulary plus the vault's own; a worn tag no registry knows yet
        // (an AI's invention mid-flight) still shows. The seed joins so it's never invisible.
        // The rack shows the kinds most books use and every tag this book wears; the
        // browse button beside it opens the whole library.
        let usual: Set<String> = ["subscription", "rent", "emi", "insurance", "salary", "utility", "telecom", "education", "health & fitness", "streaming"]
        let own = Set(model.customTags(kind: "commitment")).union(model.editChoices.categories)
        let choices = model.tagChoices(kind: "commitment").filter { usual.contains($0.name) || own.contains($0.name) || $0.name == tag }
        let known = Set(model.tagChoices(kind: "commitment").map(\.name))
        let worn = model.editChoices.categories.filter { !known.contains($0) }
        let extra = tag.flatMap {
            known.contains($0) || worn.contains($0) || addingCategory ? nil : [$0]
        } ?? []
        return VStack(alignment: .leading, spacing: LBSpacing.s2) {
            FormRack("Category", adding: "category",
                     chosen: tag,
                     focusID: addingCategory ? Self.tagFieldID : nil,
                     railWidth: $railWidth,
                     add: { addingCategory = true },
                     browse: { browsing = .tag },
                     editor: {
                         if addingCategory {
                             // Bound straight to the tag, so what's typed IS the answer — a
                             // buffer committed on submit loses the name when Save is tapped.
                             LBChipField(BrowseTarget.tag.prompt, text: Binding(
                                 get: { tag ?? "" },
                                 set: { tag = $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 }
                             ), width: 148, focus: $tagFocused, onSubmit: { addingCategory = false })
                             .id(Self.tagFieldID)
                         }
                     }) {
                // The chosen tag first, then one just typed, then the rest — never behind
                // twenty seeded chips where it lands off-screen and has to be scrolled to.
                ForEach(orderedTags(worn: worn, extra: extra, choices: choices), id: \.name) { item in
                    editableChip(item.name, icon: item.icon).id(item.name)
                }
            }
        }
        .modifier(browsed(.tag))
    }

    private func orderedTags(worn: [String], extra: [String], choices: [(name: String, icon: String?)]) -> [(name: String, icon: String?)] {
        var items: [(name: String, icon: String?)] = (worn + extra).map { ($0, nil) } + choices
        if let tag = openedWith.tag, let at = items.firstIndex(where: { $0.name == tag }) {
            items.insert(items.remove(at: at), at: 0)
        }
        return items
    }

    /// One tag: a tap picks it, a press and hold opens what can be done to it. The
    /// system menu brings its own knock and its own blur, so the chip stays a chip.
    private func editableChip(_ name: String, icon: String?) -> some View {
        LBChip(categoryWord(name), symbol: icon ?? CategoryGlyph.symbol(name),
               style: .choice(selected: tag == name)) {
            tag = tag == name ? nil : name
            addingCategory = false
        }
        .contextMenu {
            Button { Measure.used("edit_tag", .contextMenu); editingTag = TagTarget(name: name) } label: {
                Label("Edit Tag", systemImage: "pencil")
            }
            // Only a tag this vault owns can be deleted. A seeded one has no registry
            // entry to remove, so the delete appeared to work and the chip returned on
            // the next render — an affordance that lied.
            if model.customTags(kind: "commitment").contains(name) {
                Button(role: .destructive) { Measure.used("delete_tag", .contextMenu); deletingTag = TagTarget(name: name) } label: {
                    Label("Delete Tag", systemImage: "trash")
                }
            }
        }
        .accessibilityHint("Press and hold to edit or delete this tag")
    }

    private var howPaid: some View {
        VStack(alignment: .leading, spacing: LBSpacing.s2) {
            FormRack("Account", adding: "account",
                     chosen: accountId,
                     focusID: addingMethod ? Self.methodFieldID : nil,
                     railWidth: $railWidth,
                     add: { addingMethod = true },
                     browse: { browsing = .account },
                     editor: {
                         if addingMethod {
                             LBChipField(BrowseTarget.account.prompt, text: $typedMethod,
                                         width: 148, focus: $methodFocused,
                                         onSubmit: { methodRefusal = addMethod(typedMethod) })
                                 .id(Self.methodFieldID)
                         }
                     }) {
                ForEach(leading(model.editChoices.methods, id: openedWith.method), id: \.id) { method in
                    LBChip(method.name, symbol: LBGlyph.account, style: .choice(selected: accountId == method.id)) {
                        accountId = accountId == method.id ? nil : method.id
                        addingMethod = false
                    }
                    .frame(maxWidth: 230, alignment: .leading)
                    .id(method.id)
                    .chipMenu(
                        edit: { editingEntity = EntityTarget(kind: .paymentMethod, entityId: method.id, name: method.name) },
                        delete: { deletingEntity = EntityTarget(kind: .paymentMethod, entityId: method.id, name: method.name) },
                        noun: "Account"
                    )
                }
            }
            if let methodRefusal { refusalLine(methodRefusal) }
        }
        .modifier(browsed(.account))
        .onChange(of: typedMethod) { _, _ in methodRefusal = nil }
        .onChange(of: addingMethod) { _, open in if !open { methodRefusal = nil } }
    }

    private var whoFor: some View {
        VStack(alignment: .leading, spacing: LBSpacing.s2) {
            FormRack("Person", adding: "person",
                     chosen: memberId,
                     focusID: addingMember ? Self.memberFieldID : nil,
                     railWidth: $railWidth,
                     add: { addingMember = true },
                     browse: { browsing = .member },
                     editor: {
                         if addingMember {
                             LBChipField(BrowseTarget.member.prompt, text: $typedMember,
                                         width: 148, focus: $memberFocused,
                                         onSubmit: { memberRefusal = addMember(typedMember) })
                                 .id(Self.memberFieldID)
                         }
                     }) {
                ForEach(leading(model.editChoices.members, id: openedWith.member), id: \.id) { member in
                    LBChip(member.name, symbol: LBGlyph.member, style: .choice(selected: memberId == member.id)) {
                        memberId = memberId == member.id ? nil : member.id
                        addingMember = false
                    }
                    .frame(maxWidth: 230, alignment: .leading)
                    .id(member.id)
                    .chipMenu(
                        edit: { editingEntity = EntityTarget(kind: .familyMember, entityId: member.id, name: member.name) },
                        delete: { deletingEntity = EntityTarget(kind: .familyMember, entityId: member.id, name: member.name) },
                        noun: "Person"
                    )
                }
            }
            if let memberRefusal { refusalLine(memberRefusal) }
        }
        .modifier(browsed(.member))
        .onChange(of: typedMember) { _, _ in memberRefusal = nil }
        .onChange(of: addingMember) { _, open in if !open { memberRefusal = nil } }
    }

    /// A refusal where the name was typed, in the form's urgent footnote.
    private func refusalLine(_ text: String) -> some View {
        Text(text)
            .lbText(.footnote)
            .foregroundStyle(LBColor.urgent.color)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// The chosen one leads its rack, so an open form shows what is set without a scroll.
    private func leading(_ list: [(id: String, name: String)], id: String?) -> [(id: String, name: String)] {
        guard let id, let at = list.firstIndex(where: { $0.id == id }) else { return list }
        return [list[at]] + list.enumerated().filter { $0.offset != at }.map(\.element)
    }

    /// Naming an account or a person writes it into the vault, then selects it — matched on
    /// the normalised name, so a name already there is chosen rather than duplicated. Nil once
    /// chosen; otherwise the writer's refusal, for the caller to show where the name was typed.
    private func addMethod(_ name: String) -> String? {
        let known = Set(model.editChoices.methods.map(\.id))
        guard let id = model.addEntity(.paymentMethod, named: name) else { return refusal() }
        if !known.contains(id) { typing.added.append(id) }
        accountId = id
        typedMethod = ""
        addingMethod = false
        return nil
    }

    private func addMember(_ name: String) -> String? {
        let known = Set(model.editChoices.members.map(\.id))
        guard let id = model.addEntity(.familyMember, named: name) else { return refusal() }
        if !known.contains(id) { typing.added.append(id) }
        memberId = id
        typedMember = ""
        addingMember = false
        return nil
    }

    /// The write's refusal of a typed name, felt and announced as the One-time refusal is:
    /// a name left standing in its pill is easy to miss.
    private func refusal() -> String {
        let why = model.saveError ?? "That didn’t save."
        LBHaptics.warn()
        AccessibilityNotification.Announcement(why).post()
        return why
    }

    /// A name left in an open pill, written and chosen as return would. An empty pill is
    /// left alone; a refused name stops the Save, its refusal under the pill's rack.
    private func submitTyped() -> Bool {
        if addingMethod, !typedMethod.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let refused = addMethod(typedMethod) {
            methodRefusal = refused
            return false
        }
        if addingMember, !typedMember.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let refused = addMember(typedMember) {
            memberRefusal = refused
            return false
        }
        return true
    }

    /// A deleted account or person stops being the form's choice, so Save never writes its
    /// id back — whether it went from the chip's menu or from its own edit sheet.
    private func forget(_ target: EntityTarget) {
        if target.kind == .paymentMethod, accountId == target.entityId { accountId = nil }
        if target.kind == .familyMember, memberId == target.entityId { memberId = nil }
    }

    /// Naming one in the full list does what naming it on the rail does: the tag is set as
    /// the field sets it, and an account or a person is written and then selected. A refusal
    /// goes back to the list, which keeps the name and says why.
    private func createBrowsed(_ target: BrowseTarget, _ name: String) -> String? {
        switch target {
        case .tag:
            tag = name
            addingCategory = false
            return nil
        case .account:
            return addMethod(name)
        case .member:
            return addMember(name)
        }
    }

    /// The same set the rail carries, in the same order — the list is the rack, not a
    /// second opinion about it. A tag the vault wears but no registry knows still shows.
    private func browseChoices(_ target: BrowseTarget) -> [ChoicePickerView.Choice] {
        switch target {
        case .tag:
            let choices = model.tagChoices(kind: "commitment")
            let known = Set(choices.map(\.name))
            let worn = model.editChoices.categories.filter { !known.contains($0) }
            let extra = tag.flatMap { known.contains($0) || worn.contains($0) ? nil : [$0] } ?? []
            return (worn + extra).map {
                ChoicePickerView.Choice(id: $0, name: categoryWord($0), symbol: CategoryGlyph.symbol($0))
            } + choices.map {
                ChoicePickerView.Choice(id: $0.name, name: categoryWord($0.name),
                                        symbol: $0.icon ?? CategoryGlyph.symbol($0.name))
            }
        case .account:
            // An account's row says whose it is.
            let owners = Dictionary(model.entityChoices(.paymentMethod).compactMap { account in
                account.owner.map { (account.id, $0.name) }
            }, uniquingKeysWith: { first, _ in first })
            return model.editChoices.methods.map {
                ChoicePickerView.Choice(id: $0.id, name: $0.name, symbol: LBGlyph.account, detail: owners[$0.id])
            }
        case .member:
            let ties = Dictionary(model.entityChoices(.familyMember).compactMap { person in
                person.tag.flatMap { $0.isEmpty ? nil : (person.id, EntityCopy.tagWord($0)) }
            }, uniquingKeysWith: { first, _ in first })
            return model.editChoices.members.map {
                ChoicePickerView.Choice(id: $0.id, name: $0.name, symbol: LBGlyph.member, detail: ties[$0.id])
            }
        }
    }

    private func browseSelection(_ target: BrowseTarget) -> String? {
        switch target {
        case .tag: return tag
        case .account: return accountId
        case .member: return memberId
        }
    }

    /// A pick sets the rack's field, None clears it, and a name half typed on the rail closes.
    private func pickBrowsed(_ target: BrowseTarget, _ value: String?) {
        switch target {
        case .tag:
            tag = value
            addingCategory = false
        case .account:
            accountId = value
            addingMethod = false
        case .member:
            memberId = value
            addingMember = false
        }
    }
}

/// A rack's full list on the Mac, dropping from the rack as a choice field's list drops from
/// its field. A phone pushes the list, so the rack is left as it is.
private struct BrowsePopover: ViewModifier {
    @Binding var open: Bool
    let list: () -> ChoiceList

    func body(content: Content) -> some View {
        #if os(macOS)
        content
            .measured("form_parts_browsing", .popover, when: open)
            .popover(isPresented: $open, arrowEdge: .bottom) { list().lbKeyboardFocusEffects() }
        #else
        content
        #endif
    }
}

/// A chip that names something the vault owns: held down, it offers the two things that
/// can be done to that thing. The system menu supplies the knock and the blur.
private extension View {
    func chipMenu(edit: @escaping () -> Void, delete: @escaping () -> Void, noun: String) -> some View {
        contextMenu {
            Button(action: { Measure.used("edit"); edit() }) { Label("Edit \(noun)", systemImage: "pencil") }
            Button(role: .destructive, action: { Measure.used("delete"); delete() }) { Label("Delete \(noun)", systemImage: "trash") }
        }
        .accessibilityHint("Press and hold to edit or delete this \(noun.lowercased())")
    }
}

// MARK: - the money picker

/// Which way the money moves: two rows, one chosen. Money in is kept beside the spending and
/// never added to a total. A transfer is no choice: its accounts make it one, so a row that is
/// one reads so, with nothing to pick.
struct MoneyPicker: View {
    @Binding var direction: String?
    let onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: LBSpacing.s3) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Money")
                        .lbText(.screenTitle)
                        .foregroundStyle(LBColor.textPrimary.color)
                    Text("Which way it moves.")
                        .lbText(.footnote)
                        .foregroundStyle(LBColor.textTertiary.color)
                }
                Spacer()
                Button(action: { Measure.used("close"); onDone() }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(LBColor.textSecondary.color)
                        .frame(width: 30, height: 30)
                        .background(LBColor.chrome.color, in: Circle())
                }
                .lbButtonStyle()
                .help("Close")
                .accessibilityLabel("Close")
            }
            if direction == "transfer" {
                optionLabel("Transfer", detail: "Both accounts belong to a person whose Relationship is Self. It changes when its accounts or their owners do.",
                            symbol: LBGlyph.transfer, selected: true)
            } else {
                // Out is written as absence; the core decides what the file keeps of the other.
                option("Money out", detail: "Money that goes out.", symbol: LBGlyph.expense,
                       selected: VaultPatch.storedDirection(direction) == nil) {
                    direction = VaultPatch.storedDirection("out")
                }
                option("Money in", detail: "Money that comes in. Kept beside your expenses, never added to them.",
                       symbol: LBGlyph.income, selected: direction == "in") {
                    direction = VaultPatch.storedDirection("in")
                }
            }
        }
        .padding(LBSpacing.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LBColor.canvas.color)
        #if os(iOS)
        .presentationDetents([.height(380)])
        .presentationDragIndicator(.visible)
        #else
        .frame(width: 380)
        #endif
        .lbClosesOnOutsideClick(onDone)
    }

    private func option(_ title: String, detail: String, symbol: String, selected: Bool,
                        pick: @escaping () -> Void) -> some View {
        Button {
            Measure.used("pick_done")
            LBHaptics.tap()
            pick()
            onDone()
        } label: {
            optionLabel(title, detail: detail, symbol: symbol, selected: selected)
        }
        .lbButtonStyle()
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func optionLabel(_ title: String, detail: String, symbol: String, selected: Bool) -> some View {
        HStack(spacing: LBSpacing.s3) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(selected ? LBColor.onBrandTint.color : LBColor.textSecondary.color)
                .frame(width: 30, height: 30)
                .background(selected ? LBColor.brand.color.opacity(0.16) : LBColor.chrome.color, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .lbText(.body)
                    .foregroundStyle(LBColor.textPrimary.color)
                Text(detail)
                    .lbText(.footnote)
                    .foregroundStyle(LBColor.textTertiary.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: LBSpacing.s2)
            if selected {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(LBColor.brandText.color)
            }
        }
        .padding(LBSpacing.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LBColor.card.color, in: RoundedRectangle(cornerRadius: LBRadius.sm, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: LBRadius.sm, style: .continuous)
                .strokeBorder(selected ? LBColor.brand.color : LBColor.hairline.color, lineWidth: 1)
        )
        .contentShape(Rectangle())
    }
}

// MARK: - an Edit form's foot

/// The foot of an Edit form, under everything it acts on: on the Mac Delete at the left, Cancel
/// and Save at the right with Esc and Return bound to them; on a phone Cancel and Save, Delete
/// being the form's last row. Each button takes only its own width.
struct EditFormFooter<Delete: View>: View {
    /// What the form edits, in Save's name.
    let word: String
    var canSave = true
    /// Whether Return saves: a form beside a list only while focus is in it.
    var saveOnReturn = true
    let cancel: () -> Void
    let save: () -> Void
    @ViewBuilder let delete: () -> Delete

    var body: some View {
        HStack(spacing: LBSpacing.s2) {
            #if os(macOS)
            delete().fixedSize()
            Spacer(minLength: 0)
            cancelButton
            #else
            cancelButton
            Spacer(minLength: LBSpacing.s2)
            #endif
            saveButton
        }
        .padding(.horizontal, LBSpacing.s4)
        .padding(.vertical, LBSpacing.s3)
        .background(LBColor.canvas.color)
    }

    private var cancelButton: some View {
        Button(action: { Measure.used("cancel"); cancel() }) {
            Text("Cancel")
                .lbText(.label)
                .foregroundStyle(LBColor.textSecondary.color)
                .lineLimit(1)
                .fixedSize()
                .frame(minHeight: 32)
                .contentShape(Rectangle())
        }
        .lbButtonStyle()
        .keyboardShortcut(.cancelAction)
    }

    private var saveButton: some View {
        Button(action: { Measure.used("save"); save() }) {
            Text("Save \(word)")
                .lbText(.label)
                .foregroundStyle((canSave ? LBColor.onBrand : LBColor.textTertiary).color)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, LBSpacing.s3)
                .frame(minHeight: saveHeight)
                .background((canSave ? LBColor.brand : LBColor.chrome).color, in: Capsule())
                .contentShape(Capsule())
        }
        .lbButtonStyle(.capsule)
        .disabled(!canSave)
        .keyboardShortcut(saveOnReturn ? .defaultAction : nil)
    }

    private var saveHeight: CGFloat {
        #if os(macOS)
        32
        #else
        44
        #endif
    }
}

/// An Edit form's red word, the same at the foot of the Mac's form and the end of a phone's.
struct EditFormDeleteLabel: View {
    let title: String

    var body: some View {
        Text(title)
            .lbText(.label)
            .foregroundStyle(LBColor.danger.color)
            .lineLimit(1)
            .frame(minHeight: 32)
            .contentShape(Rectangle())
    }
}
