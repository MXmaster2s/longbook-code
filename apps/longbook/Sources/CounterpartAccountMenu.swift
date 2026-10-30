import DesignSystem
import LongbookCore
import SwiftUI

/// The account on the other side of one row: pick one of the book's accounts, or None. A
/// pick re-runs the Transfers rule, and asks first when that turns rows into Transfers or back.
struct CounterpartAccountMenu: View {
    let model: DashboardModel
    /// The commitment whose row this edits.
    let id: String

    private struct Ask: Identifiable {
        let id = UUID()
        let accountId: String?
        let flips: TransferFlipWords.Flips
    }

    @State private var asking: Ask?

    private var named: (id: String?, name: String?) {
        model.subscription(id: id).map(CounterpartAccounts.counterpart(of:)) ?? (nil, nil)
    }

    private var current: String? {
        named.id.flatMap { model.entityNames(memberId: nil, methodId: $0).method } ?? named.name
    }

    /// Every account but the one the row is paid from.
    private var choices: [(id: String, name: String)] {
        let own = model.subscription(id: id)?.paymentMethodId
        return model.editChoices.methods.filter { $0.id != own }
    }

    var body: some View {
        Menu {
            Button("None") { Measure.used("counterpart_none", .menuItem); pick(nil) }
            ForEach(choices, id: \.id) { choice in
                Button(choice.name) { Measure.used("counterpart_account", .menuItem); pick(choice.id) }
            }
        } label: {
            HStack(spacing: LBSpacing.s1) {
                Text(current ?? "None")
                    .lbText(.body)
                    .foregroundStyle(current == nil ? LBColor.textTertiary.color : LBColor.textPrimary.color)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(LBColor.textTertiary.color)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .lbButtonStyle()
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("Counterpart account")
        .accessibilityValue(current ?? "None")
        .measured("counterpart_confirming_flip", .alert, when: asking != nil)
        .alert("Change charges?", isPresented: Binding(get: { asking != nil }, set: { if !$0 { asking = nil } }),
               presenting: asking) { ask in
            Button("Change") {
                Measure.used("change")
                model.setCounterpartAccount(ask.accountId, onCommitment: id)
            }
            Button("Cancel", role: .cancel) { Measure.used("cancel") }
        } message: { ask in
            Text(TransferFlipWords.message(ask.flips))
        }
    }

    private func pick(_ accountId: String?) {
        guard accountId != named.id else { return }
        let flips = model.transferFlips(settingCounterpart: accountId, onCommitment: id)
        if TransferFlipWords.isZero(flips) {
            model.setCounterpartAccount(accountId, onCommitment: id)
        } else {
            asking = Ask(accountId: accountId, flips: flips)
        }
    }
}
