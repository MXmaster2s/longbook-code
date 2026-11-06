import SwiftUI
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// A translucent state layer: black or white at an opacity, laid over a control. Washes
/// carry no contrast floor of their own; the surface under them keeps its floor, and a
/// wash only nudges it. Authored dark like `LBColorValue`, with light siblings in
/// `LBColorLight` resolved by `color`.
public struct LBWash: Sendable, Equatable {
    public let base: LBColorValue
    public let opacity: Double

    public init(_ hex: UInt32, opacity: Double) {
        base = LBColorValue(hex)
        self.opacity = opacity
    }

    /// The rendered wash, swapped for its light sibling when the view sits in Light.
    public var color: Color {
        let light = Self.counterparts.first { $0.dark == self }?.light ?? self
        #if canImport(UIKit)
        return Color(UIColor { trait in
            let w = trait.userInterfaceStyle == .light ? light : self
            return UIColor(red: w.base.red, green: w.base.green, blue: w.base.blue, alpha: w.opacity)
        })
        #else
        return Color(NSColor(name: nil) { appearance in
            let w = appearance.bestMatch(from: [.aqua, .darkAqua]) == .aqua ? light : self
            return NSColor(srgbRed: w.base.red, green: w.base.green, blue: w.base.blue, alpha: w.opacity)
        })
        #endif
    }

    static let counterparts: [(dark: LBWash, light: LBWash)] = [
        (LBColor.stateHover, LBColorLight.stateHover),
        (LBColor.statePressed, LBColorLight.statePressed),
        (LBColor.stateSelectionInactive, LBColorLight.stateSelectionInactive),
    ]
}
