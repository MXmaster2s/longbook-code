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

    /// Text ink and its fill, composited to opaque so the contrast floors measure the
    /// pair that renders. Per palette on purpose: a blend is a computed value the
    /// appearance resolver cannot pair, and a dark-card blend once rendered dark on
    /// dark in light mode.
    public func inks(in palette: LBPalette) -> (text: LBColorValue, fill: LBColorValue) {
        switch self {
        case .brand: (palette.brandText, palette.brand.blended(over: palette.card, alpha: 0.18))
        case .urgent: (palette.urgent, palette.urgent.blended(over: palette.card, alpha: 0.14))
        case .muted: (palette.textTertiary, palette.sunken)
        case .positive: (palette.mintTint, palette.mintFill)
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
            .background(inks.fill.absolute, in: Capsule())
            .overlay(Capsule().strokeBorder(LBColor.hairline.color, lineWidth: 1))
            .lineLimit(1)
            .fixedSize()
    }
}
