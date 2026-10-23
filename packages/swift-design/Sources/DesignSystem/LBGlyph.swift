import SwiftUI

/// The SF Symbol each fact wears, so a date reads as a date on every screen. Outline
/// weights, matching the filter row; a category's own picture stays with the app.
public enum LBGlyph {
    public static let date = "calendar"
    public static let cycle = "arrow.triangle.2.circlepath"
    public static let category = "tag"
    public static let member = "person"
    public static let account = "creditcard"
    public static let status = "circle.lefthalf.filled"
    public static let currency = "coloncurrencysign.circle"
    public static let paid = "checkmark.circle.fill"
    public static let unpaid = "circle"
    public static let income = "arrow.down.left"
    public static let expense = "arrow.up.right"
    /// Money moving between the owner's own accounts: shown, never summed.
    public static let transfer = "arrow.left.arrow.right"
    public static let categoryFilled = "tag.fill"
    /// Who wrote a row: an AI by name, or the owner in the app.
    public static let ai = "sparkles"
    public static let owner = "person.fill"
    /// Many rows folded into one line.
    public static let rows = "square.stack"
    /// A kind, on the doors to it and the tabs that count it: a commitment repeats, a
    /// charge is money that landed, a change waits in its tray. History keeps the clock;
    /// the cycle fact on a card keeps its own arrows, so the two never read alike.
    public static let commitment = "repeat"
    public static let charge = "banknote"
    public static let change = "tray.full"
}

/// One fact on a row's meta line: the glyph that names its kind, and its words. An
/// empty symbol draws the words alone. A placeholder stands where a fact is missing
/// and names the action that fills it; it wears the same glyph in the brand's ink.
public struct LBMetaFact: Hashable, Sendable {
    public let symbol: String
    public let text: String
    public let placeholder: Bool

    public init(symbol: String, text: String, placeholder: Bool = false) {
        self.symbol = symbol
        self.text = text
        self.placeholder = placeholder
    }
}
