import DesignSystem
import LongbookCore
import SwiftUI

#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// The screens behind More's rows. Every one states only what longbook actually knows: where
/// the account stands, where the vault is, what the file can and cannot hold.
struct SettingsScreen<Content: View>: View {
    let title: String
    let note: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LBSpacing.s4) {
                VStack(alignment: .leading, spacing: 2) {
                    LBPageTitle(title)
                    // An empty note is absent, not a blank line: a screen with nothing
                    // true to say under its title leaves the line out.
                    if !note.isEmpty {
                        Text(note)
                            .lbText(.footnote)
                            .foregroundStyle(LBColor.textTertiary.color)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                content()
            }
            .lbPageColumn(.reading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LBColor.canvas.color)
        .lbScreenTitle(title)
    }
}

/// A labelled fact. The label is the question, the value is longbook's whole answer.
struct FactRow: View {
    let label: String
    let value: String
    var tone: LBColorValue = LBColor.textPrimary

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: LBSpacing.s3) {
            Text(label)
                .lbText(.bodySM)
                .foregroundStyle(LBColor.textTertiary.color)
            Spacer(minLength: LBSpacing.s2)
            Text(value)
                .lbText(.bodySM)
                .foregroundStyle(tone.color)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

/// One settings row's face: a tinted icon tile, a title over a subtitle, and a trailing
/// symbol. More and Help & about both draw their rows with it. An empty subtitle is left out.
struct SettingsRowLabel: View {
    let symbol: String
    let ink: Int?
    let title: String
    let subtitle: String
    var trailing: String?
    var soon = false
    var separated = false
    /// Destructive rows wear danger — a label at the boundary floor, per the rule
    /// delete buttons already follow.
    var destructive = false

    private var tint: LBColorValue {
        destructive ? LBColor.danger : (ink.map { LBColor.dataInk(rank: $0) } ?? LBColor.neutralFold)
    }

    var body: some View {
        HStack(spacing: LBSpacing.s3) {
            RoundedRectangle(cornerRadius: LBRadius.xs, style: .continuous)
                .fill(tint.color.opacity(0.16))
                .frame(width: 34, height: 34)
                .overlay(
                    Image(systemName: symbol)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(tint.color)
                )
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                // Beside the icon a row holds a word only so large; past this size
                // "Bookmarks" broke in two.
                Text(title)
                    .lbText(.body)
                    .dynamicTypeSize(...DynamicTypeSize.accessibility3)
                    .foregroundStyle(destructive ? LBColor.danger.color : LBColor.textPrimary.color)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .lbText(.footnote)
                        .foregroundStyle(LBColor.textTertiary.color)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            Spacer(minLength: LBSpacing.s2)
            if soon {
                Text("Soon")
                    .lbText(.tabLabel)
                    .foregroundStyle(LBColor.textTertiary.color)
            } else if let trailing {
                Image(systemName: trailing)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(LBColor.textQuaternary.color)
            }
        }
        .padding(LBSpacing.s3)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) {
            if separated {
                Rectangle().fill(LBColor.hairline.color).frame(height: 1)
                    .padding(.leading, 34 + LBSpacing.s3 * 2)
            }
        }
    }
}

/// The plan in words, or nil while nothing is known: an unknown plan is left off the screen.
func planWords(_ state: EntitlementState) -> (String, LBColorValue)? {
    if state.hasLicence { return ("Licensed", LBColor.textPrimary) }
    // Urgent is a call to act, and while enforcement is off there is nothing to act on and
    // no door to act through: the days have run out, everything still writes. Same words,
    // stated rather than alarmed.
    if state.readOnly { return ("No licence", TrialRibbon.enforced ? LBColor.urgent : LBColor.textPrimary) }
    if let days = state.trialDaysLeft() {
        return (days <= 1 ? "Trial — ends today" : "Trial — \(days) days left", LBColor.textPrimary)
    }
    return nil
}

