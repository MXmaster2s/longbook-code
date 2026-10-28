#if os(macOS)
import DesignSystem
import SwiftUI

/// The search field at the top of a Mac list, as a mail app keeps one over its messages:
/// a capsule naming what it searches, ⌘F at its end, and the Edit menu's Find puts the
/// cursor in it.
struct MacSearchField: View {
    @Binding var text: String
    let prompt: String
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: LBSpacing.s2) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(LBColor.textTertiary.color)
                .accessibilityHidden(true)
            TextField("", text: $text, prompt: Text(prompt).foregroundStyle(LBColor.textTertiary.color))
                .textFieldStyle(.plain)
                .lbText(.body)
                .foregroundStyle(LBColor.textPrimary.color)
                .focused($focused)
                .accessibilityLabel(prompt)
            if text.isEmpty {
                Text("⌘F")
                    .lbText(.footnote)
                    .foregroundStyle(LBColor.textQuaternary.color)
                    .accessibilityHidden(true)
            } else {
                Button {
                    Measure.used("clear_search")
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(LBColor.textTertiary.color)
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .lbButtonStyle()
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, LBSpacing.s3)
        .frame(height: 32)
        .background(LBColor.card.color, in: Capsule())
        .overlay(Capsule().strokeBorder(LBColor.hairline.color, lineWidth: 1))
        .onMacCommand(.find) { focused = true }
    }
}
#endif
