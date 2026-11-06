import DesignSystem
import LongbookCore
import StoreKit
import SwiftUI
import UniformTypeIdentifiers

/// Statements in, one write out: every file is read on the device and named by the server by
/// its lines, or when those don't prove themselves read there a few pages at a time. What was
/// read is saved once, right after reading, and can be taken back whole.
struct StatementImportView: View {
    let model: DashboardModel
    @ObservedObject var auth: AuthViewModel
    /// Setup's last step: the screen says what the statement is for, and can be passed over.
    var setup: Bool = false
    /// Why the screen opened, when a month with nothing in it asked for it.
    var prompt: String?
    /// What the statement is for, in the words handed to the owner's own AI. Unset, it follows
    /// `setup`: the set-up prompt there, the statement prompt everywhere else.
    var context: SetupPrompt.Context?
    /// Setup's step before this one; a swipe to the right goes there.
    var onBack: (() -> Void)?
    /// Opened from a button that already said Upload: the consent, then the picker, at once.
    var picksOnOpen = false
    /// Files dropped on the window: read at once, after the consent, without the picker.
    var dropped: [URL] = []
    let onDone: () -> Void
    @Environment(\.requestReview) private var requestReview

    private enum Stage: Equatable { case pick, reading, locked, notRecent, tour }

    /// A quiet text button's height: 44 points on the phone, the Mac's 32 on the Mac.
    private static let quietButtonHeight: CGFloat = {
        #if os(iOS)
        44
        #else
        32
        #endif
    }()

    /// How many files one pick may hold.
    static let filesAtOnce = 5

    /// The shapes the import reads: PDF, CSV, text and Excel.
    static func readable(_ url: URL) -> Bool {
        ["pdf", "csv", "txt", "xls", "xlsx"].contains(url.pathExtension.lowercased())
    }
    #if os(macOS)
    /// The window every stage shares on the Mac, over the setup step or the Dashboard.
    private static let sheetWidth: CGFloat = 600
    private static let sheetHeight: CGFloat = 690
    #endif

    /// One file of the batch: its pieces, how far its reading has come, its answer, and the
    /// account it is. `id` keys its lines among the candidates.
    private struct FileRead: Identifiable {
        let id = UUID().uuidString
        let url: URL
        /// The server counts every piece and the review of a file against this.
        var importId = StatementCloud.newImportId()
        var pieces: [StatementCloud.Piece] = []
        /// Set when the device's own lines prove themselves: then the model only names them.
        var plan: StatementLinePass.Plan?
        /// How far the reading of the plan has come, for the reading screen.
        var counts: StatementLinePass.Progress?
        var prepared: StatementCloud.Prepared?
        var unread: [String] = []
        /// Why nothing came of it: refused as not a statement, or failed.
        var problem: String?
        var account = ""
        var balance: Double?
        var balanceDate: String?
        /// The password that opened it, kept for the device's own reading of the file.
        var password: String?
        /// The server's reading against the file's own lines, once every piece is back.
        var report: StatementCompleteness.Report?
        /// Lines the server left out, read from the file instead.
        var filled: [StatementCandidate] = []
        /// The days the statement covers: its printed period, or its first and last line.
        var period: FirstStatementCheck.Period?
        var name: String { url.lastPathComponent }
        var isCut: Bool { plan != nil || !pieces.isEmpty }
        /// Calls to wait for: the head, each batch and the look-over, or every piece and the review.
        var units: Int { plan.map { $0.batches.count + 2 } ?? pieces.count + 1 }
    }

    /// PDF, CSV, text and Excel — the shapes banks hand out. The Excel types are named by
    /// identifier so a device without them registered simply offers fewer.
    static let pickable: [UTType] = [.pdf, .commaSeparatedText, .plainText]
        + ["org.openxmlformats.spreadsheetml.sheet", "com.microsoft.excel.xls"].compactMap(UTType.init)

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var stage: Stage = .pick
    @State private var picking = false
    /// Accepted once by this account on this device before any statement leaves it; until
    /// then a pick or a drop waits behind the consent sheet.
    @AppStorage(AIConsent.statements.key) private var consented = false
    @State private var askingConsent = false
    @State private var afterConsent: (() -> Void)?
    @State private var password = ""
    @FocusState private var passwordFocused: Bool
    /// The files picked, in the order picked; each is its own reading on the server.
    @State private var files: [FileRead] = []
    /// The file waiting for its password, while the others wait behind it.
    @State private var lockedIndex: Int?
    @State private var candidates: [StatementCandidate] = []
    @State private var repeats: [StatementCloud.Repeat] = []
    @State private var members: [StatementCloud.Member] = []
    /// Accounts on the other side of transfers and card payments, new to the book.
    @State private var foundAccounts: [StatementCounterparts.Account] = []
    @State private var currency = "INR"
    @State private var problem: String?
    /// The server has read its share of statements for this account for now; the pick
    /// stage says so, with the way to write to us. How many is never said.
    @State private var shareSpent = false
    /// The other way in, opened on request: the owner's own AI.
    @State private var ownAI = false
    @State private var confirmingClose = false
    /// The save is under way; nothing closes the sheet until it answers.
    @State private var adding = false
    /// Read and saved: the bar is full.
    @State private var saved = false
    /// The save refused, in words. Nothing was written, and it can be tried again.
    @State private var notSaved: String?
    /// Whether this run is still wanted: a reading left behind never writes.
    @State private var run = ImportRun()
    @State private var reading: Task<Void, Never>?
    /// What the one write left, once it has landed: what Undo Import takes back.
    @State private var savedImport: DashboardModel.SavedImport?
    /// The tour's cards, read back from the book; people as the import wrote them.
    @State private var findings = StatementTour.Findings()
    @State private var tourPeople: [StatementTour.Card] = []
    /// Every card the import found and the people taken out and saved, for the one count sent
    /// when the tour ends.
    @State private var tourFound = StatementTour.Findings()
    @State private var peopleRemoved: Set<String> = []
    /// A refusal from Undo Import or from taking a person out.
    @State private var tourProblem: String?
    /// Whether the game was played: if not, what comes after the reading opens by itself.
    @State private var played = false
    /// A file is being dragged over the Mac's drop zone.
    @State private var dropping = false
    /// Why a first statement was turned away, and the names of the files it held; nothing of
    /// them is kept.
    @State private var refusal: FirstStatementCheck.Outcome?
    @State private var refusedNames: [String] = []

    /// Setup's own statement step, or the onboarding finish: their words stay as written.
    private var inSetup: Bool { setup || context == .setup }

    /// The Mac's file panel opens from this button, so its word ends in an ellipsis.
    private var pickWord: String {
        #if os(macOS)
        "Securely Upload Statement…"
        #else
        "Securely Upload Statement"
        #endif
    }

    /// The units of the reading — every piece of every file, and each file's look-over —
    /// and how many are done.
    @State private var units = 1.0
    @State private var doneUnits = 0
    /// The seconds this batch should take, for the bar's pace.
    @State private var expectedSeconds = ReadingBar.linesSeconds

