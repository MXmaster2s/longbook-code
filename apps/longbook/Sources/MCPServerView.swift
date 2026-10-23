import DesignSystem
import LongbookCore
import SwiftUI
#if os(macOS)
import AppKit
#endif

/// The MCP server screen: one switch, the address an AI agent visits, whether it may
/// write, who is connected, and the keys for tools that cannot sign in — folded away.
struct MCPServerView: View {
    let model: DashboardModel
    @ObservedObject var auth: AuthViewModel
    /// Inside Automations: the panels alone, no title and no scroll of its own.
    var embedded = false

    @State private var enabled = false
    @State private var confirmingEnable = false
    @State private var busy = false
    @State private var error: String?
    @State private var pushedAt: Date?
    @State private var copied = false
    @State private var grants: [HostedMemory.AIGrant] = []
    @State private var disconnecting: String?
    @State private var keys: [HostedMemory.AccessKey] = []
    @State private var newKeyName = ""
    @State private var newKeyScope: HostedMemory.KeyScope = .read
    @State private var freshKey: String?
    @State private var keyBusy = false
    @State private var webPropose = false
    @State private var webProposeBusy = false
    @State private var keychainWord: String?
    @State private var freshKeyName = "access key"
    @State private var macSetupWord: String?
    @State private var claudeConfigured = false
    @State private var showingKeys = false
    @State private var showingConfig = false
    /// The harness pictures the enabled screen without a session.
    @State private var staged = false
    /// The Cloud door, opened when the switch or a key asks for the server without it.
    @State private var paywall = false

    private var signedIn: Bool { auth.isSignedIn || staged }