/// The Cloud row's words: the subscription as the server holds it, the trial that covers
/// it, or a grant made by hand. A subscription that has ended keeps Cloud while either runs.
func cloudWords(_ state: EntitlementState, now: Date = Date()) -> (String, LBColorValue)? {
    guard state.signedIn else { return nil }
    let timeLeft = state.cloudExpiresAt.map { $0 > now } ?? false
    switch state.cloudStatus {
    case "active" where timeLeft:
        return (state.cloudAutoRenew ? "Subscribed" : "Subscribed, cancelled", LBColor.textPrimary)
    case "grace" where timeLeft:
        return ("Subscribed, payment pending", LBColor.urgent)
    case "billing_retry":
        return ("Ended, payment failed", LBColor.urgent)
    default:
        break
    }
    if let ends = state.trialEndsAt, ends > now { return ("Included in the trial", LBColor.textPrimary) }
    // Served with neither a subscription nor a trial: Cloud the server granted by hand.
    // A licence brings its first 12 months of Cloud, granted on the server at purchase.
    if state.hasCloud { return (state.hasLicence ? "Included with your licence" : "Granted", LBColor.textPrimary) }
    return (state.cloudStatus == nil ? "Not subscribed" : "Ended", LBColor.textTertiary)
}

/// The date beside the Cloud row, with its label: when it renews, when it ends, or when
/// the trial that covers it ends. Nil when there is no date worth a line.
func cloudDateLine(_ state: EntitlementState, now: Date = Date()) -> (String, String)? {
    if let ends = state.cloudExpiresAt, ends > now, ["active", "grace"].contains(state.cloudStatus ?? "") {
        return (state.cloudAutoRenew && state.cloudStatus == "active" ? "Renews" : "Ends", LB.longDate(ends))
    }
    if let ends = state.trialEndsAt, ends > now, state.hasLicence { return ("Trial ends", LB.longDate(ends)) }
    return nil
}

// MARK: account

/// The old doors, kept because the Mac picture harness still names them. Both open the
/// one account screen in AccountScreenView.swift.
struct AccountDetailsView: View {
    let auth: AuthViewModel
    let entitlement: EntitlementStore

    var body: some View {
        AccountScreenView(auth: auth, entitlement: entitlement)
    }
}

struct BillingView: View {
    let entitlement: EntitlementStore
    let auth: AuthViewModel

    var body: some View {
        AccountScreenView(auth: auth, entitlement: entitlement)
    }
}

// MARK: display and currency

struct DisplayCurrencyView: View {
    let model: DashboardModel
    @State private var saved: String?
    @AppStorage("appearance") private var appearance = LBAppearance.system.rawValue

