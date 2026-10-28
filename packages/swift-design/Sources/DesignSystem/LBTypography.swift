import CoreText
import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// The type roles: a face, a size, an exact weight, and for Fraunces an optical size.
/// Both faces are variable and their named instances are cut for 9pt, so setting the
/// axes is the only way to draw correctly at every size.
public enum LBTextStyle: CaseIterable, Sendable {
    case displayXL, displayLG, title
    case largeTitle, screenTitle, windowTitle, headline, eyebrow, heroSans, statNumber, tabLabel
    case body, bodySM, footnote, label
    case numberDisplay, numberMD, numberSM

    var face: LBTypeface {
        switch self {
        case .displayXL, .displayLG, .title, .numberDisplay: .fraunces
        case .largeTitle, .screenTitle, .windowTitle, .headline, .eyebrow, .heroSans, .statNumber, .tabLabel: .publicSans
        case .body, .bodySM, .footnote, .label, .numberMD, .numberSM: .publicSans
        }
    }

    /// Sizes follow each platform's own text styles: the phone's Body 17, Subheadline 15,
    /// Footnote 13 and Large Title 34; the Mac's Body 13 with 11–12 secondary text. The
    /// eyebrow is a sentence-case section header; the window title is the Mac toolbar's.
    var size: CGFloat {
        #if os(iOS)
        switch self {
        case .displayXL: return 56
        case .displayLG: return 28
        case .title: return 20
        case .largeTitle: return 34
        case .screenTitle: return 22
        case .windowTitle: return 17
        case .headline: return 17
        case .eyebrow: return 13
        case .heroSans: return 30
        case .statNumber: return 24
        case .tabLabel: return 10
        case .body: return 17
        case .bodySM: return 15
        case .footnote: return 13
        case .label: return 13
        case .numberDisplay: return 44
        case .numberMD: return 22
        case .numberSM: return 17
        }
        #else
        switch self {
        case .displayXL: return 64
        case .displayLG: return 32
        case .title: return 22
        case .largeTitle: return 26
        case .screenTitle: return 20
        case .windowTitle: return 17
        case .headline: return 13
        case .eyebrow: return 11
        case .heroSans: return 34
        case .statNumber: return 27
        case .tabLabel: return 11
        case .body: return 13
        case .bodySM: return 12
        case .footnote: return 11
        case .label: return 13
        case .numberDisplay: return 50
        case .numberMD: return 26
        case .numberSM: return 13
        }
        #endif
    }

    var weight: CGFloat {
        switch self {
        case .displayXL: 480
        case .displayLG: 460
        case .title: 440
        case .largeTitle, .screenTitle, .heroSans, .statNumber: 700
        case .headline, .eyebrow, .windowTitle: 600
        case .tabLabel: 500
        case .body, .bodySM, .footnote: 400
        case .label, .numberDisplay, .numberMD, .numberSM: 500
        }
    }

    /// Tracking in points. Bright type blooms against near-black, and the bloom reads
    /// strongest at small sizes, so the small roles carry the most. Section headers are
    /// sentence case, so they carry none.
    var tracking: CGFloat {
        switch self {
        case .body: 0.16
        case .bodySM: 0.14
        case .footnote: 0.2
        case .label: 0.13
        case .tabLabel: 0.2
        default: 0
        }
    }

    /// Only numbers that stack in a column need tabular figures. Public Sans has them;
    /// Fraunces does not, which is why `numberDisplay` is for standalone amounts alone.
    var tabularFigures: Bool {
        switch self {
        case .numberMD, .numberSM, .statNumber: true
        default: false
        }
    }

    /// What this role scales against when someone raises their text size.
    var textStyle: Font.TextStyle {
        switch self {
        case .displayXL, .numberDisplay, .heroSans, .largeTitle: .largeTitle
        case .displayLG, .statNumber: .title
        case .title, .numberMD, .screenTitle: .title2
        case .windowTitle: .title3
        case .headline: .headline
        case .eyebrow: .footnote
        case .tabLabel: .caption2
        case .body, .numberSM: .body
        case .bodySM: .subheadline
        case .footnote, .label: .footnote
        }
    }
}

enum LBTypeface: String {
    case fraunces = "Fraunces-Variable"
    case publicSans = "PublicSans-Variable"

    /// Fraunces carries an optical-size axis; Public Sans does not.
    var hasOpticalSize: Bool { self == .fraunces }
}

public extension View {
    /// Applies a role's face, axes, and tracking together, so a call site cannot take the
    /// font and forget the letter-spacing that was measured with it.
    func lbText(_ style: LBTextStyle) -> some View {
        modifier(LBTextModifier(style: style))
    }
}

/// Scales by the text size the view is given, not only the phone's: a grid capped with
/// `.dynamicTypeSize(...)` stops growing as a system font would.
private struct LBTextModifier: ViewModifier {
    let style: LBTextStyle
    @Environment(\.dynamicTypeSize) private var typeSize

    func body(content: Content) -> some View {
        content
            .font(LBFont.font(style, size: typeSize))
            .tracking(style.tracking)
    }
}

public enum LBFont {
    public static func font(_ style: LBTextStyle) -> Font {
        LBFontLoader.shared.font(style, size: nil)
    }

