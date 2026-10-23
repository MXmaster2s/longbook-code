import DesignSystem
import LongbookCore
import SwiftUI

/// The review half of "the file is the truth": an outside edit is already live, and this
/// strip says so above every screen but Changes, on both platforms. Show changes opens the
/// review; Keep changes adopts it. Undo lives on the Changes screen alone.
struct ReviewCard: View {
    let model: DashboardModel
    @Binding var path: [Destination]
    /// Why the last Keep was refused, said under the buttons until one goes through.
    @State private var refusal: String?
    /// On the Mac with the sidebar away, the hidden title bar's traffic lights sit on the
    /// strip's first row; this pads the strip down past them.
    var clearsTitleBar = false

    var body: some View {
        if model.outsideChangeFrom != nil, path.last != .changes {
            let diff = model.reviewDiff()
            VStack(alignment: .leading, spacing: LBSpacing.s2) {
                HStack(spacing: LBSpacing.s2) {
                    Image(systemName: LBGlyph.ai)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(LBColor.brandText.color)
                        .accessibilityHidden(true)
                    Text(headline(diff))
                        .lbText(.label)
                        .foregroundStyle(LBColor.textPrimary.color)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
                HStack(spacing: LBSpacing.s2) {
                    Button {
                        // The Mac sidebar replaces the path; the phone pushes onto its tab.
                        #if os(macOS)
                        path = [.changes]
                        #else
                        path.append(.changes)
                        #endif
                    } label: {
                        capsule("Show changes", ink: LBColor.onBrand, fill: LBColor.brand)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Opens the Changes screen.")
                    Button {
                        if model.keepOutsideChange() {
                            refusal = nil
                            Telemetry.shared.send("app.proposal_reviewed", ["decision": "kept"])
                        } else {
                            refusal = model.saveError
                        }
                    } label: {
                        capsule("Keep changes", ink: LBColor.textSecondary, fill: LBColor.chrome)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Adopts the change as it stands, on every device.")
                }
                if let refusal {
                    Text(refusal)
                        .lbText(.footnote)
                        .foregroundStyle(LBColor.urgent.color)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, LBSpacing.s4)
            .padding(.vertical, LBSpacing.s3)
            .padding(.top, clearsTitleBar ? 28 : 0)
            .background(LBColor.sunken.color)
            .overlay(alignment: .bottom) { Rectangle().fill(LBColor.hairline.color).frame(height: 1) }
        }
    }

    /// One of the strip's two answers, drawn as a capsule.
    private func capsule(_ words: String, ink: LBColorValue, fill: LBColorValue) -> some View {
        Text(words)
            .lbText(.label)
            .foregroundStyle(ink.color)
            .padding(.horizontal, LBSpacing.s4)
            .frame(minHeight: 34)
            .background(fill.color, in: Capsule())
            .contentShape(Capsule())
    }

    /// Who proposed how much, counted as the Changes screen counts its lines: a plan is one,
    /// a one-time commitment and its charge are one. The writer is named when one outside
    /// hand signed every row; only its first letter is raised, the rest reads as signed.
    private func headline(_ diff: [EntityDiff]) -> String {
        let count = ChangesView.foldedLineCount(diff)
        guard count > 0 else { return "Your folder changed outside longbook" }
        let plural = count == 1 ? "" : "s"
        if let writer = model.reviewWriter(diff) {
            return "\(writer.capitalizedFirst) proposed \(count) change\(plural)"
        }
        // Only added rows are new items; a changed or removed row among them makes changes.
        let allNew = diff.allSatisfy { $0.removed.isEmpty && $0.changed.isEmpty }
        return allNew
            ? "\(count) new item\(plural) proposed in Changes"
            : "\(count) change\(plural) proposed in Changes"
    }
}
