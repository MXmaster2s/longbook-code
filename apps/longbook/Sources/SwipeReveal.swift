import DesignSystem
import SwiftUI

/// A row that slides left under the finger to show what can be done to it. One row is
/// open at a time; a tap on the open row, or a swipe back, closes it. A row that opens
/// nothing of its own can open on a tap as well.
struct SwipeReveal<Actions: View>: ViewModifier {
    let id: String
    @Binding var open: String?
    var opensOnTap = false
    @ViewBuilder let actions: () -> Actions
    @State private var drag: CGFloat = 0
    @State private var width: CGFloat = 0

    func body(content: Content) -> some View {
        let resting: CGFloat = open == id ? -width : 0
        let shift = min(0, max(resting + drag, -width - 24))
        content
            .overlay {
                if open == id {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { close() }
                } else if opensOnTap {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture {
                            LBHaptics.tap()
                            withAnimation(.snappy(duration: 0.25)) { open = id }
                        }
                }
            }
            .offset(x: shift)
            .background(alignment: .trailing) {
                HStack(spacing: LBSpacing.s2) { actions() }
                    .padding(.leading, LBSpacing.s2)
                    .background(
                        GeometryReader { proxy in
                            Color.clear.onAppear { width = proxy.size.width }
                        }
                    )
                    .opacity(shift < -4 ? 1 : 0)
            }
            .clipped()
            // High priority: the row may be a link, and a link's own gesture otherwise
            // swallows the drag before it is a swipe.
            .highPriorityGesture(
                DragGesture(minimumDistance: 20, coordinateSpace: .local)
                    .onChanged { value in
                        guard abs(value.translation.width) > abs(value.translation.height) else { return }
                        drag = value.translation.width
                    }
                    .onEnded { value in
                        let target = resting + value.translation.width
                        withAnimation(.snappy(duration: 0.25)) {
                            drag = 0
                            if target < -width / 2 {
                                open = id
                            } else if open == id {
                                open = nil
                            }
                        }
                    }
            )
            .animation(.snappy(duration: 0.25), value: open)
    }

    private func close() {
        withAnimation(.snappy(duration: 0.25)) { open = nil }
    }
}

extension View {
    func swipeReveal<Actions: View>(
        id: String, open: Binding<String?>, opensOnTap: Bool = false, @ViewBuilder actions: @escaping () -> Actions
    ) -> some View {
        modifier(SwipeReveal(id: id, open: open, opensOnTap: opensOnTap, actions: actions))
    }
}
