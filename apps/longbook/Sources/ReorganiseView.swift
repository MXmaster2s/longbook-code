import DesignSystem
import LongbookCore
import SwiftUI

/// "Reorganise my longbook": one sheet that says what the pass does, runs it on the server,
/// and says what came back. Nothing applies by itself beyond the one change that waits in
/// Changes, where the owner keeps or undoes the whole pass at once.
struct ReorganiseView: View {
    let model: DashboardModel
    @ObservedObject var auth: AuthViewModel
    let onDone: () -> Void

    private enum Stage: Equatable { case ready, running, done, failed(String) }
    @State private var stage: Stage = .ready
    /// The same consent statements ask for: the whole file goes to Anthropic's Claude.
    @AppStorage(AIConsent.statements.key) private var consented = false
    @State private var askingConsent = false
    @State private var summary = ""
    @State private var applied = 0
    @State private var skipped = 0

    private static let pitch = "longbook's AI reads your whole longbook and proposes it the way you'd keep it: names as you'd say them, every row categorised, people and accounts linked, doubles merged, nothing lost. Amounts and dates are never touched."

    var body: some View {
        VStack(alignment: .leading, spacing: LBSpacing.s4) {
            header
            switch stage {
            case .ready: ready
            case .running: running
            case .done: done
            case .failed(let why): failed(why)
            }
            Spacer(minLength: 0)
        }
        .padding(LBSpacing.s6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(LBColor.canvas.color)
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 360)
        #else
        .presentationDetents([.medium, .large])
        #endif
        .interactiveDismissDisabled(stage == .running)
        .measured("reorganise_asking_consent", .sheet, when: askingConsent)
        .sheet(isPresented: $askingConsent) {
            ConsentSheet(consent: .statements, onAccept: {
                consented = true
                askingConsent = false
                Task { await run() }
            }, onDecline: { askingConsent = false })
        }
    }

    /// Runs the pass once the reader has accepted that the file goes to the AI.
    private func begin() {
        if consented { Task { await run() } } else { askingConsent = true }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Reorganise my longbook")
                .lbText(.title)
                .foregroundStyle(LBColor.textPrimary.color)
            Spacer()
            if stage != .running {
                Button("Done", action: { Measure.used("done"); onDone() })
                    .buttonStyle(.plain)
                    .lbText(.label)
                    .foregroundStyle(LBColor.brandText.color)
                    .keyboardShortcut(.cancelAction)
            }
        }
    }

    private var ready: some View {
        VStack(alignment: .leading, spacing: LBSpacing.s3) {
            Text(Self.pitch)
                .lbText(.body)
                .foregroundStyle(LBColor.textPrimary.color)
                .fixedSize(horizontal: false, vertical: true)
            Text("Your longbook is sent to longbook's server for this one pass and not kept. Everything lands in Changes as one change, to keep or undo at once.")
                .lbText(.footnote)
                .foregroundStyle(LBColor.textTertiary.color)
                .fixedSize(horizontal: false, vertical: true)
            if !auth.isSignedIn {
                Text(ReorganiseCloud.CloudError.notSignedIn.localizedDescription)
                    .lbText(.bodySM)
                    .foregroundStyle(LBColor.textSecondary.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
            primary("Reorganise", enabled: auth.isSignedIn && model.vaultText != nil) { begin() }
        }
    }

    private var running: some View {
        VStack(alignment: .leading, spacing: LBSpacing.s3) {
            HStack(spacing: LBSpacing.s2) {
                ProgressView().controlSize(.small)
                Text("Reading your longbook…")
                    .lbText(.body)
                    .foregroundStyle(LBColor.textPrimary.color)
            }
            Text("A minute or two for a full book. Leave this open.")
                .lbText(.footnote)
                .foregroundStyle(LBColor.textTertiary.color)
        }
    }

    private var done: some View {
        VStack(alignment: .leading, spacing: LBSpacing.s3) {
            if !summary.isEmpty {
                Text(summary)
                    .lbText(.body)
                    .foregroundStyle(LBColor.textPrimary.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(count)
                .lbText(.bodySM)
                .foregroundStyle(LBColor.textSecondary.color)
                .fixedSize(horizontal: false, vertical: true)
            if applied > 0 {
                Text("Keep or undo it in Changes.")
                    .lbText(.footnote)
                    .foregroundStyle(LBColor.textTertiary.color)
            }
            primary("Done", action: onDone)
        }
    }

    /// What landed, in the owner's words; a skipped one is said without blame.
    private var count: String {
        var words = applied == 0 ? "Nothing needed changing." : applied == 1 ? "One change waits in Changes." : "\(applied) changes wait in Changes, as one."
        if skipped > 0 { words += skipped == 1 ? " One suggestion did not fit your file and was left out." : " \(skipped) suggestions did not fit your file and were left out." }
        return words
    }

    private func failed(_ why: String) -> some View {
        VStack(alignment: .leading, spacing: LBSpacing.s3) {
            Text(why)
                .lbText(.body)
                .foregroundStyle(LBColor.textPrimary.color)
                .fixedSize(horizontal: false, vertical: true)
            primary("Try Again") { begin() }
        }
    }

    private func run() async {
        guard let text = model.vaultText else { return }
        stage = .running
        let token = await auth.accessToken()
        do {
            let answer = try await ReorganiseCloud.run(vaultText: text, token: token)
            let landed = try model.reorganise(answer.proposals)
            summary = answer.summary
            applied = landed.applied
            skipped = landed.skipped + answer.dropped
            stage = .done
        } catch {
            stage = .failed(error.localizedDescription)
        }
    }

    private func primary(_ title: String, enabled: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: { Measure.used("reorganise_primary"); action() }) {
            Text(title)
                .lbText(.body)
                .foregroundStyle(LBColor.onBrand.color)
                .frame(maxWidth: .infinity)
                .padding(.vertical, LBSpacing.s3)
                .background(LBColor.brand.color.opacity(enabled ? 1 : 0.4), in: RoundedRectangle(cornerRadius: LBRadius.sm, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}
