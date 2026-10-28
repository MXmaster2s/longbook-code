import DesignSystem
import LongbookCore
import SwiftUI

/// Step 3 of the way in: the first statement. One statement read here, or the owner's own AI
/// through the connector, as two buttons, so one of them is plainly enough. Once a statement
/// is kept the dashboard opens; Skip opens it as it is.
struct OnboardingFinishView: View {
    let model: DashboardModel
    @ObservedObject var auth: AuthViewModel
    let clock: OnboardingClock
    let onDone: () -> Void
    let onNotNow: () -> Void
    let onBack: () -> Void
    /// Setup reopened from Settings: the way out.
    var onClose: (() -> Void)? = nil
    /// The demo longbook, for a reader who wants to see one before filling theirs.
    var onDemo: (() -> Void)? = nil

    @State private var importing = false
    @State private var showingAI = false
    @State private var enabling = false
    @State private var enableError: String?
    @State private var copied: Set<String> = []
    /// Charges in the book when the importer opened: more after it closes means one was kept.
    @State private var chargesBefore = 0

    static let claudePrompt = "Connect longbook to this Claude. In Claude Code or Cowork, add the plugin marketplace MXmaster2s/longbook-claude-plugin and install the plugin longbook@longbook. Where plugins cannot be installed, add a custom connector named longbook with the URL https://longbook.app/mcp. Then connect it with my longbook account."
    static let chatGPTPrompt = "Plugin Creator: create a plugin named longbook, all lowercase, from my MCP server https://longbook.app/mcp. Display name: longbook. Version: the one the server reports. Website: https://longbook.app. Icon and logo: https://longbook.app/apple-touch-icon.png. Description: Your longbook of bills, subscriptions and expenses, for your AI to read and to suggest changes to. Use the server's tools and its guide, and sign in with my longbook account."
    /// The catalogue's set-up phrase, the words the Automations screen and the servers use.
    static var setupPrompt: String { PromptCatalog.phrase(id: "set-up-my-longbook") }

    static let aiTitle = "Continue in Claude or ChatGPT"
    static let aiDetail = "Your AI reads your statements and fills in your longbook."
    /// Said beside every statement upload: who reads it, and that nothing is kept.
    static let privacyLine = "No one at longbook sees your statement. It travels encrypted, is read once by an AI model, and longbook keeps none of it. Only the charges you keep are written to your longbook, in your own folder."

    var body: some View {
        OnboardingStep(dot: 2, mark: .symbol("doc.text.fill")) {
            OnboardingWords(title: "Import a statement",
                            line: "Start with your bank or card statement, and longbook finds the payments you make every month.",
                            note: "Recommended: most recent 12-month statement")
        } actions: {
            OnboardingPrimaryButton(title: "Securely Upload Statement") { chargesBefore = model.chargeCount; importing = true }
            OnboardingSecondaryButton(title: "Use My Own AI") { showingAI = true }
            HStack(spacing: LBSpacing.s2) {
                if let onDemo { OnboardingTextButton(title: "See Demo", action: onDemo).frame(maxWidth: .infinity) }
                OnboardingTextButton(title: "Skip", action: onNotNow).frame(maxWidth: .infinity)
            }
        }
        .overlay(alignment: .topTrailing) {
            if let onClose { OnboardingCloseButton(action: onClose).padding(LBSpacing.s2) }
        }
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(.upArrow) { onBack(); return .handled }
        .onKeyPress(.leftArrow) { onBack(); return .handled }
        // A statement kept opens the book: the reader never comes back to this step.
        .measured("onboarding_finish_importing", .sheet, when: importing)
        .sheet(isPresented: $importing, onDismiss: { if model.chargeCount > chargesBefore { onDone() } }) {
            StatementImportView(model: model, auth: auth, context: .setup, picksOnOpen: true, onDone: { importing = false })
                #if os(macOS)
                .frame(minWidth: 560, minHeight: 620)
                #endif
        }
        .measured("onboarding_finish_showing_ai", .sheet, when: showingAI)
        .sheet(isPresented: $showingAI) { aiSheet }
    }

