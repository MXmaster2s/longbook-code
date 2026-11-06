import DesignSystem
import SwiftUI

/// Every tip the reading screen turns through, standing still, each a door to the thing it
/// describes: a screen in the app, or a page that shows how.
struct TipsView: View {
    /// The import door, when the screen that opened Tips has one; otherwise the tip opens
    /// the site's page on statements.
    var importStatement: (() -> Void)? = nil

    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LBSpacing.s4) {
                LBPageTitle("Tips")
                VStack(spacing: LBSpacing.s3) {
                    ForEach(TipsTicker.tips, content: door)
                }
            }
            .lbPageColumn(.reading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LBColor.canvas.color)
        .lbScreenTitle("Tips")
    }

    @ViewBuilder
    private func door(_ tip: TipsTicker.Tip) -> some View {
        switch tip.door {
        case .screen(let destination):
            NavigationLink(value: destination) {
                TipsTicker.card(tip, chevron: true)
            }
            .lbButtonStyle()
        case .link(let url):
            Button {
                Measure.used("open_tip_link")
                openURL(url)
            } label: {
                TipsTicker.card(tip, chevron: true)
            }
            .lbButtonStyle()
        case .importStatement:
            Button {
                Measure.used("tip_import_statement")
                if let importStatement { importStatement() } else { openURL(TipsTicker.statementsPage) }
            } label: {
                TipsTicker.card(tip, chevron: true)
            }
            .lbButtonStyle()
        }
    }
}
