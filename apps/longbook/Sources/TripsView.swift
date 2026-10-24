import DesignSystem
import LongbookCore
import SwiftUI

/// Trips: one running from today, or one that is over, each kept as a report narrowed to its
/// days, people and accounts. One grouped list: the running trip on top with the way to end
/// it, the two ways in, then the trips so far.
struct TripsView: View {
    let model: DashboardModel
    @Binding var path: [Destination]
    @State private var flow: TripFlowView.Mode?
    @State private var confirmingEnd = false

    var body: some View {
        let trips = model.trips().filter { $0.id != model.openTripId }
        List {
            #if os(macOS)
            VStack(alignment: .leading, spacing: LBSpacing.s1) {
                LBPageTitle("Trips")
                Text("See what each trip cost.")
                    .lbText(.bodySM)
                    .foregroundStyle(LBColor.textSecondary.color)
            }
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            #endif
            if let open = model.openTrip() {
                Section {
                    openCard(open)
                        .lbListRowBackground()
                }
            }
            Section {
                // Start is offered only while no trip runs; a past trip can be added at any time.
                if model.openTripId == nil {
                    Button { Measure.used("start_a_trip"); flow = .start } label: {
                        LBListRow("Start a trip", secondary: "Collects charges until you end it.", chevron: true) {
                            tile("airplane.departure", ink: 7)
                        }
                    }
                    .buttonStyle(.plain)
                    .lbListRowBackground()
                }
                Button { Measure.used("add_a_past_trip"); flow = .past } label: {
                    LBListRow("Add a past trip", chevron: true) { tile("calendar.badge.plus", ink: 2) }
                }
                .buttonStyle(.plain)
                .lbListRowBackground()
            } footer: {
                #if os(iOS)
                Text("See what each trip cost.")
                    .lbText(.footnote)
                    .foregroundStyle(LBColor.textTertiary.color)
                #endif
            }
            Section {
                if trips.isEmpty {
                    Text("No past trips yet.")
                        .lbText(.bodySM)
                        .foregroundStyle(LBColor.textTertiary.color)
                        .lbListRowBackground()
                } else {
                    ForEach(trips) { trip in
                        NavigationLink(value: Destination.report(id: trip.id)) { tripRow(trip) }
                            .lbListRowBackground()
                    }
                }
            } header: {
                LBSectionHeader(trips.isEmpty ? "Past trips" : "Past trips · \(trips.count)")
            }
        }
        .lbGroupedList()
        // A list keeps to the reading measure on a wide Mac window, as the other pages do.
        .frame(maxWidth: LBPageWidth.reading.maxWidth)
        .frame(maxWidth: .infinity)
        .background(LBColor.canvas.color)
        .lbScreenTitle("Trips")
        .onAppear {
            model.drawMonthlyReports()
            #if DEBUG
            // The harness opens the flow the way a tap would.
            switch ProcessInfo.processInfo.environment["LONGBOOK_SNAPSHOT_SCREEN"] {
            case "addtrip": flow = .past
            case "starttrip": flow = .start
            default: break
            }
            #endif
        }
        .measured("trips_flow", .sheet, when: flow != nil)
        .sheet(item: $flow) { mode in
            TripFlowView(model: model, mode: mode, onCreated: { id in
                flow = nil
                path.append(.report(id: id))
            }, onClose: { flow = nil })
            #if os(iOS)
            .presentationDetents([.large])
            #endif
        }
        .measured("trips_confirming_end", .dialog, when: confirmingEnd)
        .confirmationDialog("End this trip?", isPresented: $confirmingEnd, titleVisibility: .visible) {
            Button("End Trip") { Measure.used("end_trip"); model.endTrip() }
            Button("Cancel", role: .cancel) { Measure.used("cancel") }
        } message: {
            Text("The report keeps the days from the trip’s first day to today.")
        }
    }

    private func tile(_ symbol: String, ink: Int) -> some View {
        RoundedRectangle(cornerRadius: LBRadius.xs, style: .continuous)
            .fill(LBColor.dataInk(rank: ink).color.opacity(0.16))
            .frame(width: 30, height: 30)
            .overlay(
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(LBColor.dataInk(rank: ink).color)
            )
            .accessibilityHidden(true)
    }