    private var aiSheet: some View {
        VStack(alignment: .leading, spacing: LBSpacing.s4) {
            HStack {
                Text(Self.aiTitle)
                    .lbText(.headline)
                    .foregroundStyle(LBColor.textPrimary.color)
                Spacer()
                Button("Done") { Measure.used("done"); showingAI = false }
                    .lbText(.body)
                    .foregroundStyle(LBColor.brandText.color)
            }
            ScrollView {
                aiSteps
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(LBSpacing.s4)
        .background(LBColor.canvas.color)
        #if os(macOS)
        .frame(width: 480, height: 520)
        #else
        .presentationDetents([.medium, .large])
        #endif
    }

    // MARK: the AI door

    private var aiSteps: some View {
        VStack(alignment: .leading, spacing: LBSpacing.s3) {
            numbered(1, "Let your AI read your longbook")
            HStack(spacing: LBSpacing.s2) {
                if model.hostedPush {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(LBColor.brandText.color)
                    Text("Enabled").lbText(.bodySM).foregroundStyle(LBColor.textPrimary.color)
                } else {
                    OnboardingPill(title: enabling ? "Enabling…" : "Enable") { Task { await enable() } }
                }
            }
            .padding(.leading, LBSpacing.s6)
            if let enableError {
                Text(enableError).lbText(.footnote).foregroundStyle(LBColor.urgent.color)
                    .padding(.leading, LBSpacing.s6)
            }
            numbered(2, "Add the longbook connector on your computer")
            VStack(alignment: .leading, spacing: LBSpacing.s2) {
                copyPill("Claude", copied: "Copied prompt. Paste it in your Claude.", text: Self.claudePrompt, mark: .claude)
                copyPill("ChatGPT", copied: "Copied prompt. Paste it in your ChatGPT.", text: Self.chatGPTPrompt, mark: .chatGPT)
            }
            .padding(.leading, LBSpacing.s6)
            numbered(3, "Ask it to finish setting up your longbook.")
            copyPill("Copy Prompt", copied: "Prompt copied. Give it to your AI", text: Self.setupPrompt)
                .padding(.leading, LBSpacing.s6)
        }
    }

    private func numbered(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: LBSpacing.s2) {
            Text("\(number)")
                .lbText(.bodySM)
                .fontWeight(.semibold)
                .foregroundStyle(LBColor.brandText.color)
                .frame(width: 16, alignment: .leading)
            Text(text)
                .lbText(.bodySM)
                .foregroundStyle(LBColor.textSecondary.color)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// A pill that copies its prompt and says so in place; the AI's own mark leads it until then.
    private func copyPill(_ title: String, copied done: String, text: String, mark: AIPartner? = nil) -> some View {
        Button {
            Measure.used("copy")
            copy(text)
            withAnimation(.easeOut(duration: 0.2)) { _ = copied.insert(title) }
        } label: {
            HStack(spacing: LBSpacing.s2) {
                if let mark, !copied.contains(title) {
                    PartnerMark(partner: mark, size: 16)
                }
                Text(copied.contains(title) ? done : title)
                    .lbText(.bodySM)
                    .fontWeight(.medium)
                    .foregroundStyle(LBColor.textPrimary.color)
            }
            .padding(.horizontal, LBSpacing.s4)
            .frame(minHeight: 44)
            .background(LBColor.chrome.color, in: Capsule())
            .contentShape(Capsule())
        }
        .lbButtonStyle()
    }

    // MARK: doing

    private func enable() async {
        enabling = true
        enableError = await model.setHostedPush(true)
        if enableError == nil { _ = await HostedMemory.setWebPropose(true) }
        enabling = false
    }

    private func copy(_ text: String) {
        #if os(iOS)
        UIPasteboard.general.string = text
        #else
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
        LBHaptics.tap()
    }
}
