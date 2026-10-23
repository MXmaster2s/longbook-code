import DesignSystem
import LongbookCore
import SwiftUI

/// Step 3: how the history gets in. A statement read here, or the owner's own AI through
/// the connector: two rows on the phone, two tiles side by side on the Mac. The dashboard
/// opens once the book holds enough to be one; the reader is never shown the list.
struct OnboardingFinishView: View {
    let model: DashboardModel
    @ObservedObject var auth: AuthViewModel
    let clock: OnboardingClock
    let onDone: () -> Void
    let onNotNow: () -> Void
    let onBack: () -> Void
    /// Setup reopened from More: the way out.
    var onClose: (() -> Void)? = nil
    /// The demo longbook, for a reader who wants to see one before filling theirs.
    var onDemo: (() -> Void)? = nil

    @State private var importing = false
    @State private var showingAI = false
    @State private var enabling = false
    @State private var enableError: String?
    @State private var copied: Set<String> = []

    static let claudePrompt = "Guide me to setup my longbook MCP connector in Claude. Name: longbook  MCP server URL: https://longbook.app/mcp"
    static let chatGPTPrompt = "@Plugin Creator Help me create a plugin for https://longbook.app/mcp"
    /// The catalogue's set-up phrase, the words the Automations screen and the servers use.
    static var setupPrompt: String { PromptCatalog.phrase(id: "set-up-my-longbook") }

    private var statementButtonTitle: String { model.chargeCount > 0 ? "Read Another Statement" : "Securely Upload Statement" }

    /// The AI door's name and what happens behind it, in the reader's words, not the plumbing's.
    static let aiTitle = "Continue in Claude or ChatGPT"
    static let aiDetail = "Your AI reads your statements and fills in your longbook."
    /// The promise the upload rests on, in one breath, wherever a statement is asked for.
    static let privacyLine = "No one at longbook sees your statement. It travels encrypted, is read once by an AI model, and longbook keeps none of it. Only the charges you keep are written to your longbook, in your own folder."

