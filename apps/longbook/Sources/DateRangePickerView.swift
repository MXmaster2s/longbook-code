import DesignSystem
import LongbookCore
import SwiftUI

/// The list's Date window: a first day and a last, each picked on its own day sheet. A
/// change lands as it is made — the sheet is a lens on the list, never a draft of it.
struct DateRangePickerView: View {
    @Binding var from: Date?
    @Binding var to: Date?
    let onDone: () -> Void

    @State private var pickingFrom = false
    @State private var pickingTo = false

    /// The day sheet wants a day to stand on; an open end stands on the other, else today.
    private var fromDay: Binding<Date> {
        Binding(get: { from ?? to ?? LB.todayMid() }, set: { from = $0 })
    }

    private var toDay: Binding<Date> {
        Binding(get: { to ?? from ?? LB.todayMid() }, set: { to = $0 })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: LBSpacing.s3) {
            header
            // Each end is bounded by the other, so an inverted window cannot be made.
            FormDateControl(title: "From", date: fromDay, picking: $pickingFrom, latest: to,
                            unset: from == nil ? "Not set" : nil)
            FormDateControl(title: "To", date: toDay, picking: $pickingTo, earliest: from,
                            unset: to == nil ? "Not set" : nil)
            clearButton
        }
        .padding(LBSpacing.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LBColor.canvas.color)
        #if os(iOS)
        .presentationDetents([.height(330)])
        .presentationDragIndicator(.visible)
        #else
        .frame(width: 380)
        #endif
        .lbClosesOnOutsideClick(onDone)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Date")
                    .lbText(.screenTitle)
                    .foregroundStyle(LBColor.textPrimary.color)
                Text("The first day and the last, both included.")
                    .lbText(.footnote)
                    .foregroundStyle(LBColor.textTertiary.color)
            }
            Spacer()
            Button(action: onDone) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(LBColor.textSecondary.color)
                    .frame(width: 30, height: 30)
                    .background(LBColor.chrome.color, in: Circle())
            }
            .buttonStyle(.plain)
            #if os(macOS)
            .keyboardShortcut(.cancelAction)
            #endif
            .accessibilityLabel("Close")
        }
    }

    /// Both ends open again. Quiet while there is nothing to clear.
    private var clearButton: some View {
        let empty = from == nil && to == nil
        return Button {
            LBHaptics.tap()
            from = nil
            to = nil
        } label: {
            Text("Clear")
                .lbText(.footnote)
                .foregroundStyle(empty ? LBColor.textQuaternary.color : LBColor.brandText.color)
                .padding(.vertical, LBSpacing.s2)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(empty)
    }
}
