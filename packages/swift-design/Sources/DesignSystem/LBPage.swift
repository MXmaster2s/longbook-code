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

    /// A screen's name where the platform puts it. On iPhone it is the navigation bar's
    /// Large Title, which folds into the bar on scroll; on the Mac it is the window's title,
    /// inline in the toolbar. An empty name leaves the Mac's title as it stands.
    @ViewBuilder
    func lbScreenTitle(_ title: String, large: Bool = true) -> some View {
        #if os(iOS)
        navigationTitle(title)
            .navigationBarTitleDisplayMode(large ? .large : .inline)
        #else
        if title.isEmpty { self } else { navigationTitle(title) }
        #endif
    }

    /// A screen's name with actions at the trailing end of the iPhone navigation bar, and
    /// of the Mac's window toolbar.
    func lbScreenTitle<Trailing: View>(
        _ title: String, large: Bool = true, @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        let actions = trailing()
        #if os(iOS)
        return lbScreenTitle(title, large: large)
            .toolbar { ToolbarItemGroup(placement: .topBarTrailing) { actions } }
        #else
        return lbScreenTitle(title, large: large)
            .toolbar { ToolbarItemGroup(placement: .primaryAction) { actions } }
        #endif
    }
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