    var body: some View {
        VStack(alignment: .leading, spacing: LBSpacing.s3) {
            if stage == .pick || stage == .locked || stage == .notRecent { header }
            switch stage {
            case .pick: pickStage
            case .reading: readingStage
            case .locked: lockedStage
            case .notRecent: notRecentStage
            case .tour: tourStage
            }
        }
        .padding(stage == .pick || stage == .locked || stage == .notRecent ? LBSpacing.s4 : 0)
        .frame(maxWidth: 640)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        #if os(macOS)
        // One fixed window: a Mac sheet keeps the size it opened at, and every stage fits it.
        .frame(width: setup ? nil : Self.sheetWidth, height: setup ? nil : Self.sheetHeight)
        .frame(minWidth: setup ? 600 : nil, minHeight: setup ? 640 : nil)
        #endif
        .background(LBColor.canvas.color)
        // A click outside never closes it; once a statement is being read only its own controls do.
        .interactiveDismissDisabled(stage != .pick && stage != .notRecent)
        #if os(iOS)
        .presentationDragIndicator(.visible)
        #endif
        .onAppear { if !setup { ImportBackdrop.shared.active = true } }
        .onDisappear {
            leave()
            if !setup { ImportBackdrop.shared.active = false }
        }
        .measured("statement_import_confirming_close", .dialog, when: confirmingClose)
        .confirmationDialog("Leave the import?", isPresented: $confirmingClose, titleVisibility: .visible) {
            Button("Leave", role: .destructive, action: { Measure.used("leave"); leave(); onDone() })
            Button("Stay", role: .cancel) { Measure.used("stay") }
        } message: {
            Text("What was read is not kept.")
        }
        .onAppear {
            // With no home currency, the phone's own region: a London phone starts in pounds.
            currency = model.homeCurrency ?? Locale.current.currency?.identifier ?? "INR"
            // After the sheet has risen, so the consent or the picker is not refused mid-presentation.
            if !dropped.isEmpty, stage == .pick {
                let files = Array(dropped.prefix(Self.filesAtOnce))
                // Already agreed to, the reading is the first frame: nothing else rises over it.
                if consented { start(files) } else {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { withConsent { start(files) } }
                }
            } else if picksOnOpen, stage == .pick {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { withConsent { picking = true } }
            }
            #if DEBUG
            // The snapshot harness names a saved answer to show, so the review can be pictured.
            if let path = ProcessInfo.processInfo.environment["LONGBOOK_SNAPSHOT_PREPARED"], stage == .pick,
               let data = FileManager.default.contents(atPath: path),
               let piece = try? JSONDecoder().decode(StatementCloud.ChargesAnswer.self, from: data) {
                let looked = (try? JSONDecoder().decode(StatementCloud.ReviewAnswer.self, from: data)) ?? .empty
                var one = FileRead(url: URL(fileURLWithPath: "hdfc-savings-2025-2026.pdf"))
                one.prepared = StatementCloud.Prepared.assemble([piece], review: looked)
                one.account = one.prepared?.account ?? ""
                one.balance = one.prepared?.balance
                one.balanceDate = one.prepared?.balanceDate
                files = [one]
                Task { @MainActor in
                    await show()
                    // Pictured without writing: the same write, kept in memory.
                    if let raw = model.loadedRaw, let written = try? StatementImport.write(reviewToWrite().review, to: raw, now: Date(), schema: nil) {
                        findings = StatementTour.findings(before: raw, after: written.vault)
                        tourPeople = findings.people
                    }
                    saved = true
                    played = ProcessInfo.processInfo.environment["LONGBOOK_SNAPSHOT_READY"] != nil
                    stage = played ? .reading : .tour
                }
            }
            // Files named here (paths separated by |) are read as if dropped, without the open panel.
            if let paths = ProcessInfo.processInfo.environment["LONGBOOK_SNAPSHOT_PICK"], stage == .pick {
                let picked = paths.split(separator: "|").map { URL(fileURLWithPath: String($0)) }
                if !picked.isEmpty {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { withConsent { start(picked) } }
                }
            }
            if ProcessInfo.processInfo.environment["LONGBOOK_SNAPSHOT_OWN_AI"] != nil { ownAI = true }
            if ProcessInfo.processInfo.environment["LONGBOOK_SNAPSHOT_CONSENT"] != nil { askingConsent = true }
            if ProcessInfo.processInfo.environment["LONGBOOK_SNAPSHOT_LIMIT"] != nil {
                shareSpent = true
            }
            // A locked statement, with a made-up file name; LONGBOOK_SNAPSHOT_ID adds a wrong
            // password or a typed one. Reads no vault and writes nothing.
            if ["lockedstatement"].contains(ProcessInfo.processInfo.environment["LONGBOOK_SNAPSHOT_SHEET"] ?? ProcessInfo.processInfo.environment["LONGBOOK_SNAPSHOT_SCREEN"] ?? "") {
                files = [FileRead(url: URL(fileURLWithPath: "statement-demo.pdf"))]
                lockedIndex = 0
                stage = .locked
                switch ProcessInfo.processInfo.environment["LONGBOOK_SNAPSHOT_ID"] ?? "" {
                case "wrong":
                    password = "demo"
                    problem = StatementText.ReadError.wrongPassword.errorDescription
                case "typed": password = "demo"
                case "long": files = [FileRead(url: URL(fileURLWithPath: "Statement of account 4521 for the period 01-04-2025 to 31-03-2026 final copy.pdf"))]
                default: break
                }
            }
            // A first statement turned away, with a made-up file name; LONGBOOK_SNAPSHOT_ID
            // "short" pictures the short one. Reads no vault and writes nothing.
            if (ProcessInfo.processInfo.environment["LONGBOOK_SNAPSHOT_SHEET"] ?? ProcessInfo.processInfo.environment["LONGBOOK_SNAPSHOT_SCREEN"]) == "notrecent" {
                refusal = ProcessInfo.processInfo.environment["LONGBOOK_SNAPSHOT_ID"] == "short" ? .tooShort : .notRecent
                refusedNames = ["statement-demo.pdf"]
                stage = .notRecent
            }
            if ProcessInfo.processInfo.environment["LONGBOOK_SNAPSHOT_WORKING"] != nil {
                files = [FileRead(url: URL(fileURLWithPath: "hdfc-savings-2025-2026.pdf"))]
                stage = .reading
            }
            #endif
        }
        .fileImporter(isPresented: $picking, allowedContentTypes: Self.pickable, allowsMultipleSelection: true) { result in
            guard case .success(let urls) = result, !urls.isEmpty else { return }
            start(Array(urls.prefix(Self.filesAtOnce)))
        }
        .measured("statement_import_own_ai", .sheet, when: ownAI)
        .sheet(isPresented: $ownAI) { ownAISheet.lbKeyboardFocusEffects() }
        .measured("statement_import_asking_consent", .sheet, when: askingConsent)
        .sheet(isPresented: $askingConsent) {
            ConsentSheet(consent: .statements, onAccept: {
                consented = true
                askingConsent = false
                let next = afterConsent
                afterConsent = nil
                // The picker cannot open while this sheet is still leaving.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { next?() }
            }, onDecline: {
                askingConsent = false
                afterConsent = nil
            })
                .lbKeyboardFocusEffects()
        }
    }

