import DesignSystem
import SwiftUI

/// Many charges folded into one line, counted.
struct ChangeCountPill: View {
    let count: Int

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: LBGlyph.rows)
                .font(.system(size: 9, weight: .semibold))
            Text("\(count) charges")
                .lbText(.tabLabel)
        }
        .foregroundStyle(LBColor.onBrandTint.color)
        .padding(.horizontal, LBSpacing.s2)
        .padding(.vertical, 3)
        .background(LBColor.brand.color.opacity(0.16), in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(count) charges")
    }
}

/// One kind of row the review holds, as a tab: its name and how many lines wait in it.
/// A year's statement is hundreds of lines; each kind in its own tab keeps them readable.
struct ChangeKindTab: View {
    let title: String
    var symbol: String? = nil
    let count: Int
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: { Measure.used("change_action"); action() }) {
            HStack(spacing: LBSpacing.s2) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 11, weight: .medium))
                        .accessibilityHidden(true)
                }
                Text(title)
                    .lbText(.bodySM)
                Text("\(count)")
                    .lbText(.tabLabel)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        selected ? LBColor.onBrand.color.opacity(0.2) : LBColor.sunken.color,
                        in: Capsule()
                    )
            }
            .foregroundStyle(selected ? LBColor.onBrand.color : LBColor.textSecondary.color)
            .padding(.horizontal, LBSpacing.s3)
            .frame(minHeight: 36)
            .background(selected ? LBColor.brand.color : LBColor.chrome.color, in: Capsule())
            .contentShape(Capsule())
        }
        .lbButtonStyle()
        .accessibilityLabel("\(title), \(count)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// The answer buttons a review stands behind: Undo All and Keep All on Changes, Discard
/// and Add on a statement import. Wide on the phone, a capsule in the Mac's bar.
struct ChangeActionLabel: View {
    let title: String
    let symbol: String
    let filled: Bool
    let wide: Bool

    var body: some View {
        HStack(spacing: LBSpacing.s2) {
            Image(systemName: symbol)
                .font(.system(size: wide ? 14 : 12, weight: .medium))
                .accessibilityHidden(true)
            Text(title)
                .lbText(wide ? .body : .label)
        }
        .foregroundStyle(filled ? LBColor.onBrand.color : LBColor.textPrimary.color)
        .padding(.horizontal, wide ? 0 : LBSpacing.s4)
        .frame(maxWidth: wide ? .infinity : nil, minHeight: wide ? 44 : 32)
        .background(
            filled ? LBColor.brand.color : LBColor.chrome.color,
            in: RoundedRectangle(cornerRadius: LBRadius.sm, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: LBRadius.sm, style: .continuous)
                .strokeBorder(LBColor.hairline.color, lineWidth: filled ? 0 : 1)
        )
        .contentShape(Rectangle())
    }
}