    var body: some View {
        VStack(spacing: 0) {
            OnboardingHeader(step: 3, clock: clock, onClose: onClose)
            ScrollView {
                VStack(spacing: LBSpacing.s4) {
                    VStack(spacing: LBSpacing.s3) {
                        Text("Complete your longbook setup")
                            .lbText(.displayLG)
                            .foregroundStyle(LBColor.textPrimary.color)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Securely, from a bank statement, or by your AI.")
                            .lbText(.bodySM)
                            .foregroundStyle(LBColor.textSecondary.color)
                    }
                    .padding(.top, LBSpacing.s4)
                    #if os(macOS)
                    HStack(alignment: .top, spacing: LBSpacing.s3) {
                        statementTile
                        aiTile
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    #else
                    optionRow(symbol: "lock.doc.fill", title: "Securely upload a bank statement", detail: "PDF, CSV or Excel · read once, kept by no one") { importing = true }
                    optionRow(symbol: "wand.and.stars", title: Self.aiTitle, detail: Self.aiDetail) { showingAI = true }
                    #endif
                    HStack(alignment: .top, spacing: LBSpacing.s2) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(LBColor.brandText.color)
                        Text(Self.privacyLine)
                            .lbText(.bodySM)
                            .foregroundStyle(LBColor.textSecondary.color)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    HStack(alignment: .top, spacing: LBSpacing.s2) {
                        Image(systemName: "calendar")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(LBColor.brandText.color)
                        Text("A year of statements gives the best start.")
                            .lbText(.bodySM)
                            .foregroundStyle(LBColor.textSecondary.color)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, LBSpacing.s2)
                }
                .padding(LBSpacing.s4)
            }
            footer
        }
        .onboardingColumn(width: OnboardingWidth.wide)
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(.upArrow) { onBack(); return .handled }
        .onKeyPress(.leftArrow) { onBack(); return .handled }
        .sheet(isPresented: $importing) {
            StatementImportView(model: model, auth: auth, context: .setup, onDone: { importing = false })
                #if os(macOS)
                .frame(minWidth: 560, minHeight: 620)
                #endif
        }
        #if os(iOS)
        .sheet(isPresented: $showingAI) { aiSheet }
        #endif
    }

    /// The import is the recommended way on, so it is the primary until the book can open;
    /// Skip is the one way past it.
    private var footer: some View {
        VStack(spacing: LBSpacing.s3) {
            Rectangle().fill(LBColor.hairline.color).frame(height: 1)
            HStack {
                if let onDemo {
                    OnboardingTextButton(title: "Show Demo", action: onDemo)
                }
                Spacer()
                OnboardingThemeButton()
                OnboardingTextButton(title: "Skip", action: onNotNow)
            }
            HStack(spacing: LBSpacing.s3) {
                #if os(macOS)
                OnboardingCancelButton(action: onClose)
                OnboardingPrimaryButton(title: "Show My longbook", enabled: model.dashboardAllowed, hint: "Add a statement, or Skip, to continue", action: onDone)
                #else
                if model.dashboardAllowed {
                    OnboardingPrimaryButton(title: "Show My longbook", action: onDone)
                } else {
                    OnboardingPrimaryButton(title: statementButtonTitle) { importing = true }
                }
                #endif
            }
        }
        .padding(.horizontal, LBSpacing.s4)
        .padding(.bottom, LBSpacing.s4)
    }

    // MARK: the phone's rows

    /// One option as a row: the whole row is the tap, and the chevron says it goes somewhere.
    private func optionRow(symbol: String, title: String, detail: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: LBSpacing.s3) {
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(LBColor.brandText.color)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .lbText(.body)
                        .fontWeight(.semibold)
                        .foregroundStyle(LBColor.textPrimary.color)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(detail)
                        .lbText(.footnote)
                        .foregroundStyle(LBColor.textTertiary.color)
                }
                Spacer(minLength: LBSpacing.s2)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(LBColor.textTertiary.color)
            }
            .padding(LBSpacing.s4)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background(LBColor.card.color, in: RoundedRectangle(cornerRadius: LBRadius.md, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: LBRadius.md, style: .continuous).strokeBorder(LBColor.hairline.color, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// The AI door's three steps on the phone, as a sheet the row opens.
    private var aiSheet: some View {
        VStack(alignment: .leading, spacing: LBSpacing.s4) {
            HStack {
                Text(Self.aiTitle)
                    .lbText(.headline)
                    .foregroundStyle(LBColor.textPrimary.color)
                Spacer()
                Button("Done") { showingAI = false }
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
        .presentationDetents([.medium, .large])
    }

    // MARK: the Mac's tiles

    private var statementTile: some View {
        // The privacy line stands once, under both tiles, as on the phone.
        tile(symbol: "lock.doc.fill", title: "Securely upload a bank statement", detail: "PDF, CSV or Excel · read once, kept by no one", action: { importing = true }) {
            if model.chargeCount > 0 {
                HStack(spacing: LBSpacing.s2) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(LBColor.brandText.color)
                    Text("\(model.chargeCount) \(model.chargeCount == 1 ? "charge" : "charges") in your longbook")
                        .lbText(.bodySM)
                        .foregroundStyle(LBColor.textPrimary.color)
                }
            }
            Spacer(minLength: 0)
            OnboardingPrimaryButton(title: statementButtonTitle) { importing = true }
        }
    }

    private var aiTile: some View {
        tile(symbol: "wand.and.stars", title: Self.aiTitle, detail: Self.aiDetail, action: nil) {
            aiSteps
        }
    }

    /// A tile is its icon, its title, and what it offers; a tap anywhere on it is its
    /// action when it has one.
    private func tile<Body: View>(symbol: String, title: String, detail: String, action: (() -> Void)?, @ViewBuilder body: () -> Body) -> some View {
        VStack(alignment: .leading, spacing: LBSpacing.s3) {
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(LBColor.brandText.color)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .lbText(.body)
                    .fontWeight(.semibold)
                    .foregroundStyle(LBColor.textPrimary.color)
                    .fixedSize(horizontal: false, vertical: true)
                Text(detail)
                    .lbText(.footnote)
                    .foregroundStyle(LBColor.textTertiary.color)
            }
            body()
        }
        .padding(LBSpacing.s4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(LBColor.card.color, in: RoundedRectangle(cornerRadius: LBRadius.md, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: LBRadius.md, style: .continuous).strokeBorder(LBColor.hairline.color, lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture { action?() }
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
        .buttonStyle(.plain)
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
