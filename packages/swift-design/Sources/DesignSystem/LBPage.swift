import SwiftUI

/// How wide a page's column may grow. A phone is narrower than either; the Mac and the
/// iPad let a page of cards, lists or tables use the window, and keep prose to a line a
/// reader can follow.
public enum LBPageWidth: Sendable {
    /// Sentences and settings: a readable measure.
    case reading
    /// Cards, grids, lists and tables: the window's width, up to a sensible cap.
    case wide

    public var maxWidth: CGFloat {
        #if os(macOS)
        switch self {
        case .reading: 700
        case .wide: 1440
        }
        #else
        switch self {
        case .reading: 700
        case .wide: 1320
        }
        #endif
    }
}

public extension View {
    /// A page's column: the standard margins, the width cap, centred in what is left.
    /// The Mac adds room above, where the phone's navigation bar would sit.
    func lbPageColumn(_ width: LBPageWidth = .reading) -> some View {
        padding(LBSpacing.s4)
            #if os(macOS)
            .padding(.top, LBSpacing.s6)
            #endif
            .frame(maxWidth: width.maxWidth)
            .frame(maxWidth: .infinity)
    }

    /// A screen's name where the platform puts it: the iPhone navigation bar's Large Title,
    /// which folds on scroll, or the Mac window toolbar's 17 pt title with `count` in a pill
    /// beside it. An empty name leaves the Mac's toolbar as it stands.
    @ViewBuilder
    func lbScreenTitle(_ title: String, large: Bool = true, count: Int? = nil) -> some View {
        #if os(iOS)
        navigationTitle(title)
            .navigationBarTitleDisplayMode(large ? .large : .inline)
        #else
        if title.isEmpty {
            self
        } else {
            navigationTitle(title).modifier(LBToolbarTitleModifier(title: title, count: count))
        }
        #endif
    }

    /// A screen's name with actions at the trailing end of the iPhone navigation bar, and
    /// as one bordered group at the trailing end of the Mac's window toolbar.
    func lbScreenTitle<Trailing: View>(
        _ title: String, large: Bool = true, count: Int? = nil, @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        let actions = trailing()
        #if os(iOS)
        return lbScreenTitle(title, large: large)
            .toolbar { ToolbarItemGroup(placement: .topBarTrailing) { actions } }
        #else
        return lbScreenTitle(title, large: large, count: count)
            .toolbar { ToolbarItem(placement: .primaryAction) { ControlGroup { actions } } }
        #endif
    }
}

#if os(macOS)
/// The toolbar's own 17 pt title in place of the system's, where the system's can be
/// removed (macOS 15); before that the system title stands alone.
private struct LBToolbarTitleModifier: ViewModifier {
    let title: String
    let count: Int?

    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content
                .toolbar(removing: .title)
                .toolbar { ToolbarItem(placement: .navigation) { LBToolbarTitle(title: title, count: count) } }
        } else {
            content
        }
    }
}

/// The Mac toolbar's name for the screen on show, and how many things it lists.
public struct LBToolbarTitle: View {
    let title: String
    let count: Int?

    public init(title: String, count: Int?) {
        self.title = title
        self.count = count
    }

    public var body: some View {
        HStack(spacing: LBSpacing.s2) {
            Text(title)
                .lbText(.windowTitle)
                .foregroundStyle(LBColor.textPrimary.color)
            if let count {
                Text("\(count)")
                    .lbText(.footnote)
                    .foregroundStyle(LBColor.textSecondary.color)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(LBColor.chrome.color, in: Capsule())
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}
#endif

public extension View {
}

/// The page's own title on the Mac, where a window's toolbar does not already name the
/// screen (`lbPageTitleHidden`). On iPhone it draws nothing: `lbScreenTitle` puts the name
/// in the bar.
public struct LBPageTitle: View {
    private let title: String
    @Environment(\.lbPageTitleHidden) private var hidden
    @Environment(\.lbPageHeader) private var header

    public init(_ title: String) {
        self.title = title
    }

    public var body: some View {
        #if os(macOS)
        if let header {
            header
        } else if !hidden {
            Text(title)
                .lbText(.largeTitle)
                .foregroundStyle(LBColor.textPrimary.color)
                .accessibilityAddTraits(.isHeader)
        }
        #else
        EmptyView()
        #endif
    }
}

private struct LBPageTitleHiddenKey: EnvironmentKey {
    static let defaultValue = false
}

private struct LBPageHeaderKey: EnvironmentKey {
    static let defaultValue: AnyView? = nil
}

public extension EnvironmentValues {
    /// True where a window's own title already names the page, as in the main window's
    /// toolbar or a Settings pane, so the page draws no second title.
    var lbPageTitleHidden: Bool {
        get { self[LBPageTitleHiddenKey.self] }
        set { self[LBPageTitleHiddenKey.self] = newValue }
    }

    /// A header drawn in place of the page's title, as a Settings pane's header card.
    var lbPageHeader: AnyView? {
        get { self[LBPageHeaderKey.self] }
        set { self[LBPageHeaderKey.self] = newValue }
    }
}
