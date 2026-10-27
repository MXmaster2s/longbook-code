import DesignSystem
import LongbookCore
import SwiftUI

/// Every note the AI has left, gathered in one findable place — grouped by the area
/// each note annotates, tapping through to it. longbook never writes these itself;
/// see docs/insights-format.md. Not a port of the archived app's computed engine,
/// which the owner retired 2026-08-07 in favour of this file.
struct InsightsView: View {
    let model: DashboardModel
    @Binding var path: [Destination]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LBSpacing.s4) {
                header
                let areas = model.insightAreas()
                if areas.isEmpty {
                    empty
                } else {
                    ForEach(areas) { area in
                        areaSection(area)
                            .tutorialTarget(area.id == areas.first?.id ? .insightsFirst
                                            : ["accounts", "members"].contains(area.id) ? .insightsEntities : nil)
                    }
                }
            }
            // Notes are sentences: a wider line stops reading as one.
            .lbPageColumn(.wide)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LBColor.canvas.color)
        .screenTutorial(.insights)
        .lbScreenTitle("Insights")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: LBSpacing.s1) {
            LBPageTitle("Insights")
            Text("Notes from your AI.")
                .lbText(.bodySM)
                .foregroundStyle(LBColor.textTertiary.color)
        }
    }

    private var empty: some View {
        LBPanel {
            VStack(alignment: .leading, spacing: LBSpacing.s3) {
                Text("Nothing yet")
                    .lbText(.body)
                    .foregroundStyle(LBColor.textPrimary.color)
                Text("Ask your AI to read your longbook and leave notes: patterns, changes, anything the figures alone do not show.")
                    .lbText(.footnote)
                    .foregroundStyle(LBColor.textTertiary.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func areaSection(_ area: DashboardModel.InsightArea) -> some View {
        VStack(alignment: .leading, spacing: LBSpacing.s2) {
            LBSectionHeader(area.title)
            VStack(spacing: 0) {
                ForEach(Array(area.rows.enumerated()), id: \.element.id) { index, row in
                    insightRow(row, separated: index < area.rows.count - 1)
                }
            }
            .background(LBColor.card.color, in: RoundedRectangle(cornerRadius: LBRadius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: LBRadius.md, style: .continuous)
                    .strokeBorder(LBColor.hairline.color, lineWidth: 1)
            )
        }
    }

    /// The note, the door it opens if it has one, and the way to be rid of it. The cross
    /// sits beside the door, not inside it, so a tap on either does only its own thing.
    private func insightRow(_ row: DashboardModel.InsightPlace, separated: Bool) -> some View {
        HStack(alignment: .top, spacing: 0) {
            Button { Measure.used("open_insight"); open(row) } label: {
                insightRowBody(row)
            }
            .lbButtonStyle()
            Button { Measure.used("remove_insight"); model.removeInsight(row.id) } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(LBColor.textTertiary.color)
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .lbButtonStyle()
            .lbTapHaptic()
            .padding(.top, LBSpacing.s2)
            .padding(.trailing, LBSpacing.s2)
            .accessibilityLabel("Remove this insight")
        }
        .overlay(alignment: .bottom) {
            if separated {
                Rectangle().fill(LBColor.hairline.color).frame(height: 1)
                    .padding(.leading, LBSpacing.s3)
            }
        }
    }

    /// Every note opens where it belongs. On the Mac a dashboard note opens the dashboard,
    /// the sidebar's own root; the phone's tabs are out of reach here, so it opens the
    /// screen the note's card opens.
    private func open(_ row: DashboardModel.InsightPlace) {
        #if os(macOS)
        if row.id.hasPrefix("dashboard.") {
            path = []
            return
        }
        #endif
        if let door = row.door { path = [door] }
    }

    private func insightRowBody(_ row: DashboardModel.InsightPlace) -> some View {
        HStack(alignment: .top, spacing: LBSpacing.s3) {
            VStack(alignment: .leading, spacing: 2) {
                // An account or member keeps its ink beside its name, the colour it wears elsewhere.
                HStack(spacing: LBSpacing.s2) {
                    if let ink = row.ink {
                        Circle()
                            .fill(LBColor.dataInk(rank: ink).color)
                            .frame(width: 7, height: 7)
                            .accessibilityHidden(true)
                    }
                    Text(row.place)
                        .lbText(.footnote)
                        .foregroundStyle(LBColor.textTertiary.color)
                }
                Text(row.insight.text)
                    .lbText(.bodySM)
                    .foregroundStyle(LBColor.textPrimary.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: LBSpacing.s2)
            #if os(macOS)
            // A pointer reads a word where a finger reads a chevron.
            Text("Show")
                .lbText(.label)
                .foregroundStyle(LBColor.brandText.color)
                .padding(.top, 2)
            #else
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(LBColor.textQuaternary.color)
                .accessibilityHidden(true)
            #endif
        }
        .padding(LBSpacing.s3)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