    var body: some View {
        Group {
            if embedded {
                panels
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: LBSpacing.s4) {
                        LBPageTitle("MCP server")
                        panels
                    }
                    .padding(LBSpacing.s4)
                    #if os(macOS)
                    .padding(.top, LBSpacing.s6)
                    #endif
                    .frame(maxWidth: 700)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(LBColor.canvas.color)
                .lbScreenTitle("MCP server")
            }
        }
        .onAppear {
            enabled = model.hostedPush
            #if os(macOS)
            refreshClaudeConfigured()
            #endif
            #if DEBUG
            if let mode = ProcessInfo.processInfo.environment["LONGBOOK_SNAPSHOT_MCP"] {
                staged = true
                enabled = true
                webPropose = true
                pushedAt = Date()
                confirmingEnable = mode == "confirm"
                return
            }
            #endif
            guard auth.isSignedIn else { return }
            Task { pushedAt = await HostedMemory.pushedAt() }
            Task { webPropose = await HostedMemory.webProposeAllowed() }
            Task { grants = await HostedMemory.grants() }
            Task { keys = await HostedMemory.accessKeys() }
        }
        .cloudPaywall(isPresented: $paywall, auth: auth)
    }

    /// Every panel, in order — the same set whether the screen stands alone or sits
    /// inside Automations.
    @ViewBuilder
    private var panels: some View {
                if signedIn {
                    serverPanel
                    if enabled && !confirmingEnable { readyPanel }
                    if enabled && !confirmingEnable { writePanel }
                    if !grants.isEmpty { connectedPanel }
                    if enabled { otherTools }
                    #if os(macOS)
                    connectMacPanel
                    #endif
                } else {
                    LBPanel {
                        Text("Sign in first. Your account is what your AI signs in with.")
                            .lbText(.footnote)
                            .foregroundStyle(LBColor.textTertiary.color)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
    }

    private var serverPanel: some View {
        LBPanel {
            VStack(alignment: .leading, spacing: LBSpacing.s3) {
                switchRow("Let AI Read My longbook", detail: statusWord, isOn: $enabled)
                    .disabled(busy)
                    .onChange(of: enabled) { _, wanted in
                        guard !staged, wanted != model.hostedPush, !busy else { return }
                        // The hosted copy is a Cloud feature: without it the switch stays off
                        // and the door to Cloud opens instead of the confirmation.
                        if wanted, !model.hasCloud { enabled = false; paywall = true; return }
                        if wanted { confirmingEnable = true } else { confirmingEnable = false; Task { await apply(false) } }
                    }
                // Enabling is a decision: what it lets an agent do is said once, here,
                // before anything is hosted, and the switch waits on the answer.
                if confirmingEnable {
                    VStack(alignment: .leading, spacing: LBSpacing.s3) {
                        Text("Your AI agents — ChatGPT or Claude — will be able to read and write your longbook. What they write waits in Changes for you to keep or undo.")
                            .lbText(.bodySM)
                            .foregroundStyle(LBColor.textSecondary.color)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("A copy of your memory file is stored with your account so your AI can read it. It is replaced when you save, and deleted when you turn this off or after 90 days without the app.")
                            .lbText(.footnote)
                            .foregroundStyle(LBColor.textTertiary.color)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: LBSpacing.s3) {
                            Button {
                                confirmingEnable = false
                                Task { await apply(true) }
                            } label: {
                                Text("Enable")
                                    .lbText(.label)
                                    .foregroundStyle(LBColor.onBrand.color)
                                    .padding(.horizontal, LBSpacing.s4)
                                    .frame(minHeight: 34)
                                    .background(LBColor.brand.color, in: Capsule())
                            }
                            .buttonStyle(.plain)
                            Button {
                                confirmingEnable = false
                                enabled = false
                            } label: {
                                Text("Not Now")
                                    .lbText(.label)
                                    .foregroundStyle(LBColor.textSecondary.color)
                                    .padding(.horizontal, LBSpacing.s3)
                                    .frame(minHeight: 34)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(LBSpacing.s3)
                    .background(LBColor.brand.color.opacity(0.10), in: RoundedRectangle(cornerRadius: LBRadius.sm, style: .continuous))
                }
                if let error {
                    Text(error)
                        .lbText(.footnote)
                        .foregroundStyle(LBColor.urgent.color)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !enabled || confirmingEnable {
                    Text("Off. Nothing is hosted. Turning it off later deletes the hosted copy.")
                        .lbText(.footnote)
                        .foregroundStyle(LBColor.textTertiary.color)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if model.hostedPush, !model.hasCloud, !staged { lapsedNote }
            }
        }
    }

    /// The switch is on but Cloud has ended: the copy stands as it was, unrefreshed, until
    /// the server removes it or a subscription brings it back.
    private var lapsedNote: some View {
        VStack(alignment: .leading, spacing: LBSpacing.s2) {
            Text("longbook Cloud has ended, so the hosted copy is no longer refreshed. It is deleted 30 days after Cloud ends unless the server is switched off first.")
                .lbText(.footnote)
                .foregroundStyle(LBColor.urgent.color)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                paywall = true
            } label: {
                Text("Subscribe to longbook Cloud")
                    .lbText(.label)
                    .foregroundStyle(LBColor.onBrand.color)
                    .padding(.horizontal, LBSpacing.s4)
                    .frame(minHeight: 34)
                    .background(LBColor.brand.color, in: Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    /// The one thing to tell an agent, once the switch is on.
    private var readyPanel: some View {
        LBPanel {
            VStack(alignment: .leading, spacing: LBSpacing.s3) {
                Text("Ask ChatGPT or Claude to visit longbook.app/mcp.")
                    .lbText(.body)
                    .foregroundStyle(LBColor.textPrimary.color)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: LBSpacing.s2) {
                    Text(HostedMemory.endpoint.absoluteString)
                        .lbText(.footnote)
                        .foregroundStyle(LBColor.textPrimary.color)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: LBSpacing.s2)
                    Button {
                        copy(Self.connectPrompt)
                    } label: {
                        HStack(spacing: LBSpacing.s1) {
                            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                                .font(.system(size: 11, weight: .medium))
                            Text(copied ? "Copied" : "Copy Prompt")
                                .lbText(.label)
                        }
                        .foregroundStyle(LBColor.brandText.color)
                        .frame(minHeight: 34)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Copy a ready prompt with the address")
                }
            }
        }
    }

    /// What one paste hands another AI: the address wrapped in its own instructions.
    static let connectPrompt = """
    I am giving you an MCP server. Please help me connect it step by step: \
    https://longbook.app/mcp. It is my longbook financial memory. \
    If your app supports MCP connectors or custom servers, add it there. Sign-in will \
    open in my browser.
    """

    /// Whether a signed-in agent may write. On from the moment the server is enabled;
    /// off, an agent reads and nothing more. Enforced by the server, not by hiding tools.
    private var writePanel: some View {
        LBPanel {
            switchRow("Allow suggested changes", detail: "You review them in Changes.",
                      isOn: Binding(get: { webPropose }, set: { _ in toggleWrite() }))
                .disabled(webProposeBusy)
        }
    }

    /// A title over its detail with the switch at the trailing edge, the same on both platforms:
    /// the Mac would otherwise seat the switch right after the words.
    private func switchRow(_ title: String, detail: String, isOn: Binding<Bool>) -> some View {
        HStack(alignment: .center, spacing: LBSpacing.s3) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .lbText(.body)
                    .foregroundStyle(LBColor.textPrimary.color)
                Text(detail)
                    .lbText(.footnote)
                    .foregroundStyle(LBColor.textTertiary.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: LBSpacing.s2)
            Toggle(title, isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(LBColor.brand.color)
        }
        .accessibilityElement(children: .combine)
    }

    private func toggleWrite() {
        guard !webProposeBusy else { return }
        let wanted = !webPropose
        webProposeBusy = true
        Task {
            if let message = await HostedMemory.setWebPropose(wanted) {
                error = message
            } else {
                webPropose = wanted
            }
            webProposeBusy = false
        }
    }

    /// Who is connected right now — each one removable without touching the hosted copy.
    private var connectedPanel: some View {
        VStack(alignment: .leading, spacing: LBSpacing.s2) {
            Text("Connected")
                .lbText(.label)
                .foregroundStyle(LBColor.textPrimary.color)
            LBPanel {
                VStack(alignment: .leading, spacing: LBSpacing.s3) {
                    ForEach(grants) { grant in
                        HStack(spacing: LBSpacing.s2) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(grant.name)
                                    .lbText(.bodySM)
                                    .foregroundStyle(LBColor.textPrimary.color)
                                if let granted = grant.grantedAt {
                                    Text("Connected \(LB.shortDate(granted))")
                                        .lbText(.footnote)
                                        .foregroundStyle(LBColor.textTertiary.color)
                                }
                            }
                            Spacer(minLength: LBSpacing.s2)
                            DangerButton(
                                title: disconnecting == grant.clientId ? "Removing…" : "Disconnect",
                                question: "Disconnect \(grant.name)?",
                                detail: "It will ask for your permission again next time.",
                                confirmLabel: "Disconnect"
                            ) {
                                disconnecting = grant.clientId
                                Task {
                                    if let message = await HostedMemory.revokeGrant(clientId: grant.clientId) {
                                        error = message
                                    } else {
                                        grants = await HostedMemory.grants()
                                    }
                                    disconnecting = nil
                                }
                            }
                            .disabled(disconnecting != nil)
                            .accessibilityLabel("Disconnect \(grant.name)")
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }

    /// The keys, folded away: a tool that cannot open a browser is the rare case.
    private var otherTools: some View {
        VStack(alignment: .leading, spacing: LBSpacing.s2) {
            Button {
                withAnimation(.easeOut(duration: 0.2)) { showingKeys.toggle() }
            } label: {
                HStack(spacing: LBSpacing.s1) {
                    Text("Access keys")
                        .lbText(.label)
                        .foregroundStyle(LBColor.textPrimary.color)
                    Image(systemName: showingKeys ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(LBColor.textTertiary.color)
                    Spacer(minLength: 0)
                }
                .frame(minHeight: 32)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(showingKeys ? "Hides the access keys" : "Shows the access keys, for tools that cannot sign in")
            if showingKeys { accessKeysPanel }
        }
    }

    /// Keys are the fallback for AI tools that cannot open a browser to sign in.
    /// Each is shown once; the server keeps only its hash.
    private var accessKeysPanel: some View {
        VStack(alignment: .leading, spacing: LBSpacing.s2) {
            LBPanel {
                VStack(alignment: .leading, spacing: LBSpacing.s3) {
                    Text("Access keys, for a tool that cannot open a browser to sign in — a morning brief, a scheduled agent. Treat a key like a password.")
                        .lbText(.footnote)
                        .foregroundStyle(LBColor.textTertiary.color)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Keys stay valid until revoked, even with the server off.")
                        .lbText(.footnote)
                        .foregroundStyle(LBColor.textTertiary.color)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: LBSpacing.s2) {
                        TextField("", text: $newKeyName, prompt: Text("Name this key").foregroundStyle(LBColor.textTertiary.color))
                            .textFieldStyle(.plain)
                            .lbText(.bodySM)
                            .foregroundStyle(LBColor.textPrimary.color)
                            .padding(.horizontal, LBSpacing.s3)
                            .frame(minHeight: 34)
                            .background(LBColor.chrome.color, in: RoundedRectangle(cornerRadius: LBRadius.xs, style: .continuous))
                        Button {
                            createKey()
                        } label: {
                            Text(keyBusy ? "Creating…" : "Create")
                                .lbText(.label)
                                .foregroundStyle(LBColor.onBrand.color)
                                .padding(.horizontal, LBSpacing.s3)
                                .frame(minHeight: 34)
                                .background(LBColor.brand.color, in: Capsule())
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .disabled(keyBusy || newKeyName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    // What the key may do, in words rather than scope names. Nothing here
                    // can rewrite the memory: a suggestion waits for the owner in Changes.
                    VStack(alignment: .leading, spacing: LBSpacing.s1) {
                        HStack(spacing: LBSpacing.s2) {
                            ForEach(HostedMemory.KeyScope.allCases, id: \.self) { scope in
                                Button {
                                    newKeyScope = scope
                                } label: {
                                    Text(scope.label)
                                        .lbText(.label)
                                        .foregroundStyle(newKeyScope == scope ? LBColor.onBrand.color : LBColor.textSecondary.color)
                                        .padding(.horizontal, LBSpacing.s3)
                                        .frame(minHeight: 28)
                                        .background(
                                            newKeyScope == scope ? LBColor.brand.color : LBColor.chrome.color,
                                            in: Capsule()
                                        )
                                        .contentShape(Capsule())
                                }
                                .buttonStyle(.plain)
                                .accessibilityAddTraits(newKeyScope == scope ? [.isSelected] : [])
                            }
                        }
                        Text(newKeyScope.explanation)
                            .lbText(.footnote)
                            .foregroundStyle(LBColor.textTertiary.color)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let freshKey {
                        VStack(alignment: .leading, spacing: LBSpacing.s1) {
                            Text("This is the only time this key is shown.")
                                .lbText(.footnote)
                                .foregroundStyle(LBColor.urgent.color)
                            HStack(spacing: LBSpacing.s2) {
                                Text(freshKey)
                                    .lbText(.footnote)
                                    .foregroundStyle(LBColor.textPrimary.color)
                                    .textSelection(.enabled)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Spacer(minLength: LBSpacing.s2)
                                Button {
                                    copy(freshKey)
                                } label: {
                                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(LBColor.brandText.color)
                                        .frame(width: 44, height: 44)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Copy the new key")
                            }
                            .padding(.horizontal, LBSpacing.s3)
                            .background(LBColor.chrome.color, in: RoundedRectangle(cornerRadius: LBRadius.xs, style: .continuous))
                            #if os(macOS)
                            Button {
                                keychainWord = KeyKeychain.save(freshKey, named: freshKeyName)
                            } label: {
                                Text("Save to Keychain")
                                    .lbText(.label)
                                    .foregroundStyle(LBColor.textSecondary.color)
                                    .padding(.horizontal, LBSpacing.s3)
                                    .frame(minHeight: 28)
                                    .background(LBColor.chrome.color, in: Capsule())
                                    .contentShape(Capsule())
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint("Stores the key in this Mac’s keychain so an agent can read it without a file.")
                            if let keychainWord {
                                Text(keychainWord)
                                    .lbText(.footnote)
                                    .foregroundStyle(LBColor.textTertiary.color)
                                    .textSelection(.enabled)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            #endif
                        }
                    }
                    ForEach(keys) { key in
                        HStack(spacing: LBSpacing.s2) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(key.name)
                                    .lbText(.bodySM)
                                    .foregroundStyle(LBColor.textPrimary.color)
                                Text(keyMeta(key))
                                    .lbText(.footnote)
                                    .foregroundStyle(LBColor.textTertiary.color)
                            }
                            Spacer(minLength: LBSpacing.s2)
                            DangerButton(
                                title: "Revoke",
                                question: "Revoke '\(key.name)'?",
                                detail: "Anything connecting with this key loses access immediately.",
                                confirmLabel: "Revoke"
                            ) {
                                Task {
                                    if await HostedMemory.revokeAccessKey(id: key.id) {
                                        keys = await HostedMemory.accessKeys()
                                    }
                                }
                            }
                            .accessibilityLabel("Revoke \(key.name)")
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }

    private func keyMeta(_ key: HostedMemory.AccessKey) -> String {
        let created = key.createdAt.map { "Created \(LB.shortDate($0))" } ?? "Created"
        let used = key.lastUsedAt.map { "last used \(LB.shortDate($0))" } ?? "never used"
        let expiry = key.expiresAt.map { " · expires \(LB.shortDate($0))" } ?? ""
        return "\(key.scope.label) · \(created) · \(used)\(expiry)"
    }

    private func createKey() {
        let name = newKeyName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        // A key opens the hosted door, which is Cloud's; the server refuses one without it.
        guard model.hasCloud else { paywall = true; return }
        keyBusy = true
        Task {
            freshKey = await HostedMemory.createAccessKey(name: name, scope: newKeyScope)
            if freshKey != nil {
                freshKeyName = name
                keychainWord = nil
                newKeyName = ""
                keys = await HostedMemory.accessKeys()
            } else {
                error = "The key could not be created. Try again."
            }
            keyBusy = false
        }
    }

    #if os(macOS)
    /// The local door: Claude Desktop reads the folder directly through the server
    /// this app ships — no cloud in between, and no key needed on the same machine.
    private var connectMacPanel: some View {
        VStack(alignment: .leading, spacing: LBSpacing.s2) {
            LBSectionHeader("On this Mac")
            LBPanel {
                VStack(alignment: .leading, spacing: LBSpacing.s3) {
                    Text("Claude Desktop reads your longbook directly on this Mac, with no hosted copy. What Claude reads goes to Anthropic as part of the conversation.")
                        .lbText(.footnote)
                        .foregroundStyle(LBColor.textSecondary.color)
                        .fixedSize(horizontal: false, vertical: true)
                    if claudeConfigured {
                        HStack(spacing: LBSpacing.s2) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(LBColor.brandText.color)
                            Text("Claude Desktop is set up. Restart it and longbook appears in its tools.")
                                .lbText(.footnote)
                                .foregroundStyle(LBColor.textSecondary.color)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    HStack(spacing: LBSpacing.s2) {
                        Button {
                            macSetupWord = writeClaudeDesktopConfig()
                            refreshClaudeConfigured()
                            if claudeConfigured { macSetupWord = nil }
                            // A setup that could not finish points at the configuration to copy.
                            if macSetupWord != nil { showingConfig = true }
                        } label: {
                            Text(claudeConfigured ? "Set Up Again" : "Set Up Claude Desktop")
                                .lbText(.label)
                                .foregroundStyle(claudeConfigured ? LBColor.textSecondary.color : LBColor.onBrand.color)
                                .padding(.horizontal, LBSpacing.s3)
                                .frame(minHeight: 34)
                                .background(claudeConfigured ? LBColor.chrome.color : LBColor.brand.color, in: Capsule())
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                    Link(destination: Self.desktopHelp) {
                        Text("How Claude Desktop connects")
                            .lbText(.footnote)
                            .foregroundStyle(LBColor.brandText.color)
                    }
                    // For any other local MCP client: the configuration to paste, folded away.
                    Button {
                        withAnimation(.easeOut(duration: 0.2)) { showingConfig.toggle() }
                    } label: {
                        HStack(spacing: LBSpacing.s1) {
                            Text("Advanced")
                                .lbText(.label)
                                .foregroundStyle(LBColor.textSecondary.color)
                            Image(systemName: showingConfig ? "chevron.up" : "chevron.down")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(LBColor.textTertiary.color)
                        }
                        .frame(minHeight: 28)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if showingConfig {
                        Button {
                            if let json = localConfigJSON() { copy(json) }
                        } label: {
                            Text(copied ? "Copied" : "Copy Configuration")
                                .lbText(.label)
                                .foregroundStyle(LBColor.textSecondary.color)
                                .padding(.horizontal, LBSpacing.s3)
                                .frame(minHeight: 34)
                                .background(LBColor.chrome.color, in: Capsule())
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Copies the MCP config for any other local client.")
                    }
                    if let macSetupWord {
                        Text(macSetupWord)
                            .lbText(.footnote)
                            .foregroundStyle(LBColor.textTertiary.color)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    /// The steps and the details, on the site, so the panel keeps to what to press.
    private static let desktopHelp = URL(string: "https://longbook.app/features/automate-longbook-with-claude/")!

    /// Where node actually is on this Mac. Three fixed paths missed every version
    /// manager — nvm, fnm, volta, asdf, mise all put it under the home folder — so the
    /// login shell is asked first, and the known locations are the fallback.
    private func nodePath() -> String? {
        if let found = nodeFromLoginShell(), FileManager.default.isExecutableFile(atPath: found) { return found }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = [
            "/opt/homebrew/bin/node", "/usr/local/bin/node", "/usr/bin/node",
            "\(home)/.volta/bin/node", "\(home)/.local/share/mise/shims/node",
            "\(home)/.asdf/shims/node", "\(home)/.bun/bin/node",
        ]
        if let fixed = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) { return fixed }
        // nvm and fnm keep a version per folder; the newest installed one is the answer.
        for base in ["\(home)/.nvm/versions/node", "\(home)/.local/state/fnm_multishells", "\(home)/Library/Application Support/fnm/node-versions"] {
            let versions = (try? FileManager.default.contentsOfDirectory(atPath: base)) ?? []
            for version in versions.sorted(by: >) {
                let path = "\(base)/\(version)/bin/node"
                if FileManager.default.isExecutableFile(atPath: path) { return path }
            }
        }
        return nil
    }

    /// The login shell knows about version managers because the owner's profile set them
    /// up. Asked once, with a short leash: a shell that hangs must not hang this window.
    private func nodeFromLoginShell() -> String? {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let task = Process()
        task.executableURL = URL(fileURLWithPath: shell)
        task.arguments = ["-lic", "command -v node"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        do { try task.run() } catch { return nil }
        let deadline = Date().addingTimeInterval(3)
        while task.isRunning && Date() < deadline { usleep(50_000) }
        if task.isRunning {
            task.terminate()
            return nil
        }
        let bytes = pipe.fileHandleForReading.readDataToEndOfFile()
        let path = String(decoding: bytes, as: UTF8.self)
            .split(separator: "\n").last.map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (path?.hasPrefix("/") == true) ? path : nil
    }

    /// macOS runs an app opened from a disk image or Downloads out of a hidden read-only
    /// copy, and the path it reports then belongs to nothing the owner can find. A config
    /// written from there points at a path that vanishes.
    private var isTranslocated: Bool {
        Bundle.main.bundleURL.path.contains("/AppTranslocation/")
    }

    private func serverPieces() -> (node: String, server: String, vault: String)? {
        guard let server = Bundle.main.url(forResource: "longbook-mcp", withExtension: "mjs"),
              let vault = model.vaultFolderURL?.path,
              let node = nodePath()
        else { return nil }
        return (node, server.path, vault)
    }

    private func localConfigJSON() -> String? {
        guard let pieces = serverPieces() else { return nil }
        return """
        {
          "mcpServers": {
            "longbook": {
              "command": "\(pieces.node)",
              "args": ["\(pieces.server)", "--vault", "\(pieces.vault)"]
            }
          }
        }
        """
    }

    /// Claude Desktop's own folder, outside this app's sandbox. The first setup asks for
    /// it once through the system's panel; the grant is kept as a security-scoped bookmark
    /// so later reads and writes need no second asking.
    private static let claudeBookmarkKey = "longbook.claudeFolderBookmark"

    private static var claudeFolder: URL? {
        guard let data = UserDefaults.standard.data(forKey: claudeBookmarkKey) else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: [.withSecurityScope], bookmarkDataIsStale: &stale),
              !stale else { return nil }
        return url
    }

    /// The panel opens on the folder Claude Desktop keeps its configuration in; the reader
    /// only confirms it. Anything else chosen is refused rather than written into.
    private static func askForClaudeFolder() -> URL? {
        let expected = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Claude")
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = expected
        panel.message = "Choose Claude Desktop’s folder (Library › Application Support › Claude) so longbook can write its configuration there."
        panel.prompt = "Use this folder"
        guard panel.runModal() == .OK, let url = panel.url, url.lastPathComponent == "Claude" else { return nil }
        if let data = try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil) {
            UserDefaults.standard.set(data, forKey: claudeBookmarkKey)
        }
        return url
    }

    /// Runs `work` inside the folder's grant when one is held; without a grant the folder
    /// is tried as it is, which a development build outside the sandbox can reach.
    private static func withClaudeFolder<T>(_ work: (URL) throws -> T) rethrows -> T {
        let fallback = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Claude")
        guard let granted = claudeFolder else { return try work(fallback) }
        let opened = granted.startAccessingSecurityScopedResource()
        defer { if opened { granted.stopAccessingSecurityScopedResource() } }
        return try work(granted)
    }

    /// Read from disk, never remembered: configured means Claude Desktop's file names
    /// this build's server and this vault, so the answer survives navigation.
    private func refreshClaudeConfigured() {
        claudeConfigured = {
            guard let pieces = serverPieces() else { return false }
            let file = Self.withClaudeFolder { $0.appendingPathComponent("claude_desktop_config.json") }
            guard let bytes = Self.withClaudeFolder({ _ in try? Data(contentsOf: file) }),
                  let root = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any],
                  let servers = root["mcpServers"] as? [String: Any],
                  let entry = servers["longbook"] as? [String: Any],
                  let args = entry["args"] as? [String]
            else { return false }
            return args.first == pieces.server && args.last == pieces.vault
        }()
    }

    /// Merges the longbook entry into Claude Desktop's own config, touching nothing
    /// else in it. The entry points at this app bundle and the open vault.
    private func writeClaudeDesktopConfig() -> String {
        guard !isTranslocated else {
            return "Move longbook to your Applications folder first, then reopen it — macOS is running this copy from a temporary place that will disappear."
        }
        guard model.vaultFolderURL != nil else { return "Open your vault first — the configuration points at it." }
        guard Bundle.main.url(forResource: "longbook-mcp", withExtension: "mjs") != nil else {
            return "This build is missing the bundled server."
        }
        guard let pieces = serverPieces() else {
            return "Node.js was not found on this Mac. Install it from nodejs.org, then try again — or use Copy configuration and point it at your own node."
        }
        // The sandbox keeps this app out of Claude Desktop's folder until the reader
        // grants it once; a first write that fails asks, then tries again with the grant.
        if let done = Self.writeConfig(pieces) { return done }
        guard Self.askForClaudeFolder() != nil else {
            return "Claude Desktop’s folder was not chosen, so nothing was written. Use Copy configuration instead."
        }
        return Self.writeConfig(pieces) ?? "The configuration could not be written."
    }

    /// One merge into Claude Desktop's file: nil when the folder could not be written.
    private static func writeConfig(_ pieces: (node: String, server: String, vault: String)) -> String? {
        withClaudeFolder { dir in
            let file = dir.appendingPathComponent("claude_desktop_config.json")
            var root: [String: Any] = [:]
            if let bytes = try? Data(contentsOf: file),
               let parsed = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any] {
                root = parsed
            }
            var servers = root["mcpServers"] as? [String: Any] ?? [:]
            servers["longbook"] = ["command": pieces.node, "args": [pieces.server, "--vault", pieces.vault]]
            root["mcpServers"] = servers
            do {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                let bytes = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
                try bytes.write(to: file, options: .atomic)
                return "Done. Restart Claude Desktop and longbook appears in its tools."
            } catch {
                return nil
            }
        }
    }
    #endif

    private var statusWord: String {
        if busy { return enabled ? "Enabling…" : "Turning off…" }
        guard model.hostedPush || staged else { return "Off" }
        guard let pushedAt else { return "On" }
        return "On. Last updated \(LB.shortDate(pushedAt))."
    }

    private func apply(_ wanted: Bool) async {
        busy = true
        error = nil
        if let message = await model.setHostedPush(wanted) {
            error = message
            enabled = model.hostedPush
        } else {
            pushedAt = wanted ? Date() : nil
            // Enabled means an agent may write, from the start; the switch below turns it off.
            if wanted, !webPropose {
                if let message = await HostedMemory.setWebPropose(true) { error = message } else { webPropose = true }
            }
        }
        busy = false
    }

    private func copy(_ value: String) {
        #if os(iOS)
        UIPasteboard.general.string = value
        #else
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
        #endif
        copied = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            copied = false
        }
    }
}
