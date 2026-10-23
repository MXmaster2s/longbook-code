import SwiftUI

/// The four areas of the app, each owning a hue. A section is a pair: a deep-muted fill
/// carries the surface, a bright tint carries everything written on it.
public enum LBSection: CaseIterable, Sendable {
    case overview, payments, members, spending

    public var fill: LBColorValue {
        switch self {
        case .overview: LBColor.goldFill
        case .payments: LBColor.skyFill
        case .members: LBColor.mintFill
        case .spending: LBColor.plumFill
        }
    }

    public var tint: LBColorValue {
        switch self {
        case .overview: LBColor.goldTint
        case .payments: LBColor.skyTint
        case .members: LBColor.mintTint
        case .spending: LBColor.plumTint
        }
    }

    public var name: String {
        switch self {
        case .overview: "overview"
        case .payments: "payments"
        case .members: "members"
        case .spending: "spending"
        }
    }
}