    // MARK: stages

    private var pickStage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LBSpacing.s3) {
                if let prompt {
                    Text(prompt)
                        .lbText(.body)
                        .foregroundStyle(LBColor.textPrimary.color)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text("Up to five at once: PDF, CSV or Excel, as your bank sends them.")
                    .lbText(.body)
                    .foregroundStyle(LBColor.textSecondary.color)
                    .fixedSize(horizontal: false, vertical: true)
                // Said before any file is chosen, never behind a tap: where the statement goes.
                HStack(alignment: .firstTextBaseline, spacing: LBSpacing.s2) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(LBColor.brandText.color)
                        .accessibilityHidden(true)
                    Text("\(OnboardingFinishView.privacyLine) A copy of each file is kept in your folder’s documents.")
                        .lbText(.footnote)
                        .foregroundStyle(LBColor.textSecondary.color)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let problem {
                    Text(problem)
                        .lbText(.footnote)
                        .foregroundStyle(LBColor.urgent.color)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if shareSpent {
                    shareNotice
                } else {
                    let retrying = problem != nil && !files.isEmpty
                    let pick = primary(retrying ? "Try Again" : setup ? "Securely Upload Statement" : pickWord, badge: retrying || !setup ? nil : "Recommended") {
                        if retrying { start(files.map(\.url)) } else { withConsent { picking = true } }
                    }
                    #if os(macOS)
                    if inSetup {
                        pick.padding(.top, LBSpacing.s2)
                    } else {
                        dropZone { pick.frame(maxWidth: 260) }
                            .padding(.top, LBSpacing.s2)
                    }
                    #else
                    pick.padding(.top, LBSpacing.s2)
                    #endif
                }
                // The other door, for the owner who has an AI of their own: its own sheet, so
                // the statement stays the one path on this screen. Never in the first run.
                if !inSetup {
                    Button {
                        Measure.used("use_my_own_ai")
                        ownAI = true
                    } label: {
                        HStack(spacing: LBSpacing.s1) {
                            Text("Use My Own AI")
                                .lbText(shareSpent ? .body : .label)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 9, weight: .semibold))
                        }
                        .foregroundStyle(LBColor.brandText.color)
                        .frame(maxWidth: .infinity, minHeight: shareSpent ? 44 : 32)
                        .overlay {
                            if shareSpent {
                                RoundedRectangle(cornerRadius: LBRadius.sm, style: .continuous)
                                    .strokeBorder(LBColor.hairline.color, lineWidth: 1)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .lbButtonStyle()
                    .accessibilityHint("Opens the steps for your own AI")
                }
                if setup {
                    Button(action: { Measure.used("skip"); onDone() }) {
                        HStack(spacing: LBSpacing.s2) {
                            Text("Skip")
                                .lbText(.footnote)
                                .foregroundStyle(LBColor.textSecondary.color)
                            LBBadge("Not recommended", tone: .muted)
                        }
                        .frame(maxWidth: .infinity, minHeight: 32)
                        .contentShape(Rectangle())
                    }
                    .lbButtonStyle()
                }
            }
        }
        .contentShape(Rectangle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 40).onEnded { drag in
                guard setup, drag.translation.width > 0, drag.translation.width > abs(drag.translation.height) * 1.5 else { return }
                onBack?()
            }
        )
    }

    /// The share spent, as a quiet notice: what happened, the way to write to us, and outside
    /// the first run the own-AI door below it. How many reads there were is never said.
    private var shareNotice: some View {
        HStack(alignment: .top, spacing: LBSpacing.s3) {
            Image(systemName: "clock")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(LBColor.textSecondary.color)
                .padding(.top, 1)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: LBSpacing.s1) {
                Text("Statement reads are used up for now")
                    .lbText(.body)
                    .foregroundStyle(LBColor.textPrimary.color)
                Text(inSetup ? "longbook’s server has read all the statements it can for your account for now."
                     : "longbook’s server has read all the statements it can for your account for now. Your own AI can read the rest, below.")
                    .lbText(.footnote)
                    .foregroundStyle(LBColor.textSecondary.color)
                    .fixedSize(horizontal: false, vertical: true)
                if let mail = FeedbackMail.statementShare {
                    Link(destination: mail) {
                        Text("Write to us for more")
                            .lbText(.label)
                            .foregroundStyle(LBColor.brandText.color)
                            .frame(minHeight: 32)
                    }
                    .lbLinkPointer()
                }
            }
            Spacer(minLength: 0)
        }
        .padding(LBSpacing.s3)
        .background(LBColor.card.color, in: RoundedRectangle(cornerRadius: LBRadius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: LBRadius.md, style: .continuous)
                .strokeBorder(LBColor.hairline.color, lineWidth: 1)
        )
    }

    #if os(macOS)
    /// A statement dragged from Finder starts the reading as a picked one does; the pick
    /// button sits inside the zone for the reader who would rather browse.
    private func dropZone<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: LBSpacing.s3) {
            Image(systemName: "arrow.down.doc")
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(dropping ? LBColor.brandText.color : LBColor.textTertiary.color)
                .accessibilityHidden(true)
            Text("Drop a statement here")
                .lbText(.body)
                .foregroundStyle(LBColor.textSecondary.color)
            content()
        }
        .padding(LBSpacing.s6)
        .frame(maxWidth: .infinity)
        .background(dropping ? LBColor.brand.color.opacity(0.10) : Color.clear,
                    in: RoundedRectangle(cornerRadius: LBRadius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: LBRadius.md, style: .continuous)
                .strokeBorder(dropping ? LBColor.brand.color : LBColor.textQuaternary.color,
                              style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
        )
        .dropDestination(for: URL.self) { urls, _ in
            guard !urls.isEmpty else { return false }
            withConsent { start(Array(urls.prefix(Self.filesAtOnce))) }
            return true
        } isTargeted: { dropping = $0 }
    }
    #endif

    /// The bar, its line and the game, through the reading and once it is prepared.
    private var readingStage: some View {
        StatementReadingView(
            done: Double(doneUnits) / max(units, 1), expected: expectedSeconds, full: saved,
            isPrepared: saved && played, notSaved: notSaved, played: $played,
            onClose: {
                guard !adding else { return }
                if saved { onDone() } else { confirmingClose = true }
            },
            onContinue: openTour,
            onTryAgain: { Task { await save() } }
        )
    }

    private func openTour() {
        withAnimation(LBMotion.rise(reduceMotion: reduceMotion)) { stage = .tour }
    }

    private var tourStage: some View {
        StatementTourView(
            findings: findings, people: tourPeople,
            troubles: files.compactMap(\.problem) + files.flatMap { read in read.unread.map { "\(read.name): \($0)" } },
            problem: tourProblem, photo: model.photoURL,
            flips: { person, besides in
                savedImport.map { model.transferFlips(removing: person, besides: besides, from: $0) } ?? (0, 0)
            },
            applyRemoved: applyRemoved,
            onUndo: undoImport,
            onEnd: countTour,
            onImportAnother: {
                backToPick()
                withConsent { picking = true }
            },
            onOpenDashboard: {
                onDone()
                NotificationCenter.default.post(name: .longbookOpenDashboard, object: nil)
                // The import is done and the Dashboard shows it: Apple's prompt may follow.
                if RatingPrompt.importKept(duringSetup: setup || context == .setup) { RatingPrompt.ask(requestReview) }
            }
        )
    }

    /// The people taken out on See All, saved as one change; the other cards read again.
    private func applyRemoved(_ people: Set<String>) -> Bool {
        guard var kept = savedImport else { return false }
        tourProblem = nil
        guard model.setPeopleRemoved(people, from: &kept) else {
            tourProblem = model.saveError
            return false
        }
        savedImport = kept
        peopleRemoved = people
        if let raw = model.loadedRaw { findings = StatementTour.findings(before: kept.before, after: raw) }
        return true
    }

    private func undoImport() {
        guard let kept = savedImport else { return }
        tourProblem = nil
        guard model.undoImport(kept) else {
            tourProblem = model.saveError
            return
        }
        countImport(outcome: "undone")
        countTour(.undone)
        backToPick()
    }

    /// The import over: the next one starts from the door.
    private func backToPick() {
        files = []
        savedImport = nil
        findings = StatementTour.Findings()
        tourPeople = []
        tourFound = StatementTour.Findings()
        peopleRemoved = []
        tourProblem = nil
        saved = false
        problem = nil
        stage = .pick
    }

    /// The locked file asks for its password: one compact group at the top, as the pick
    /// stage sits, with Unlock under the field and the rest left as quiet space.
    private var lockedStage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LBSpacing.s3) {
                HStack(alignment: .firstTextBaseline, spacing: LBSpacing.s2) {
                    Image(systemName: "lock")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(LBColor.textSecondary.color)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: LBSpacing.s1) {
                        Text("This statement is locked")
                            .lbText(.headline)
                            .foregroundStyle(LBColor.textPrimary.color)
                            .accessibilityAddTraits(.isHeader)
                        if let index = lockedIndex {
                            Text(files[index].name)
                                .lbText(.bodySM)
                                .foregroundStyle(LBColor.textSecondary.color)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                }
                Text("Enter the password your bank set for this file. The email that carried the statement usually says what it is.")
                    .lbText(.body)
                    .foregroundStyle(LBColor.textPrimary.color)
                    .fixedSize(horizontal: false, vertical: true)
                // Shown as typed: a bank's password is a name and a birthday, not a secret to
                // hide from the person typing it, and a wrong one costs a minute.
                field {
                    TextField("", text: $password, prompt: Text("Password").foregroundStyle(LBColor.textTertiary.color))
                        .textFieldStyle(.plain)
                        .lbText(.body)
                        .foregroundStyle(LBColor.textPrimary.color)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .submitLabel(.go)
                        #endif
                        .focused($passwordFocused)
                        .onSubmit { if !password.isEmpty { cut() } }
                }
                if let problem {
                    Text(problem)
                        .lbText(.footnote)
                        .foregroundStyle(LBColor.urgent.color)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text("Used once to open the file, and not kept.")
                    .lbText(.footnote)
                    .foregroundStyle(LBColor.textSecondary.color)
                    .fixedSize(horizontal: false, vertical: true)
                primary("Unlock", enabled: !password.isEmpty) { cut() }
                Button {
                    Measure.used("pick_another_file")
                    password = ""
                    problem = nil
                    files = []
                    lockedIndex = nil
                    stage = .pick
                } label: {
                    Text("Pick Another File")
                        .lbText(.footnote)
                        .foregroundStyle(LBColor.textSecondary.color)
                        .frame(maxWidth: .infinity, minHeight: Self.quietButtonHeight)
                        .contentShape(Rectangle())
                }
                .lbButtonStyle()
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        // The password field takes the focus as the stage appears, after the sheet has settled.
        .onAppear { DispatchQueue.main.async { passwordFocused = true } }
    }

    /// A first statement that is old or short: what it is, what to fetch instead, and one way
    /// back to the pick. No dates or numbers are shown.
    private var notRecentStage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LBSpacing.s3) {
                VStack(alignment: .leading, spacing: LBSpacing.s1) {
                    Text(refusal == .tooShort ? "This statement is too short" : "This isn’t a recent statement")
                        .lbText(.headline)
                        .foregroundStyle(LBColor.textPrimary.color)
                        .accessibilityAddTraits(.isHeader)
                    if !refusedNames.isEmpty {
                        Text(refusedNames.joined(separator: ", "))
                            .lbText(.bodySM)
                            .foregroundStyle(LBColor.textSecondary.color)
                            .lineLimit(2)
                            .truncationMode(.middle)
                    }
                }
                Text("Download your most recent six-month statement from your bank’s app or website, then add it here.")
                    .lbText(.body)
                    .foregroundStyle(LBColor.textPrimary.color)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Your first statement needs to be a recent one. You can add older statements once your longbook is ready.")
                    .lbText(.footnote)
                    .foregroundStyle(LBColor.textSecondary.color)
                    .fixedSize(horizontal: false, vertical: true)
                primary("Choose Another Statement", measure: "choose_another_statement") {
                    refusal = nil
                    refusedNames = []
                    files = []
                    stage = .pick
                }
            }
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private var money: String { currency.trimmingCharacters(in: .whitespaces).uppercased() }

    private func cycleWord(_ repeated: StatementCloud.Repeat) -> String {
        switch repeated.cycle {
        case "monthly": return "monthly"
        case "yearly": return "yearly"
        default: return repeated.customDays.map { "every \($0) days" } ?? "repeats"
        }
    }

    // MARK: pieces

    @ViewBuilder
    private var header: some View {
        if setup {
            VStack(alignment: .leading, spacing: LBSpacing.s2) {
                Text("Secure statement reading")
                    .lbText(.label)
                    .foregroundStyle(LBColor.brandText.color)
                HStack(alignment: .firstTextBaseline, spacing: LBSpacing.s2) {
                    Text("Upload your bank statement securely")
                        .lbText(.displayLG)
                        .foregroundStyle(LBColor.textPrimary.color)
                        .fixedSize(horizontal: false, vertical: true)
                    LBBadge("Recommended", tone: .positive)
                }
                Text(OnboardingFinishView.privacyLine)
                    .lbText(.bodySM)
                    .foregroundStyle(LBColor.textSecondary.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, LBSpacing.s2)
        } else {
            HStack(spacing: LBSpacing.s2) {
                Text("Import a statement")
                    .lbText(.headline)
                    .foregroundStyle(LBColor.textPrimary.color)
                Spacer()
                Button {
                    Measure.used("close")
                    // Nothing is held on the pick or a turned-away statement: no question to ask.
                    if stage == .pick || stage == .notRecent { onDone() } else { confirmingClose = true }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(LBColor.textSecondary.color)
                        .frame(width: 30, height: 30)
                        .background(LBColor.chrome.color, in: Circle())
                }
                .lbButtonStyle()
                .disabled(adding)
                .help("Close")
                .accessibilityLabel("Close")
            }
        }
    }

    /// The owner's own AI as its own sheet: a title, a way out, and the steps.
    private var ownAISheet: some View {
        VStack(alignment: .leading, spacing: LBSpacing.s3) {
            HStack(spacing: LBSpacing.s2) {
                Text("Use My Own AI")
                    .lbText(.headline)
                    .foregroundStyle(LBColor.textPrimary.color)
                Spacer()
                Button("Done") { Measure.used("done"); ownAI = false }
                    .lbText(.body)
                    .foregroundStyle(LBColor.brandText.color)
                    .lbButtonStyle()
                    .keyboardShortcut(.cancelAction)
            }
            ScrollView {
                OwnAIHelp(model: model, auth: auth, context: context ?? (setup ? .setup : .reports), onFinish: setup ? onDone : nil)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(LBSpacing.s4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        #if os(macOS)
        .frame(minWidth: 520, minHeight: 560)
        #endif
        .background(LBColor.canvas.color)
    }

    /// The brand button; `badge` adds a small positive pill beside its word.
    private func primary(_ title: String, badge: String? = nil, enabled: Bool = true, measure: StaticString = "statement_option",
                         action: @escaping () -> Void) -> some View {
        Button(action: { Measure.used(measure); action() }) {
            HStack(spacing: LBSpacing.s2) {
                Text(title)
                    .lbText(.body)
                    .foregroundStyle(LBColor.onBrand.color)
                if let badge {
                    LBBadge(badge, tone: .positive)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, LBSpacing.s3)
            .background(LBColor.brand.color.opacity(enabled ? 1 : 0.4), in: RoundedRectangle(cornerRadius: LBRadius.sm, style: .continuous))
        }
        .lbButtonStyle()
        .disabled(!enabled)
    }

    private func field<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(LBSpacing.s3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(LBColor.card.color, in: RoundedRectangle(cornerRadius: LBRadius.xs, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: LBRadius.xs, style: .continuous)
                    .strokeBorder(LBColor.hairline.color, lineWidth: 1)
            )
    }

    // MARK: work

    /// Runs `go` once the reader has accepted that statements go to the AI; asks first if not.
    private func withConsent(_ go: @escaping () -> Void) {
        if consented { go(); return }
        afterConsent = go
        askingConsent = true
    }

    /// Cuts each file into pieces, a locked one waiting for its password, then reads them
    /// all at once on the server and looks each year over for people and repeats.
    private func start(_ urls: [URL]) {
        // The same files again keep their ids, and with them their budgets on the server.
        if files.map(\.url) != urls { files = urls.map { FileRead(url: $0) } }
        for index in files.indices {
            files[index].pieces = []
            files[index].plan = nil
            files[index].counts = nil
            files[index].prepared = nil
            files[index].unread = []
            files[index].problem = nil
        }
        problem = nil
        shareSpent = false
        played = false
        saved = false
        notSaved = nil
        run = ImportRun()
        doneUnits = 0
        lockedIndex = nil
        cut()
    }

    /// Reads the files in order on the device, off the main actor: each is planned by its
    /// lines or cut into pieces. The first locked one stops to ask for its password; a file
    /// that cannot be read is set aside with the reason.
    private func cut() {
        stage = .reading
        reading = Task {
            for index in files.indices where !files[index].isCut && files[index].problem == nil {
                let url = files[index].url
                let typed = password.isEmpty ? nil : password
                do {
                    let reading = try await Task.detached(priority: .userInitiated) { try StatementCloud.reading(for: url, password: typed) }.value
                    files[index].password = typed
                    password = ""
                    switch reading {
                    case .lines(let plan):
                        files[index].plan = plan
                        files[index].counts = StatementLinePass.Progress(lines: plan.lines.count, batches: plan.batches.count)
                    case .document(let pieces, _):
                        if pieces.isEmpty {
                            files[index].problem = "Nothing was read from \(files[index].name)."
                        } else {
                            files[index].pieces = pieces
                        }
                    }
                } catch StatementText.ReadError.locked {
                    lockedIndex = index
                    stage = .locked
                    return
                } catch StatementText.ReadError.wrongPassword {
                    lockedIndex = index
                    problem = StatementText.ReadError.wrongPassword.errorDescription
                    stage = .locked
                    return
                } catch {
                    Telemetry.shared.failed(.statementImport, error)
                    files[index].problem = "\(files[index].name): \(error.friendlyDescription)"
                }
            }
            lockedIndex = nil
            problem = nil
            guard files.contains(where: \.isCut) else {
                problem = files.compactMap(\.problem).joined(separator: "\n")
                stage = .pick
                countImport(ok: false)
                return
            }
            await readAll()
        }
    }

    /// Every file at once. The units are each file's calls; the bar lands on a mark as each
    /// comes back.
    private func readAll() async {
        let token = await auth.accessToken()
        let tags = model.commitmentTagNames
        let known = (members: model.memberNames, accounts: model.accountNames)
        let money = currency
        let readable = files.indices.filter { files[$0].isCut }
        units = Double(readable.reduce(0) { $0 + files[$1].units })
        doneUnits = 0
        expectedSeconds = ReadingBar.expected(lineFiles: readable.filter { files[$0].plan != nil }.count,
                                              pieces: readable.compactMap { files[$0].plan == nil ? files[$0].pieces.count : nil })
        await withTaskGroup(of: Void.self) { group in
            for index in readable {
                group.addTask { @MainActor in
                    await readFile(index, token: token, tags: tags, known: known, money: money)
                }
            }
        }
        let got = readable.filter { files[$0].prepared != nil }
        guard !got.isEmpty else {
            problem = (files.compactMap(\.problem) + files.flatMap(\.unread)).joined(separator: "\n")
            stage = .pick
            countImport(ok: false)
            return
        }
        guard !run.left else { return }
        // A new longbook's first statement must be recent before anything is laid out or saved.
        if checksFirstStatement {
            let periods = got.compactMap { files[$0].period }
            let outcome = FirstStatementCheck.judge(periods, today: LB.toISO(LB.todayMid()))
            guard outcome == .pass else { return turnAway(outcome) }
        }
        await show()
        guard !run.left else { return }
        await save()
    }

    /// The first run's first statement only: a longbook that holds an import, the demo and
    /// App Review's account take any statement.
    private var checksFirstStatement: Bool {
        guard inSetup, !model.isDemo, model.pastImports().isEmpty, model.importedChargeKeys().isEmpty else { return false }
        return !(model.signedInEmail.map(isReviewAccount) ?? false)
    }

    /// The reading set aside whole, as Pick Another File leaves it: nothing of it is kept.
    private func turnAway(_ outcome: FirstStatementCheck.Outcome) {
        countImport(outcome: outcome == .tooShort ? "too_short" : "not_recent")
        refusal = outcome
        refusedNames = files.filter { $0.prepared != nil }.map(\.name)
        password = ""
        problem = nil
        files = []
        lockedIndex = nil
        candidates = []
        repeats = []
        members = []
        foundAccounts = []
        stage = .notRecent
    }

    /// One file: the first piece alone, which names the account and is checked as a
    /// statement; the rest three at a time; then the look-over.
    @MainActor
    private func readFile(_ index: Int, token: String?, tags: [String], known: (members: [String], accounts: [String]), money: String) async {
        if let plan = files[index].plan {
            if await readLines(plan, index, token: token, tags: tags, known: known, money: money) { return }
            // Whatever went wrong with the lines, the document path still reads the file.
            do {
                let pieces = try StatementCloud.pieces(for: files[index].url, password: files[index].password)
                units += Double(pieces.count + 1)
                files[index].pieces = pieces
                files[index].plan = nil
            } catch {
                Telemetry.shared.failed(.statementImport, error)
                files[index].problem = "\(files[index].name): \(error.friendlyDescription)"
                return
            }
        }
        let pieces = files[index].pieces
        let id = files[index].importId
        var answers: [StatementCloud.ChargesAnswer?] = Array(repeating: nil, count: pieces.count)
        do {
            answers[0] = try await StatementCloud.charges(
                of: pieces[0], importId: id, accountHint: nil,
                categories: tags, members: known.members, accounts: known.accounts, currency: money, token: token
            )
        } catch StatementCloud.CloudError.shareSpent {
            shareSpent = true
            Telemetry.shared.send("app.statement_share_spent")
            files[index].problem = "\(files[index].name): not read, the server has read its share for now."
            return
        } catch StatementCloud.CloudError.notStatement(let said) {
            Telemetry.shared.send("app.statement_refused")
            files[index].problem = said
            return
        } catch {
            Telemetry.shared.failed(.statementImport, error)
            files[index].unread.append("\(pieces[0].label): \(error.friendlyDescription)")
        }
        advance()
        let hint = answers[0]?.account
        var first = 1
        while first < pieces.count {
            let batch = Array(first..<min(first + 3, pieces.count))
            let results = await withTaskGroup(of: (Int, Result<StatementCloud.ChargesAnswer, Error>).self,
                                              returning: [(Int, Result<StatementCloud.ChargesAnswer, Error>)].self) { group in
                for piece in batch {
                    let one = pieces[piece]
                    group.addTask {
                        do {
                            let answer = try await StatementCloud.charges(
                                of: one, importId: id, accountHint: hint,
                                categories: tags, members: known.members, accounts: known.accounts, currency: money, token: token
                            )
                            return (piece, .success(answer))
                        } catch {
                            return (piece, .failure(error))
                        }
                    }
                }
                var out: [(Int, Result<StatementCloud.ChargesAnswer, Error>)] = []
                for await result in group { out.append(result) }
                return out
            }
            for (piece, result) in results {
                switch result {
                case .success(let answer): answers[piece] = answer
                case .failure(let error):
                    Telemetry.shared.failed(.statementImport, error)
                    files[index].unread.append("\(pieces[piece].label): \(error.friendlyDescription)")
                }
            }
            advance(by: batch.count)
            first += batch.count
        }
        guard answers.contains(where: { $0 != nil }) else {
            files[index].problem = "\(files[index].name): " + files[index].unread.joined(separator: "; ")
            files[index].unread = []
            return
        }
        // The file's own reading, off the main actor, against what came back. A piece that
        // left lines out is asked once more, told which lines.
        let url = files[index].url
        let opened = files[index].password
        let expected = await Task.detached(priority: .userInitiated) { StatementCompleteness.expected(for: url, password: opened) }.value
        let firstLook = StatementCompleteness.compare(prepared: .assemble(answers.compactMap { $0 }, review: .empty), expected: expected)
        if !firstLook.missing.isEmpty {
            let again = StatementCompleteness.piecesToAskAgain(missing: firstLook.missing, pieces: pieces.count)
            await withTaskGroup(of: (Int, StatementCloud.ChargesAnswer?).self) { group in
                for (piece, lines) in again {
                    group.addTask {
                        let answer = try? await StatementCloud.charges(
                            of: pieces[piece], importId: id, accountHint: hint, categories: tags, members: known.members,
                            accounts: known.accounts, currency: money, token: token, hint: StatementCompleteness.hint(for: lines)
                        )
                        return (piece, answer)
                    }
                }
                for await (piece, answer) in group {
                    guard let answer else { continue }
                    answers[piece] = answers[piece].map { StatementCompleteness.merge($0, with: answer, missing: again[piece] ?? []) } ?? answer
                }
            }
        }
        let read = answers.compactMap { $0 }
        var prepared = StatementCloud.Prepared.assemble(read, review: .empty)
        let looked = (try? await StatementCloud.review(prepared, importId: id, categories: tags,
                                                        members: known.members, currency: money, token: token)) ?? .empty
        prepared = StatementCloud.Prepared.assemble(read, review: looked)
        let unread = files[index].unread
        if !unread.isEmpty { prepared.notes = (["Not read: " + unread.joined(separator: "; ") + "."] + [prepared.notes]).joined(separator: " ") }
        // Lines still missing are read from the file itself, ticked and marked so.
        prepared = StatementCompleteness.mended(prepared, expected: expected)
        let report = StatementCompleteness.compare(prepared: prepared, expected: expected)
        files[index].filled = StatementCompleteness.fill(missing: report.missing, among: tags)
        finish(index, prepared: prepared, report: report, expected: expected)
    }

    /// A file by the lines the device read: the model names them as the batches return.
    /// False when the file should be read as a document instead; a share spent or a file
    /// refused ends here, as the document path's first piece would.
    @MainActor
    private func readLines(_ plan: StatementLinePass.Plan, _ index: Int, token: String?, tags: [String],
                           known: (members: [String], accounts: [String]), money: String) async -> Bool {
        let asking = StatementLinePass.Asking(importId: files[index].importId, categories: tags, members: known.members,
                                              accounts: known.accounts, currency: money)
        do {
            let outcome = try await StatementLinePass.read(plan, asking: asking, transport: { try await StatementCloud.post($0, token: token) }) { state in
                await MainActor.run {
                    let before = files[index].counts?.batchesDone ?? 0
                    files[index].counts = state
                    if state.batchesDone > before { advance(by: state.batchesDone - before) }
                }
            }
            advance()
            finish(index, prepared: outcome.prepared, report: outcome.report, expected: plan.expected)
            return true
        } catch StatementCloud.CloudError.shareSpent {
            shareSpent = true
            Telemetry.shared.send("app.statement_share_spent")
            files[index].problem = "\(files[index].name): not read, the server has read its share for now."
            return true
        } catch StatementCloud.CloudError.notStatement(let said) {
            Telemetry.shared.send("app.statement_refused")
            files[index].problem = said
            return true
        } catch {
            Telemetry.shared.failed(.statementImport, error)
            return false
        }
    }

    /// A file's reading laid in, by whichever path it took.
    @MainActor
    private func finish(_ index: Int, prepared: StatementCloud.Prepared, report: StatementCompleteness.Report,
                        expected: StatementCompleteness.Expected?) {
        files[index].report = report
        files[index].prepared = prepared
        // The period the file prints, else its dated lines: the device's own when it read
        // any, the server's otherwise.
        let lines = expected?.lines.map(\.date) ?? []
        files[index].period = FirstStatementCheck.period(printed: expected?.period,
                                                         dates: lines.isEmpty ? prepared.charges.map(\.date) : lines)
        // The currency the statement prints: a pound statement read with a rupee guess was
        // written in rupees.
        if let printed = prepared.currency { currency = printed }
        files[index].account = prepared.account
        files[index].balance = prepared.balance
        files[index].balanceDate = prepared.balanceDate
        advance()
    }

    /// A unit came back, for the bar.
    private func advance(by count: Int = 1) {
        doneUnits += count
    }

    /// The answers laid out for the one write: every file's lines in one list, keyed to its
    /// file; the people and repeats of all of them together. The rules run off the main
    /// thread: they read every line of every file.
    @MainActor
    private func show() async {
        var found: [StatementCandidate] = []
        var seenRepeats: [StatementCloud.Repeat] = []
        var seenMembers: [StatementCloud.Member] = []
        for index in files.indices {
            guard var prepared = files[index].prepared else { continue }
            // The holder is called as the book calls them, so they are never a second person.
            if let holder = prepared.holder {
                prepared = prepared.calling(holder: StatementHolder.resolve(holder, among: model.memberNames))
                files[index].prepared = prepared
            }
            var mine = prepared.candidates(among: model.commitmentTagNames, book: model.statementBook) + files[index].filled
            for i in mine.indices { mine[i].file = files[index].id }
            found += mine
            for repeated in prepared.repeats where !seenRepeats.contains(where: { $0.name.caseInsensitiveCompare(repeated.name) == .orderedSame }) {
                seenRepeats.append(repeated)
            }
            for member in prepared.members where !seenMembers.contains(where: { $0.name.caseInsensitiveCompare(member.name) == .orderedSame }) {
                seenMembers.append(member)
            }
        }
        // A person a line names is a person on the statement, whether the look-over listed them.
        for name in found.compactMap(\.member) where !seenMembers.contains(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            seenMembers.append(StatementCloud.Member(name: name, role: "", reason: "Named on a line"))
        }
        StatementImport.markAlreadyPresent(&found, in: model.importedChargeKeys())
        StatementImport.markCorrectedLinesPresent(&found, held: model.heldStatementLines(),
                                                  accounts: Dictionary(files.map { ($0.id, $0.account) }, uniquingKeysWith: { first, _ in first }))
        // What the model saw, plus the rhythms the rules see in the same charges, settled here.
        var seen = seenRepeats
        let named = Set(seen.map { $0.name.lowercased() })
        for ruled in StatementImport.repeats(in: found) where !named.contains(ruled.name.lowercased()) {
            seen.append(StatementCloud.Repeat(name: ruled.name, cycle: ruled.cycle.rawValue, customDays: ruled.customDays,
                                              amount: ruled.amount, dates: ruled.dates, category: nil, endsOn: nil,
                                              guessed: ruled.guessed, reason: ruled.reason))
        }
        let lines = found, proposed = seen, holders = files.compactMap { $0.prepared?.holder }
        let settled = await Task.detached(priority: .userInitiated) {
            StatementRepeats.settle(proposed, candidates: lines, holders: holders)
        }.value
        candidates = settled.candidates
        repeats = settled.repeats
        // The other side of each transfer and card payment: an account or a person the book
        // does not hold yet, matched loosely, the people among the names to tick.
        var others = StatementCounterparts.Found()
        for read in files {
            guard let prepared = read.prepared else { continue }
            let more = prepared.counterparts(knownAccounts: model.statementBook.accounts + files.map { StatementBook.Account(name: $0.account, owner: $0.prepared?.holder) }
                                                + others.accounts.map { StatementBook.Account(name: $0.name, owner: $0.person) },
                                             knownPeople: model.heldMemberNames + seenMembers.map(\.name) + others.people)
            others.accounts += more.accounts
            others.people += more.people
        }
        seenMembers += others.people.map { StatementCloud.Member(name: $0, role: "", reason: "Named on a transfer") }
        members = seenMembers
        foundAccounts = others.accounts
    }

    /// The one write, whole, as a review with everything kept, and the files it files. With the
    /// switch off, statements add no people or accounts of their own accord.
    private func reviewToWrite() -> (review: StatementImport.Review, statements: [URL]) {
        var rows = candidates
        // A person found is a person in the book, whatever the lines say; the lines that name
        // them carry them. With the switch off they stay names on the lines.
        var chosen = StatementFinds.on ? members.map(\.name) : []
        let heldNames = model.heldMemberNames
        // With the switch on, a person a kept line names is added too, matched loosely.
        if StatementFinds.on {
            for row in rows where row.keep {
                guard let named = row.member?.trimmingCharacters(in: .whitespacesAndNewlines), !named.isEmpty,
                      !(chosen + heldNames).contains(where: { nameKey($0) == nameKey(named) }) else { continue }
                chosen.append(named)
            }
        }
        // Each statement's holder is a person and Self, whatever is ticked.
        for holder in files.compactMap({ $0.prepared?.holder }) where !chosen.contains(holder) { chosen.append(holder) }
        for index in rows.indices {
            if let member = rows[index].member, !chosen.contains(member),
               !heldNames.contains(where: { nameKey($0) == nameKey(member) }) {
                rows[index].member = nil
            } else if rows[index].member == nil, rows[index].keep,
                      let carried = chosen.first(where: { Self.names($0, in: rows[index]) }) {
                rows[index].member = carried
            }
        }
        // A line that belongs to a recurring commitment the book already holds is that
        // commitment's charge, never a twin: those rows go on as charges, the rest as
        // one-time rows. It must move the same way: a transfer never joins a spend.
        let recurring = model.commitmentIdNames.filter { $0.cycle != .once }
        var reviewed: [StatementImport.ReviewFile] = []
        var statements: [URL] = []
        // Each file lands on its own account, from its own copy in documents.
        for read in files where read.prepared != nil {
            var attached: [(id: String, charges: [[String: Any]])] = []
            var ownRows: [StatementCandidate] = []
            for row in rows where row.file == read.id {
                if row.keep, let home = recurring.first(where: {
                    $0.name.caseInsensitiveCompare(row.name) == .orderedSame
                        && VaultPatch.storedDirection(model.subscription(id: $0.id)?.direction) == VaultPatch.storedDirection(row.direction)
                }) {
                    var charge: [String: Any] = ["date": row.line.date, "amount": row.line.amount, "paid": true, "basis": "statement"]
                    let line = StatementNaming.scrubbed(row.line.payee)
                    if !line.isEmpty { charge["note"] = StatementImport.notePrefix + line }
                    if let at = attached.firstIndex(where: { $0.id == home.id }) { attached[at].charges.append(charge) } else { attached.append((home.id, [charge])) }
                } else {
                    ownRows.append(row)
                }
            }
            reviewed.append(StatementImport.ReviewFile(
                rows: ownRows, attached: attached, account: read.account.trimmingCharacters(in: .whitespaces),
                addsAccount: StatementFinds.on, source: nil,
                balance: read.balance, balanceDate: read.balanceDate, owner: read.prepared?.holder))
            statements.append(read.url)
        }
        // A repeat becomes one recurring commitment over the lines it names, planned ahead. One
        // with no lines to carry waits on the timeline with the ones setup named.
        let found = repeats.map {
            (repeated: $0, placeholder: CommitmentPlaceholder(name: $0.name, group: $0.dates.isEmpty ? "Named" : cycleWord($0).capitalized,
                                                                tag: $0.category ?? ""))
        }
        // A statement read again adds nobody: a person or an account comes in only with a line
        // that is being added, however the reader spelled them this time.
        var addingAccounts = StatementFinds.on ? foundAccounts : []
        if rows.contains(where: { $0.skipReason?.hasPrefix("already in") == true }) {
            let kept = rows.filter(\.keep)
            let holders = files.compactMap { $0.prepared?.holder }
            chosen.removeAll { name in
                !holders.contains(name) && !kept.contains { $0.member.map(nameKey) == nameKey(name) }
            }
            addingAccounts.removeAll { account in
                !kept.contains { $0.counterpartAccount.map(nameKey) == nameKey(account.name) }
            }
        }
        let review = StatementImport.Review(members: chosen, accounts: addingAccounts,
                                            files: reviewed, currency: money, repeats: found, waiting: model.placeholders)
        return (review, statements)
    }

    /// The one write, right after reading. A refusal writes nothing and says so here, with a
    /// way to try again that reads nothing twice.
    private func save() async {
        guard !adding, !run.left else { return }
        adding = true
        defer { adding = false }
        notSaved = nil
        let plan = reviewToWrite()
        let before = Set(model.commitmentIdNames.map { $0.id })
        do {
            var written = try await model.importReview(plan.review, statements: plan.statements)
            // An import that moved no row added nothing to Past Imports.
            if !vaultDiff(from: written.before, to: written.written.vault).isEmpty {
                written.records = files.compactMap { read in read.report.map { ImportRecord(file: read.name, date: LB.toISO(LB.todayMid()), report: $0) } }
                model.recordImports(written.records)
            }
            countImport(ok: true, charges: written.written.charges)
            countCompleteness(written.written.vault, before: before)
            let was = written.before, now = written.written.vault
            let read = await Task.detached(priority: .userInitiated) { StatementTour.findings(before: was, after: now) }.value
            savedImport = written
            findings = read
            tourFound = read
            tourPeople = read.people
            saved = true
            // A game being played finishes on its own terms; otherwise the steps open by themselves.
            if !played {
                try? await Task.sleep(for: .milliseconds(reduceMotion ? 0 : 350))
                if !run.left { openTour() }
            }
        } catch {
            Telemetry.shared.failed(.statementImport, error)
            notSaved = error.friendlyDescription
            countImport(outcome: "add_failed")
        }
    }

    /// Whatever closes the sheet: a reading still running stops, and never writes.
    private func leave() {
        run.left = true
        reading?.cancel()
    }

    /// Usage count for an import that ended: how it ended, and how many charges it wrote.
    /// Nothing from the statement itself. A failed add can be retried, so it is told apart.
    private func countImport(ok: Bool, charges: Int = 0) {
        countImport(outcome: ok ? "ok" : "failed", charges: charges)
    }

    /// With it the batch's size: files, pieces, PDFs, kilobytes rounded to fifty. Never a line.
    private func countImport(outcome: String, charges: Int = 0) {
        let bytes = files.reduce(0) { $0 + $1.pieces.reduce(0) { $0 + $1.data.utf8.count } } * 3 / 4
        Telemetry.shared.send("app.statement_imported", [
            "outcome": outcome, "charge_count": charges, "file_count": files.count,
            "piece_count": files.reduce(0) { $0 + $1.pieces.count },
            "pdf_count": files.filter { StatementText.kind(of: $0.url) == .pdf }.count,
            "line_read_count": files.filter { $0.plan != nil }.count,
            "kb_total": Int((Double(bytes) / 1024 / 50).rounded()) * 50,
        ])
    }

    /// Usage count for the walk through the cards, when it ends: cards found and taken out per
    /// kind, and the kind of each commitment taken out. Counts and fixed words; never a name.
    private func countTour(_ ending: StatementTour.Ending) {
        guard let saved = savedImport else { return }
        Telemetry.shared.send("app.import_review_ended",
                              StatementTour.endProperties(ending, found: tourFound, removed: [.people: peopleRemoved], vault: saved.written.vault))
    }

    /// Usage count for what the reading proved: lines read against the file's own count,
    /// lines filled from the file, the balance verdicts, and the written vault's findings
    /// by kind. Counts only.
    private func countCompleteness(_ vault: [String: Any], before: Set<String>) {
        let reports = files.compactMap(\.report)
        let ids = Set((vault["commitments"] as? [[String: Any]] ?? []).compactMap { $0["id"] as? String }).subtracting(before)
        var props: [String: Any] = [
            "file_count": files.filter { $0.prepared != nil }.count,
            "read": reports.reduce(0) { $0 + $1.read },
            "expected": reports.compactMap(\.expectedCount).reduce(0, +),
            "unchecked_count": reports.filter { $0.expectedCount == nil }.count,
            "filled": reports.reduce(0) { $0 + $1.missing.count },
            "extra": reports.reduce(0) { $0 + $1.extra },
            "balance_matches": reports.filter { $0.balance == .matches }.count,
            "balance_off": reports.filter { if case .off = $0.balance { return true } else { return false } }.count,
            "balance_unknown": reports.filter { $0.balance == .unknown }.count,
        ]
        for finding in StatementCompleteness.check(vault: vault, importedIds: ids) { props["finding_" + finding.kind] = finding.count }
        Telemetry.shared.send("app.statement_completeness", props)
    }

    /// Whether a line names this person — as a whole word in what it is called or what
    /// the statement said, so "Anil" is found and "Anila" is not.
    private static func names(_ member: String, in candidate: StatementCandidate) -> Bool {
        let wanted = member.lowercased()
        for text in [candidate.name, candidate.line.payee] {
            let words = text.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init)
            if words.contains(wanted) { return true }
        }
        return false
    }
}

/// The window behind the import, blurred while the import sits over it, from whichever screen
/// opened it. The root view reads it.
@MainActor
@Observable
final class ImportBackdrop {
    static let shared = ImportBackdrop()
    var active = false
    /// How far it blurs: its words only just visible.
    static let radius: CGFloat = 14
}

extension Notification.Name {
    /// The import's Open Dashboard, from whichever screen opened it.
    static let longbookOpenDashboard = Notification.Name("longbook.openDashboard")
}

/// A reading in flight, shared with its tasks. A box because the sheet may be gone by the time
/// a task asks.
@MainActor
private final class ImportRun {
    var left = false
}

/// The Settings switch "Add accounts and people found in statements", on unless turned
/// off. On, a statement adds its own account, the accounts and people its transfers go to,
/// and every person its lines name; off, Accounts and People list only what the owner adds.
enum StatementFinds {
    static let key = "longbook.statements.addFound"
    static var on: Bool { UserDefaults.standard.object(forKey: key) as? Bool ?? true }
    static let onDetail = "On: a statement adds its account, the accounts its transfers go to and the people it names to Accounts and People."
    static let offDetail = "Off: statements still name them for your AI, but Accounts and People list only what you add."
}
