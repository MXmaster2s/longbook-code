import Observation
import SwiftUI

/// One colour a kind of card can wear: a dark value and its light sibling, each clearing the
/// mark floor on the card of its palette. The first entries are today's bands.
public struct LBCardSwatch: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let dark: LBColorValue
    public let light: LBColorValue

    public func value(in palette: LBPalette) -> LBColorValue {
        palette.name == LBPalette.light.name ? light : dark
    }

    /// The twenty on offer.
    public static let all: [LBCardSwatch] = {
        let dark = LBColor.dataRamp, light = LBColorLight.dataRamp
        func ramp(_ id: String, _ name: String, _ rank: Int) -> LBCardSwatch {
            LBCardSwatch(id: id, name: name, dark: dark[rank], light: light[rank])
        }
        return [
            ramp("green", "Green", 11),
            ramp("lime", "Lime", 6),
            LBCardSwatch(id: "sky", name: "Sky", dark: LBColor.skyTint, light: LBColorLight.skyTint),
            LBCardSwatch(id: "brand", name: "Violet", dark: LBColor.brand, light: LBColorLight.brand),
            ramp("orchid", "Orchid", 0),
            ramp("amber", "Amber", 8),
            LBCardSwatch(id: "slate", name: "Slate", dark: LBColorValue(0x8A94A6), light: LBColorValue(0x5B6472)),
            ramp("olive", "Olive", 1),
            ramp("azure", "Azure", 2),
            ramp("rust", "Rust", 3),
            ramp("jade", "Jade", 4),
            ramp("raspberry", "Raspberry", 5),
            ramp("blue", "Blue", 7),
            ramp("teal", "Teal", 9),
            ramp("coral", "Coral", 10),
            LBCardSwatch(id: "gold", name: "Gold", dark: LBColor.goldTint, light: LBColorLight.goldTint),
            LBCardSwatch(id: "mint", name: "Mint", dark: LBColorValue(0x8CF0B4), light: LBColorValue(0x134A1F)),
            LBCardSwatch(id: "rose", name: "Rose", dark: LBColor.plumTint, light: LBColorLight.plumTint),
            LBCardSwatch(id: "lavender", name: "Lavender", dark: LBColorValue(0xC2B6F7), light: LBColorValue(0x4B2FA8)),
            LBCardSwatch(id: "cocoa", name: "Cocoa", dark: LBColorValue(0xB08968), light: LBColorValue(0x8A6A5C)),
        ]
    }()

    static func id(of kind: LBCardKind) -> String {
        switch kind {
        case .charge: "green"
        case .earning: "lime"
        case .transfer: "sky"
        case .commitment: "brand"
        case .people: "orchid"
        case .account: "amber"
        case .report: "slate"
        }
    }

    static func named(_ id: String) -> LBCardSwatch? { all.first { $0.id == id } }
}

/// Which colour each kind of card wears on this device, one kind to a colour. Every band reads
/// it through `LBCardKind.ink`, so a choice reaches every card drawn at once.
@Observable
public final class LBCardColours {
    public static let shared = LBCardColours(defaults: .standard)
    public static let storageKey = "card_colours"

    @ObservationIgnored private let defaults: UserDefaults
    /// The kinds moved off their default: kind to swatch, by name.
    private var chosen: [String: String]

    public init(defaults: UserDefaults) {
        self.defaults = defaults
        chosen = Self.settled(defaults.dictionary(forKey: Self.storageKey) as? [String: String] ?? [:])
    }

    public func swatch(for kind: LBCardKind) -> LBCardSwatch {
        Self.swatch(for: kind, in: chosen)
    }

    /// The kind wearing this colour.
    public func holder(of swatch: LBCardSwatch) -> LBCardKind? {
        LBCardKind.allCases.first { self.swatch(for: $0).id == swatch.id }
    }

    /// Gives the kind this colour. Refused, and nothing changes, while another kind holds it.
    @discardableResult
    public func assign(_ swatch: LBCardSwatch, to kind: LBCardKind) -> Bool {
        if let holder = holder(of: swatch) { return holder == kind }
        chosen[kind.rawValue] = swatch.id
        store()
        return true
    }

    public var isDefault: Bool { chosen.isEmpty }

    public func reset() {
        chosen = [:]
        store()
    }

    private func store() {
        defaults.set(chosen, forKey: Self.storageKey)
    }

    private static func swatch(for kind: LBCardKind, in chosen: [String: String]) -> LBCardSwatch {
        let id = chosen[kind.rawValue] ?? LBCardSwatch.id(of: kind)
        return LBCardSwatch.named(id) ?? LBCardSwatch.named(LBCardSwatch.id(of: kind))!
    }

    /// What storage holds, with anything unknown or shared with another kind let go.
    private static func settled(_ stored: [String: String]) -> [String: String] {
        var out = stored.filter { key, id in LBCardKind(rawValue: key) != nil && LBCardSwatch.named(id) != nil }
        while let clash = LBCardKind.allCases.first(where: { kind in
            out[kind.rawValue] != nil && LBCardKind.allCases.contains { $0 != kind && swatch(for: $0, in: out).id == swatch(for: kind, in: out).id }
        }) {
            out[clash.rawValue] = nil
        }
        return out
    }
}
