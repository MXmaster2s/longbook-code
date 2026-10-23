import DesignSystem
import LongbookCore
import SwiftUI

/// Everything that can write into the book without a hand on it: an AI agent through
/// the server, a scheduled agent each morning, the Shortcuts app, Siri. One screen, a
/// section each, in the words a product uses.
struct AutomationsView: View {
    let model: DashboardModel
    @ObservedObject var auth: AuthViewModel

    /// The copy button last pressed, as place plus prompt id: the daily-round prompt sits in the
    /// morning card and in the list, and only the one pressed turns to Copied.
    @State private var copied: String?
    /// The prompt groups folded the other way from their default: the first starts open.
    @State private var openGroups: Set<String> = []
    /// The prompt whose description is open beside it.
    @State private var explained: String?
    /// The Reorganise sheet.
    @State private var reorganising = false

    /// The daily-round prompt's id; its title names the morning card's copy button.
    static let morningId = "set-up-a-daily-longbook-email-round"

    /// What the owner tells their AI, once: the catalogue's daily-round phrase. The method
    /// lives at longbook.app/mcp, so it improves without a new build.
    static var morningPrompt: String { PromptCatalog.phrase(id: morningId) }

    /// One prompt as the list shows it.
    struct PromptRow {
        let id: String
        let title: String
        let phrase: String
        let result: String
        /// What the owner's AI needs besides longbook, said in a line; nil when nothing.
        let needs: String?
    }

    /// The catalogue's prompts under their group titles, each with the words to copy and what
    /// it does. A month prompt names the month in progress, so it pastes as it stands.
    static func promptSections(on date: Date = Date()) -> [(title: String, rows: [PromptRow])] {
        let month = PromptCatalog.monthName(of: date)
        return PromptCatalog.groups.compactMap { group in
            let rows = PromptCatalog.prompts(in: group).map { prompt in
                PromptRow(id: prompt.id, title: prompt.title, phrase: PromptCatalog.phrase(for: prompt, month: month),
                          result: prompt.result, needs: needsLine(prompt.needs))
            }
            return rows.isEmpty ? nil : (title: group.title, rows: rows)
        }
    }

    /// The catalogue's needs in the owner's words. An unknown need is left out, not shown raw.
    static func needsLine(_ needs: [String]?) -> String? {
        let needs = Set(needs ?? [])
        switch (needs.contains("mail"), needs.contains("scheduler")) {
        case (true, true): return "Needs a mail connector and scheduled tasks in your AI’s app"
        case (true, false): return "Needs a mail connector"
        case (false, true): return "Needs scheduled tasks in your AI’s app"
        case (false, false): return nil
        }
    }

    /// Where a copy button sits, so one prompt shown twice keeps two states.
    private enum Place: String { case morning, list }

