import DesignSystem
import LongbookCore
import SwiftUI

/// The sentence an owner hands their own AI, and where the folder is. Short on purpose:
/// everything an AI needs is in llms.txt inside the folder it is pointed at. A prompt that
/// teaches is a prompt that goes stale.
@MainActor
enum SetupPrompt {
    /// What the statement is for: setting the book up, adding charges and reports to one, or
    /// filling one month that has nothing in it, named in English as the phrases are.
    enum Context: Equatable {
        case setup, reports
        case month(String)
    }

    /// The catalogue's phrases, so the words match the Automations screen and the servers.
    private static var setupJob: String { PromptCatalog.phrase(id: "set-up-my-longbook") }

    /// add-my-statement's second phrase, the one naming longbook, so an AI with other
    /// connectors knows which book to update. The first phrase if a catalogue lists only one.
    private static var reportsJob: String {
        let phrases = PromptCatalog.phrases(id: "add-my-statement")
        return phrases.dropFirst().first ?? phrases.first ?? "Update my longbook from my statements"
    }

    private static func job(_ context: Context) -> String {
        switch context {
        case .setup: setupJob
        case .reports: reportsJob
        case .month(let name): PromptCatalog.phrase(id: "add-a-month-report-in-my-longbook", month: name)
        }
    }

    /// The same sentence, naming where the folder really is: in iCloud Drive, or on this
    /// device — including a folder someone picked. An AI sent to the wrong one writes where
    /// nothing is watching.
    static func prompt(for model: DashboardModel, context: Context = .setup) -> String {
        guard let place = location(for: model) else { return "\(job(context))." }
        return "\(job(context)) — the folder is \(place)."
    }

    /// On the phone an AI reaches longbook only through the server, and the connector is
    /// where it writes. The server tells the AI what the book already names.
    static func connectorPrompt(_ context: Context) -> String {
        "\(job(context)) through the longbook connector."
    }

    /// Where the folder is, in the app's own words, for any prompt that has to name it.
    /// Nil while no vault is loaded: a guess is the fault this exists to avoid.
    static func location(for model: DashboardModel) -> String? {
        guard case .loaded(let data) = model.state else { return nil }
        return place(data.vaultLocation, folder: model.vaultFolderURL)
    }

    /// The app's own words for the place, plus the path on the Mac, where a folder is
    /// named by its path and an AI can be handed one.
    private static func place(_ location: String, folder: URL?) -> String {
        #if os(macOS)
        guard let folder else { return location }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let path = folder.standardizedFileURL.path
        let shown = path.hasPrefix(home) ? "~" + String(path.dropFirst(home.count)) : path
        return "\(location) at \(shown)"
        #else
        return location
        #endif
    }
}

/// The owner's own AI as the way in. On the phone: three steps through the server, because
/// an AI on a phone cannot reach the folder. On the Mac: the folder prompt for an AI that
/// can, and the hosted door for one that cannot.
struct OwnAIHelp: View {
    let model: DashboardModel
    @ObservedObject var auth: AuthViewModel
    var context: SetupPrompt.Context = .setup
    /// In setup, the way on to the dashboard once the AI has been handed its prompt.
    var onFinish: (() -> Void)? = nil

    @State private var copied: String?
    @State private var connecting = false
    @State private var enabling = false
    @State private var problem: String?
    /// The connector step, ticked by hand: the app cannot see inside Claude.
    @State private var markedURL = false
    /// The full account-copy terms, opened under their one-line summary.
    @State private var showingTerms = false

