import DesignSystem
import LongbookCore
import SwiftUI
import UniformTypeIdentifiers

/// Statements in, one review out: every file goes to longbook's server a few pages at a
/// time, all at once, and comes back as charges; each year goes once more for its people
/// and rhythms; the owner ticks and adds, and it lands in Changes, undoable.
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
    let onDone: () -> Void

    private enum Stage: Equatable { case pick, working(String), locked, ready, review, added(Int, Int, Int) }

    /// How many files one pick may hold.
    static let filesAtOnce = 5

    /// One file of the batch: its pieces, how far its reading has come, its answer, and
    /// the account it is as the review edits it. `id` keys its lines among the candidates.
    private struct FileRead: Identifiable {
        let id = UUID().uuidString
        let url: URL
        /// The server counts every piece and the review of a file against this.
        var importId = StatementCloud.newImportId()
        var pieces: [StatementCloud.Piece] = []
        /// The piece under way, for the progress list.
        var word = ""
        var prepared: StatementCloud.Prepared?
        var unread: [String] = []
        /// Why nothing came of it: refused as not a statement, or failed.
        var problem: String?
        var account = ""
        var balance: Double?
        var balanceDate: String?
        var name: String { url.lastPathComponent }
    }

    /// A repeat being filled in as a commitment, as a sheet's item, with the book's
    /// commitments as they were when the form opened — what it makes is what is new.
    private struct Filling: Identifiable {
        let repeated: StatementCloud.Repeat
        let before: Set<String>
        var id: String { repeated.name }
    }

    /// PDF, CSV, text and Excel — the shapes banks hand out. The Excel types are named by
    /// identifier so a device without them registered simply offers fewer.
    private static let pickable: [UTType] = [.pdf, .commaSeparatedText, .plainText]
        + ["org.openxmlformats.spreadsheetml.sheet", "com.microsoft.excel.xls"].compactMap(UTType.init)

    @State private var stage: Stage = .pick
    @State private var picking = false
    /// Accepted once on this device before any statement leaves it; until then a pick or a
    /// drop waits behind the consent sheet.
    @AppStorage(AIConsent.statements.key) private var consented = false
    @State private var askingConsent = false
    @State private var afterConsent: (() -> Void)?
    @State private var password = ""
    /// The files picked, in the order picked; each is its own reading on the server.
    @State private var files: [FileRead] = []
    /// The file waiting for its password, while the others wait behind it.
    @State private var lockedIndex: Int?
    @State private var candidates: [StatementCandidate] = []
    @State private var repeats: [StatementCloud.Repeat] = []
    @State private var chosenRepeats: Set<String> = []
    @State private var members: [StatementCloud.Member] = []
    @State private var chosenMembers: Set<String> = []
    @State private var notes = ""
    @State private var currency = "INR"
    /// Whether the reader typed the currency. Until then the statement's own wins.
    @State private var currencyTyped = false
    @State private var problem: String?
    /// The server has read its share of statements for this account for now; the pick
    /// stage says so, with the way to write to us. How many is never said.
    @State private var shareSpent = false
    /// The lines show from the start; the summary row above them folds them away.
    @State private var showingCharges = true
    /// The review, one kind at a time: the lines, the people, the repeats.
    @State private var reviewTab = 0
    #if os(iOS)
    @State private var openLine: OpenLine?
    #else
    @State private var lineOrder: [KeyPathComparator<LineRow>] = [KeyPathComparator(\.date)]
    #endif
    /// The privacy line under the file types, opened from its info button.
    /// A member's name being corrected, and the correction as typed.
    @State private var renaming: String?
    @State private var renamed = ""
    /// A repeat's name being corrected, and the correction as typed.
    @State private var renamingRepeat: String?
    @State private var renamedRepeat = ""
    /// A name being added by hand under members or under commitments.
    @State private var addingMember = false
    @State private var typedMember = ""
    @State private var addingRepeat = false
    @State private var typedRepeat = ""
    /// The cursor in whichever line was just revealed, and the names the review scrolls to.
    @FocusState private var memberFocused: Bool
    @FocusState private var repeatFocused: Bool
    private static let memberFieldID = "lb-new-member"
    private static let repeatFieldID = "lb-new-repeat"
    @State private var filling: Filling?
    /// The other way in, opened on request: the owner's own AI.
    @State private var ownAI = false
    @State private var confirmingClose = false
    /// How far the reading has come, as a share; it creeps while a piece is being read
    /// and lands on the mark when the piece comes back.
    @State private var progress = 0.0
    @State private var creeping: Task<Void, Never>?
    /// A file is being dragged over the Mac's drop zone.
    @State private var dropping = false

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

    /// The column the sheet keeps to; the Mac's review table takes a wider one.
    private var columnWidth: CGFloat {
        #if os(macOS)
        stage == .review ? 960 : 640
        #else
        640
        #endif
    }
    /// The units of the reading — every piece of every file, and each file's look-over —
    /// and how many are done.
    @State private var units = 1.0
    @State private var doneUnits = 0

    var body: some View {
        VStack(alignment: .leading, spacing: LBSpacing.s3) {
            header
            switch stage {
            case .pick: pickStage
            case .working(let word): workingStage(word)
            case .locked: lockedStage
            case .ready: readyStage
            case .review: reviewStage
            case .added(let charges, let made, let waiting): addedStage(charges, made, waiting)
            }
        }
        .padding(LBSpacing.s4)
        .frame(maxWidth: columnWidth)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        #if os(macOS)
        // The review's table wants every column in view: the sheet grows for it.
        .frame(minWidth: stage == .review ? 800 : 520, minHeight: 560)
        #endif
        .background(LBColor.canvas.color)
        .lbClosesOnOutsideClick(onDone)
        // A pull-down with a statement read would lose it; the close button asks instead.
        .interactiveDismissDisabled(stage != .pick)
        .measured("statement_import_confirming_close", .dialog, when: confirmingClose)
        .confirmationDialog("Leave the import?", isPresented: $confirmingClose, titleVisibility: .visible) {
            Button("Leave", role: .destructive, action: { Measure.used("leave"); onDone() })
            Button("Stay", role: .cancel) { Measure.used("stay") }
        } message: {
            Text("What was read is not kept.")
        }
        .onAppear {
            // With no home currency, the phone's own region: a London phone starts in pounds.
            currency = model.homeCurrency ?? Locale.current.currency?.identifier ?? "INR"
            // After the sheet has risen, so the consent or the picker is not refused mid-presentation.
            if picksOnOpen, stage == .pick {
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
                show()
                if ProcessInfo.processInfo.environment["LONGBOOK_SNAPSHOT_READY"] == nil { stage = .review }
                #if os(iOS)
                if let line = ProcessInfo.processInfo.environment["LONGBOOK_SNAPSHOT_LINE"].flatMap(Int.init),
                   candidates.indices.contains(line) { openLine = OpenLine(id: line) }
                #endif
            }
            if ProcessInfo.processInfo.environment["LONGBOOK_SNAPSHOT_OWN_AI"] != nil { ownAI = true }
            if ProcessInfo.processInfo.environment["LONGBOOK_SNAPSHOT_CONSENT"] != nil { askingConsent = true }
            if ProcessInfo.processInfo.environment["LONGBOOK_SNAPSHOT_LIMIT"] != nil {
                shareSpent = true
            }
            if ProcessInfo.processInfo.environment["LONGBOOK_SNAPSHOT_WORKING"] != nil {
                files = [FileRead(url: URL(fileURLWithPath: "hdfc-savings-2025-2026.pdf"))]
                progress = 0.42
                stage = .working("Reading hdfc-savings-2025-2026.pdf")
            }
            #endif
        }
        .fileImporter(isPresented: $picking, allowedContentTypes: Self.pickable, allowsMultipleSelection: true) { result in
            guard case .success(let urls) = result, !urls.isEmpty else { return }
            start(Array(urls.prefix(Self.filesAtOnce)))
        }
        .measured("statement_import_own_ai", .sheet, when: ownAI)
        .sheet(isPresented: $ownAI) { ownAISheet }
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
        }
        #if os(iOS)
        .measured("statement_import_open_line", .sheet, when: openLine != nil)
        .sheet(item: $openLine) { line in lineDetail(line.id) }
        #endif
        .measured("statement_import_filling", .sheet, when: filling != nil)
        .sheet(item: $filling) { item in
            RenewalFormView(
                model: model, editingId: nil,
                seedCategory: item.repeated.category, seedName: item.repeated.name,
                seedAmount: item.repeated.amount, seedCycle: BillingCycle(rawValue: item.repeated.cycle) ?? .monthly,
                seedCustomDays: item.repeated.customDays
            ) {
                // Whatever the form made is the repeat, under whichever name it was given:
                // the pill goes, and the statement's lines take the new name so they land
                // as that commitment's charges.
                if let made = model.commitmentIdNames.first(where: { !item.before.contains($0.id) }) {
                    repeats.removeAll { $0.name == item.repeated.name }
                    chosenRepeats.remove(item.repeated.name)
                    for index in candidates.indices where candidates[index].name.caseInsensitiveCompare(item.repeated.name) == .orderedSame {
                        candidates[index].name = made.name
                    }
                }
                filling = nil
            }
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
                // the statement stays the one path on this screen.
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

    /// The share spent, as a quiet notice: what happened, the way to write to us, and the
    /// own-AI door below it. How many reads there were is never said.
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
                Text("longbook’s server has read all the statements it can for your account for now. Your own AI can read the rest, below.")
                    .lbText(.footnote)
                    .foregroundStyle(LBColor.textSecondary.color)
                    .fixedSize(horizontal: false, vertical: true)
                // The mail carries the install id, so what the account did can be seen before more is read for it.
                if let mail = FeedbackMail.statementShare(installId: Telemetry.shared.installIdIfSharing) {
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

    /// The piece under way named over a bar, and a small game for the minute each piece
    /// takes. The answer goes straight to the review.
    private func workingStage(_ word: String) -> some View {
        VStack(alignment: .leading, spacing: LBSpacing.s3) {
            Text(word)
                .lbText(.body)
                .foregroundStyle(LBColor.textSecondary.color)
                .fixedSize(horizontal: false, vertical: true)
            ProgressView(value: progress)
                .tint(LBColor.brand.color)
                .animation(.easeOut(duration: 0.4), value: progress)
            if files.count > 1 {
                VStack(alignment: .leading, spacing: LBSpacing.s1) {
                    ForEach(files) { read in
                        HStack(spacing: LBSpacing.s2) {
                            Text(read.name)
                                .lbText(.footnote)
                                .foregroundStyle(LBColor.textSecondary.color)
                                .lineLimit(1)
                            Spacer(minLength: LBSpacing.s2)
                            Text(read.problem != nil ? "Not read" : read.prepared != nil ? "Read" : read.word.isEmpty ? "Waiting" : read.word)
                                .lbText(.footnote)
                                .foregroundStyle(LBColor.textTertiary.color)
                                .lineLimit(1)
                        }
                    }
                }
            }
            WaitingGame()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.top, LBSpacing.s2)
            TipsTicker()
                .padding(.top, LBSpacing.s2)
        }
    }

    /// The reading finished: the bar full, the game still there, and the review a tap away.
    private var readyStage: some View {
        VStack(alignment: .leading, spacing: LBSpacing.s3) {
            Text("Done reading \(files.count == 1 ? files[0].name : "\(files.filter { $0.prepared != nil }.count) statements").")
                .lbText(.body)
                .foregroundStyle(LBColor.textSecondary.color)
                .fixedSize(horizontal: false, vertical: true)
            ProgressView(value: 1)
                .tint(LBColor.brand.color)
            WaitingGame()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.top, LBSpacing.s2)
            primary("Review \(candidates.count) \(candidates.count == 1 ? "Item" : "Items")") {
                withAnimation(.easeOut(duration: 0.2)) { stage = .review }
            }
        }
    }

    private var lockedStage: some View {
        VStack(alignment: .leading, spacing: LBSpacing.s3) {
            Text(lockedIndex.map { files[$0].name } ?? "This statement")
                .lbText(.body)
                .foregroundStyle(LBColor.textPrimary.color)
                .lineLimit(2)
            Text("This statement is locked. Enter the password the bank set for it — the email that carried the statement usually says what it is. It is used once, here, to open the file, and not kept.")
                .lbText(.bodySM)
                .foregroundStyle(LBColor.textSecondary.color)
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
                    #endif
                    .onSubmit { if !password.isEmpty { cut() } }
            }
            if let problem {
                Text(problem)
                    .lbText(.footnote)
                    .foregroundStyle(LBColor.urgent.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
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
                    .frame(maxWidth: .infinity, minHeight: 32)
                    .contentShape(Rectangle())
            }
            .lbButtonStyle()
        }
    }

    private var reviewStage: some View {
        VStack(alignment: .leading, spacing: LBSpacing.s3) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: LBSpacing.s4) {
                        // Laid out as Changes is: what this is, the two answers, what they
                        // cover, then one kind at a time, since a year's statement is
                        // hundreds of lines and its people and repeats need room of their own.
                        reviewAnswer
                        reviewTabs
                        switch reviewTab {
                        case 1: membersSection
                        case 2: repeatsSection
                        default: chargesSection
                        }
                        if !notes.isEmpty {
                            VStack(alignment: .leading, spacing: LBSpacing.s1) {
                                Text("Notes from the statement")
                                    .lbText(.footnote)
                                    .foregroundStyle(LBColor.textTertiary.color)
                                Text(notes)
                                    .lbText(.footnote)
                                    .foregroundStyle(LBColor.textSecondary.color)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(.horizontal, LBSpacing.s1)
                        }
                    }
                }
                // A line revealed at the end of a wrapping row can sit below the fold, and
                // below the keyboard. The sleep lets it exist before it is scrolled to.
                .onChange(of: addingMember) { _, adding in
                    if adding { reveal(Self.memberFieldID, with: proxy) }
                }
                .onChange(of: addingRepeat) { _, adding in
                    if adding { reveal(Self.repeatFieldID, with: proxy) }
                }
            }
        }
    }

    /// The import's own Undo All and Keep All: Discard asks first, Add writes what is ticked.
    private var reviewAnswer: some View {
        VStack(alignment: .leading, spacing: LBSpacing.s2) {
            Text("Read from \(files.count == 1 ? files[0].name : "\(files.count) files"). Untick what you don’t want, then add the rest.")
                .lbText(.bodySM)
                .foregroundStyle(LBColor.textSecondary.color)
                .fixedSize(horizontal: false, vertical: true)
            LBReflowStack(spacing: LBSpacing.s2) {
                Button { Measure.used("discard"); confirmingClose = true } label: {
                    ChangeActionLabel(title: "Discard", symbol: "xmark", filled: false, wide: true)
                }
                .lbButtonStyle()
                Button { Measure.used("checkmark_circle_fill"); add() } label: {
                    ChangeActionLabel(title: addTitle, symbol: "checkmark.circle.fill", filled: true, wide: true)
                }
                .lbButtonStyle()
                .disabled(keptCount == 0 || !accountsNamed)
                .lbPhoneDimmed(keptCount == 0 || !accountsNamed)
            }
            if let tally = reviewTally {
                Text(tally)
                    .lbText(.footnote)
                    .foregroundStyle(LBColor.textTertiary.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let problem {
                Text(problem)
                    .lbText(.footnote)
                    .foregroundStyle(LBColor.urgent.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// What Add covers, as Changes counts its rows: the lines, then the people and repeats.
    private var reviewTally: String? {
        var parts = chargesTally.map { [$0] } ?? []
        let people = members.count
        if people > 0 { parts.append("\(people) \(people == 1 ? "person" : "people")") }
        if !repeats.isEmpty { parts.append("\(repeats.count) repeat\(repeats.count == 1 ? "" : "s")") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var reviewTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: LBSpacing.s2) {
                ChangeKindTab(title: "Charges", count: candidates.count, selected: reviewTab == 0) { pickTab(0) }
                ChangeKindTab(title: "People", count: members.count, selected: reviewTab == 1) { pickTab(1) }
                ChangeKindTab(title: "Repeats", count: repeats.count, selected: reviewTab == 2) { pickTab(2) }
            }
        }
    }

    private func pickTab(_ tab: Int) {
        LBHaptics.tap()
        withAnimation(.snappy(duration: 0.25)) { reviewTab = tab }
    }

    /// What the button adds: every kept line, whatever it is — a charge, money in, a transfer.
    private var addTitle: String {
        keptCount > 0 ? "Add \(keptCount) \(keptCount == 1 ? "Item" : "Items")" : "Nothing to Add"
    }

    /// Who the statement says deserves a member entry, as names to tick, and a plus for
    /// one it missed. A long press renames one; the lines that carry the name follow it.
    private var membersSection: some View {
        VStack(alignment: .leading, spacing: LBSpacing.s2) {
            LBSectionHeader("People")
                .foregroundStyle(LBColor.textTertiary.color)
                .padding(.horizontal, LBSpacing.s1)
            LBFlow {
                ForEach(members, id: \.name) { member in
                    LBChip(member.name, style: .choice(selected: chosenMembers.contains(member.name))) {
                        if chosenMembers.contains(member.name) { chosenMembers.remove(member.name) } else { chosenMembers.insert(member.name) }
                    }
                    .contextMenu {
                        Button("Rename") {
                            Measure.used("rename", .contextMenu)
                            renamed = member.name
                            renaming = member.name
                        }
                    }
                }
                if addingMember {
                    LBChipField("Their name", text: $typedMember, width: 160,
                                focus: $memberFocused, onSubmit: addMember)
                        .id(Self.memberFieldID)
                } else {
                    LBChip("Add", symbol: "plus", style: .accent) {
                        typedMember = ""
                        addingMember = true
                    }
                    .accessibilityLabel("Add a person")
                }
            }
            Text("Names on the statement. Ticked ones are added to People.")
                .lbText(.footnote)
                .foregroundStyle(LBColor.textTertiary.color)
                .padding(.horizontal, LBSpacing.s1)
                .fixedSize(horizontal: false, vertical: true)
        }
        .measured("statement_import_renaming", .alert, when: renaming != nil)
        .alert("Their name", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } }), presenting: renaming) { old in
            TextField("Name", text: $renamed)
            Button("Save") { Measure.used("save"); rename(old, to: renamed) }
            Button("Cancel", role: .cancel) { Measure.used("cancel") }
        } message: { _ in
            Text("As you would write it on a commitment.")
        }
    }

    /// What repeats, as names to tick, and a plus for one the statement did not show.
    /// Ticked, each becomes a commitment over its lines; a long press fills one in by hand.
    private var repeatsSection: some View {
        VStack(alignment: .leading, spacing: LBSpacing.s2) {
            LBSectionHeader("Repeating payments")
                .foregroundStyle(LBColor.textTertiary.color)
                .padding(.horizontal, LBSpacing.s1)
            LBFlow {
                ForEach(repeats, id: \.name) { repeated in
                    LBChip(repeatWord(repeated), style: .choice(selected: chosenRepeats.contains(repeated.name))) {
                        if chosenRepeats.contains(repeated.name) { chosenRepeats.remove(repeated.name) } else { chosenRepeats.insert(repeated.name) }
                    }
                    .contextMenu {
                        Button { Measure.used("fill_in_the_details", .contextMenu); filling = Filling(repeated: repeated, before: Set(model.commitmentIdNames.map(\.id))) } label: {
                            Label("Fill in the details", systemImage: "pencil")
                        }
                        Button {
                            Measure.used("rename", .contextMenu)
                            renamedRepeat = repeated.name
                            renamingRepeat = repeated.name
                        } label: {
                            Label("Rename", systemImage: "character.cursor.ibeam")
                        }
                    }
                }
                if addingRepeat {
                    LBChipField("What it is", text: $typedRepeat, width: 160,
                                focus: $repeatFocused, onSubmit: addRepeat)
                        .id(Self.repeatFieldID)
                } else {
                    LBChip("Add", symbol: "plus", style: .accent) {
                        typedRepeat = ""
                        addingRepeat = true
                    }
                    .accessibilityLabel("Add a commitment")
                }
            }
            Text("Ticked ones become commitments, planned ahead.")
                .lbText(.footnote)
                .foregroundStyle(LBColor.textTertiary.color)
                .padding(.horizontal, LBSpacing.s1)
                .fixedSize(horizontal: false, vertical: true)
        }
        .measured("statement_import_renaming_repeat", .alert, when: renamingRepeat != nil)
        .alert("Its name", isPresented: Binding(get: { renamingRepeat != nil }, set: { if !$0 { renamingRepeat = nil } }), presenting: renamingRepeat) { old in
            TextField("Name", text: $renamedRepeat)
            Button("Save") { Measure.used("save"); renameRepeat(old, to: renamedRepeat) }
            Button("Cancel", role: .cancel) { Measure.used("cancel") }
        } message: { _ in
            Text("As you would say it. The statement’s lines take the name too.")
        }
    }

    private func renameRepeat(_ old: String, to new: String) {
        let clean = new.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, clean != old else { return }
        repeats = repeats.map { $0.name == old
            ? StatementCloud.Repeat(name: clean, cycle: $0.cycle, customDays: $0.customDays, amount: $0.amount, dates: $0.dates, category: $0.category, endsOn: $0.endsOn)
            : $0 }
        if chosenRepeats.remove(old) != nil { chosenRepeats.insert(clean) }
        for index in candidates.indices where candidates[index].name.caseInsensitiveCompare(old) == .orderedSame {
            candidates[index].name = clean
        }
    }

    private func repeatWord(_ repeated: StatementCloud.Repeat) -> String {
        repeated.dates.isEmpty ? repeated.name : "\(repeated.name) · \(cycleWord(repeated))"
    }

    private func cycleWord(_ repeated: StatementCloud.Repeat) -> String {
        switch repeated.cycle {
        case "monthly": return "monthly"
        case "yearly": return "yearly"
        default: return repeated.customDays.map { "every \($0) days" } ?? "repeats"
        }
    }

    private func rename(_ old: String, to new: String) {
        let clean = new.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, clean != old else { return }
        members = members.map { $0.name == old ? StatementCloud.Member(name: clean, role: $0.role, reason: $0.reason) : $0 }
        if chosenMembers.remove(old) != nil { chosenMembers.insert(clean) }
        for index in candidates.indices where candidates[index].member == old { candidates[index].member = clean }
    }

    private func reveal(_ id: String, with proxy: ScrollViewProxy) {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(60))
            proxy.scrollTo(id, anchor: .center)
        }
    }

    private func addMember() {
        let clean = typedMember.trimmingCharacters(in: .whitespacesAndNewlines)
        addingMember = false
        typedMember = ""
        guard !clean.isEmpty else { return }
        if !members.contains(where: { $0.name.caseInsensitiveCompare(clean) == .orderedSame }) {
            members.append(StatementCloud.Member(name: clean, role: "", reason: ""))
        }
        chosenMembers.insert(clean)
    }

    private func addRepeat() {
        let clean = typedRepeat.trimmingCharacters(in: .whitespacesAndNewlines)
        addingRepeat = false
        typedRepeat = ""
        guard !clean.isEmpty else { return }
        if !repeats.contains(where: { $0.name.caseInsensitiveCompare(clean) == .orderedSame }) {
            repeats.append(StatementCloud.Repeat(name: clean, cycle: "monthly", customDays: nil, amount: 0, dates: [], category: nil, endsOn: nil))
        }
        chosenRepeats.insert(clean)
    }

    /// The statement's lines under the account's name — as a count first, because a year
    /// is hundreds of lines nobody checks one by one here; the list opens on a tap, and
    /// every line stays editable in the book afterwards.
    private var chargesSection: some View {
        VStack(alignment: .leading, spacing: LBSpacing.s2) {
            Text(files.count == 1 ? files[0].name : "\(files.filter { $0.prepared != nil }.count) statements")
                .lbText(.footnote)
                .foregroundStyle(LBColor.textTertiary.color)
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.horizontal, LBSpacing.s1)
            card {
                labelledRow("Currency") {
                    TextField("", text: Binding(get: { currency }, set: { currency = $0; currencyTyped = true }),
                              prompt: Text("INR").foregroundStyle(LBColor.textTertiary.color))
                        .textFieldStyle(.plain)
                        .lbText(.body)
                        .foregroundStyle(LBColor.textPrimary.color)
                        .multilineTextAlignment(.trailing)
                        #if os(iOS)
                        .textInputAutocapitalization(.characters)
                        #endif
                }
            }
            // Each file is an account, named by the server and open to correction.
            ForEach(files.indices, id: \.self) { index in
                if files[index].prepared != nil {
                    if files.count > 1 {
                        Text(files[index].name)
                            .lbText(.footnote)
                            .foregroundStyle(LBColor.textTertiary.color)
                            .lineLimit(1)
                            .padding(.horizontal, LBSpacing.s1)
                    }
                    card {
                        labelledRow("Account") {
                            TextField("", text: $files[index].account, prompt: Text("The account this statement is").foregroundStyle(LBColor.textTertiary.color))
                                .textFieldStyle(.plain)
                                .lbText(.body)
                                .foregroundStyle(LBColor.textPrimary.color)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                    if let balance = files[index].balance {
                        Text("Balance \(fmtMoney(balance, currency.trimmingCharacters(in: .whitespaces).uppercased()))\(files[index].balanceDate.flatMap(LB.parseDate).map { " · \(monthDayWord($0))" } ?? "")")
                            .lbText(.footnote)
                            .foregroundStyle(LBColor.textTertiary.color)
                            .padding(.horizontal, LBSpacing.s1)
                    }
                }
            }
            card {
                Button { Measure.used("show_charges"); showingCharges.toggle() } label: {
                    HStack(spacing: LBSpacing.s3) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(chargesWord)
                                .lbText(.body)
                                .foregroundStyle(LBColor.textPrimary.color)
                            if let tally = chargesTally {
                                Text(tally)
                                    .lbText(.footnote)
                                    .foregroundStyle(LBColor.textTertiary.color)
                            }
                        }
                        Spacer(minLength: LBSpacing.s2)
                        Image(systemName: showingCharges ? "chevron.up" : "chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(LBColor.textQuaternary.color)
                    }
                    .padding(LBSpacing.s3)
                    .contentShape(Rectangle())
                }
                .lbButtonStyle()
                .accessibilityHint(showingCharges ? "Hides every line" : "Shows every line")
                if showingCharges {
                    keepAllRow
                    #if os(macOS)
                    chargesTable
                    #endif
                }
            }
            #if os(iOS)
            // Each line its own card, the card every list wears, so the review reads as
            // Changes does.
            if showingCharges {
                ForEach(candidates.indices, id: \.self) { index in
                    row(index)
                }
            }
            #endif
        }
    }

    /// A label on the left, its value on the right.
    private func labelledRow<Content: View>(_ label: String, @ViewBuilder _ value: () -> Content) -> some View {
        HStack(spacing: LBSpacing.s3) {
            Text(label)
                .lbText(.body)
                .foregroundStyle(LBColor.textSecondary.color)
                .fixedSize()
            value()
        }
        .padding(.horizontal, LBSpacing.s3)
        .frame(minHeight: 44)
    }

    /// The span the kept lines cover: a month by its name, a longer stretch as its two ends.
    private var chargesWord: String {
        let dates = candidates.filter(\.keep).map(\.line.date).sorted()
        guard let first = dates.first, let last = dates.last else { return "No charges to add" }
        return first.prefix(7) == last.prefix(7) ? fullMonthWord(first) : "\(monthWord(first)) to \(monthWord(last))"
    }

    /// What the span holds, kept apart by a dot: charges, money in, transfers, lines left out.
    private var chargesTally: String? {
        let spend = keptCount - keptIncome - keptTransfers
        let skipped = candidates.count - keptCount
        var parts: [String] = []
        if spend > 0 { parts.append("\(spend) charge\(spend == 1 ? "" : "s")") }
        if keptIncome > 0 { parts.append("\(keptIncome) payment\(keptIncome == 1 ? "" : "s") in") }
        if keptTransfers > 0 { parts.append("\(keptTransfers) transfer\(keptTransfers == 1 ? "" : "s")") }
        if skipped > 0 { parts.append("\(skipped) skipped") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func monthDayWord(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("d MMM y")
        return formatter.string(from: date)
    }

    private func fullMonthWord(_ iso: String) -> String {
        guard let date = LB.parseDate(iso) else { return iso }
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("LLLL y")
        return formatter.string(from: date)
    }

    private func monthWord(_ iso: String) -> String {
        guard let date = LB.parseDate(iso) else { return iso }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM yyyy"
        return formatter.string(from: date)
    }

    private func addedStage(_ charges: Int, _ made: Int, _ waiting: Int) -> some View {
        VStack(alignment: .leading, spacing: LBSpacing.s3) {
            Text("\(charges) charge\(charges == 1 ? "" : "s") recorded.")
                .lbText(.body)
                .foregroundStyle(LBColor.textPrimary.color)
            if made > 0 {
                Text("\(made) commitment\(made == 1 ? "" : "s") made and planned ahead.")
                    .lbText(.bodySM)
                    .foregroundStyle(LBColor.textSecondary.color)
            }
            if waiting > 0 {
                Text("\(waiting) commitment\(waiting == 1 ? "" : "s") to fill in, on the timeline.")
                    .lbText(.bodySM)
                    .foregroundStyle(LBColor.textSecondary.color)
            }
            Text("Keep or undo it in Proposals.")
                .lbText(.footnote)
                .foregroundStyle(LBColor.textTertiary.color)
            Spacer(minLength: 0)
            primary("Done", action: onDone)
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
                Text(stage == .review ? "Import your statement" : "Import a statement")
                    .lbText(.headline)
                    .foregroundStyle(LBColor.textPrimary.color)
                Spacer()
                Button {
                    Measure.used("close")
                    if stage == .pick { onDone() } else { confirmingClose = true }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(LBColor.textSecondary.color)
                        .frame(width: 30, height: 30)
                        .background(LBColor.chrome.color, in: Circle())
                }
                .lbButtonStyle()
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

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 0) { content() }
            .background(LBColor.card.color, in: RoundedRectangle(cornerRadius: LBRadius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: LBRadius.md, style: .continuous)
                    .strokeBorder(LBColor.hairline.color, lineWidth: 1)
            )
    }

    /// What to do with the lines, said once, above them; and every line ticked or none, in one tap.
    private var keepAllRow: some View {
        let open = candidates.filter { $0.skipReason == nil }
        let allKept = open.allSatisfy(\.keep)
        return HStack(spacing: LBSpacing.s3) {
            Text("Untick anything you don’t want to add.")
                .lbText(.footnote)
                .foregroundStyle(LBColor.textTertiary.color)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: LBSpacing.s2)
            // Both words, always: "Select All" never sweeps a transfer in; "Deselect All"
            // lets one the owner ticked go too.
            let noneKept = !candidates.contains(where: \.keep)
            keepAllButton("Select All", enabled: !allKept) {
                for index in candidates.indices where candidates[index].skipReason == nil { candidates[index].keep = true }
            }
            keepAllButton("Deselect All", enabled: !noneKept) {
                for index in candidates.indices { candidates[index].keep = false }
            }
        }
        .padding(.horizontal, LBSpacing.s3)
    }

    private func keepAllButton(_ title: String, enabled: Bool, run: @escaping () -> Void) -> some View {
        Button {
            Measure.used("keep_all")
            LBHaptics.tap()
            run()
        } label: {
            Text(title)
                .lbText(.label)
                .foregroundStyle(enabled ? LBColor.brandText.color : LBColor.textQuaternary.color)
                .frame(minHeight: 32)
                .contentShape(Rectangle())
        }
        .lbButtonStyle()
        .disabled(!enabled)
    }

    /// A line the owner cannot tick: already in the book, dated after today, or refused for
    /// another reason. An own movement stays open: kept, it is written as a transfer.
    private func isLocked(_ candidate: StatementCandidate) -> Bool {
        candidate.skipReason != nil && !candidate.isOpenTransfer
    }

    private func keepBinding(_ index: Int) -> Binding<Bool> {
        Binding(get: { candidates[index].keep }, set: { candidates[index].keep = $0 })
    }

    private func nameBinding(_ index: Int) -> Binding<String> {
        Binding(get: { candidates[index].name }, set: { candidates[index].name = $0 })
    }

    private func tagBinding(_ index: Int) -> Binding<String> {
        Binding(get: { candidates[index].tag ?? "" }, set: { candidates[index].tag = $0.isEmpty ? nil : $0 })
    }

    private func personBinding(_ index: Int) -> Binding<String> {
        Binding(get: { candidates[index].member ?? "" }, set: { candidates[index].member = $0.isEmpty ? nil : $0 })
    }

    /// The people a line can be for: the statement's names first, then any typed on a
    /// line just now, then the book's — so a name given once is offered on every line.
    private var personNames: [String] {
        var names: [String] = []
        for name in members.map(\.name) + candidates.compactMap(\.member) + model.memberNames where !names.contains(name) {
            names.append(name)
        }
        return names
    }

    #if os(macOS)
    /// Typed, not picked: the field offers the names it knows as the letters come, and keeps
    /// a new one. Return puts a new person among the People pills below as well.
    @ViewBuilder
    private func personField(_ index: Int) -> some View {
        if #available(macOS 15.0, *) {
            TextField("", text: personBinding(index), prompt: Text("Add person").foregroundStyle(LBColor.textTertiary.color))
                .textFieldStyle(.plain)
                .textInputSuggestions {
                    ForEach(suggestions(for: candidates[index].member ?? "", among: personNames), id: \.self) { name in
                        Text(name).textInputCompletion(name)
                    }
                }
                .onSubmit { notePerson(candidates[index].member) }
        } else {
            personPicker(index).labelsHidden()
        }
    }

    @ViewBuilder
    private func categoryField(_ index: Int) -> some View {
        if #available(macOS 15.0, *) {
            TextField("", text: categoryTextBinding(index), prompt: Text("Add category").foregroundStyle(LBColor.textTertiary.color))
                .textFieldStyle(.plain)
                .textInputSuggestions {
                    ForEach(suggestions(for: candidates[index].tag.map(categoryWord) ?? "",
                                        among: model.commitmentTagNames.map(categoryWord)), id: \.self) { word in
                        Text(word).textInputCompletion(word)
                    }
                }
        } else {
            categoryPicker(index).labelsHidden()
        }
    }

    /// The names that contain what was typed, a handful at most; all of them before a letter.
    private func suggestions(for typed: String, among names: [String]) -> [String] {
        let needle = typed.trimmingCharacters(in: .whitespaces).lowercased()
        let hits = needle.isEmpty ? names : names.filter { $0.lowercased().contains(needle) && $0.lowercased() != needle }
        return Array(hits.prefix(6))
    }

    /// The category as its word; a word the book knows becomes its tag, a new one stands as typed.
    private func categoryTextBinding(_ index: Int) -> Binding<String> {
        Binding(
            get: { candidates[index].tag.map(categoryWord) ?? "" },
            set: { typed in
                let clean = typed.trimmingCharacters(in: .whitespaces)
                let known = model.commitmentTagNames.first { categoryWord($0).caseInsensitiveCompare(clean) == .orderedSame }
                candidates[index].tag = clean.isEmpty ? nil : (known ?? clean)
            }
        )
    }

    /// A person named on a line is a person on the statement: a pill below, ticked.
    private func notePerson(_ name: String?) {
        guard let clean = name?.trimmingCharacters(in: .whitespacesAndNewlines), !clean.isEmpty else { return }
        if !members.contains(where: { $0.name.caseInsensitiveCompare(clean) == .orderedSame }) {
            members.append(StatementCloud.Member(name: clean, role: "", reason: ""))
        }
        chosenMembers.insert(clean)
    }
    #endif

    private func categoryPicker(_ index: Int) -> some View {
        Picker("Category", selection: tagBinding(index)) {
            Text("No category").tag("")
            ForEach(model.commitmentTagNames, id: \.self) { name in
                Text(categoryWord(name)).tag(name)
            }
        }
    }

    private func personPicker(_ index: Int) -> some View {
        Picker("Person", selection: personBinding(index)) {
            Text("No person").tag("")
            ForEach(personNames, id: \.self) { name in
                Text(name).tag(name)
            }
        }
    }

    #if os(iOS)
    /// A line opened for editing, as a sheet's item.
    private struct OpenLine: Identifiable {
        let id: Int
    }

    /// One line as the card every list wears, the tick beside it: the name, its day and
    /// what it is filed under, who it is for, the money. A tap opens the line to edit; the
    /// bank's own words wait there.
    private func row(_ index: Int) -> some View {
        let candidate = candidates[index]
        let locked = isLocked(candidate)
        return HStack(alignment: .top, spacing: LBSpacing.s2) {
            Button {
                Measure.used("checkmark_square_fill")
                if !locked { candidates[index].keep.toggle() }
            } label: {
                Image(systemName: candidate.keep ? "checkmark.square.fill" : "square")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(candidate.keep ? LBColor.brand.color : LBColor.textTertiary.color)
                    .frame(width: 28, height: 44)
                    .contentShape(Rectangle())
            }
            // A checkbox: pressed on the box, never a hover.
            .lbButtonStyle(hovers: false)
            .disabled(locked)
            .accessibilityLabel(candidate.keep ? "Kept. Tap to leave out." : "Left out. Tap to keep.")
            Button {
                Measure.used("open_line")
                openLine = OpenLine(id: index)
            } label: {
                LBCommitmentRow(
                    name: candidate.name.isEmpty ? candidate.line.payee : candidate.name,
                    facts: candidateFacts(candidate), amount: amountText(candidate),
                    ink: candidate.keep ? LBColor.brand : LBColor.textQuaternary,
                    badge: locked ? ("Skipped", .muted) : nil
                )
                .opacity(candidate.keep ? 1 : 0.7)
            }
            .lbButtonStyle()
            .accessibilityHint("Opens the line to edit it.")
        }
    }

    /// The line's facts as a card wears them: its day, then money in, a transfer or its
    /// category, then the person — a prompt where one is missing.
    private func candidateFacts(_ candidate: StatementCandidate) -> [LBMetaFact] {
        let day = LBMetaFact(symbol: LBGlyph.date, text: LB.parseDate(candidate.line.date).map(monthDayWord) ?? candidate.line.date)
        let kind: LBMetaFact = candidate.isIncome ? LBMetaFact(symbol: LBGlyph.income, text: "Money in")
            : candidate.isTransfer ? DashboardModel.transferFact
            : candidate.tag.map { LBMetaFact(symbol: LBGlyph.category, text: categoryWord($0)) } ?? DashboardModel.addCategoryFact
        let person = candidate.member.map { LBMetaFact(symbol: LBGlyph.member, text: $0) } ?? DashboardModel.addMemberFact
        let why = candidate.skipReason.map { [LBMetaFact(symbol: "", text: $0)] } ?? []
        return [day, kind] + why + [person]
    }

    private func amountText(_ candidate: StatementCandidate) -> String {
        (candidate.isIncome ? "+" : "") + candidate.line.amount.formatted(.number.precision(.fractionLength(0...2)))
    }

    /// One line, open: whether it is added, its name, category and person, its money, and
    /// the bank's own words for it, which are the evidence behind a renamed line.
    private func lineDetail(_ index: Int) -> some View {
        let candidate = candidates[index]
        let locked = isLocked(candidate)
        return NavigationStack {
            Form {
                Section {
                    Toggle("Add this item", isOn: keepBinding(index).measured("add_this_item"))
                        .disabled(locked)
                } footer: {
                    if let reason = candidate.skipReason { Text("Skipped: \(reason)") }
                }
                Section {
                    LabeledContent("Name") {
                        TextField("Name", text: nameBinding(index), prompt: Text("Name it as you would say it"))
                            .multilineTextAlignment(.trailing)
                            .disabled(locked)
                    }
                    if candidate.isIncome {
                        LabeledContent("Type", value: "Money in")
                    } else {
                        categoryPicker(index).disabled(locked)
                    }
                    personPicker(index).disabled(locked)
                    LabeledContent("Amount") { amountWord(candidate) }
                }
                Section("Statement line") {
                    Text(candidate.line.payee)
                        .textSelection(.enabled)
                    Button("Copy Statement Line") { Measure.used("copy_statement_line"); copy(candidate.line.payee) }
                }
            }
            .lbScreenTitle(LB.parseDate(candidate.line.date).map(monthDayWord) ?? candidate.line.date, large: false)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { Measure.used("done"); openLine = nil }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
    #endif

    #if os(macOS)
    /// One line as the Mac's table holds it, with the values its columns sort by.
    private struct LineRow: Identifiable {
        let id: Int
        let date: String
        let name: String
        let category: String
        let person: String
        let amount: Double
        let kept: Int
    }

    private var lineRows: [LineRow] {
        candidates.indices.map { index in
            let candidate = candidates[index]
            return LineRow(id: index, date: candidate.line.date, name: candidate.name,
                           category: candidate.isIncome ? "" : candidate.tag.map(categoryWord) ?? "",
                           person: candidate.member ?? "", amount: candidate.line.amount, kept: candidate.keep ? 1 : 0)
        }
        .sorted(using: lineOrder)
    }

    /// Every line in a sortable table, each cell edited in place; the bank's own words are
    /// the name's tooltip, so the column stays readable.
    private var chargesTable: some View {
        Table(lineRows, sortOrder: $lineOrder) {
            TableColumn("Add", value: \.kept) { row in
                Toggle("", isOn: keepBinding(row.id).measured("keep_binding"))
                    .labelsHidden()
                    .disabled(isLocked(candidates[row.id]))
                    .accessibilityLabel(candidates[row.id].keep ? "Kept" : "Left out")
            }
            .width(36)
            TableColumn("Date", value: \.date) { row in
                Text(LB.parseDate(row.date).map(monthDayWord) ?? row.date)
                    .monospacedDigit()
                    .foregroundStyle(LBColor.textSecondary.color)
            }
            .width(min: 84, ideal: 92)
            TableColumn("Name", value: \.name) { row in
                let candidate = candidates[row.id]
                HStack(spacing: LBSpacing.s1) {
                    if candidate.isTransfer {
                        Image(systemName: LBGlyph.transfer)
                            .foregroundStyle(LBColor.textSecondary.color)
                            .accessibilityHidden(true)
                    }
                    if isLocked(candidate) {
                        Text(candidate.name).foregroundStyle(LBColor.textTertiary.color)
                    } else {
                        TextField("Name", text: nameBinding(row.id))
                            .textFieldStyle(.plain)
                    }
                }
                .help(candidate.skipReason.map { "\(candidate.line.payee) — skipped: \($0)" } ?? candidate.line.payee)
            }
            .width(min: 140, ideal: 200)
            TableColumn("Category", value: \.category) { row in
                if candidates[row.id].isIncome {
                    Text("Money in").foregroundStyle(LBColor.brandText.color)
                } else {
                    categoryField(row.id)
                        .disabled(isLocked(candidates[row.id]))
                }
            }
            .width(min: 110, ideal: 130)
            TableColumn("Person", value: \.person) { row in
                personField(row.id)
                    .disabled(isLocked(candidates[row.id]))
            }
            .width(min: 90, ideal: 110)
            TableColumn("Amount", value: \.amount) { row in
                amountWord(candidates[row.id])
            }
            .width(min: 70, ideal: 90)
        }
        .frame(minHeight: 360, idealHeight: 440)
    }
    #endif

    /// The line's money, in figures of one width so a column of them lines up.
    private func amountWord(_ candidate: StatementCandidate) -> some View {
        Text((candidate.isIncome ? "+" : "") + candidate.line.amount.formatted(.number.precision(.fractionLength(0...2))))
            #if os(iOS)
            .lbText(.headline)
            #else
            .lbText(.numberSM)
            #endif
            .monospacedDigit()
            .foregroundStyle(candidate.keep ? LBColor.textPrimary.color : LBColor.textTertiary.color)
            .fixedSize()
            .frame(minWidth: 72, alignment: .trailing)
    }

    private func lineWord(_ candidate: StatementCandidate) -> String {
        let day = LB.parseDate(candidate.line.date).map(monthDayWord) ?? candidate.line.date
        // Marked as a transfer, with why it is unticked; kept, it is left out of spending.
        if candidate.isOpenTransfer {
            return "\(day) · Transfer · " + (candidate.keep ? "left out of spending" : candidate.skipReason ?? "not kept")
        }
        // A refused transfer still says what it is, then why it stays out.
        if candidate.isTransfer, let reason = candidate.skipReason { return "\(day) · Transfer · skipped: \(reason)" }
        if let reason = candidate.skipReason { return "\(day) · skipped: \(reason)" }
        return "\(day) · " + (candidate.isIncome ? "Money in" : candidate.tag.map(categoryWord) ?? "No category")
    }

    private func copy(_ value: String) {
        #if os(iOS)
        UIPasteboard.general.string = value
        #else
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
        #endif
    }

    /// The brand button; `badge` adds a small positive pill beside its word.
    private func primary(_ title: String, badge: String? = nil, enabled: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: { Measure.used("statement_option"); action() }) {
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

    // MARK: words

    private var keptCount: Int { candidates.filter(\.keep).count }
    private var keptIncome: Int { candidates.filter { $0.keep && $0.isIncome }.count }
    private var keptTransfers: Int { candidates.filter { $0.keep && $0.isTransfer }.count }
    /// Every file with a kept line has its account named.
    private var accountsNamed: Bool {
        files.allSatisfy { read in
            !candidates.contains { $0.keep && $0.file == read.id } || !read.account.trimmingCharacters(in: .whitespaces).isEmpty
        }
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
            files[index].word = ""
            files[index].prepared = nil
            files[index].unread = []
            files[index].problem = nil
        }
        problem = nil
        shareSpent = false
        progress = 0
        lockedIndex = nil
        cut()
    }

    /// Cuts the files in order. The first locked one stops to ask for its password; a
    /// file that cannot be cut is set aside with the reason.
    private func cut() {
        stage = .working("Opening \(files.count == 1 ? files[0].name : "\(files.count) files")…")
        for index in files.indices where files[index].pieces.isEmpty && files[index].problem == nil {
            do {
                let pieces = try StatementCloud.pieces(for: files[index].url, password: password.isEmpty ? nil : password)
                password = ""
                if pieces.isEmpty {
                    files[index].problem = "Nothing was read from \(files[index].name)."
                } else {
                    files[index].pieces = pieces
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
        guard files.contains(where: { !$0.pieces.isEmpty }) else {
            problem = files.compactMap(\.problem).joined(separator: "\n")
            stage = .pick
            countImport(ok: false)
            return
        }
        Task { await readAll() }
    }

    /// Every file at once. The units are every piece and each file's look-over; the bar
    /// lands on a mark as each comes back.
    private func readAll() async {
        let token = await auth.accessToken()
        let tags = model.commitmentTagNames
        let known = (members: model.memberNames, accounts: model.accountNames)
        let money = currency
        let readable = files.indices.filter { !files[$0].pieces.isEmpty }
        units = Double(readable.reduce(0) { $0 + files[$1].pieces.count } + readable.count)
        doneUnits = 0
        stage = .working(readable.count == 1 ? "Reading \(files[readable[0]].name)" : "Reading \(readable.count) statements")
        creep(from: 0, toward: 1 / units)
        await withTaskGroup(of: Void.self) { group in
            for index in readable {
                group.addTask { @MainActor in
                    await readFile(index, token: token, tags: tags, known: known, money: money)
                }
            }
        }
        creeping?.cancel()
        let got = readable.filter { files[$0].prepared != nil }
        guard !got.isEmpty else {
            problem = (files.compactMap(\.problem) + files.flatMap(\.unread)).joined(separator: "\n")
            stage = .pick
            countImport(ok: false)
            return
        }
        progress = 1
        // Read: the review is laid out now and waits behind the game until asked for.
        show()
    }

    /// One file: the first piece alone, which names the account and is checked as a
    /// statement; the rest three at a time; then the look-over.
    @MainActor
    private func readFile(_ index: Int, token: String?, tags: [String], known: (members: [String], accounts: [String]), money: String) async {
        let pieces = files[index].pieces
        let id = files[index].importId
        var answers: [StatementCloud.ChargesAnswer?] = Array(repeating: nil, count: pieces.count)
        files[index].word = pieces.count == 1 ? "Reading" : "Reading \(pieces[0].label)"
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
            files[index].word = "Reading " + (batch.count == 1 ? pieces[batch[0]].label : "pieces \(batch[0] + 1)–\(batch[batch.count - 1] + 1) of \(pieces.count)")
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
        let read = answers.compactMap { $0 }
        guard !read.isEmpty else {
            files[index].problem = "\(files[index].name): " + files[index].unread.joined(separator: "; ")
            files[index].unread = []
            return
        }
        files[index].word = "Looking the year over"
        var prepared = StatementCloud.Prepared.assemble(read, review: .empty)
        let looked = (try? await StatementCloud.review(prepared, importId: id, categories: tags,
                                                        members: known.members, currency: money, token: token)) ?? .empty
        prepared = StatementCloud.Prepared.assemble(read, review: looked)
        let unread = files[index].unread
        if !unread.isEmpty { prepared.notes = (["Not read: " + unread.joined(separator: "; ") + "."] + [prepared.notes]).joined(separator: " ") }
        files[index].prepared = prepared
        // The currency the statement prints, unless the reader set one: a pound statement
        // read with a rupee guess was written in rupees.
        if !currencyTyped, let printed = prepared.currency { currency = printed }
        files[index].account = prepared.account
        files[index].balance = prepared.balance
        files[index].balanceDate = prepared.balanceDate
        files[index].word = "Read"
        advance()
    }

    /// A unit came back: the bar lands on its mark and creeps toward the next.
    private func advance(by count: Int = 1) {
        doneUnits += count
        creep(from: Double(doneUnits) / units, toward: min(0.98, Double(doneUnits + 1) / units))
    }

    /// The bar starts a unit on its mark and eases toward the next without reaching it,
    /// because a piece's own progress is not knowable — only its end is.
    private func creep(from start: Double, toward end: Double) {
        creeping?.cancel()
        progress = start
        creeping = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(600))
                guard !Task.isCancelled else { return }
                let left = (end - 0.01) - progress
                if left > 0.001 { progress += left * 0.06 }
            }
        }
    }

    /// The answers laid out for ticking: every file's lines in one list, keyed to its
    /// file; the people and repeats of all of them together.
    private func show() {
        var found: [StatementCandidate] = []
        var seenRepeats: [StatementCloud.Repeat] = []
        var seenMembers: [StatementCloud.Member] = []
        var said: [String] = []
        for index in files.indices {
            guard let prepared = files[index].prepared else { continue }
            var mine = prepared.candidates(among: model.commitmentTagNames)
            for i in mine.indices { mine[i].file = files[index].id }
            found += mine
            for repeated in prepared.repeats where !seenRepeats.contains(where: { $0.name.caseInsensitiveCompare(repeated.name) == .orderedSame }) {
                seenRepeats.append(repeated)
            }
            for member in prepared.members where !seenMembers.contains(where: { $0.name.caseInsensitiveCompare(member.name) == .orderedSame }) {
                seenMembers.append(member)
            }
            if !prepared.notes.isEmpty { said.append(files.count > 1 ? "\(files[index].name): \(prepared.notes)" : prepared.notes) }
        }
        said += files.compactMap(\.problem)
        StatementImport.markAlreadyPresent(&found, in: model.importedChargeKeys())
        candidates = found
        // What the model saw, plus the rhythms the rules see in the same charges.
        var seen = seenRepeats
        let named = Set(seen.map { $0.name.lowercased() })
        for ruled in StatementImport.repeats(in: found) where !named.contains(ruled.name.lowercased()) {
            seen.append(StatementCloud.Repeat(name: ruled.name, cycle: ruled.cycle.rawValue, customDays: ruled.customDays,
                                              amount: ruled.amount, dates: ruled.dates, category: nil, endsOn: nil))
        }
        repeats = seen
        // Ticked by default only when the evidence is strong — three charges seen, or two
        // and a name that says it recurs. A person paid once is a suggestion, not a plan.
        chosenRepeats = Set(repeats.filter { repeated in
            guard repeated.endsOn == nil else { return false }
            let words = repeated.name.lowercased()
            let recurringWord = ["rent", "emi", "premium", "subscription", "mandate", "autopay", "insurance", "broadband", "maintenance", "salary"]
                .contains { words.contains($0) }
            return repeated.dates.count >= 3 || (repeated.dates.count >= 2 && recurringWord)
        }.map(\.name))
        members = seenMembers
        chosenMembers = Set(members.map(\.name))
        notes = said.joined(separator: " ")
        // The reading is done; the review opens when the reader is ready for it, not
        // from under a game half played.
        stage = .ready
    }

    private func add() {
        problem = nil
        do {
            var rows = candidates
            // A member ticked is a person in the book, whatever the lines say; the lines
            // that name them carry them. One unticked stays a name on the line. A name the
            // writer refuses stops the add here, its refusal on the review.
            let chosen = Array(chosenMembers)
            for name in chosen {
                guard model.addEntity(.familyMember, named: name) != nil else {
                    throw WriteError.invalid(model.saveError ?? "That didn’t save.")
                }
            }
            for index in rows.indices {
                if let member = rows[index].member, !chosenMembers.contains(member), !model.memberNames.contains(member) {
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
            let money = currency.trimmingCharacters(in: .whitespaces).uppercased()
            var written = 0
            let before = Set(model.commitmentIdNames.map(\.id))
            var firstSource: String?
            // Each file lands on its own account, from its own copy in documents.
            for read in files where read.prepared != nil {
                let mine = rows.filter { $0.file == read.id }
                guard mine.contains(where: \.keep) else { continue }
                let source = try model.fileStatement(read.url)
                firstSource = firstSource ?? source
                let named = read.account.trimmingCharacters(in: .whitespaces)
                var attached: [String: [[String: Any]]] = [:]
                var ownRows: [StatementCandidate] = []
                for row in mine {
                    if row.keep, let home = recurring.first(where: {
                        $0.name.caseInsensitiveCompare(row.name) == .orderedSame
                            && VaultPatch.storedDirection(model.subscription(id: $0.id)?.direction) == VaultPatch.storedDirection(row.direction)
                    }) {
                        attached[home.id, default: []].append(["date": row.line.date, "amount": row.line.amount, "paid": true, "basis": "statement"])
                    } else {
                        ownRows.append(row)
                    }
                }
                written += try model.importPrepared(ownRows, accounts: [read.id: named], currency: money, source: source)
                for (id, charges) in attached {
                    try model.importStatement(PendingWrite(id: UUID(), kind: "add_charges", payload: ["id": id, "charges": charges],
                                                           sourceRef: source, keyName: "statement import", origin: "statement"))
                    written += charges.count
                }
                // The statement's last line is the account's balance, dated — unless the account
                // already holds a later one: an old statement never rewinds the balance.
                if let balance = read.balance, let id = model.addEntity(.paymentMethod, named: named),
                   model.balanceIsNewer(read.balanceDate, forAccount: id) {
                    model.setEntityDetails(.paymentMethod, id: id, balance: .some(balance), balanceDate: .some(read.balanceDate))
                }
            }
            // A repeat ticked becomes one recurring commitment over the lines it names, planned
            // ahead. One with no lines to carry — typed in, or renamed away from them — waits
            // on the timeline with the ones setup named, for its amount and day.
            let ticked = repeats.filter { chosenRepeats.contains($0.name) }
            let promoted = firstSource.map { model.promoteRepeats(ticked, madeSince: before, source: $0) } ?? []
            let waiting = model.placeholders
            let taken = Set(waiting.map { $0.name.lowercased() })
            let fresh = ticked.filter { !promoted.contains($0.name) && !taken.contains($0.name.lowercased()) && !model.hasCommitment(named: $0.name) }
                .map { CommitmentPlaceholder(name: $0.name, group: $0.dates.isEmpty ? "Named" : cycleWord($0).capitalized, tag: $0.category ?? "") }
            if !fresh.isEmpty { model.setPlaceholders(waiting + fresh) }
            // Every month the new rows confirm gets its report, drawn from what was written.
            model.drawMonthlyReports()
            stage = .added(written, promoted.count, fresh.count)
            countImport(ok: true, charges: written)
        } catch {
            Telemetry.shared.failed(.statementImport, error)
            problem = error.friendlyDescription
            countImport(outcome: "add_failed")
        }
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
            "kb_total": Int((Double(bytes) / 1024 / 50).rounded()) * 50,
        ])
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
