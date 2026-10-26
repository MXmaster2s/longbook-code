import DesignSystem
import SwiftUI

/// Settings > Tutorials: every screen's tutorial, whether this device has shown it, and
/// Replay. A replay opens the screen, where the tutorial starts as it did the first time.
struct TutorialsView: View {
    private var center: TutorialCenter { TutorialCenter.shared }
    #if os(macOS)
    @Environment(\.openWindow) private var openWindow
    #endif

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LBSpacing.s3) {
                LBPageTitle("Tutorials")
                Text("Each screen shows a short tutorial the first time you open it on this device. Replay any of them here.")
                    .lbText(.footnote)
                    .foregroundStyle(LBColor.textSecondary.color)
                    .fixedSize(horizontal: false, vertical: true)
                list
                Text("Tutorials are kept per device: one you saw on your iPhone still shows the first time you open that screen on your Mac.")
                    .lbText(.footnote)
                    .foregroundStyle(LBColor.textTertiary.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .lbPageColumn(.reading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LBColor.canvas.color)
        .lbScreenTitle("Tutorials")
    }

    private var list: some View {
        // Read so the Seen words redraw after a tutorial ends or is replayed.
        let _ = center.seenRevision
        let screens = ScreenTutorial.listed
        return VStack(spacing: 0) {
            Button {
                Measure.used("replay_all_tutorials")
                center.replayAll()
                open(.dashboard)
            } label: {
                Text("Replay all tutorials")
                    .lbText(.body)
                    .foregroundStyle(LBColor.brandText.color)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .padding(.horizontal, LBSpacing.s4)
                    .contentShape(Rectangle())
            }
            .lbButtonStyle()
            rule
            ForEach(Array(screens.enumerated()), id: \.element) { index, screen in
                row(screen, control: screen.replayControl)
                if index < screens.count - 1 { rule }
            }
        }
        .background(LBColor.card.color, in: RoundedRectangle(cornerRadius: LBRadius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: LBRadius.md, style: .continuous)
                .strokeBorder(LBColor.hairline.color, lineWidth: 1)
        )
    }

    private var rule: some View {
        Rectangle().fill(LBColor.hairline.color).frame(height: 1).padding(.leading, LBSpacing.s4)
    }

    private func row(_ screen: ScreenTutorial, control: StaticString) -> some View {
        HStack(spacing: LBSpacing.s3) {
            Text(screen.title)
                .lbText(.body)
                .foregroundStyle(LBColor.textPrimary.color)
            Spacer(minLength: LBSpacing.s2)
            Text(center.isSeen(screen) ? "Seen" : "Not seen yet")
                .lbText(.footnote)
                .foregroundStyle(LBColor.textTertiary.color)
            Button {
                Measure.used(control)
                center.replay(screen)
                open(screen)
            } label: {
                Text("Replay")
                    .lbText(.label)
                    .foregroundStyle(LBColor.brandText.color)
                    .frame(minHeight: 32)
                    .contentShape(Rectangle())
            }
            .lbButtonStyle()
            .accessibilityLabel("Replay the \(screen.title) tutorial")
        }
        .frame(minHeight: 44)
        .padding(.horizontal, LBSpacing.s4)
    }

    /// The main window opens the screen; on the Mac it comes to the front first, since this
    /// page lives in the Settings window.
    private func open(_ screen: ScreenTutorial) {
        #if os(macOS)
        openWindow(id: LongbookWindow.main)
        NSApp.activate(ignoringOtherApps: true)
        #endif
        NotificationCenter.default.post(name: .longbookOpenTutorial, object: screen)
    }
}