    private static func key(_ place: Place, _ id: String) -> String { "\(place.rawValue)/\(id)" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LBSpacing.s6) {
                LBPageTitle("AI Connections")
                section("AI agents") {
                    MCPServerView(model: model, auth: auth, embedded: true)
                }
                section("Reorganise") { reorganiseCard }
                section("Claude automation") { claudeCard }
                section("Prompts for your AI") { promptsCard }
                section("Shortcuts automations") { shortcutsCard }
                section("Siri and Spotlight") { siriCard }
            }
            .lbPageColumn(.reading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LBColor.canvas.color)
        .lbScreenTitle("AI Connections")
        .sheet(isPresented: $reorganising) {
            ReorganiseView(model: model, auth: auth) { reorganising = false }
        }
    }

    /// One pass over the whole book by longbook's own AI, landing as one change in Changes.
    private var reorganiseCard: some View {
        LBPanel {
            VStack(alignment: .leading, spacing: LBSpacing.s3) {
                Text("longbook's AI reads your whole longbook and proposes it the way you'd keep it: names as you'd say them, every row categorised, people and accounts linked, doubles merged, nothing lost.")
                    .lbText(.body)
                    .foregroundStyle(LBColor.textPrimary.color)
                    .fixedSize(horizontal: false, vertical: true)
                // Beside its note on the Mac; the phone gives the button the whole width.
                AdaptiveStack(spacing: LBSpacing.s3) {
                    Button { reorganising = true } label: {
                        Text("Reorganise my longbook")
                            .lbText(.label)
                            .foregroundStyle(LBColor.onBrand.color)
                            .lineLimit(1)
                            .padding(.horizontal, LBSpacing.s4)
                            .frame(minHeight: 36)
                            .background(LBColor.brand.color, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    Text("Lands in Changes as one change.")
                        .lbText(.footnote)
                        .foregroundStyle(LBColor.textTertiary.color)
                }
            }
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: LBSpacing.s3) {
            Text(title)
                .lbText(.label)
                .foregroundStyle(LBColor.textPrimary.color)
            content()
        }
    }

    /// A scheduled task in Claude that reads the day's email and writes what it finds: one
    /// line, the prompt to copy, and the steps on the site.
    private var claudeCard: some View {
        LBPanel {
            VStack(alignment: .leading, spacing: LBSpacing.s3) {
                Text("Claude reads your email every morning and adds the charges and money in it finds.")
                    .lbText(.body)
                    .foregroundStyle(LBColor.textPrimary.color)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: LBSpacing.s3) {
                    copyButton(Self.morningPrompt, key: Self.key(.morning, Self.morningId),
                               label: "Copy Prompt", title: PromptCatalog.title(id: Self.morningId))
                    Link(destination: Self.morningHelp) {
                        Text("How to set it up")
                            .lbText(.label)
                            .foregroundStyle(LBColor.brandText.color)
                            .frame(minHeight: 34)
                    }
                }
            }
        }
    }

    /// The daily round's page on the site: the connectors it needs, when it runs, what it reads.
    private static let morningHelp = URL(string: "https://longbook.app/features/log-expenses-from-gmail/")!

    /// The Shortcuts action, on the iPhone and the Mac: it reads a bank's message into a charge.
    private var shortcutsCard: some View {
        LBPanel {
            VStack(alignment: .leading, spacing: LBSpacing.s3) {
                Text("These actions are available in the Shortcuts app:")
                    .lbText(.body)
                    .foregroundStyle(LBColor.textPrimary.color)
                    .fixedSize(horizontal: false, vertical: true)
                action("Record a charge from a message", "Hand it a bank’s message; it reads the amount, the day and the payee.")
                Text("Combine longbook actions with Messages or Mail actions to build automations on your Apple devices.")
                    .lbText(.footnote)
                    .foregroundStyle(LBColor.textTertiary.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// longbook's prompts, grouped as the catalogue groups them, each group folded but the
    /// first. A row is the words to copy; what it does shows on hover or behind its info button.
    private var promptsCard: some View {
        let sections = Self.promptSections()
        return LBPanel {
            VStack(alignment: .leading, spacing: LBSpacing.s3) {
                Text("Copy a prompt and paste it into Claude or ChatGPT with longbook connected.")
                    .lbText(.body)
                    .foregroundStyle(LBColor.textPrimary.color)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(Array(sections.enumerated()), id: \.element.title) { index, group in
                    let open = openGroups.contains(group.title) != (index == 0)
                    VStack(alignment: .leading, spacing: LBSpacing.s2) {
                        Button {
                            withAnimation(.easeOut(duration: 0.2)) {
                                if openGroups.contains(group.title) { openGroups.remove(group.title) } else { openGroups.insert(group.title) }
                            }
                        } label: {
                            HStack(spacing: LBSpacing.s2) {
                                Image(systemName: open ? "chevron.down" : "chevron.right")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(LBColor.textTertiary.color)
                                    .frame(width: 12)
                                Text(group.title)
                                    .lbText(.label)
                                    .foregroundStyle(LBColor.textSecondary.color)
                                Text("\(group.rows.count)")
                                    .lbText(.footnote)
                                    .foregroundStyle(LBColor.textTertiary.color)
                                Spacer(minLength: 0)
                            }
                            .frame(minHeight: 32)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityHint(open ? "Folds this group." : "Shows this group's prompts.")
                        if open {
                            ForEach(group.rows, id: \.id) { row in
                                promptRow(row)
                            }
                        }
                    }
                }
                Text("What your AI writes waits in Changes. A report it makes appears in Reports.")
                    .lbText(.footnote)
                    .foregroundStyle(LBColor.textTertiary.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func promptRow(_ row: PromptRow) -> some View {
        HStack(alignment: .center, spacing: LBSpacing.s2) {
            Image(systemName: "quote.opening")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(LBColor.brandText.color)
                .accessibilityHidden(true)
            Text(row.phrase)
                .lbText(.bodySM)
                .foregroundStyle(LBColor.textPrimary.color)
                .fixedSize(horizontal: false, vertical: true)
                .help(about(row))
                .accessibilityHint(about(row))
            Spacer(minLength: LBSpacing.s2)
            Button {
                explained = explained == row.id ? nil : row.id
            } label: {
                Image(systemName: "info.circle")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(LBColor.textTertiary.color)
                    .frame(width: 28, height: 34)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("What this prompt does")
            .popover(isPresented: Binding(get: { explained == row.id }, set: { if !$0 { explained = nil } })) {
                Text(about(row))
                    .lbText(.bodySM)
                    .foregroundStyle(LBColor.textSecondary.color)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(LBSpacing.s4)
                    .frame(width: 300, alignment: .leading)
                    .presentationCompactAdaptation(.popover)
            }
            copyGlyph(row.phrase, key: Self.key(.list, row.id), title: row.title)
        }
    }

    /// What a prompt does, and what it needs besides longbook.
    private func about(_ row: PromptRow) -> String {
        [row.result, row.needs.map { "\($0)." }].compactMap { $0 }.joined(separator: " ")
    }

    private var siriCard: some View {
        LBPanel {
            VStack(alignment: .leading, spacing: LBSpacing.s2) {
                Text("These commands work with Siri and Spotlight:")
                    .lbText(.body)
                    .foregroundStyle(LBColor.textPrimary.color)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(["Add a commitment in my longbook", "Add an expense in my longbook", "What do I pay next in my longbook"], id: \.self) { phrase in
                    HStack(alignment: .top, spacing: LBSpacing.s2) {
                        Image(systemName: "quote.opening")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(LBColor.brandText.color)
                            .padding(.top, 3)
                        Text(phrase)
                            .lbText(.bodySM)
                            .foregroundStyle(LBColor.textPrimary.color)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Text("Siri asks for what it needs — the name, the amount, the day. Nothing is added without your word.")
                    .lbText(.footnote)
                    .foregroundStyle(LBColor.textTertiary.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func action(_ name: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: LBSpacing.s2) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(LBColor.brandText.color)
                .padding(.top, 3)
            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .lbText(.bodySM)
                    .foregroundStyle(LBColor.textPrimary.color)
                Text(detail)
                    .lbText(.footnote)
                    .foregroundStyle(LBColor.textTertiary.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func copyButton(_ value: String, key: String, label: String, title: String) -> some View {
        Button {
            copy(value, key: key)
        } label: {
            HStack(spacing: LBSpacing.s1) {
                Image(systemName: copied == key ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 11, weight: .medium))
                Text(copied == key ? "Copied" : label)
                    .lbText(.label)
            }
            .foregroundStyle(LBColor.onBrand.color)
            .padding(.horizontal, LBSpacing.s3)
            .frame(minHeight: 34)
            .background(LBColor.brand.color, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(copied == key ? "Copied" : "Copy the prompt: \(title)")
    }

    /// The unfilled copy button of the MCP panel: four filled capsules in one list would shout.
    private func copyGlyph(_ value: String, key: String, title: String) -> some View {
        Button {
            copy(value, key: key)
        } label: {
            HStack(spacing: LBSpacing.s1) {
                Image(systemName: copied == key ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 11, weight: .medium))
                Text(copied == key ? "Copied" : "Copy")
                    .lbText(.label)
            }
            .foregroundStyle(LBColor.brandText.color)
            .frame(minHeight: 34)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(copied == key ? "Copied" : "Copy the prompt: \(title)")
    }

    private func copy(_ value: String, key: String) {
        #if os(iOS)
        UIPasteboard.general.string = value
        #else
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
        #endif
        copied = key
        LBHaptics.tap()
    }
}


/// A row on the Mac, a column on the phone: for a button and the line beside it.
private struct AdaptiveStack<Content: View>: View {
    let spacing: CGFloat
    @ViewBuilder let content: () -> Content

    var body: some View {
        #if os(macOS)
        HStack(spacing: spacing) { content() }
        #else
        VStack(alignment: .leading, spacing: spacing) { content() }
        #endif
    }
}
