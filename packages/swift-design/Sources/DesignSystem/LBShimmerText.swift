import SwiftUI

/// Words a light passes across, for a line naming work under way. With Reduce Motion they stand
/// still in their plain colour.
public struct LBShimmerText: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let text: String
    private let style: LBTextStyle
    /// Seconds for the light to cross once.
    private static let period = 1.8

    public init(_ text: String, style: LBTextStyle) {
        self.text = text
        self.style = style
    }

    public var body: some View {
        if reduceMotion {
            Text(text)
                .lbText(style)
                .foregroundStyle(LBColor.textSecondary.color)
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 20)) { context in
                let phase = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: Self.period) / Self.period
                let center = phase * 1.6 - 0.3
                Text(text)
                    .lbText(style)
                    .foregroundStyle(LinearGradient(
                        stops: [
                            .init(color: LBColor.textSecondary.color, location: 0),
                            .init(color: LBColor.textPrimary.color, location: 0.5),
                            .init(color: LBColor.textSecondary.color, location: 1),
                        ],
                        startPoint: UnitPoint(x: center - 0.3, y: 0.5),
                        endPoint: UnitPoint(x: center + 0.3, y: 0.5)
                    ))
            }
        }
    }
}