    /// A past trip: its name, its days and charges, its total.
    private func tripRow(_ trip: Report) -> some View {
        let count = trip.chargeRows.kept.count
        let meta = [
            trip.rangeName ?? trip.writtenNote,
            count > 0 ? "\(count) charge\(count == 1 ? "" : "s")" : nil,
        ].compactMap { $0 }.joined(separator: " · ")
        let total = trip.totalStat.flatMap { stat in stat.amount.flatMap { amount in stat.currency.map { fmtMoney(amount, $0) } } }
        return LBListRow(trip.title, secondary: meta, amount: total)
    }

    // MARK: the running trip

    /// The trip under way: its name, its days so far, what it has come to, and the two things
    /// to do with it.
    private func openCard(_ trip: Report) -> some View {
        let total = trip.totalStat.flatMap { stat in stat.amount.flatMap { amount in stat.currency.map { fmtMoney(amount, $0) } } }
        let count = trip.chargeRows.kept.count
        return VStack(alignment: .leading, spacing: LBSpacing.s3) {
            VStack(alignment: .leading, spacing: LBSpacing.s1) {
                LBBadge("Trip mode is on", tone: .brand)
                Text(trip.title)
                    .lbText(.displayLG)
                    .foregroundStyle(LBColor.textPrimary.color)
                    .fixedSize(horizontal: false, vertical: true)
                if let days = trip.rangeName {
                    Text(days)
                        .lbText(.bodySM)
                        .foregroundStyle(LBColor.textSecondary.color)
                }
                if let scope = trip.scopeLine {
                    Text(scope)
                        .lbText(.footnote)
                        .foregroundStyle(LBColor.textTertiary.color)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: LBSpacing.s2) {
                Text(total ?? "—")
                    .lbText(.statNumber)
                    .foregroundStyle(LBColor.textPrimary.color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                Text("\(count) charge\(count == 1 ? "" : "s")")
                    .lbText(.footnote)
                    .foregroundStyle(LBColor.textTertiary.color)
            }
            HStack(spacing: LBSpacing.s3) {
                Button {
                    Measure.used("open_report")
                    path.append(.report(id: trip.id))
                } label: {
                    capsule("Open Report", filled: true)
                }
                .buttonStyle(.borderless)
                Button {
                    Measure.used("end_trip")
                    confirmingEnd = true
                } label: {
                    capsule("End Trip", filled: false)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.vertical, LBSpacing.s2)
    }

    private func capsule(_ title: String, filled: Bool) -> some View {
        Text(title)
            .lbText(.label)
            .foregroundStyle(filled ? LBColor.onBrand.color : LBColor.textSecondary.color)
            .padding(.horizontal, LBSpacing.s4)
            .padding(.vertical, LBSpacing.s2)
            .background(filled ? LBColor.brand.color : LBColor.chrome.color, in: Capsule())
    }
}

/// One report as the lists show it: its name, its days and how many charges it holds, the
/// total at the end. A trip wears a plane; any other report a page.
struct ReportListRow: View {
    let report: Report

    var body: some View {
        let count = report.chargeRows.kept.count
        let meta = [
            report.rangeName ?? report.writtenNote,
            count > 0 ? "\(count) charge\(count == 1 ? "" : "s")" : nil,
        ].compactMap { $0 }.joined(separator: " · ")
        let total = report.totalStat.flatMap { stat in stat.amount.flatMap { amount in stat.currency.map { fmtMoney(amount, $0) } } }
        return NavigationLink(value: Destination.report(id: report.id)) {
            HStack(spacing: LBSpacing.s3) {
                Image(systemName: report.isTrip ? "airplane" : "doc.text")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(LBColor.brandText.color)
                    .frame(width: 30, height: 30)
                    .background(LBColor.chrome.color, in: RoundedRectangle(cornerRadius: LBRadius.xs, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text(report.title)
                        .lbText(.body)
                        .foregroundStyle(LBColor.textPrimary.color)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if !meta.isEmpty {
                        Text(meta)
                            .lbText(.footnote)
                            .foregroundStyle(LBColor.textTertiary.color)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                Spacer(minLength: LBSpacing.s2)
                if let total {
                    LBAmount(total, prominence: .inline)
                        .foregroundStyle(LBColor.textPrimary.color)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(LBColor.textQuaternary.color)
            }
            .padding(LBSpacing.s3)
            .background(LBColor.card.color, in: RoundedRectangle(cornerRadius: LBRadius.md, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }
}
