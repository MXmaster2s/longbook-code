import SwiftUI

/// How much room an amount is given, and so which number face it wears. `standalone` is
/// the one place Fraunces draws a number: a figure with nothing to line up against.
/// Stacked amounts take the tabular face, since Fraunces has no tabular figures.
public enum LBAmountProminence {
    case standalone, stacked, inline
}

/// A monetary amount. Takes an already-formatted string: formatting and currency rules
/// belong to the domain layer, and this package never reaches into it.
public struct LBAmount: View {
    private let text: String
    private let prominence: LBAmountProminence

    public init(_ text: String, prominence: LBAmountProminence = .stacked) {
        self.text = text
        self.prominence = prominence
    }

    public var body: some View {
        Text(text)
            .lbText(style)
            .lineLimit(1)
            // An amount may tighten to fit its line, but not so far that raising the text
            // size makes the numbers smaller than the words around them.
            .minimumScaleFactor(0.85)
    }

    private var style: LBTextStyle {
        switch prominence {
        case .standalone: .numberDisplay
        case .stacked: .numberMD
        case .inline: .numberSM
        }
    }
}
