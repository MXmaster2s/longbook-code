import SwiftUI

/// A badge marks an exception — a trial deciding, a cancellation coming, a row not
/// billing. The ordinary case wears nothing: "active" on every row would bury the one
/// row that is news.
public enum LBBadgeTone: Sendable, CaseIterable {
    /// A keep-or-cancel decision ahead (free trial).
    case brand
    /// Time-sensitive: money or a deadline moves soon (cancelling).
    case urgent
    /// Not billing — the badge recedes with the row (paused, cancelled).
    case muted
    /// The path the app suggests (recommended). The mint pair is the one green.
    case positive

    /// Text ink and its fill. Every tone sits on the Paused background, the chrome surface;
    /// only the text carries the tone. Per palette, so the floors measure the pair that renders.
    public func inks(in palette: LBPalette) -> (text: LBColorValue, fill: LBColorValue) {
        switch self {
        case .brand: (palette.brandText, palette.chrome)
        case .urgent: (palette.urgent, palette.chrome)
        case .muted: (palette.textSecondary, palette.chrome)
        case .positive: (palette.mintTint, palette.chrome)
        }
    }

    /// The authored dark pair — the floor tests sweep every palette via `inks(in:)`.
    public var inks: (text: LBColorValue, fill: LBColorValue) {
        inks(in: .dark)
    }
}

public struct LBBadge: View {
    @Environment(\.colorScheme) private var scheme
    private let text: String
    private let tone: LBBadgeTone

    public init(_ text: String, tone: LBBadgeTone) {
        self.text = text
        self.tone = tone
    }

    public var body: some View {
        let inks = tone.inks(in: scheme == .light ? .light : .dark)
        Text(text)
            .lbText(.label)
            .foregroundStyle(inks.text.absolute)
            .padding(.horizontal, LBSpacing.s2)
            .padding(.vertical, 2)
            .background(inks.fill.absolute, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .lineLimit(1)
            .fixedSize()
    }
}
