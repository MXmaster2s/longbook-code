import DesignSystem
import LongbookCore
import SwiftUI

/// The AI's note about a module, as a mark beside the module's name: a bubble that opens
/// the words in a small popover over the card, and nothing at all when there is no note —
/// silence is a fine answer. The Insights screen is where a note is dismissed.
struct InsightMark: View {
    let insight: Insight?
    var ink: LBColorValue = LBColor.brandText
    /// Said in words on a list card, where a bare bubble explains nothing. The file keeps
    /// one note per module, so the count is always one.
    var labelled = false
    @State private var open = false

    var body: some View {
        if let insight {
            Button {
                Measure.used("open_note")
                open.toggle()
            } label: {
                if labelled {
                    Text("1 note")
                        .lbText(.footnote)
                        .foregroundStyle(ink.color)
                        .frame(minHeight: 18)
                        .contentShape(Rectangle())
                } else {
                    Image(systemName: "bubble.left.fill")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(ink.color)
                        .frame(width: 20, height: 18)
                        .contentShape(Rectangle())
                }
            }
            .lbButtonStyle()
            .accessibilityLabel(labelled ? "1 note" : "Insight")
            .accessibilityHint("Shows the note")
            .measured("insight_mark_open", .popover, when: open)
            .popover(isPresented: $open, arrowEdge: .bottom) {
                Text(insight.text)
                    .lbText(.footnote)
                    .foregroundStyle(LBColor.textSecondary.color)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(LBSpacing.s3)
                    .frame(width: 280, alignment: .leading)
                    #if os(iOS)
                    .presentationCompactAdaptation(.popover)
                    #endif
            }
        }
    }
}
