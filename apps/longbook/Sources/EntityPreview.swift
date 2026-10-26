import DesignSystem
import LongbookCore
import SwiftUI

/// The list card of whatever is being edited, redrawn from the fields as they are typed, as
/// a panel beside the form where there is room for one.
struct EntityPreviewPanel: View {
    let card: DashboardModel.EntityCard

    private var eyebrow: String {
        card.kind == .paymentMethod ? "Account preview" : "Person preview"
    }

    var body: some View {
        LBPanel(eyebrow: eyebrow) {
            EntityCardView(card: card, style: .preview)
        }
    }
}

/// A few charges of an account or a person, each a door to its commitment: the latest
/// that landed, or the next still owed. "Show all" is the panel's own link to the list.
struct EntityRecentPanel: View {
    var eyebrow = "Recent activity"
    var emptyWords = "No charge has landed here yet."
    let moments: [DashboardModel.EntityMoment]
    /// Every charge of the kind, of which these are a few.
    let total: Int
    /// Where every one is listed, when there are more than shown.
    var showAll: Destination? = nil
    let open: (String) -> Void

    var body: some View {
        LBPanel(eyebrow: eyebrow, note: total > moments.count ? "\(moments.count) of \(total)" : nil) {
            if moments.isEmpty {
                Text(emptyWords)
                    .lbText(.footnote)
                    .foregroundStyle(LBColor.textSecondary.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(spacing: LBSpacing.s1) {
                ForEach(moments) { moment in
                    Button { Measure.used("open_commitment"); open(moment.commitmentId) } label: {
                        EntityMomentRow(moment: moment)
                    }
                    .lbButtonStyle()
                    .accessibilityHint("Opens \(moment.name)")
                }
            }
            if let showAll, total > moments.count || !moments.isEmpty {
                NavigationLink(value: showAll) {
                    Text("Show all")
                        .lbText(.label)
                        .foregroundStyle(LBColor.brandText.color)
                        .frame(minHeight: 28)
                }
                .lbButtonStyle()
            }
        }
    }
}

/// Two things to do from the editor without leaving it: add a commitment, and see every
/// commitment that names this account or person, listed in place.
struct EntityQuickActions: View {
    let kind: VaultPatch.EntityKind
    let commitments: [Subscription]
    let add: () -> Void
    let open: (String) -> Void

    @State private var showingAll = false

    private var word: String { EntityCopy.word(kind) }

    var body: some View {
        LBPanel(eyebrow: "Quick actions") {
            VStack(spacing: LBSpacing.s2) {
                action("New Commitment", detail: nil, symbol: "plus.circle", trailing: "chevron.right", perform: add)
                action("Show Commitments", detail: nil, symbol: "list.bullet",
                       trailing: showingAll ? "chevron.up" : "chevron.down") { showingAll.toggle() }
                .disabled(commitments.isEmpty)
                .accessibilityValue(showingAll ? "Shown" : "Hidden")
                .accessibilityHint(commitments.isEmpty ? "No commitment uses this \(word) yet."
                                   : "\(EntityCopy.counted(commitments.count, "commitment")) \(commitments.count == 1 ? "uses" : "use") this \(word).")
                if showingAll {
                    ForEach(commitments) { sub in commitmentRow(sub) }
                }
            }
        }
    }

    private func action(
        _ title: String, detail: String?, symbol: String, trailing: String, perform: @escaping () -> Void
    ) -> some View {
        Button(action: { Measure.used("perform"); perform() }) {
            HStack(spacing: LBSpacing.s3) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(LBColor.brandText.color)
                    .frame(width: 32, height: 32)
                    .background(LBColor.brand.color.opacity(0.12), in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .lbText(.bodySM)
                        .foregroundStyle(LBColor.textPrimary.color)
                    if let detail {
                        Text(detail)
                            .lbText(.footnote)
                            .foregroundStyle(LBColor.textSecondary.color)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: LBSpacing.s2)
                Image(systemName: trailing)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(LBColor.textQuaternary.color)
                    .accessibilityHidden(true)
            }
            .padding(LBSpacing.s3)
            .frame(minHeight: 44)
            .background(LBColor.sunken.color, in: RoundedRectangle(cornerRadius: LBRadius.sm, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: LBRadius.sm, style: .continuous)
                    .strokeBorder(LBColor.hairline.color, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .lbButtonStyle(shape: RoundedRectangle(cornerRadius: LBRadius.sm, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func commitmentRow(_ sub: Subscription) -> some View {
        Button { Measure.used("open_commitment"); open(sub.id) } label: {
            HStack(spacing: LBSpacing.s2) {
                Text(sub.name)
                    .lbText(.bodySM)
                    .foregroundStyle(LBColor.textPrimary.color)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: LBSpacing.s2)
                LBAmount(fmtMoney(sub.amount, sub.currency), prominence: .inline)
                    .foregroundStyle(LBColor.textSecondary.color)
                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(LBColor.textQuaternary.color)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: 36)
            .padding(.horizontal, LBSpacing.s3)
            .padding(.vertical, LBSpacing.s1)
            .contentShape(Rectangle())
        }
        .lbButtonStyle()
        .accessibilityHint("Opens \(sub.name)")
    }
}