    static func font(_ style: LBTextStyle, size: DynamicTypeSize) -> Font {
        LBFontLoader.shared.font(style, size: size)
    }

    #if canImport(UIKit)
    /// A role as a UIKit font, scaled for the reader's text size, for the system bars
    /// SwiftUI cannot style directly.
    public static func uiFont(_ style: LBTextStyle) -> UIFont {
        LBFontLoader.shared.uiFont(style)
    }
    #endif
}

/// Builds fonts from explicit variation coordinates and caches them. Fonts ship inside
/// this package, so type is owned in one place rather than configured per app target.
final class LBFontLoader: @unchecked Sendable {
    static let shared = LBFontLoader()

    private let descriptors: [LBTypeface: CTFontDescriptor]
    /// Only the drawn face is cached. The scaled font is rebuilt per call, because the
    /// reader's text size is baked in at scaling time and can change while running.
    private var cache: [LBTextStyle: CTFont] = [:]
    private let lock = NSLock()

    private static let weightAxis = 0x77676874 as CFNumber  // 'wght'
    private static let opticalAxis = 0x6F70737A as CFNumber // 'opsz'

    private init() {
        var found: [LBTypeface: CTFontDescriptor] = [:]
        for face in [LBTypeface.fraunces, .publicSans] {
            guard let url = Bundle.module.url(forResource: face.rawValue, withExtension: "ttf") else { continue }
            // Registration lets the rest of the system name the face; drawing uses the
            // descriptor below either way, so a duplicate registration is not an error.
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            if let list = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor],
               let first = list.first {
                found[face] = first
            }
        }
        descriptors = found
    }

    func font(_ style: LBTextStyle, size: DynamicTypeSize?) -> Font {
        guard let drawn = cachedFace(style) else {
            return .system(size: style.size, weight: style.weight >= 500 ? .medium : .regular)
        }
        #if canImport(UIKit)
        let metrics = UIFontMetrics(forTextStyle: uiTextStyle(style.textStyle))
        guard let size else { return Font(metrics.scaledFont(for: drawn as UIFont)) }
        let traits = UITraitCollection(preferredContentSizeCategory: Self.category(size))
        return Font(metrics.scaledFont(for: drawn as UIFont, compatibleWith: traits))
        #elseif canImport(AppKit)
        return Font(drawn as NSFont)
        #else
        return Font(drawn)
        #endif
    }

    #if canImport(UIKit)
    private static func category(_ size: DynamicTypeSize) -> UIContentSizeCategory {
        switch size {
        case .xSmall: .extraSmall
        case .small: .small
        case .medium: .medium
        case .large: .large
        case .xLarge: .extraLarge
        case .xxLarge: .extraExtraLarge
        case .xxxLarge: .extraExtraExtraLarge
        case .accessibility1: .accessibilityMedium
        case .accessibility2: .accessibilityLarge
        case .accessibility3: .accessibilityExtraLarge
        case .accessibility4: .accessibilityExtraExtraLarge
        case .accessibility5: .accessibilityExtraExtraExtraLarge
        @unknown default: .large
        }
    }

    func uiFont(_ style: LBTextStyle) -> UIFont {
        let metrics = UIFontMetrics(forTextStyle: uiTextStyle(style.textStyle))
        guard let drawn = cachedFace(style) else {
            return metrics.scaledFont(for: .systemFont(ofSize: style.size, weight: style.weight >= 600 ? .semibold : .regular))
        }
        return metrics.scaledFont(for: drawn as UIFont)
    }
    #endif

    private func cachedFace(_ style: LBTextStyle) -> CTFont? {
        lock.lock()
        defer { lock.unlock() }
        if let cached = cache[style] { return cached }
        guard let built = ctFont(style) else { return nil }
        cache[style] = built
        return built
    }

    /// The drawn font behind a role, before platform text-size scaling. Tests assert the
    /// axes on this.
    func ctFont(_ style: LBTextStyle) -> CTFont? {
        guard let base = descriptors[style.face] else { return nil }
        var variation: [CFNumber: CGFloat] = [Self.weightAxis: style.weight]
        if style.face.hasOpticalSize {
            variation[Self.opticalAxis] = min(max(style.size, 9), 144)
        }
        var attributes: [CFString: Any] = [kCTFontVariationAttribute: variation]
        if style.tabularFigures {
            attributes[kCTFontFeatureSettingsAttribute] = [
                [kCTFontFeatureTypeIdentifierKey: kNumberSpacingType,
                 kCTFontFeatureSelectorIdentifierKey: kMonospacedNumbersSelector],
            ]
        }
        let descriptor = CTFontDescriptorCreateCopyWithAttributes(base, attributes as CFDictionary)
        return CTFontCreateWithFontDescriptor(descriptor, style.size, nil)
    }

    #if canImport(UIKit)
    private func uiTextStyle(_ style: Font.TextStyle) -> UIFont.TextStyle {
        switch style {
        case .largeTitle: .largeTitle
        case .title: .title1
        case .title2: .title2
        case .title3: .title3
        case .headline: .headline
        case .subheadline: .subheadline
        case .body: .body
        case .callout: .callout
        case .footnote: .footnote
        case .caption: .caption1
        case .caption2: .caption2
        @unknown default: .body
        }
    }
    #endif
}
