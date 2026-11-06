import DesignSystem
import LongbookCore
import SwiftUI

/// One commitment, read whole: its Preview, pushed on a phone and in a sheet where a screen
/// names one from outside a stack.
struct CommitmentDetailView: View {
    let model: DashboardModel
    let id: String
    /// Present when the screen sits in a sheet rather than a push: the way out. A Mac
    /// sheet offers no swipe-down, so without this the reader would be trapped.
    var onClose: (() -> Void)?

    var body: some View {
        if let onClose {
            CardPreviewSheet(model: model, card: .commitment(id: id), onClose: onClose)
        } else {
            CardPreviewView(model: model, card: .commitment(id: id))
        }
    }
}

/// Every charge of one commitment before today, newest first: its day, amount, mark and
/// note. A tap opens that charge's form.
struct CommitmentHistoryView: View {
    let model: DashboardModel
    let id: String
    let onDone: () -> Void
    @State private var editing: Charge?

    private var past: [Charge] {
        let today = LB.todayMid()
        return model.charges(of: id).filter { $0.date < today }.reversed()
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(model.subscription(id: id)?.name ?? "History")
                    .lbText(.headline)
                    .foregroundStyle(LBColor.textPrimary.color)
                    .lineLimit(1)
                Spacer()
                Button("Done", action: { Measure.used("done"); onDone() })
                    .foregroundStyle(LBColor.brandText.color)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(LBSpacing.s4)
            List {
                Section {
                    ForEach(past) { charge in
                        Button { Measure.used("editing"); editing = charge } label: {
                            LBListRow(
                                LB.longDate(charge.date),
                                secondary: ChargeNote.labelled(charge.row.note).map { $0.label == "Note" ? $0.value : "\($0.label): \($0.value)" },
                                amount: fmtMoney(charge.amount, charge.currency),
                                chevron: true
                            )
                        }
                        .lbButtonStyle()
                        .lbListRowBackground()
                    }
                } header: {
                    LBSectionHeader("Before today")
                }
            }
            .lbGroupedList()
        }
        .background(LBColor.canvas.color)
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 480)
        #endif
        .lbClosesOnOutsideClick(onDone)
        .measured("commitment_detail_editing", .sheet, when: editing != nil)
        .sheet(item: $editing) { charge in
            RenewalFormView(model: model, editingId: id, chargeISO: charge.row.date) { editing = nil }
                .lbThreeQuarterSheet()
                .lbKeyboardFocusEffects()
        }
    }
}
