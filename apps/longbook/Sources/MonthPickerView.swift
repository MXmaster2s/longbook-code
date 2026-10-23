import DesignSystem
import LongbookCore
import SwiftUI

/// One year of months as a grid of tiles. A menu hid the year and dropped the reader at
/// the top of a two-year list; twelve tiles show a whole year at once and step by year.
/// Select mode gathers several months, tap by tap.
struct MonthPickerView: View {
    /// The months the cards answer for. A change lands as it is made: the sheet is a lens
    /// on the cards, never a draft of them.
    @Binding var selection: MonthSelection
    let range: ClosedRange<Int>
    /// The months that hold a charge, as offsets; the others draw fainter, so an empty
    /// month can be seen before it is opened.
    let filled: Set<Int>
    /// When true an empty month draws fainter and, in Select mode, shakes instead of
    /// joining the chosen months. Alone it opens, and the month card offers the way to its data.
    let gatesEmpty: Bool
    let onImport: (Int) -> Void
    let onAdd: (Int) -> Void
    let onDone: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown: Int?
    /// The empty month that shook, and the one now reading "Add data?".
    @State private var warned: Int?
    @State private var asking: Int?
    @State private var shakes = 0
    /// The only chosen month, refused when a tap tried to take it away, and its own shakes.
    @State private var refused: Int?
    @State private var refusals = 0
    /// Select mode: a tap puts a month in or takes it out, and the sheet stays open. It
    /// opens this way when several months are already chosen.
    @State private var selecting: Bool

    init(
        selection: Binding<MonthSelection>, range: ClosedRange<Int>, filled: Set<Int> = [],
        gatesEmpty: Bool = false, onImport: @escaping (Int) -> Void = { _ in },
        onAdd: @escaping (Int) -> Void = { _ in }, onDone: @escaping () -> Void
    ) {
        _selection = selection
        self.range = range
        self.filled = filled
        self.gatesEmpty = gatesEmpty
        self.onImport = onImport
        self.onAdd = onAdd
        self.onDone = onDone
        _selecting = State(initialValue: selection.wrappedValue.count > 1)
    }

    private static let columns = Array(
        repeating: GridItem(.flexible(), spacing: LBSpacing.s2), count: 3
    )
    private static let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
                                 "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

