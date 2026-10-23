import SwiftUI

/// The light appearance's values. Every name matches `LBColor` one for one, so choosing a
/// palette never changes a call site. Dark stays the authored canvas; this is the second
/// palette beside it. Floors are the same 4.5:1 text, 3:1 boundary, measured on the surface
/// each token actually sits on.
public enum LBColorLight {
    // Surfaces — warm paper. Depth is still a tone step, but the ladder runs the other way:
    // raised is lighter, and card is the brightest surface text sits on.
    public static let canvas = LBColorValue(0xF6F4EF)
    public static let sunken = LBColorValue(0xEFECE4)
    public static let card = LBColorValue(0xFFFFFF)
    public static let chrome = LBColorValue(0xE8E4DA)
    /// 1.40:1 against card — the same decorative weight the dark hairline carries, so a
    /// badge's stroke stays a whisper instead of becoming a near-black ring.
    public static let hairline = LBColorValue(0xDFDACD)

    // Text ladder, measured against card and chrome both. Quaternary is non-text only (icons, lines, off controls).
    public static let textPrimary = LBColorValue(0x26241F)
    public static let textSecondary = LBColorValue(0x57524A)
    public static let textTertiary = LBColorValue(0x655F55)
    public static let textQuaternary = LBColorValue(0x847E73)

    // Brand. Base and its states carry a light label on a filled surface, which the canvas
    // never enters, so all four hold across both palettes unchanged.
    public static let brand = LBColorValue(0x6D5AE6)
    public static let brandHover = LBColorValue(0x5D4BD1)
    public static let brandPressed = LBColorValue(0x4E3DBD)
    public static let onBrand = LBColorValue(0xFBFBFE)
    /// The dark palette's lavender is unreadable on paper; this is its deep sibling in the
    /// same hue family, clearing the text floor on every surface and brand wash it sits on.
    public static let brandText = LBColorValue(0x4A3AC8)
    /// In the light a brand tint is pale, so the brand text itself carries the label.
    public static let onBrandTint = LBColorValue(0x4A3AC8)

    // The hero gradient stays dark: it is the brand's own island, not a section surface,
    // and its labels already clear their floor on both stops.
    public static let heroTop = LBColorValue(0x3A2C86)
    public static let heroBottom = LBColorValue(0x251D4E)

    public static let chartBar = LBColorValue(0x6355DD)

    // Section hues, inverted as pairs. The rule is unchanged — a quiet fill carries the
    // surface, a vivid tint carries what is written on it — but on paper quiet means a
    // wash and vivid means deep ink.
    public static let goldFill = LBColorValue(0xF3E5C2)
    public static let goldTint = LBColorValue(0x6F510A)
    public static let skyFill = LBColorValue(0xD7EAF5)
    public static let skyTint = LBColorValue(0x0A5878)
    public static let mintFill = LBColorValue(0xD6EFDE)
    public static let mintTint = LBColorValue(0x0D5B37)
    public static let plumFill = LBColorValue(0xF5DFEA)
    public static let plumTint = LBColorValue(0x8A2D5B)

    // States. Urgent still pairs with a word, attention is still only ever a mark.
    public static let urgent = LBColorValue(0x935B00)
    public static let attention = LBColorValue(0x3D45CE)
    public static let trial = LBColorValue(0x776240)
    public static let past = LBColorValue(0x8A867C)
    public static let danger = LBColorValue(0xB8283F)
    public static let dangerFill = LBColorValue(0xD33955)

    /// Identity inks by rank. Each keeps its dark sibling's hue family — shifts are held
    /// within 12° — so a category does not change colour when the appearance does. Vivid
    /// on paper means deep: every pair is 11+ OKLab units apart and clears 3:1 on canvas,
    /// card, and its own tile wash.
    public static let dataRamp: [LBColorValue] = [
        LBColorValue(0x894190), LBColorValue(0xA28400), LBColorValue(0x0673A1),
        LBColorValue(0xDE492E), LBColorValue(0x016756), LBColorValue(0xC75A96),
        LBColorValue(0x656F02), LBColorValue(0x2F87EA), LBColorValue(0xA15602),
        LBColorValue(0x0C968D), LBColorValue(0xB3213E), LBColorValue(0x1E9817),
    ]
    /// Rank past the ramp, or none at all — separated by carrying almost no chroma, the
    /// same mechanic the dark fold uses.
    public static let neutralFold = LBColorValue(0x767268)
}

extension LBPalette {
    /// The light set, packaged exactly as the dark one is. Registering it in `all` is
    /// what puts these values under every floor, separability and blend assertion.
    public static let light = LBPalette(
        name: "light",
        canvas: LBColorLight.canvas, sunken: LBColorLight.sunken, card: LBColorLight.card,
        chrome: LBColorLight.chrome, hairline: LBColorLight.hairline,
        textPrimary: LBColorLight.textPrimary, textSecondary: LBColorLight.textSecondary,
        textTertiary: LBColorLight.textTertiary, textQuaternary: LBColorLight.textQuaternary,
        brand: LBColorLight.brand, brandHover: LBColorLight.brandHover,
        brandPressed: LBColorLight.brandPressed, onBrand: LBColorLight.onBrand,
        brandText: LBColorLight.brandText, onBrandTint: LBColorLight.onBrandTint,
        heroTop: LBColorLight.heroTop, heroBottom: LBColorLight.heroBottom,
        chartBar: LBColorLight.chartBar,
        goldFill: LBColorLight.goldFill, goldTint: LBColorLight.goldTint,
        skyFill: LBColorLight.skyFill, skyTint: LBColorLight.skyTint,
        mintFill: LBColorLight.mintFill, mintTint: LBColorLight.mintTint,
        plumFill: LBColorLight.plumFill, plumTint: LBColorLight.plumTint,
        urgent: LBColorLight.urgent, attention: LBColorLight.attention,
        trial: LBColorLight.trial, past: LBColorLight.past, danger: LBColorLight.danger,
        dangerFill: LBColorLight.dangerFill,
        dataRamp: LBColorLight.dataRamp, neutralFold: LBColorLight.neutralFold
    )
}
