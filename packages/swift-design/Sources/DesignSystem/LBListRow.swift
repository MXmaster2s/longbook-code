import SwiftUI

/// One row of a plain list: what it is, an optional second line, an amount at the trailing
/// edge, and a chevron when the row opens something. One line when there is no second.
/// Made for `List`, whose own insets and separators frame it.
public struct LBListRow<Leading: View>: View {
    @Environment(\.dynamicTypeSize) private var typeSize

    private let title: String
    private let secondary: String?
    private let amount: String?
    private let amountColor: LBColorValue
    private let chevron: Bool
    private let leading: Leading

    public init(
        _ title: String,
        secondary: String? = nil,
        amount: String? = nil,
        amountColor: LBColorValue = LBColor.textPrimary,
        chevron: Bool = false,
        @ViewBuilder leading: () -> Leading
    ) {
        self.title = title
        self.secondary = secondary
        self.amount = amount
        self.amountColor = amountColor
        self.chevron = chevron
        self.leading = leading()
    }

    public var body: some View {
        HStack(spacing: LBSpacing.s3) {
            if typeSize.isAccessibilitySize {
                // Side by side, a raised text size truncates the name and breaks "commitments"
                // beside the picture; the picture goes above the words instead.
                VStack(alignment: .leading, spacing: LBSpacing.s1) {
                    leading
                    words
                    amountText
                }
                Spacer(minLength: 0)
            } else {
                leading
                words
                Spacer(minLength: LBSpacing.s2)
                amountText
            }
            if chevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(LBColor.textQuaternary.color)
                    .accessibilityHidden(true)
            }
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var words: some View {
        VStack(alignment: .leading, spacing: 2) {
            // A name beside an amount gets a second line before it is cut: "HDFC Savings 4542"
            // and "₹81,110" both have to be read.
            Text(title)
                .lbText(.body)
                .foregroundStyle(LBColor.textPrimary.color)
                .lineLimit(typeSize.isAccessibilitySize ? nil : (amount == nil ? 1 : 2))
            if let secondary, !secondary.isEmpty {
                Text(secondary)
                    .lbText(.footnote)
                    .foregroundStyle(LBColor.textSecondary.color)
                    .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
            }
        }
    }

    @ViewBuilder
    private var amountText: some View {
        if let amount {
            LBAmount(amount, prominence: .inline)
                .foregroundStyle(amountColor.color)
                .layoutPriority(1)
        }
    }
}

public extension LBListRow where Leading == EmptyView {
    init(
        _ title: String,
        secondary: String? = nil,
        amount: String? = nil,
        amountColor: LBColorValue = LBColor.textPrimary,
        chevron: Bool = false
    ) {
        self.init(title, secondary: secondary, amount: amount, amountColor: amountColor, chevron: chevron) {
            EmptyView()
        }
    }
}

/// A list section's name: sentence case, semibold, in the quiet ink. Takes the words as
/// written; it never re-cases them.
public struct LBSectionHeader: View {
    private let text: String

    public init(_ text: String) {
        self.text = text
    }

    public var body: some View {
        Text(text)
            .lbText(.eyebrow)
            .foregroundStyle(LBColor.textSecondary.color)
            .textCase(nil)
            .accessibilityAddTraits(.isHeader)
    }
}

public extension View {
    /// A grouped list in the design's colours: the canvas behind, card-coloured rows.
    /// Inset-grouped on iPhone, inset on the Mac.
    func lbGroupedList() -> some View {
        #if os(iOS)
        listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(LBColor.canvas.color)
        #else
        listStyle(.inset)
            .scrollContentBackground(.hidden)
            .background(LBColor.canvas.color)
        #endif
    }

    /// The row fill `lbGroupedList` expects, set on each row.
    func lbListRowBackground() -> some View {
        listRowBackground(LBColor.card.color)
    }
}
