import DesignSystem
import LongbookCore
import SwiftUI

/// Whether What's New is up, and when it opens by itself: once per version on this device,
/// the first time the book shows after an update. Settings opens it any time.
@MainActor
@Observable
final class WhatsNewCenter {
    static let shared = WhatsNewCenter()

    var presented = false

    private init() {}

    #if DEBUG
    /// Pictures and simulator runs show screens as they are, with nothing over them.
    private static let disabled: Bool = {
        let env = ProcessInfo.processInfo.environment
        return ["LONGBOOK_SNAPSHOT", "LONGBOOK_SNAPSHOT_SCREEN", "LONGBOOK_WINDOW_SNAPSHOT", "LONGBOOK_NO_TUTORIALS",
                "LONGBOOK_NO_WHATS_NEW"].contains { env[$0] != nil }
    }()
    #else
    private static let disabled = false
    #endif

    /// This copy's version, as its bundle states it.
    static var version: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "" }

    /// This version's changes from the changelog the app ships.
    static var changes: [WhatsNew.Change] { WhatsNew.changes(for: version, in: AppUpdates.releases) }

    func open() { presented = true }

    /// A new install meets setup first, not a list of changes it never saw before.
    func recordInstall() {
        guard !Self.disabled else { return }
        UserDefaults.standard.set(Self.version, forKey: WhatsNew.seenKey)
    }

    /// Opens once when this version is newer than the last one shown here, then keeps it.
    func openIfDue() {
        guard !Self.disabled, !presented else { return }
        let seen = UserDefaults.standard.string(forKey: WhatsNew.seenKey)
        guard WhatsNew.isDue(current: Self.version, seen: seen), !Self.changes.isEmpty else { return }
        UserDefaults.standard.set(Self.version, forKey: WhatsNew.seenKey)
        presented = true
    }
}

/// "What's New in longbook 1.5.0": this version's changes, each with its New or Fixed badge
/// and its first sentence in bold, then Open in Browser for every version and Done.
struct WhatsNewView: View {
    let onDone: () -> Void
    @Environment(\.openURL) private var openURL

    static let releaseNotesURL = URL(string: "https://longbook.app/release-notes/")!
    private let changes = WhatsNewCenter.changes

    var body: some View {
        VStack(alignment: .leading, spacing: LBSpacing.s4) {
            HStack(spacing: LBSpacing.s3) {
                Image("SidebarMark")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 36, height: 36)
                    .accessibilityHidden(true)
                Text("What’s New in longbook \(WhatsNewCenter.version)")
                    .lbText(.screenTitle)
                    .foregroundStyle(LBColor.textPrimary.color)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: LBSpacing.s4) {
                    ForEach(changes) { change in row(change) }
                }
                .padding(.vertical, LBSpacing.s1)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            #if os(macOS)
            .frame(height: 360)
            #endif
            buttons
        }
        .padding(LBSpacing.s6)
        #if os(macOS)
        .frame(width: 520)
        .background(LBColor.card.color)
        #else
        .frame(maxHeight: .infinity, alignment: .top)
        .presentationBackground(LBColor.card.color)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        #endif
        .tint(LBColor.brandText.color)
    }

    private func row(_ change: WhatsNew.Change) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: LBSpacing.s3) {
            LBBadge(change.kind.label, tone: change.kind == .fixed ? .muted : .positive)
            Text(change.rest.isEmpty
                 ? "\(Text(change.lead).fontWeight(.semibold).foregroundStyle(LBColor.textPrimary.color))"
                 : "\(Text(change.lead).fontWeight(.semibold).foregroundStyle(LBColor.textPrimary.color)) \(change.rest)")
                .lbText(.bodySM)
                .foregroundStyle(LBColor.textSecondary.color)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var buttons: some View {
        #if os(macOS)
        HStack(spacing: LBSpacing.s2) {
            Button("Open in Browser") { Measure.used("whats_new_open_in_browser"); openURL(Self.releaseNotesURL) }
            Spacer(minLength: LBSpacing.s3)
            Button("Done") { Measure.used("whats_new_done"); onDone() }
                .keyboardShortcut(.defaultAction)
                .tint(LBColor.brand.color)
                .buttonStyle(.borderedProminent)
        }
        .controlSize(.large)
        #else
        HStack(spacing: LBSpacing.s2) {
            filled("Open in Browser", primary: false, measure: "whats_new_open_in_browser") { openURL(Self.releaseNotesURL) }
            filled("Done", primary: true, measure: "whats_new_done", action: onDone)
        }
        #endif
    }

    #if os(iOS)
    private func filled(_ title: String, primary: Bool, measure: StaticString, action: @escaping () -> Void) -> some View {
        Button(action: { Measure.used(measure); action() }) {
            Text(title)
                .lbText(.body)
                .foregroundStyle(primary ? LBColor.onBrand.color : LBColor.textPrimary.color)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(primary ? LBColor.brand.color : LBColor.chrome.color,
                            in: RoundedRectangle(cornerRadius: LBRadius.md, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(OnboardingPressStyle())
    }
    #endif
}

/// What's New as a sheet over the view it sits on, counted while it is up; tutorials wait
/// behind it.
struct WhatsNewPresenter: ViewModifier {
    @Bindable private var center = WhatsNewCenter.shared

    func body(content: Content) -> some View {
        content
            .measured("whats_new", .sheet, when: center.presented)
            .sheet(isPresented: $center.presented) {
                WhatsNewView { center.presented = false }
                    .onAppear { TutorialCenter.shared.hold(true) }
                    .onDisappear { TutorialCenter.shared.hold(false) }
            }
    }
}
