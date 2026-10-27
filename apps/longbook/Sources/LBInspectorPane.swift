import DesignSystem
import SwiftUI

#if os(macOS)
/// The Mac's preview pane, in the manner of Apple's inspector: it slides in from the right
/// when something is chosen and leaves when the choice is cleared. Drawn by hand because
/// the window's one system inspector column is the Support panel's.
struct LBInspectorPane<Pane: View>: ViewModifier {
    @Binding var isPresented: Bool
    let width: CGFloat
    @ViewBuilder let pane: () -> Pane
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        HStack(spacing: 0) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if isPresented {
                Divider()
                pane()
                    .frame(width: width)
                    .frame(maxHeight: .infinity)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: isPresented)
    }
}

extension View {
    func lbInspector<Pane: View>(isPresented: Binding<Bool>, width: CGFloat = 360, @ViewBuilder pane: @escaping () -> Pane) -> some View {
        modifier(LBInspectorPane(isPresented: isPresented, width: width, pane: pane))
    }
}
#endif