    var body: some View {
        VStack(alignment: .leading, spacing: LBSpacing.s3) {
            #if os(iOS)
            phoneSteps
            #else
            Text("Your AI reads your statements, asks you a few questions, and fills the folder in. It lands in Changes, where you keep or undo it.")
                .lbText(.footnote)
                .foregroundStyle(LBColor.textTertiary.color)
                .fixedSize(horizontal: false, vertical: true)
            promptCard(SetupPrompt.prompt(for: model, context: context), named: promptName)
            connectCard
            #endif
            if context == .setup, let onFinish {
                Button(action: onFinish) {
                    Text("Go to My Dashboard")
                        .lbText(.body)
                        .foregroundStyle(LBColor.onBrand.color)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, LBSpacing.s3)
                        .background(LBColor.brand.color, in: RoundedRectangle(cornerRadius: LBRadius.sm, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        // Outside any navigation stack, so the MCP screen is reached as a sheet with its own way back.
        .sheet(isPresented: $connecting) {
            NavigationStack {
                MCPServerView(model: model, auth: auth)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { connecting = false }
                        }
                    }
            }
            #if os(macOS)
            .frame(minWidth: 560, minHeight: 520)
            #endif
            .lbClosesOnOutsideClick { connecting = false }
        }
    }

    // MARK: the phone's three steps

    private var phoneSteps: some View {
        VStack(alignment: .leading, spacing: LBSpacing.s3) {
            step(1, "Let your AI read your longbook") {
                if model.hostedPush {
                    HStack(spacing: LBSpacing.s1) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Enabled")
                            .lbText(.label)
                    }
                    .foregroundStyle(LBColor.brandText.color)
                } else {
                    Button {
                        enable()
                    } label: {
                        Text(enabling ? "Enabling…" : "Enable")
                            .lbText(.label)
                            .foregroundStyle(LBColor.onBrand.color)
                            .padding(.horizontal, LBSpacing.s3)
                            .frame(minHeight: 32)
                            .background(LBColor.brand.color, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(enabling || !auth.isSignedIn)
                }
                // The short line, and every fact of the full one a tap away under Learn More.
                Text("A copy stays with your account while this is on.")
                    .lbText(.footnote)
                    .foregroundStyle(LBColor.textTertiary.color)
                    .fixedSize(horizontal: false, vertical: true)
                if showingTerms {
                    Text("A copy of your memory file is stored with your account so your AI can read it. It is replaced when you save, and deleted when you turn this off or after 90 days without the app.")
                        .lbText(.footnote)
                        .foregroundStyle(LBColor.textTertiary.color)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Button("Learn More") { withAnimation(.easeOut(duration: 0.2)) { showingTerms = true } }
                        .lbText(.footnote)
                        .foregroundStyle(LBColor.brandText.color)
                        .buttonStyle(.plain)
                }
                if let problem {
                    Text(problem)
                        .lbText(.footnote)
                        .foregroundStyle(LBColor.urgent.color)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            gated(model.hostedPush) {
                step(2, "In Claude, add the connector") {
                    Text("Connectors › Add custom connector. Name: longbook. URL: longbook.app/mcp")
                        .lbText(.footnote)
                        .foregroundStyle(LBColor.textSecondary.color)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: LBSpacing.s4) {
                        copyLine("https://longbook.app/mcp", label: "Copy URL")
                        markDone
                    }
                }
            }
            gated(model.hostedPush && markedURL) {
                step(3, "Paste this prompt in Claude, with your statements attached") {
                    promptCard(SetupPrompt.connectorPrompt(context), named: promptName)
                }
            }
            if let waiting = lockedCaption {
                Text(waiting)
                    .lbText(.footnote)
                    .foregroundStyle(LBColor.textSecondary.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("On iPhone, only Claude can connect.")
                .lbText(.footnote)
                .foregroundStyle(LBColor.textTertiary.color)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onAppear { model.rereadHostedPush() }
        // An AI already signed in means the connector was added on an earlier visit.
        .task(id: model.hostedPush) {
            guard model.hostedPush, !markedURL, auth.isSignedIn else { return }
            if !(await HostedMemory.grants()).isEmpty { markedURL = true }
        }
    }

    /// One step as its own card: the number, a mark for what it does, the words, and
    /// the one control it needs, readable at a glance.
    private func step<Content: View>(_ number: Int, _ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        let symbol = ["icloud.and.arrow.up", "link", "text.quote"][min(max(number - 1, 0), 2)]
        return HStack(alignment: .top, spacing: LBSpacing.s3) {
            Text("\(number)")
                .lbText(.label)
                .foregroundStyle(LBColor.onBrand.color)
                .frame(width: 24, height: 24)
                .background(LBColor.brand.color, in: Circle())
                .accessibilityHidden(true)
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(LBColor.brandText.color)
                .frame(width: 44, height: 44)
                .background(LBColor.sunken.color, in: RoundedRectangle(cornerRadius: LBRadius.sm, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: LBSpacing.s2) {
                Text(title)
                    .lbText(.body)
                    .foregroundStyle(LBColor.textPrimary.color)
                    .fixedSize(horizontal: false, vertical: true)
                content()
            }
            Spacer(minLength: 0)
        }
        .padding(LBSpacing.s3)
        .background(LBColor.card.color, in: RoundedRectangle(cornerRadius: LBRadius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: LBRadius.md, style: .continuous)
                .strokeBorder(LBColor.hairline.color, lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Step \(number): \(title)")
    }

    /// A step that waits on the one before: dimmed and inert, its words left readable. One
    /// caption under the steps says what opens them.
    private func gated<Content: View>(_ open: Bool, @ViewBuilder _ content: () -> Content) -> some View {
        content()
            .opacity(open ? 1 : 0.45)
            .disabled(!open)
            .allowsHitTesting(open)
            .animation(.easeOut(duration: 0.2), value: open)
    }

    /// What the dimmed steps wait for, or nil once every step is open.
    private var lockedCaption: String? {
        if !model.hostedPush { return "Steps 2 and 3 open once step 1 is on." }
        if !markedURL { return "Step 3 opens once step 2 is marked done." }
        return nil
    }

    /// The prompt's name, so the first-run prompt and the later ones read as two on purpose.
    private var promptName: String {
        switch context {
        case .setup: "Set-up prompt"
        case .reports: "Update prompt"
        case .month: "Month prompt"
        }
    }

    /// The tick for the connector step, since the app cannot see it done.
    private var markDone: some View {
        Button {
            withAnimation(.easeOut(duration: 0.2)) { markedURL.toggle() }
            LBHaptics.tap()
        } label: {
            HStack(spacing: LBSpacing.s1) {
                Image(systemName: markedURL ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 11, weight: .medium))
                Text(markedURL ? "Done" : "Mark Done")
                    .lbText(.label)
            }
            .foregroundStyle(LBColor.brandText.color)
            .frame(minHeight: 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(markedURL ? "Connector added" : "Mark the connector as added")
    }

    /// Turns on hosted push and web proposals together, as the MCP screen's switch and box do.
    private func enable() {
        enabling = true
        problem = nil
        Task {
            if let message = await model.setHostedPush(true) {
                problem = message
            } else if let message = await HostedMemory.setWebPropose(true) {
                problem = message
            }
            enabling = false
        }
    }

    // MARK: pieces

    private func promptCard(_ prompt: String, named name: String) -> some View {
        LBCard {
            VStack(alignment: .leading, spacing: LBSpacing.s3) {
                Text(name)
                    .lbText(.footnote)
                    .foregroundStyle(LBColor.brandText.color)
                Text(prompt)
                    .lbText(.body)
                    .foregroundStyle(LBColor.textPrimary.color)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    copy(prompt)
                } label: {
                    HStack(spacing: LBSpacing.s2) {
                        Image(systemName: copied == prompt ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 12, weight: .semibold))
                        Text(copied == prompt ? "Copied. Paste it to your AI." : "Copy Prompt")
                            .lbText(.label)
                    }
                    .foregroundStyle(LBColor.onBrand.color)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, LBSpacing.s3)
                    .background(LBColor.brand.color, in: RoundedRectangle(cornerRadius: LBRadius.sm, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func copyLine(_ value: String, label: String) -> some View {
        Button {
            copy(value)
        } label: {
            HStack(spacing: LBSpacing.s1) {
                Image(systemName: copied == value ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 11, weight: .medium))
                Text(copied == value ? "Copied" : label)
                    .lbText(.label)
            }
            .foregroundStyle(LBColor.brandText.color)
            .frame(minHeight: 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// For an AI that cannot write into the folder — one that lives in a browser — the
    /// hosted door is the other way in.
    private var connectCard: some View {
        Button { connecting = true } label: {
            HStack(spacing: LBSpacing.s2) {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(LBColor.brandText.color)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Connect your AI")
                        .lbText(.label)
                        .foregroundStyle(LBColor.textPrimary.color)
                    Text("For an AI that cannot reach this folder — connect it to longbook’s server instead.")
                        .lbText(.footnote)
                        .foregroundStyle(LBColor.textTertiary.color)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: LBSpacing.s2)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(LBColor.textTertiary.color)
            }
            .padding(LBSpacing.s3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(LBColor.card.color, in: RoundedRectangle(cornerRadius: LBRadius.sm, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func copy(_ value: String) {
        #if os(iOS)
        UIPasteboard.general.string = value
        #else
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
        #endif
        copied = value
        LBHaptics.tap()
    }
}
