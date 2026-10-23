import DesignSystem
import LongbookCore
import SwiftUI

/// A commitment named at setup, waiting for its details: the name, its group, and the two
/// things to do with it — fill it in, or let it go. The whole card is the Edit button.
struct PlaceholderCard: View {
    let placeholder: CommitmentPlaceholder
    let onEdit: () -> Void
    let onRemove: () -> Void
    static let width: CGFloat = 136

    init(_ placeholder: CommitmentPlaceholder, onEdit: @escaping () -> Void, onRemove: @escaping () -> Void) {
        self.placeholder = placeholder
        self.onEdit = onEdit
        self.onRemove = onRemove
    }

    var body: some View {
        // Two siblings, never a button inside a button: the face is the Edit button and
        // Remove lies over it in its own place, so a tap on Remove cannot reach Edit.
        Button(action: onEdit) { face }
            .buttonStyle(.plain)
            .lbTapHaptic()
            .accessibilityLabel("Edit \(placeholder.name)")
            .accessibilityHint("Opens the form to add its amount and day")
            .overlay(alignment: .bottomLeading) {
                controls(live: true)
                    .padding(LBSpacing.s3)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("\(placeholder.name), needs details")
    }

    private var face: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(placeholder.name)
                .lbText(.bodySM)
                .foregroundStyle(LBColor.textPrimary.color)
                .lineLimit(1)
                .truncationMode(.tail)
            Text(placeholder.tag.isEmpty ? placeholder.group : categoryWord(placeholder.tag))
                .lbText(.footnote)
                .foregroundStyle(LBColor.textTertiary.color)
                .lineLimit(1)
            controls(live: false)
                .padding(.top, LBSpacing.s1)
        }
        .padding(LBSpacing.s3)
        .frame(width: Self.width, alignment: .topLeading)
        .background(LBColor.canvas.color, in: RoundedRectangle(cornerRadius: LBRadius.md, style: .continuous))
        .lbDashedOutline(cornerRadius: LBRadius.md)
        .contentShape(RoundedRectangle(cornerRadius: LBRadius.md, style: .continuous))
    }

    /// The words at the card's foot, laid out once and drawn twice. The face shows Edit
    /// and keeps Remove's room; the live copy hides Edit and carries the Remove button,
    /// so both land on the same spot.
    private func controls(live: Bool) -> some View {
        HStack(spacing: LBSpacing.s3) {
            if live {
                word("Edit").hidden()
                Button(action: onRemove) { word("Remove") }
                    .buttonStyle(.plain)
                    .lbTapHaptic()
                    .accessibilityLabel("Remove \(placeholder.name)")
            } else {
                word("Edit")
                word("Remove").hidden()
            }
        }
    }

    private func word(_ title: String) -> some View {
        Text(title)
            .lbText(.label)
            .foregroundStyle(LBColor.brandText.color)
            .padding(.horizontal, LBSpacing.s1)
            .frame(minHeight: 32)
            .contentShape(Rectangle())
    }
}
