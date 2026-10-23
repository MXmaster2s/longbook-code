import DesignSystem
import SwiftUI

/// The one sentence that tells a reader a pill hides more: a press and hold on the
/// phone, a right-click on the Mac. Said under the pills it applies to, never assumed.
enum LongPressHint {
    static func words(_ does: String) -> String {
        #if os(macOS)
        return "Right-click \(does)"
        #else
        return "Press and hold \(does)"
        #endif
    }
}

struct LongPressHintText: View {
    let does: String

    var body: some View {
        Text(LongPressHint.words(does))
            .lbText(.footnote)
            .foregroundStyle(LBColor.textTertiary.color)
            .fixedSize(horizontal: false, vertical: true)
    }
}
