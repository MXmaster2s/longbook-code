import DesignSystem
import LongbookCore
import SwiftUI

/// A day to pick, in the system's own calendar: it brings the reader's locale, its
/// accessibility and today's mark with it. The bounds say which days can be taken; a day
/// outside them is shown, never taken. Done closes the sheet; the pick is live before it.
struct DayPickerView: View {
    let title: String
    let selected: Date
    /// The first and last days that can be picked.
    var earliest: Date?
    var latest: Date?
    let onPick: (Date) -> Void
    let onDone: () -> Void

    var body: some View {
        // Scrolled, because the calendar grows with the reader's type size and a sheet at a
        // fixed detent would otherwise cut off the last week.
        ScrollView {
            VStack(alignment: .leading, spacing: LBSpacing.s2) {
                header
                calendar
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                    .tint(LBColor.brand.color)
                    .frame(maxWidth: .infinity)
            }
            .padding(LBSpacing.s4)
            .frame(maxWidth: 460)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        #if os(macOS)
        // A popover's own size: the calendar at its natural width, no scroll to speak of.
        .frame(width: 300, height: 330)
        #endif
        .background(LBColor.canvas.color)
        .lbClosesOnOutsideClick(onDone)
    }

    private var header: some View {
        HStack(spacing: LBSpacing.s2) {
            Text(title)
                .lbText(.label)
                .foregroundStyle(LBColor.textPrimary.color)
            Spacer(minLength: LBSpacing.s3)
            Button(action: { Measure.used("done"); onDone() }) {
                Text("Done")
                    .lbText(.label)
                    .foregroundStyle(LBColor.brandText.color)
                    .padding(.horizontal, LBSpacing.s2)
                    .frame(minHeight: 34)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.defaultAction)
            // On the Mac the sheet has no swipe down, so Escape closes it too.
            #if os(macOS)
            Button(action: { Measure.used("close"); onDone() }) {
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
    }

    /// The pick lands on the host at once, at midnight of the day, as the grid's taps did.
    private var day: Binding<Date> {
        Binding(get: { selected }, set: { picked in
            LBHaptics.tap()
            onPick(LB.dayOf(picked))
        })
    }

    @ViewBuilder
    private var calendar: some View {
        switch (earliest.map(LB.dayOf), latest.map(LB.dayOf)) {
        case let (first?, last?) where first <= last:
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
