import SwiftUI
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// A design token's raw sRGB value. Kept numeric so contrast floors are testable;
/// views consume the derived `color`.
public struct LBColorValue: Sendable, Equatable {
    public let red: Double
    public let green: Double
    public let blue: Double

    public init(_ hex: UInt32) {
        red = Double((hex >> 16) & 0xFF) / 255
        green = Double((hex >> 8) & 0xFF) / 255
        blue = Double(hex & 0xFF) / 255
    }

    private init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    /// This token laid over `base` at `alpha` — the composite a translucent fill actually
    /// renders, so contrast floors measure what the eye gets, not the pre-blend value.
    public func blended(over base: LBColorValue, alpha: Double) -> LBColorValue {
        LBColorValue(
            red: red * alpha + base.red * (1 - alpha),
            green: green * alpha + base.green * (1 - alpha),
            blue: blue * alpha + base.blue * (1 - alpha)
        )
    }

    /// The rendered color, resolved against the appearance the view actually sits in:
    /// authored dark values swap to their light siblings from `LBPalette.counterparts`;
    /// anything outside the authored set (a computed blend) renders exactly as it is.
    public var color: Color {
        guard let light = LBPalette.lightCounterpart(of: self) else {
            return Color(.sRGB, red: red, green: green, blue: blue)
        }
        #if canImport(UIKit)
        return Color(UIColor { trait in
            let v = trait.userInterfaceStyle == .light ? light : self
            return UIColor(red: v.red, green: v.green, blue: v.blue, alpha: 1)
        })
        #else
        return Color(NSColor(name: nil) { appearance in
            let v = appearance.bestMatch(from: [.aqua, .darkAqua]) == .aqua ? light : self
            return NSColor(srgbRed: v.red, green: v.green, blue: v.blue, alpha: 1)
        })
        #endif
    }

    /// This exact value, rendered literally in every appearance — for callers that have
    /// already resolved which palette they are in and must not be re-paired.
    public var absolute: Color {
        Color(.sRGB, red: red, green: green, blue: blue)
    }

    private var relativeLuminance: Double {
        func lin(_ v: Double) -> Double { v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(red) + 0.7152 * lin(green) + 0.0722 * lin(blue)
    }

    /// WCAG contrast ratio between two token values.
    public func contrast(with other: LBColorValue) -> Double {
        let a = relativeLuminance, b = other.relativeLuminance
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    /// Position in OKLab, where equal distances look equally different. Contrast answers
    /// "can this be read against that"; this answers "can these two be told apart".
    private var oklab: (l: Double, a: Double, b: Double) {
        func lin(_ v: Double) -> Double { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        let r = lin(red), g = lin(green), bl = lin(blue)
        let l = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * bl)
        let m = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * bl)
        let s = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * bl)
        return (
            0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
            1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
            0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
        )
    }

    /// Perceptual distance, scaled so the familiar thresholds apply: under about 2 is
    /// invisible, over about 10 is unmistakable.
    public func perceptualDistance(to other: LBColorValue) -> Double {
        let a = oklab, b = other.oklab
        return 100 * sqrt(pow(a.l - b.l, 2) + pow(a.a - b.a, 2) + pow(a.b - b.b, 2))
    }
}