    var body: some View {
        SettingsScreen(title: "Display & currency", note: "") {
            LBCard {
                if choices.count > 1 {
                    VStack(alignment: .leading, spacing: LBSpacing.s3) {
                        HStack(spacing: LBSpacing.s3) {
                            Text("Home currency")
                                .lbText(.body)
                                .foregroundStyle(LBColor.textPrimary.color)
                            Spacer(minLength: LBSpacing.s2)
                            Picker("Home currency", selection: currencyChoice) {
                                ForEach(choices, id: \.self) { code in
                                    Text(code).tag(String?.some(code))
                                }
                                Text("Automatic").tag(String?.none)
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .tint(LBColor.brandText.color)
                        }
                        Text("Totals in other currencies are shown separately.")
                            .lbText(.footnote)
                            .foregroundStyle(LBColor.textTertiary.color)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    // A picker of one option would be dead UI, and picking would change nothing.
                    Text("Everything in your folder is in \(choices.first ?? "one currency"). A second currency adds a choice here.")
                        .lbText(.bodySM)
                        .foregroundStyle(LBColor.textSecondary.color)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            LBSectionHeader("Appearance")
            LBCard {
                // "Automatic", as iOS and macOS name the choice that follows the device.
                LBSegmented(selection: $appearance, choices: LBAppearance.allCases.map { ($0.rawValue, $0 == .system ? "Automatic" : $0.label) })
                    .accessibilityLabel("Appearance")
            }
            if let saveError = model.saveError {
                Text(saveError)
                    .lbText(.footnote)
                    .foregroundStyle(LBColor.urgent.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear { model.clearSaveError(); saved = model.homeCurrency }
    }

    private var current: String? { saved ?? model.homeCurrency }

    /// The chosen code, or nil for the one that follows the data.
    private var currencyChoice: Binding<String?> {
        Binding(
            get: { current },
            set: { code in
                model.setHomeCurrency(code)
                saved = code
            }
        )
    }

    private var choices: [String] {
        if case .loaded(let data) = model.state { return data.scopeChoices }
        return []
    }
}

// MARK: data and privacy

struct DataPrivacyView: View {
    let model: DashboardModel
    @State private var backup: URL?
    @State private var revealNote: String?
    @State private var moving = false
    @State private var moveError: String?
    @State private var vaultBytes = 0
    @State private var showingFiles = false
    @State private var pickingFolder = false
    @State private var checkingFolder = false
    @State private var folderRefusal: FolderRefusal?
    #if os(macOS)
    @State private var confirmingDelete = false
    @State private var deleteError: String?
    @Environment(\.lbPageTitleHidden) private var titleHidden
    @Environment(\.lbPageHeader) private var pageHeader
    #endif
    @Environment(\.openURL) private var openURL

    var body: some View {
        List {
            #if os(macOS)
            // The Settings window draws its header card here, and names the pane itself.
            if !titleHidden || pageHeader != nil {
                LBPageTitle("Data & privacy")
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
            #endif
            yourLongbook
            anotherFolder
            if let folder = model.vaultFolderURL, !inICloud(folder) { movePane(folder) }
            backupSection
            SwiftUI.Section {
                Text("longbook never stores a full card number, CVV, expiry, PIN or password: a save carrying one is refused.")
                    .lbText(.bodySM)
                    .foregroundStyle(LBColor.textSecondary.color)
                    .fixedSize(horizontal: false, vertical: true)
                    .lbListRowBackground()
            } header: {
                LBSectionHeader("Card details")
            }
            SwiftUI.Section {
                point("Your data stays on your devices, except while AI access is on (turning it off deletes that copy), when you share a report, or when you import a statement.")
                    .lbListRowBackground()
                point("Your account keeps each tag’s kind, name and icon, never a commitment’s name, amount, date or note.")
                    .lbListRowBackground()
            } header: {
                LBSectionHeader("What longbook keeps")
            }
            #if os(macOS)
            // The Mac's Settings window has no Help & about pane, so the account of what
            // leaves the device, and its two switches, sit here.
            SwiftUI.Section {
                DataLeavingCard(model: model)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
            } header: {
                LBSectionHeader("What leaves this device")
            }
            #endif
            deleteSection
        }
        .lbGroupedList()
        // A list keeps to the reading measure on a wide Mac window, as the other pages do.
        .frame(maxWidth: LBPageWidth.reading.maxWidth)
        .frame(maxWidth: .infinity)
        .background(LBColor.canvas.color)
        .lbScreenTitle("Data & privacy")
        .onAppear { vaultBytes = model.vaultFolderURL.map { VaultMigration.totalBytes(in: $0) } ?? 0 }
        .onChange(of: model.vaultFolderURL) { _, folder in
            vaultBytes = folder.map { VaultMigration.totalBytes(in: $0) } ?? 0
        }
        .measured("open_another_folder_picker", .sheet, when: pickingFolder)
        .fileImporter(isPresented: $pickingFolder, allowedContentTypes: [.folder]) { result in
            if case .success(let folder) = result { open(folder) }
        }
        .measured("folder_not_opened_notice", .alert, when: folderRefusal != nil)
        .alert(folderRefusal?.title ?? "", isPresented: Binding(get: { folderRefusal != nil }, set: { if !$0 { folderRefusal = nil } }),
               presenting: folderRefusal) { refusal in
            if refusal.explainsFormat {
                Button("Learn More") {
                    Measure.used("folder_notice_learn_more")
                    if let url = Self.formatPostURL { openURL(url) }
                }
            }
            Button("OK", role: .cancel) { Measure.used("folder_notice_ok") }
        } message: { refusal in
            Text(refusal.line)
        }
    }

    /// Why a picked folder was not opened, in the notice's own words.
    private struct FolderRefusal {
        let title: String
        let line: String
        /// A missing or foreign file points at the post about the format; a read failure does not.
        let explainsFormat: Bool
    }

    static let formatPostURL = URL(string: "https://longbook.app/blog/open-any-folder-in-longbook/")
    private static let formatTitle = "This file isn’t in longbook’s format"

    /// Another folder, checked before longbook switches to it. The folder in use is never
    /// written or moved, so it opens again the same way.
    @ViewBuilder
    private var anotherFolder: some View {
        if !model.isDemo {
            SwiftUI.Section {
                Button { Measure.used("open_another_folder"); pickingFolder = true } label: {
                    Text(checkingFolder ? "Checking…" : "Open Another Folder…")
                        .lbText(.body)
                        .foregroundStyle(LBColor.brandText.color)
                }
                .lbActionButtonStyle()
                .disabled(checkingFolder)
                .opacity(checkingFolder ? 0.45 : 1)
                .lbListRowBackground()
            } header: {
                LBSectionHeader("Another folder")
            } footer: {
                Text("longbook reads and writes the folder you choose. Your current folder stays as it is.")
                    .lbText(.footnote)
                    .foregroundStyle(LBColor.textTertiary.color)
            }
        }
    }

    /// Switches only to a folder longbook's own reader opens; anything else keeps the current one.
    private func open(_ folder: URL) {
        checkingFolder = true
        Task {
            let verdict = await VaultFolderCheck.checkDownloading(folder)
            checkingFolder = false
            switch verdict {
            case .opens:
                VaultBookmark.save(folder)
                model.load()
            case .noDataFile:
                folderRefusal = FolderRefusal(title: Self.formatTitle,
                                              line: "No financial_memory.json was found in that folder.", explainsFormat: true)
            case .notLongbookFormat:
                folderRefusal = FolderRefusal(title: Self.formatTitle,
                                              line: "longbook opens a financial_memory.json that follows its open format.",
                                              explainsFormat: true)
            case .notDownloaded:
                folderRefusal = FolderRefusal(title: "That folder didn’t open",
                                              line: "Its financial_memory.json is still in iCloud. Open the folder in \(fileApp) on Wi-Fi, then try again.",
                                              explainsFormat: false)
            case .unreadable:
                folderRefusal = FolderRefusal(title: "That folder didn’t open",
                                              line: "longbook couldn’t read that folder. Your current folder stays as it is.",
                                              explainsFormat: false)
            }
        }
    }

    /// Where the folder is, how big, how much history, and the door to it.
    private var yourLongbook: some View {
        SwiftUI.Section {
            if let folder = model.vaultFolderURL {
                HStack(spacing: LBSpacing.s3) {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(LBColor.brandText.color)
                        .accessibilityHidden(true)
                    Text(placeWords(folder))
                        .lbText(.body)
                        .foregroundStyle(LBColor.textPrimary.color)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                    Spacer(minLength: LBSpacing.s2)
                    #if os(macOS)
                    revealButton(folder)
                    #endif
                }
                .lbListRowBackground()
            }
            valueRow("Stored", location.capitalizedFirst)
            if vaultBytes > 0 {
                valueRow("Size", ByteCountFormatter.string(fromByteCount: Int64(vaultBytes), countStyle: .file))
            }
            valueRow("History", historyWord)
            #if os(iOS)
            if let folder = model.vaultFolderURL {
                revealButton(folder)
                    .lbListRowBackground()
            }
            if showingFiles {
                valueRow("Data file", VaultReader.dataFile)
                valueRow("Preferences", WorkspaceStore.fileName)
            }
            Button {
                Measure.used("hide_files")
                withAnimation(.easeOut(duration: 0.2)) { showingFiles.toggle() }
            } label: {
                Text(showingFiles ? "Hide Files" : "Show Files")
                    .lbText(.body)
                    .foregroundStyle(LBColor.brandText.color)
            }
            .buttonStyle(.borderless)
            .lbListRowBackground()
            #endif
        } header: {
            LBSectionHeader("Your longbook")
        } footer: {
            VStack(alignment: .leading, spacing: LBSpacing.s1) {
                if let folder = model.vaultFolderURL {
                    Text(inICloud(folder)
                        ? "Changes sync through iCloud Drive to every device signed in to your iCloud."
                        : "The folder is on this device only. It doesn’t sync anywhere.")
                }
                if let revealNote {
                    Text(revealNote).foregroundStyle(LBColor.urgent.color)
                }
            }
            .lbText(.footnote)
            .foregroundStyle(LBColor.textTertiary.color)
        }
    }

    /// Show in Finder on the Mac, beside the path; Open in Files on the phone, a row of its own.
    private func revealButton(_ folder: URL) -> some View {
        Button { Measure.used("reveal"); reveal(folder) } label: {
            Text(revealWord)
                .lbText(.body)
                .foregroundStyle(LBColor.brandText.color)
                .frame(minHeight: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
    }

    private func valueRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: LBSpacing.s3) {
            Text(label)
                .lbText(.body)
                .foregroundStyle(LBColor.textPrimary.color)
            Spacer(minLength: LBSpacing.s2)
            Text(value)
                .lbText(.body)
                .foregroundStyle(LBColor.textSecondary.color)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .lbListRowBackground()
    }

    private var backupSection: some View {
        SwiftUI.Section {
            if let backup {
                ShareLink(item: backup) {
                    Text("Share Backup")
                        .lbText(.body)
                        .foregroundStyle(LBColor.brandText.color)
                }
                .lbListRowBackground()
            } else {
                Button { Measure.used("back_up_now"); backup = model.exportBackup() } label: {
                    Text("Back Up Now")
                        .lbText(.body)
                        .foregroundStyle(LBColor.brandText.color)
                }
                .lbActionButtonStyle()
                .lbListRowBackground()
            }
        } header: {
            LBSectionHeader("Backup")
        } footer: {
            Text("Save a copy of your longbook.")
                .lbText(.footnote)
                .foregroundStyle(LBColor.textTertiary.color)
        }
    }

    /// The Mac moves the folder to the Bin, asking first; the phone says where to delete it.
    @ViewBuilder
    private var deleteSection: some View {
        #if os(macOS)
        if let folder = model.vaultFolderURL {
            SwiftUI.Section {
                Button { Measure.used("delete_longbook"); confirmingDelete = true } label: {
                    Text("Delete longbook…")
                        .lbText(.body)
                        .foregroundStyle(LBColor.danger.color)
                }
                .buttonStyle(.borderless)
                .lbListRowBackground()
                .measured("settings_confirming_delete", .dialog, when: confirmingDelete)
                .confirmationDialog("Move your longbook to the Bin?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                    Button("Move to Bin", role: .destructive) { Measure.used("move_to_bin"); deleteFolder(folder) }
                    Button("Cancel", role: .cancel) { Measure.used("cancel") }
                } message: {
                    Text(inICloud(folder)
                        ? "The folder at \(placeWords(folder)) moves to the Bin and leaves every device that syncs it. Until you empty the Bin you can put it back."
                        : "The folder at \(placeWords(folder)) moves to the Bin. Until you empty the Bin you can put it back.")
                }
            } footer: {
                if let deleteError {
                    Text(deleteError)
                        .lbText(.footnote)
                        .foregroundStyle(LBColor.urgent.color)
                }
            }
        }
        #else
        SwiftUI.Section {
        } footer: {
            Text("To delete your longbook, delete its folder in \(fileApp).")
                .lbText(.footnote)
                .foregroundStyle(LBColor.textTertiary.color)
        }
        #endif
    }

    #if os(macOS)
    private func deleteFolder(_ folder: URL) {
        deleteError = nil
        NSWorkspace.shared.recycle([folder]) { _, error in
            Task { @MainActor in
                if let error {
                    deleteError = error.friendlyDescription
                } else {
                    model.load()
                }
            }
        }
    }
    #endif

    /// Under any "Mobile Documents" path — the app's own container, or a picked folder in
    /// the reader's own iCloud Drive. Either way it already syncs, so the move pane shows
    /// only for a folder that lives on this device alone.
    private func inICloud(_ folder: URL) -> Bool {
        folder.path.contains("Mobile Documents")
    }

    #if os(macOS)
    private let fileApp = "Finder"
    private let revealWord = "Show in Finder"
    #else
    private let fileApp = "Files"
    private let revealWord = "Open in Files"
    #endif

    private func movePane(_ folder: URL) -> some View {
        SwiftUI.Section {
            Button { Measure.used("moving"); move(folder) } label: {
                Text(moving ? "Moving…" : "Move to iCloud")
                    .lbText(.body)
                    .foregroundStyle(LBColor.brandText.color)
            }
            .lbActionButtonStyle()
            .disabled(moving)
            .opacity(moving ? 0.45 : 1)
            .lbListRowBackground()
        } header: {
            LBSectionHeader("iCloud")
        } footer: {
            VStack(alignment: .leading, spacing: LBSpacing.s1) {
                Text("Use your longbook on all your devices.")
                if let moveError {
                    Text(moveError).foregroundStyle(LBColor.urgent.color)
                }
            }
            .lbText(.footnote)
            .foregroundStyle(LBColor.textTertiary.color)
        }
    }

    /// One plain statement on its own line.
    private func point(_ text: String) -> some View {
        HStack(alignment: .top, spacing: LBSpacing.s2) {
            Circle()
                .fill(LBColor.textQuaternary.color)
                .frame(width: 4, height: 4)
                .padding(.top, 7)
            Text(text)
                .lbText(.bodySM)
                .foregroundStyle(LBColor.textSecondary.color)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The folder in words the reader can find it by: the Mac shows the real path, since
    /// that is how Mac folders are named; an iOS path is sandbox noise, so the place is
    /// named the way the Files app names it.
    private func placeWords(_ folder: URL) -> String {
        #if os(macOS)
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let path = folder.standardizedFileURL.path
        return path.hasPrefix(home) ? "~" + String(path.dropFirst(home.count)) : path
        #else
        if folder.path.contains("iCloud~app~longbook") { return "iCloud Drive › longbook" }
        if folder.path.contains("/Data/Application/") { return "On My \(UIDevice.current.model) › longbook" }
        return "\(fileApp) › \(folder.lastPathComponent)"
        #endif
    }

    private func reveal(_ folder: URL) {
        revealNote = nil
        #if os(macOS)
        NSWorkspace.shared.activateFileViewerSelecting([folder])
        #else
        // Files opens a folder through the shareddocuments scheme — the file URL, rebadged.
        var parts = URLComponents(url: folder.standardizedFileURL, resolvingAgainstBaseURL: false)
        parts?.scheme = "shareddocuments"
        guard let url = parts?.url else { return }
        openURL(url) { opened in
            if !opened { revealNote = "Files couldn’t open this folder on this device." }
        }
        #endif
    }

    private func move(_ source: URL) {
        moving = true
        moveError = nil
        Task {
            let outcome = await Task.detached(priority: .userInitiated) {
                Result { try VaultMigration.moveToICloud(from: source) }
            }.value
            moving = false
            switch outcome {
            case .success:
                // A picked-folder bookmark now names a folder with no vault in it; forgotten,
                // so resolution lands on the container the vault moved into.
                if VaultBookmark.resolve()?.standardizedFileURL.path == source.standardizedFileURL.path {
                    VaultBookmark.forget()
                }
                model.load()
            case .failure(let error):
                moveError = error.friendlyDescription
                vaultBytes = VaultMigration.totalBytes(in: source)
            }
        }
    }

    private var location: String {
        if case .loaded(let data) = model.state { return data.vaultLocation }
        return "No folder is open"
    }

    /// Every change is kept — this is the visible face of "git inside the app".
    private var historyWord: String {
        let count = model.historyCount()
        return count == 0 ? "Starts with the first change" : "\(count) version\(count == 1 ? "" : "s") kept"
    }
}

extension View {
    /// An action in a settings list: a bordered button sized to its words on the Mac, where a
    /// borderless row reads as text; the phone's row stays a row.
    @ViewBuilder
    func lbActionButtonStyle() -> some View {
        #if os(macOS)
        buttonStyle(.bordered).controlSize(.regular)
        #else
        buttonStyle(.borderless)
        #endif
    }
}