    private var anchor: Date { LB.firstOfMonth(LB.todayMid()) }
    /// The year stepped to, else the year of the latest month chosen.
    private var year: Int {
        shown ?? LB.calendar.component(.year, from: LB.addMonths(anchor, selection.months.last ?? 0))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: LBSpacing.s4) {
            header
            LazyVGrid(columns: Self.columns, spacing: LBSpacing.s2) {
                ForEach(0..<12, id: \.self) { index in
                    tile(index)
                }
            }
            currentButton
        }
        .contentShape(Rectangle())
        // A sideways swipe steps the year, as the chevrons do, when that year has a month to open.
        .simultaneousGesture(
            DragGesture(minimumDistance: 24).onEnded { drag in
                guard abs(drag.translation.width) > abs(drag.translation.height) else { return }
                let next = year + (drag.translation.width < 0 ? 1 : -1)
                guard (1...12).contains(where: { month in offset(month, in: next).map(range.contains) ?? false }) else { return }
                LBHaptics.tap()
                shown = next
            }
        )
        .padding(LBSpacing.s4)
        .frame(maxWidth: 460)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        #if os(macOS)
        .frame(minWidth: 380, minHeight: 360)
        #endif
        .background(LBColor.canvas.color)
        .lbClosesOnOutsideClick(onDone)
        .onAppear {
            #if DEBUG
            // The snapshot harness names a month offset to show shaken or asking, and can
            // open the grid in Select mode.
            let env = ProcessInfo.processInfo.environment
            if let raw = env["LONGBOOK_SNAPSHOT_WARN"], let off = Int(raw) { warned = off }
            if let raw = env["LONGBOOK_SNAPSHOT_ASK"], let off = Int(raw) { asking = off }
            if env["LONGBOOK_SNAPSHOT_SELECT"] == "1" { selecting = true }
            #endif
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: LBSpacing.s1) {
            HStack(spacing: LBSpacing.s2) {
                Text("Choose Month")
                    .lbText(.headline)
                    .foregroundStyle(LBColor.textPrimary.color)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: LBSpacing.s3)
                step(-1, "chevron.left")
                Text(String(year))
                    .lbText(.label)
                    .foregroundStyle(LBColor.textPrimary.color)
                    .monospacedDigit()
                step(1, "chevron.right")
                selectButton
                // On the Mac a sheet swallows every click outside it, so a picker with no
                // close control is a trap: the only way out was choosing a month.
                #if os(macOS)
                Button(action: onDone) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(LBColor.textSecondary.color)
                        .padding(LBSpacing.s2)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
                .accessibilityLabel("Close")
                #endif
            }
            // Only a count worth saying: one month is what the tile already shows.
            if selecting, selection.count > 1 {
                Text("\(selection.count) months selected")
                    .lbText(.footnote)
                    .foregroundStyle(LBColor.textTertiary.color)
            }
        }
    }

    /// The way back to this month alone, from any year and any selection.
    private var currentButton: some View {
        Button {
            LBHaptics.tap()
            selecting = false
            selection = MonthSelection()
            onDone()
        } label: {
            Text("This Month")
                .foregroundStyle(LBColor.brandText.color)
                .lbText(.footnote)
                .foregroundStyle(atCurrent ? LBColor.textQuaternary.color : LBColor.brandText.color)
                .padding(.horizontal, LBSpacing.s3)
                .frame(minHeight: 34)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(atCurrent)
        .frame(maxWidth: .infinity)
        .accessibilityLabel("Back to the current month")
    }

    /// Nothing for the button to do: this month alone, its own year on show, outside Select mode.
    private var atCurrent: Bool {
        selection == MonthSelection() && shown == nil && !selecting
    }

    /// Select gathers several months; Done closes the sheet on whatever is chosen.
    private var selectButton: some View {
        Button {
            LBHaptics.tap()
            if selecting {
                onDone()
            } else {
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) { selecting = true }
            }
        } label: {
            Text(selecting ? "Done" : "Select")
                .lbText(.footnote)
                .foregroundStyle(LBColor.brandText.color)
                .padding(.horizontal, LBSpacing.s2)
                .frame(minHeight: 34)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(selecting ? "Done" : "Select several months")
    }

    private func step(_ delta: Int, _ symbol: String) -> some View {
        let next = year + delta
        let open = (1...12).contains { month in offset(month, in: next).map(range.contains) ?? false }
        return Button {
            LBHaptics.tap()
            shown = next
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(open ? LBColor.textSecondary.color : LBColor.textQuaternary.color)
                .frame(width: 34, height: 34)
                .background(LBColor.chrome.color, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!open)
        .accessibilityLabel(delta < 0 ? "Previous year" : "Next year")
    }

    private func tile(_ index: Int) -> some View {
        let off = offset(index + 1, in: year)
        let open = off.map(range.contains) ?? false
        let picked = off.map(selection.contains) ?? false
        // A month with charges is bright; one the book has nothing for is faint. Gated,
        // the empty one shakes at the first tap, asks at the second, and opens the way
        // to its data at the third; ungated it simply opens.
        let holds = filled.isEmpty || off.map(filled.contains) ?? false
        let gated = gatesEmpty && !holds && !picked
        let isWarned = gated && warned == off
        let isAsking = gated && asking == off
        let isRefused = refused != nil && refused == off
        // In Select mode a month that opens is a switch: a tap puts it in or takes it out.
        let toggles = selecting && open && !gated
        return Button {
            guard let off, open else { return }
            if selecting {
                // Several months together: an empty one has nothing to add to the sum,
                // so it shakes instead of joining.
                if gated {
                    LBHaptics.warn()
                    asking = nil
                    warned = off
                    withAnimation(reduceMotion ? nil : .default) { shakes += 1 }
                } else {
                    toggle(off)
                }
            } else {
                // One month alone opens, empty or not: the month card then says what
                // to add and offers the way.
                LBHaptics.tap()
                selection = MonthSelection(off)
                onDone()
            }
        } label: {
            // One line, not two. The year was set in all twelve tiles while the header
            // states it two lines above — and being the widest thing in the tile, it was
            // what forced the height and left the month sitting in a quarter of its cell.
            Text(isAsking ? "Add data?" : Self.months[index])
                .lbText(.body)
                .foregroundStyle(picked ? LBColor.onBrand.color
                                 : !open ? LBColor.textQuaternary.color
                                 : isWarned ? LBColor.urgent.color
                                 : isAsking ? LBColor.brandText.color
                                 : holds ? LBColor.textPrimary.color : LBColor.textTertiary.color)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 48)
                .modifier(Shake(times: isWarned && !reduceMotion ? CGFloat(shakes) : 0))
                .modifier(Shake(times: isRefused && !reduceMotion ? CGFloat(refusals) : 0))
            .background(
                picked ? LBColor.brand.color : LBColor.card.color,
                in: RoundedRectangle(cornerRadius: LBRadius.sm, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: LBRadius.sm, style: .continuous)
                    .strokeBorder(picked ? Color.clear : LBColor.hairline.color, lineWidth: 1)
            )
            // A chosen month in Select mode carries a check, so the choice reads without colour.
            .overlay(alignment: .topTrailing) {
                if selecting && picked {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(LBColor.onBrand.color)
                        .padding(LBSpacing.s2)
                        .accessibilityHidden(true)
                }
            }
            // A month with nothing in it sits well back, so the eye sees the gap.
            .opacity(gated && !isWarned && !isAsking ? 0.38 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!open)
        .accessibilityLabel(isAsking ? "Add data for \(Self.months[index]) \(year)" : "\(Self.months[index]) \(year)")
        .accessibilityValue(gated && !isAsking ? "No charges" : "")
        .accessibilityHint(toggles ? "Adds or removes this month" : "")
        .accessibilityAddTraits(picked ? [.isSelected] : [])
        .accessibilityAddTraits(toggles ? [.isToggle] : [])
    }

    /// One month in or out, at once. The year on show holds still while the months change
    /// under it. Taking away the only month is refused: felt, seen as a shake, and said.
    private func toggle(_ off: Int) {
        var next = selection
        guard next.toggle(off) else {
            LBHaptics.warn()
            refused = off
            withAnimation(reduceMotion ? nil : .default) { refusals += 1 }
            AccessibilityNotification.Announcement("At least one month stays selected").post()
            return
        }
        LBHaptics.tap()
        shown = year
        warned = nil
        asking = nil
        selection = next
    }

    /// A sideways shudder, three swings, over the change of `times`.
    private struct Shake: GeometryEffect {
        var times: CGFloat
        var animatableData: CGFloat {
            get { times }
            set { times = newValue }
        }
        func effectValue(size: CGSize) -> ProjectionTransform {
            ProjectionTransform(CGAffineTransform(translationX: 6 * sin(times * .pi * 6), y: 0))
        }
    }

    /// How far a month sits from this one, or nil for a date the calendar cannot make.
    private func offset(_ month: Int, in year: Int) -> Int? {
        guard let date = LB.calendar.date(from: DateComponents(year: year, month: month, day: 1))
        else { return nil }
        return LB.calendar.dateComponents([.month], from: anchor, to: LB.firstOfMonth(date)).month
    }
}
