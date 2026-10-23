import DesignSystem
import SwiftUI

/// What longbook can do, one card at a time, while the reader waits. The cards turn on
/// their own; a sideways swipe turns them by hand and holds them still for a moment.
struct TipsTicker: View {
    /// Where a tip leads: a screen of the app, a page outside it, or the import door.
    enum Door {
        case screen(Destination)
        case link(URL)
        case importStatement
    }

    struct Tip: Identifiable {
        /// Its place in the turn, never shown.
        let number: Int
        let title: String
        let detail: String
        let door: Door
        var id: Int { number }
    }

    /// How to add the widget on this platform: the Home Screen widget, or the Mac's menu bar.
    static let widgetPage: URL = {
        #if os(macOS)
        URL(string: "https://longbook.app/features/see-your-next-payment-in-the-mac-menu-bar/")!
        #else
        URL(string: "https://longbook.app/features/add-longbook-widget-to-your-iphone/")!
        #endif
    }()
    static let statementsPage = URL(string: "https://longbook.app/features/import-your-bank-statements/")!

    /// One tip per idea, unnumbered. Each platform's widget tip names its own place, and the
    /// app tip points at the other device: the Mac is told about the iPhone, and back.
    static let tips: [Tip] = {
        #if os(macOS)
        let widget = Tip(number: 1, title: "See what’s due next",
                         detail: "The menu bar shows what’s due next on your Mac.", door: .link(widgetPage))
        let otherDevice = Tip(number: 3, title: "longbook for iPhone",
                              detail: "Get it from the App Store to carry your longbook with you.",
                              door: .link(URL(string: "https://apps.apple.com/app/id\(AppUpdates.appStoreID)")!))
        #else
        let widget = Tip(number: 1, title: "See what’s due next",
                         detail: "Add the widget to see what’s due next on your Home Screen.", door: .link(widgetPage))
        let otherDevice = Tip(number: 3, title: "longbook for Mac",
                              detail: "Get it from the App Store to see your longbook on your Mac too.",
                              door: .link(AppUpdates.url(for: .appStore)))
        #endif
        return [
            widget,
            Tip(number: 2, title: "Add a year of history",
                detail: "Start with a year of your bank statements.", door: .importStatement),
            otherDevice,
            Tip(number: 4, title: "Ask your AI",
                detail: "Connect Claude to ask about your money.", door: .screen(.mcpServer)),
            Tip(number: 5, title: "Every change is undoable",
                detail: "What a statement or an AI writes waits in Changes. Keep it or undo it in one tap.", door: .screen(.changes)),
        ]
    }()

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown: Int? = 1
    /// When the reader last turned a card by hand: the automatic turn waits five seconds after it.
    @State private var heldAt: Date?
    @State private var turning = false

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: LBSpacing.s3) {
                ForEach(Self.tips) { tip in
                    Self.card(tip)
                        .containerRelativeFrame(.horizontal)
                        .id(tip.number)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $shown)
        .onChange(of: shown) { _, _ in
            // A turn the reader made, not this view: hold the automatic turn back.
            if !turning { heldAt = Date() }
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(6))
                guard !Task.isCancelled else { return }
                if let heldAt, Date().timeIntervalSince(heldAt) < 5 { continue }
                turn()
            }
        }
        .accessibilityHint("Swipe sideways for another tip")
    }

    /// The card; with `chevron`, one that says it opens somewhere.
    static func card(_ tip: Tip, chevron: Bool = false) -> some View {
        HStack(alignment: .center, spacing: LBSpacing.s3) {
            VStack(alignment: .leading, spacing: LBSpacing.s1) {
                Text(tip.title)
                    .lbText(.body)
                    .foregroundStyle(LBColor.textPrimary.color)
                    .fixedSize(horizontal: false, vertical: true)
                Text(tip.detail)
                    .lbText(.footnote)
                    .foregroundStyle(LBColor.textTertiary.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if chevron {
                Spacer(minLength: LBSpacing.s2)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(LBColor.textTertiary.color)
            }
        }
        .padding(LBSpacing.s3)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(LBColor.card.color, in: RoundedRectangle(cornerRadius: LBRadius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: LBRadius.md, style: .continuous)
                .strokeBorder(LBColor.hairline.color, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private func turn() {
        let next = ((shown ?? 1) % Self.tips.count) + 1
        turning = true
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.4)) { shown = next }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            turning = false
        }
    }
}
