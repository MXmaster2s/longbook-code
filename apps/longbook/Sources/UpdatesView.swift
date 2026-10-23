import DesignSystem
import LongbookCore
import SwiftUI

/// What What’s New opens (Check for Updates on the Mac): the version this copy is, what changed in it, the earlier
/// versions, and the one way to a newer build. The App Store or TestFlight does the updating.
struct UpdatesView: View {
    @State private var place = AppUpdates.Place.testFlight
    @Environment(\.openURL) private var openURL

    /// One version's changes across every build it shipped as, newest first, each said once.
    private struct VersionNotes: Identifiable {
        let version: String
        var changes: [String]
        var id: String { version }
    }

    private var versions: [VersionNotes] {
        var out: [VersionNotes] = []
        var index: [String: Int] = [:]
        for release in AppUpdates.releases {
            if index[release.version] == nil {
                index[release.version] = out.count
                out.append(VersionNotes(version: release.version, changes: []))
            }
            let at = index[release.version]!
            for change in release.changes where !out[at].changes.contains(change) {
                out[at].changes.append(change)
            }
        }
        return out
    }

    private var currentVersion: String? { AppUpdates.currentRelease?.version }
    @State private var showingEarlier = false

    /// A note as the screen shows it: its first sentence, which says what changed; the rest
    /// explains how. A build whose note says nothing changes for the reader is left out.
    static func shown(_ changes: [String]) -> [String] {
        changes
            .filter { !$0.hasPrefix("Nothing you will see") }
            .map(firstSentence)
    }

    private static func firstSentence(_ text: String) -> String {
        var index = text.startIndex
        while let stop = text[index...].firstIndex(of: ".") {
            let next = text.index(after: stop)
            // A full stop ends the sentence only before a space and a capital, so "1.3.6" holds.
            if next < text.endIndex, text[next] == " ",
               let after = text[next...].dropFirst().first, after.isUppercase {
                return String(text[..<next])
            }
            index = next
        }
        return text
    }

    var body: some View {
        SettingsScreen(title: AppUpdates.screenTitle, note: "") {
            let versions = versions
            LBCard {
                HStack(spacing: LBSpacing.s3) {
                    Image("SidebarMark")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 40, height: 40)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("longbook")
                            .lbText(.body)
                            .foregroundStyle(LBColor.textPrimary.color)
                        Text("\(AppUpdates.versionLine), installed")
                            .lbText(.footnote)
                            .foregroundStyle(LBColor.textTertiary.color)
                            .textSelection(.enabled)
                    }
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)
            }
            if let current = versions.first(where: { $0.version == currentVersion }) {
                LBSectionHeader("What’s new in \(current.version)")
                LBCard { changes(Self.shown(current.changes)) }
            }
            let earlier = versions.filter { $0.version != currentVersion }
            if !earlier.isEmpty {
                Button {
                    withAnimation(.easeOut(duration: 0.2)) { showingEarlier.toggle() }
                } label: {
                    HStack(spacing: LBSpacing.s1) {
                        LBSectionHeader("Earlier versions")
                        Image(systemName: showingEarlier ? "chevron.up" : "chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(LBColor.textTertiary.color)
                        Spacer(minLength: 0)
                    }
                    .frame(minHeight: 32)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint(showingEarlier ? "Hides the earlier versions." : "Shows what changed in earlier versions.")
                if showingEarlier {
                    ForEach(earlier) { version in
                        LBCard {
                            VStack(alignment: .leading, spacing: LBSpacing.s2) {
                                Text(version.version)
                                    .lbText(.label)
                                    .foregroundStyle(LBColor.textPrimary.color)
                                changes(Self.shown(version.changes))
                            }
                        }
                    }
                }
            }
            LBSectionHeader("Get the latest")
            Button {
                openURL(AppUpdates.url(for: place))
            } label: {
                Text(AppUpdates.button(for: place))
                    .lbText(.label)
                    .foregroundStyle(LBColor.onBrand.color)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(LBColor.brand.color, in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            Text(AppUpdates.message(for: place))
                .lbText(.footnote)
                .foregroundStyle(LBColor.textTertiary.color)
                .fixedSize(horizontal: false, vertical: true)
        }
        .task { place = await AppUpdates.place() }
    }

    private func changes(_ changes: [String]) -> some View {
        VStack(alignment: .leading, spacing: LBSpacing.s2) {
            ForEach(Array(changes.enumerated()), id: \.offset) { _, change in
                HStack(alignment: .top, spacing: LBSpacing.s2) {
                    Circle()
                        .fill(LBColor.textQuaternary.color)
                        .frame(width: 4, height: 4)
                        .padding(.top, 7)
                    Text(change)
                        .lbText(.bodySM)
                        .foregroundStyle(LBColor.textSecondary.color)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}
