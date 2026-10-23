import SwiftUI

/// Radii — generous and continuous throughout.
public enum LBRadius {
    public static let xs: CGFloat = 10
    public static let sm: CGFloat = 12
    public static let md: CGFloat = 16
    public static let lg: CGFloat = 20
    public static let xl: CGFloat = 28
    public static let xxl: CGFloat = 44
}

/// 4-based spacing rhythm, written as values on purpose — no named steps to forget.
public enum LBSpacing {
    public static let s1: CGFloat = 4
    public static let s2: CGFloat = 8
    public static let s3: CGFloat = 12
    public static let s4: CGFloat = 16
    public static let s6: CGFloat = 24
    public static let s8: CGFloat = 32
    public static let s12: CGFloat = 48
}

/// The whole motion system: two curves, one stagger. Everything arrives with rise,
/// resolves with resolve. Nothing animates while someone is reading a number.
public enum LBMotion {
    public static let rise = Animation.timingCurve(0.16, 1, 0.3, 1, duration: 0.28)
    public static let resolve = Animation.timingCurve(0.32, 0, 0.67, 0, duration: 0.12)
    public static let stagger: Double = 0.06

    /// Reduce-motion-aware variants — pass `@Environment(\.accessibilityReduceMotion)`.
    /// Every consumer takes these, never the bare curves, so the gate can't be forgotten.
    public static func rise(reduceMotion: Bool) -> Animation? { reduceMotion ? nil : rise }
    public static func resolve(reduceMotion: Bool) -> Animation? { reduceMotion ? nil : resolve }
}
