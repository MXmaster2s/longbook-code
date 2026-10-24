import DesignSystem
import LongbookCore
import SwiftUI

/// A made-up household with a year of history, written fresh into a scratch folder on each
/// visit; edits stay there. Exit Demo returns to setup. The Mac hosts the sidebar too, so
/// Reports, Calendar and Commitments are a click away.
struct DemoLongbookView: View {
    @ObservedObject var auth: AuthViewModel
    let onLeave: () -> Void

    @State private var model: DashboardModel?
    @State private var path: [Destination] = []
    @State private var trouble: String?
    /// The Mac sidebar's Add commitment, writing into the demo's own folder.
    @State private var adding = false

    var body: some View {
        // A sibling above the stack, not a safe-area inset: the stack's UIKit side does not
        // pass an inset set outside it down to its root.
        VStack(spacing: 0) {
            banner
            if let model {
                #if os(macOS)
                HStack(spacing: 0) {
                    SidebarView(model: model, path: $path) { adding = true }
                    stack(model)
                }
                .measured("demo_longbook_adding", .sheet, when: adding)
                .sheet(isPresented: $adding) {
                    RenewalFormView(model: model, editingId: nil) { adding = false }
                }
                #else
                stack(model)
                #endif
            } else if let trouble {
                VStack(spacing: LBSpacing.s3) {
                    Text("The demo could not be written.")
                        .lbText(.body)
                        .foregroundStyle(LBColor.textPrimary.color)
                    Text(trouble)
                        .lbText(.bodySM)
                        .foregroundStyle(LBColor.textSecondary.color)
                        .multilineTextAlignment(.center)
                }
                .padding(LBSpacing.s8)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(LBColor.canvas.color)
        .task { open() }
        // The demo's screens are not the owner's: no tutorial starts, here or behind it.
        .onAppear { TutorialCenter.shared.hold(true) }
        .onDisappear { TutorialCenter.shared.hold(false) }
    }

    private func stack(_ model: DashboardModel) -> some View {
        NavigationStack(path: $path) {
            DashboardView(model: model, auth: auth, path: $path)
                .navigationDestination(for: Destination.self) { screen in
                    #if os(iOS)
                    destination(screen, model: model)
                    #else
                    destination(screen, model: model)
                        .navigationBarBackButtonHidden(true)
                    #endif
                }
            #if os(macOS)
            .safeAreaInset(edge: .top, spacing: 0) { macBackBar }
            #endif
        }
    }

    /// Says what this is on every demo screen, and holds the one way out.
    private var banner: some View {
        HStack(spacing: LBSpacing.s3) {
            Image(systemName: "sparkles")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(LBColor.brandText.color)
            // Edits land in the demo's scratch folder, which the next visit starts afresh.
            Text("Demo: made-up data. Changes aren’t kept.")
                .lbText(.label)
                .foregroundStyle(LBColor.textPrimary.color)
                .fixedSize(horizontal: false, vertical: true)
            Button("Exit Demo", action: { Measure.used("exit_demo"); onLeave() })
                .buttonStyle(.bordered)
                .keyboardShortcut(.cancelAction)
            Spacer(minLength: LBSpacing.s2)
        }
        .padding(.horizontal, LBSpacing.s4)
        .padding(.vertical, LBSpacing.s3)
        .background(LBColor.sunken.color)
        .overlay(alignment: .bottom) { Rectangle().fill(LBColor.hairline.color).frame(height: 1) }
    }

    /// The screens a dashboard opens. Settings, the account and the connector are the
    /// reader's own and stay outside the demo.
    @ViewBuilder
    private func destination(_ screen: Destination, model: DashboardModel) -> some View {
        switch screen {
        case .commitments(let filter):
            CommitmentsView(model: model, filter: filter).id(screen)
        case .commitment(let id):
            CommitmentDetailView(model: model, id: id)
        case .calendar:
            CalendarView(model: model)
        case .accounts:
            AccountsView(model: model)
        case .members:
            MembersView(model: model)
        case .reports:
            ReportsView(model: model, auth: auth)
        case .report(let id):
            ReportDetailView(model: model, id: id, auth: auth)
        case .insights:
            InsightsView(model: model, path: $path)
        case .changes:
            ChangesView(model: model)
        default:
            VStack(spacing: LBSpacing.s3) {
                Text("That screen is outside the demo.")
                    .lbText(.body)
                    .foregroundStyle(LBColor.textPrimary.color)
                Text("It opens on your own longbook once setup is done.")
                    .lbText(.bodySM)
                    .foregroundStyle(LBColor.textSecondary.color)
            }
            .padding(LBSpacing.s8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(LBColor.canvas.color)
        }
    }

    #if os(macOS)
    @ViewBuilder
    private var macBackBar: some View {
        if !path.isEmpty {
            HStack {
                Button {
                    Measure.used("back")
                    path.removeLast()
                } label: {
                    HStack(spacing: LBSpacing.s1) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Back").lbText(.label)
                    }
                    .foregroundStyle(LBColor.textSecondary.color)
                    .padding(.horizontal, LBSpacing.s2)
                    .padding(.vertical, 4)
                    .background(LBColor.chrome.color, in: Capsule())
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")
                Spacer()
            }
            .padding(.horizontal, LBSpacing.s4)
            .padding(.top, LBSpacing.s3)
            .padding(.bottom, LBSpacing.s1)
        }
    }
    #endif

    /// A fresh household every time: the last visit's folder goes first, so its edits and
    /// history never carry over. Only a folder the demo wrote is ever removed.
    private func open() {
        guard model == nil else { return }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("demo-longbook", isDirectory: true)
        do {
            if FileManager.default.fileExists(atPath: folder.appendingPathComponent(DemoVault.marker).path) {
                try FileManager.default.removeItem(at: folder)
            }
            try DemoVault.write(into: folder)
            let made = DashboardModel(pinnedFolder: folder)
            made.load()
            model = made
            Telemetry.shared.send("app.demo_opened", [:])
        } catch {
            trouble = error.localizedDescription
        }
    }
}
