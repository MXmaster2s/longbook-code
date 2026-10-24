import DesignSystem
import LongbookCore
import StoreKit
import SwiftUI
#if os(iOS)
import UIKit
typealias SupportImage = UIImage
#else
import AppKit
typealias SupportImage = NSImage
#endif

/// Support: longbook's AI answering from the help articles, asked about once (the consent
/// sheet), opened from Settings and Help & about, and from every screen while a conversation
/// is recent. A person replies by email when asked. The conversation lives on this device.
@MainActor
final class SupportCenter: ObservableObject {
    static let shared = SupportCenter()

    private static let conversationKey = "longbook.support.conversation"
    private static let askerKey = "longbook.support.askerId"
    private static let reviewAskedKey = "longbook.support.reviewAsked"
    /// A conversation counts as open for a day after its last message.
    private static let openFor: TimeInterval = 24 * 60 * 60
    static let offer = "Want me to ask someone on the team to reply to you by email?"

    /// Where a reply by email has got to: offered, asking for the address, waiting for the
    /// code, sending, or sent. Shown as one card at the foot of the conversation.
    enum ReplyStep: Equatable {
        case offered
        case address(error: String?)
        case code(email: String, error: String?)
        case sending
        case sent(email: String)
        case failed(String)
    }

    /// What follows a rating: after a thumbs up, the App Store; after a thumbs down, sending
    /// the conversation to the team to review.
    enum Follow: Equatable {
        case appStore
        case review(sending: Bool)
        case reviewed
    }

    @Published var presented = false
    @Published var askingConsent = false
    @Published private(set) var messages: [SupportMessage] = []
    @Published private(set) var answering = false
    @Published var replyStep: ReplyStep?
    @Published var follow: Follow?
    /// The screen behind Support, taken the moment it opened, and whether it goes to the team.
    @Published private(set) var behind: SupportImage?
    @Published var screenshotAttached = false
    private var asking: Task<Void, Never>?

    var active: Bool {
        guard let last = messages.last?.at else { return false }
        return last.addingTimeInterval(Self.openFor) > Date()
    }

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.conversationKey),
           let saved = try? JSONDecoder().decode([SupportMessage].self, from: data) {
            messages = saved
        }
        // An offer left unanswered last time is still open.
        if messages.last?.text.contains("reply to you by email?") == true { replyStep = .offered }
    }

    func open() {
        guard !presented else { return }
        behind = SupportScreenshot.capture()
        screenshotAttached = false
        if AIConsent.support.given { presented = true } else { askingConsent = true }
    }

    func accepted() {
        UserDefaults.standard.set(true, forKey: AIConsent.support.key)
        askingConsent = false
        // The chat cannot open while the consent sheet is still leaving.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { self.presented = true }
    }

    func declined() { askingConsent = false }

    func close() {
        presented = false
        if case .sent = replyStep { replyStep = nil }
        if follow == .reviewed || follow == .appStore { follow = nil }
    }

    /// A random id for counting questions when signed out, apart from usage data's install id.
    private var askerId: String {
        if let id = UserDefaults.standard.string(forKey: Self.askerKey) { return id }
        let id = UUID().uuidString
        UserDefaults.standard.set(id, forKey: Self.askerKey)
        return id
    }

    private var turns: [SupportCloud.Turn] {
        messages.filter { !$0.failed && !$0.text.isEmpty }.map {
            SupportCloud.Turn(role: $0.role == .user ? "user" : "assistant", content: $0.text)
        }
    }

    func send(_ text: String, token: String?) {
        let question = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !answering else { return }
        if replyStep == .offered { replyStep = nil }
        follow = nil
        messages.append(SupportMessage(role: .user, text: question))
        let turns = turns
        let answer = SupportMessage(role: .assistant, text: "")
        messages.append(answer)
        answering = true
        asking = Task {
            do {
                for try await event in SupportCloud.ask(turns, askerId: askerId, token: token) {
                    switch event {
                    case .text(let words): update(answer.id) { $0.text += words }
                    case .done(let id, let key, let sources, let email):
                        update(answer.id) { $0.serverId = id; $0.serverKey = key; $0.sources = sources }
                        // An answer that ends on the offer gets its buttons, whatever the server said.
                        if email || (messages.last?.text.contains("reply to you by email") ?? false) { replyStep = .offered }
                    }
                }
            } catch {
                let words = (error as? SupportCloud.Failure)?.message ?? "Support couldn't answer just now. Try again in a minute."
                update(answer.id) { $0.text = words; $0.failed = true }
                replyStep = .offered
            }
            answering = false
            save()
        }
    }

    private func update(_ id: UUID, _ change: (inout SupportMessage) -> Void) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        change(&messages[index])
    }

    private func save() {
        let kept = messages.filter { !$0.text.isEmpty }
        UserDefaults.standard.set(try? JSONEncoder().encode(kept), forKey: Self.conversationKey)
    }

    /// Forgets the conversation and the counting id; the server never had the messages.
    func clearHistory() {
        asking?.cancel()
        messages = []
        answering = false
        replyStep = nil
        follow = nil
        UserDefaults.standard.removeObject(forKey: Self.conversationKey)
        UserDefaults.standard.removeObject(forKey: Self.askerKey)
    }

    // MARK: a person, by email

    /// The envelope in the bar: the offer, as if Support had made it.
    func askForPerson() {
        guard replyStep == nil || replyStep == .offered else { return }
        if messages.last?.text != Self.offer {
            messages.append(SupportMessage(role: .assistant, text: Self.offer))
            save()
        }
        replyStep = .offered
    }

    /// Yes to the offer: signed in, straight to sending to the account's address; else the address.
    func acceptReply(email: String?, token: String?) {
        if let email, token != nil { sendForReply(email: email, code: nil, token: token) } else { replyStep = .address(error: nil) }
    }

    func requestCode(_ email: String, token: String?) {
        let address = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        replyStep = .sending
        Task {
            do {
                try await SupportCloud.requestCode(email: address, askerId: askerId, token: token)
                replyStep = .code(email: address, error: nil)
            } catch {
                replyStep = .address(error: (error as? SupportCloud.Failure)?.message)
            }
        }
    }

    func sendForReply(email: String, code: String?, token: String?) {
        replyStep = .sending
        Task {
            do {
                let to = try await SupportCloud.send(
                    turns, review: false, email: email, code: code, rating: nil, app: AppVersion.line,
                    screenshotPNG: screenshotPNG, askerId: askerId, token: token)
                replyStep = .sent(email: to ?? email)
                messages.append(SupportMessage(role: .assistant, text: "Done. Someone on the team will reply to you at \(to ?? email). You'll get a copy of this conversation there too."))
                save()
            } catch let failure as SupportCloud.Failure {
                replyStep = code == nil ? .failed(failure.message) : .code(email: email, error: failure.message)
            } catch {
                replyStep = .failed("That didn't go through. Try again in a minute.")
            }
        }
    }

    private var screenshotPNG: Data? { screenshotAttached ? behind.flatMap(SupportScreenshot.png) : nil }

    // MARK: ratings

    func rate(_ message: SupportMessage, up: Bool, token: String?) {
        update(message.id) { $0.rating = up }
        save()
        if let id = message.serverId, let key = message.serverKey { Task { await SupportCloud.rate(answer: id, key: key, up: up, askerId: askerId, token: token) } }
        if up {
            // The App Store is asked about once, after the first answer that helped.
            if !UserDefaults.standard.bool(forKey: Self.reviewAskedKey) { follow = .appStore }
        } else {
            follow = .review(sending: false)
        }
    }

    func appStoreAsked() {
        UserDefaults.standard.set(true, forKey: Self.reviewAskedKey)
        follow = nil
    }

    func sendForReview(token: String?) {
        follow = .review(sending: true)
        Task {
            _ = try? await SupportCloud.send(
                turns, review: true, email: nil, code: nil, rating: false, app: AppVersion.line,
                screenshotPNG: screenshotPNG, askerId: askerId, token: token)
            follow = .reviewed
        }
    }
}

struct SupportMessage: Codable, Identifiable, Equatable {
    enum Role: String, Codable { case user, assistant }
    var id = UUID()
    let role: Role
    var text: String
    var at = Date()
    var sources: [SupportCloud.Source] = []
    /// The server's record of this answer, which a rating names.
    var serverId: Int?
    /// The key that lets this device, and only it, rate the answer.
    var serverKey: String?
    var rating: Bool?
    var failed = false
}

// MARK: the articles

/// The help articles the app ships, the same files the support function answers from.
struct HelpArticle: Codable, Identifiable, Hashable {
    let slug: String
    let title: String
    let body: String
    var id: String { slug }

    static let all: [HelpArticle] = {
        guard let url = Bundle.main.url(forResource: "help-articles", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([HelpArticle].self, from: data)) ?? []
    }()

    static func named(_ slug: String) -> HelpArticle? { all.first { $0.slug == slug } }
}

/// One article, read in the app: its headings, lists and paragraphs, with bold and links.
struct HelpArticleView: View {
    let article: HelpArticle
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Help article")
                    .lbText(.label)
                    .foregroundStyle(LBColor.textTertiary.color)
                Spacer()
                Button("Done") { Measure.used("support_article_done"); onDone() }
                    .lbText(.body)
                    .foregroundStyle(LBColor.brandText.color)
                    .buttonStyle(.plain)
            }
            .padding(.horizontal, LBSpacing.s4)
            .padding(.vertical, LBSpacing.s3)
            ScrollView {
                VStack(alignment: .leading, spacing: LBSpacing.s3) {
                    Text(article.title)
                        .lbText(.screenTitle)
                        .foregroundStyle(LBColor.textPrimary.color)
                        .padding(.bottom, LBSpacing.s2)
                    ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in block }
                }
                .padding(LBSpacing.s4)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(LBColor.canvas.color)
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 480)
        #endif
    }

    private var blocks: [AnyView] {
        article.body.components(separatedBy: "\n").compactMap { raw in
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { return nil }
            // A table row reads as its cells side by side; the rule under the header is dropped.
            if line.hasPrefix("|") {
                let cells = line.trimmingCharacters(in: CharacterSet(charactersIn: "|")).components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
                if cells.allSatisfy({ $0.allSatisfy { "-: ".contains($0) } }) { return nil }
                return AnyView(HStack(alignment: .firstTextBaseline, spacing: LBSpacing.s3) {
                    ForEach(Array(cells.enumerated()), id: \.offset) { index, cell in
                        Text(inline(cell))
                            .foregroundStyle(index == 0 ? LBColor.textPrimary.color : LBColor.textSecondary.color)
                            .frame(minWidth: index == 0 ? 72 : 0, alignment: .leading)
                    }
                }.lbText(.bodySM))
            }
            if line.hasPrefix("#") {
                let words = line.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces)
                return AnyView(Text(inline(words)).lbText(.headline).foregroundStyle(LBColor.textPrimary.color).padding(.top, LBSpacing.s2))
            }
            let bullet = line.hasPrefix("- ") ? "•" : line.range(of: #"^\d+\."#, options: .regularExpression).map { String(line[$0]) }
            if let bullet {
                let words = line.hasPrefix("- ") ? String(line.dropFirst(2)) : line.replacingOccurrences(of: #"^\d+\.\s*"#, with: "", options: .regularExpression)
                return AnyView(HStack(alignment: .firstTextBaseline, spacing: LBSpacing.s2) {
                    Text(bullet).foregroundStyle(LBColor.textTertiary.color).frame(minWidth: 20, alignment: .leading)
                    Text(inline(words)).foregroundStyle(LBColor.textSecondary.color)
                }.lbText(.bodySM))
            }
            return AnyView(Text(inline(line)).lbText(.bodySM).foregroundStyle(LBColor.textSecondary.color).fixedSize(horizontal: false, vertical: true))
        }
    }

    private func inline(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text)) ?? AttributedString(text)
    }
}

// MARK: screenshot

enum SupportScreenshot {
    /// The front window as it is drawn now.
    @MainActor
    static func capture() -> SupportImage? {
        #if os(iOS)
        let window = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }
        guard let window else { return nil }
        return UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: false)
        }
        #else
        guard let view = (NSApp.mainWindow ?? NSApp.keyWindow)?.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: rep)
        let image = NSImage(size: view.bounds.size)
        image.addRepresentation(rep)
        return image
        #endif
    }

    static func png(_ image: SupportImage) -> Data? {
        #if os(iOS)
        image.pngData()
        #else
        image.tiffRepresentation.flatMap { NSBitmapImageRep(data: $0)?.representation(using: .png, properties: [:]) }
        #endif
    }

}

// MARK: the sheet, the panel

/// What Support shows: a bar, the conversation (or a greeting with starter questions), and the
/// composer. Answers stream in beside Support's mark; the articles they used sit under them,
/// with a thumbs up or down. Asking for a person, or a thumbs down, leads to the team by email.
struct SupportScreen: View {
    @ObservedObject var auth: AuthViewModel
    @ObservedObject private var center = SupportCenter.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openURL) private var openURL
    @Environment(\.requestReview) private var requestReview
    @State private var draft = ""
    @State private var address = ""
    @State private var code = ""
    @State private var reading: HelpArticle?
    @FocusState private var typing: Bool
    @FocusState private var filling: Bool

    private static let starters = [
        "How do I import a bank statement?",
        "How do I connect Claude or ChatGPT?",
        "How do I get a refund?",
        "Where is my data kept?",
    ]
    private static let greeting = "Hi, I'm longbook's AI. Ask me anything about longbook. Please don't share amounts, or account or card numbers. If I can't help, someone on the team will reply by email."

    var body: some View {
        VStack(spacing: 0) {
            bar
            conversation
            composer
        }
        .background(LBColor.canvas.color)
        .measured("support_article", .sheet, when: reading != nil)
        .sheet(item: $reading) { article in
            HelpArticleView(article: article) { reading = nil }
        }
        #if os(iOS)
        .presentationDetents([.large])
        .presentationBackground(LBColor.canvas.color)
        #endif
    }

    private var rise: Animation? { LBMotion.rise(reduceMotion: reduceMotion) }
    private var spring: Animation? { reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.8) }

    private var bar: some View {
        HStack(spacing: LBSpacing.s3) {
            SupportAvatar(kind: .support, size: 34)
            VStack(alignment: .leading, spacing: 1) {
                Text("longbook Support")
                    .lbText(.headline)
                    .foregroundStyle(LBColor.textPrimary.color)
                    .accessibilityAddTraits(.isHeader)
                Text("AI · answers right away")
                    .lbText(.footnote)
                    .lineLimit(1)
                    .foregroundStyle(LBColor.textTertiary.color)
            }
            Spacer(minLength: LBSpacing.s3)
            Button {
                Measure.used("support_person")
                withAnimation(spring) { center.askForPerson() }
            } label: {
                Image(systemName: "person.crop.circle.badge.questionmark")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(LBColor.textSecondary.color)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Ask a person")
            .accessibilityLabel("Ask a person")
            #if os(iOS)
            Button("Done") { Measure.used("support_done"); center.close() }
                .lbText(.body)
                .foregroundStyle(LBColor.brandText.color)
            #else
            Button { Measure.used("support_hide"); center.close() } label: {
                Image(systemName: "minus")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(LBColor.textSecondary.color)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Hide Support")
            .accessibilityLabel("Hide Support")
            #endif
        }
        .padding(.horizontal, LBSpacing.s4)
        .padding(.vertical, LBSpacing.s3)
        .background(LBColor.chrome.color)
        .overlay(alignment: .bottom) { Rectangle().fill(LBColor.hairline.color).frame(height: 1) }
    }

    // MARK: conversation

    private var conversation: some View {
        ScrollViewReader { scroller in
            ScrollView {
                // A plain stack: a lazy one unloads a card that slides under the keyboard, and
                // the field in it loses the typing.
                VStack(alignment: .leading, spacing: LBSpacing.s4) {
                    supportRow { bubble(Self.greeting) }
                    if center.messages.isEmpty { starters }
                    ForEach(center.messages) { message in
                        row(message)
                            .id(message.id)
                            .transition(reduceMotion ? .opacity : .asymmetric(
                                insertion: .move(edge: .bottom).combined(with: .opacity),
                                removal: .opacity))
                    }
                    if let replyStep = center.replyStep { replyCard(replyStep).transition(cardMotion) }
                    if let follow = center.follow { followCard(follow).transition(cardMotion) }
                    Color.clear.frame(height: 1).id("end")
                }
                .padding(LBSpacing.s4)
                .animation(rise, value: center.messages.count)
                .animation(spring, value: center.replyStep)
                .animation(spring, value: center.follow)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: center.messages.last?.text) { _, _ in withAnimation(rise) { scroller.scrollTo("end", anchor: .bottom) } }
            .onChange(of: center.messages.count) { _, _ in withAnimation(rise) { scroller.scrollTo("end", anchor: .bottom) } }
            .onChange(of: center.replyStep) { _, _ in
                // A card that grows lays out a beat later; scroll again once it has.
                withAnimation(rise) { scroller.scrollTo("end", anchor: .bottom) }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { withAnimation(rise) { scroller.scrollTo("end", anchor: .bottom) } }
            }
            .onChange(of: center.follow) { _, _ in withAnimation(rise) { scroller.scrollTo("end", anchor: .bottom) } }
            .onChange(of: filling) { _, now in
                // The keyboard takes a moment to rise; the card follows it up once it has.
                if now { DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { withAnimation(rise) { scroller.scrollTo("end", anchor: .bottom) } } }
            }
            .onAppear { scroller.scrollTo("end", anchor: .bottom) }
        }
    }

    private var cardMotion: AnyTransition {
        reduceMotion ? .opacity : .scale(scale: 0.96, anchor: .bottomLeading).combined(with: .opacity)
    }

    private var starters: some View {
        VStack(alignment: .trailing, spacing: LBSpacing.s2) {
            ForEach(Array(Self.starters.enumerated()), id: \.offset) { index, question in
                Button { Measure.used("support_starter"); ask(question) } label: {
                    Text(question)
                        .lbText(.bodySM)
                        .foregroundStyle(LBColor.textPrimary.color)
                        .padding(.horizontal, LBSpacing.s3)
                        .padding(.vertical, LBSpacing.s2)
                        .background(LBColor.card.color, in: Capsule())
                        .overlay(Capsule().strokeBorder(LBColor.hairline.color))
                }
                .buttonStyle(.plain)
                .modifier(Arrive(delay: Double(index) * LBMotion.stagger, reduceMotion: reduceMotion))
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    /// Support's side: its mark at the foot of the message, and what belongs to the message
    /// (its articles, the thumbs) under it, in line with the bubble.
    private func supportRow<Content: View, Below: View>(
        @ViewBuilder _ content: () -> Content, @ViewBuilder below: () -> Below = { EmptyView() }
    ) -> some View {
        VStack(alignment: .leading, spacing: LBSpacing.s2) {
            HStack(alignment: .bottom, spacing: LBSpacing.s2) {
                SupportAvatar(kind: .support, size: 28)
                content()
                Spacer(minLength: LBSpacing.s8)
            }
            below().padding(.leading, 28 + LBSpacing.s2)
        }
    }

    @ViewBuilder
    private func row(_ message: SupportMessage) -> some View {
        if message.role == .user {
            HStack(alignment: .bottom, spacing: LBSpacing.s2) {
                Spacer(minLength: LBSpacing.s8)
                Text(message.text)
                    .lbText(.bodySM)
                    .foregroundStyle(LBColor.textPrimary.color)
                    .padding(.horizontal, LBSpacing.s3)
                    .padding(.vertical, LBSpacing.s2 + 2)
                    .background(LBColor.chrome.color, in: RoundedRectangle(cornerRadius: LBRadius.lg, style: .continuous))
                    .textSelection(.enabled)
                SupportAvatar(kind: .person(email: auth.email, photo: auth.avatarURL), size: 28)
            }
        } else {
            supportRow {
                if message.text.isEmpty {
                    TypingDots(reduceMotion: reduceMotion)
                        .padding(.horizontal, LBSpacing.s3)
                        .padding(.vertical, LBSpacing.s3)
                        .background(LBColor.card.color, in: RoundedRectangle(cornerRadius: LBRadius.lg, style: .continuous))
                } else {
                    bubble(message.text, quiet: message.failed)
                }
            } below: {
                if !message.sources.isEmpty || message.serverId != nil {
                    VStack(alignment: .leading, spacing: LBSpacing.s1) {
                        if !message.sources.isEmpty { sources(message.sources) }
                        if message.serverId != nil { thumbs(message) }
                    }
                }
            }
        }
    }

    private func bubble(_ text: String, quiet: Bool = false) -> some View {
        Text((try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text))
            .lbText(.bodySM)
            .foregroundStyle(quiet ? LBColor.textSecondary.color : LBColor.textPrimary.color)
            .padding(.horizontal, LBSpacing.s3)
            .padding(.vertical, LBSpacing.s2 + 2)
            .background(LBColor.card.color, in: RoundedRectangle(cornerRadius: LBRadius.lg, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: LBRadius.lg, style: .continuous).strokeBorder(LBColor.hairline.color))
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
    }

    private func sources(_ sources: [SupportCloud.Source]) -> some View {
        LBFlow(spacing: LBSpacing.s2) {
            ForEach(sources, id: \.slug) { source in
                Button {
                    Measure.used("support_source")
                    reading = HelpArticle.named(source.slug)
                } label: {
                    Label(source.title, systemImage: "doc.text")
                        .lbText(.label)
                        .foregroundStyle(LBColor.brandText.color)
                        .lineLimit(1)
                        .padding(.horizontal, LBSpacing.s3)
                        .padding(.vertical, 6)
                        .background(LBColor.brand.color.opacity(0.12), in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// A quiet thumbs up and down under an answer; the chosen one stays, filled.
    private func thumbs(_ message: SupportMessage) -> some View {
        HStack(spacing: LBSpacing.s1) {
            ForEach([true, false], id: \.self) { up in
                if message.rating == nil || message.rating == up {
                    Button {
                        if up { Measure.used("support_thumb_up") } else { Measure.used("support_thumb_down") }
                        Task {
                            let token = await auth.accessToken()
                            withAnimation(spring) { center.rate(message, up: up, token: token) }
                        }
                    } label: {
                        Image(systemName: up ? (message.rating == true ? "hand.thumbsup.fill" : "hand.thumbsup")
                                             : (message.rating == false ? "hand.thumbsdown.fill" : "hand.thumbsdown"))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(message.rating == nil ? LBColor.textTertiary.color : LBColor.brandText.color)
                            .frame(width: 28, height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(message.rating != nil)
                    .accessibilityLabel(up ? "Helpful" : "Not helpful")
                    .transition(.opacity)
                }
            }
        }
    }

    // MARK: cards

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        supportRow {
            VStack(alignment: .leading, spacing: LBSpacing.s3) { content() }
                .padding(LBSpacing.s3)
                .frame(maxWidth: 340, alignment: .leading)
                .background(LBColor.card.color, in: RoundedRectangle(cornerRadius: LBRadius.lg, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: LBRadius.lg, style: .continuous).strokeBorder(LBColor.brand.color.opacity(0.35)))
        }
    }

    private func pill(_ title: String, primary: Bool = true, measure: StaticString, _ action: @escaping () -> Void) -> some View {
        Button { Measure.used(measure); action() } label: {
            Text(title)
                .lbText(.label)
                .foregroundStyle(primary ? LBColor.onBrand.color : LBColor.textPrimary.color)
                .padding(.horizontal, LBSpacing.s3)
                .padding(.vertical, 8)
                .background(primary ? LBColor.brand.color : LBColor.chrome.color, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func note(_ text: String, error: Bool = false) -> some View {
        Text(text)
            .lbText(.footnote)
            .foregroundStyle(error ? LBColor.danger.color : LBColor.textTertiary.color)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func field(_ prompt: String, text: Binding<String>, code: Bool = false) -> some View {
        TextField(prompt, text: text)
            .lbText(.bodySM)
            .textFieldStyle(.plain)
            .focused($filling)
            .autocorrectionDisabled()
            #if os(iOS)
            .textInputAutocapitalization(.never)
            .keyboardType(code ? .numberPad : .emailAddress)
            .textContentType(code ? .oneTimeCode : .emailAddress)
            #endif
            .padding(.horizontal, LBSpacing.s3)
            .padding(.vertical, 9)
            .background(LBColor.sunken.color, in: RoundedRectangle(cornerRadius: LBRadius.sm, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: LBRadius.sm, style: .continuous).strokeBorder(LBColor.hairline.color))
    }

    @ViewBuilder
    private func replyCard(_ step: SupportCenter.ReplyStep) -> some View {
        switch step {
        case .offered:
            card {
                HStack(spacing: LBSpacing.s2) {
                    pill("Yes, ask the team", measure: "support_reply_yes") {
                        Task {
                            let token = await auth.accessToken()
                            withAnimation(spring) { center.acceptReply(email: auth.email, token: token) }
                        }
                    }
                    pill("No thanks", primary: false, measure: "support_reply_no") { withAnimation(spring) { center.replyStep = nil } }
                }
                if center.screenshotAttached { note("Your screenshot goes with it.") }
            }
        case .address(let error):
            card {
                Text("Which email should we reply to?").lbText(.bodySM).foregroundStyle(LBColor.textPrimary.color)
                field("you@example.com", text: $address)
                    .onSubmit { sendCode() }
                if let error { note(error, error: true) } else { note("We'll send a code to check it's yours.") }
                pill("Send code", measure: "support_send_code") { sendCode() }
                    .disabled(!address.contains("@"))
            }
        case .code(let email, let error):
            card {
                Text("Enter the code we sent to \(email).").lbText(.bodySM).foregroundStyle(LBColor.textPrimary.color)
                field("6-digit code", text: $code, code: true)
                    .onSubmit { sendReply(email) }
                if let error { note(error, error: true) }
                HStack(spacing: LBSpacing.s2) {
                    pill("Send to the team", measure: "support_send_reply") { sendReply(email) }
                        .disabled(code.filter(\.isNumber).count != 6)
                    pill("Change email", primary: false, measure: "support_other_email") { code = ""; center.replyStep = .address(error: nil) }
                }
            }
        case .sending:
            card {
                HStack(spacing: LBSpacing.s2) {
                    ProgressView().controlSize(.small)
                    note("Sending…")
                }
            }
        case .sent:
            EmptyView()
        case .failed(let words):
            card {
                note(words, error: true)
                HStack(spacing: LBSpacing.s2) {
                    pill("Try again", measure: "support_retry") { center.replyStep = .offered }
                    pill("Write to us", primary: false, measure: "support_write") {
                        if let url = FeedbackMail.url(subject: "longbook Support") { openURL(url) }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func followCard(_ follow: SupportCenter.Follow) -> some View {
        switch follow {
        case .appStore:
            card {
                Text("Glad that helped. Would you rate longbook on the App Store? It helps other people find it.")
                    .lbText(.bodySM).foregroundStyle(LBColor.textPrimary.color)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: LBSpacing.s2) {
                    pill("Rate longbook", measure: "support_rate_app") { requestReview(); center.appStoreAsked() }
                    pill("Not now", primary: false, measure: "support_rate_later") { withAnimation(spring) { center.appStoreAsked() } }
                }
            }
        case .review(let sending):
            card {
                Text("Sorry that didn't help. Can I send this conversation to the longbook team so they can do better?")
                    .lbText(.bodySM).foregroundStyle(LBColor.textPrimary.color)
                    .fixedSize(horizontal: false, vertical: true)
                if sending {
                    HStack(spacing: LBSpacing.s2) { ProgressView().controlSize(.small); note("Sending…") }
                } else {
                    HStack(spacing: LBSpacing.s2) {
                        pill("Send it", measure: "support_review_send") {
                            Task {
                                let token = await auth.accessToken()
                                withAnimation(spring) { center.sendForReview(token: token) }
                            }
                        }
                        pill("No thanks", primary: false, measure: "support_review_no") { withAnimation(spring) { center.follow = nil } }
                    }
                    note("No email address goes with it.")
                }
            }
        case .reviewed:
            supportRow { bubble("Thanks, the team will read it.") }
        }
    }

    private func sendCode() {
        guard address.contains("@") else { return }
        Task {
            let token = await auth.accessToken()
            withAnimation(spring) { center.requestCode(address, token: token) }
        }
    }

    private func sendReply(_ email: String) {
        let digits = code.filter(\.isNumber)
        guard digits.count == 6 else { return }
        Task {
            let token = await auth.accessToken()
            withAnimation(spring) { center.sendForReply(email: email, code: digits, token: token) }
            code = ""
        }
    }

    // MARK: composer

    private var composer: some View {
        VStack(alignment: .leading, spacing: LBSpacing.s2) {
            if center.screenshotAttached, let image = center.behind { attachedShot(image) }
            HStack(alignment: .bottom, spacing: LBSpacing.s2) {
                Button {
                    Measure.used("support_screenshot")
                    withAnimation(rise) { center.screenshotAttached.toggle() }
                } label: {
                    Image(systemName: center.screenshotAttached ? "camera.viewfinder" : "camera")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(center.screenshotAttached ? LBColor.brandText.color : LBColor.textSecondary.color)
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(center.behind == nil)
                .help("Attach a screenshot for the team")
                .accessibilityLabel(center.screenshotAttached ? "Remove the screenshot" : "Attach a screenshot for the team")

                TextField("Ask a question", text: $draft, axis: .vertical)
                    .lbText(.bodySM)
                    .lineLimit(1...5)
                    .textFieldStyle(.plain)
                    .focused($typing)
                    .padding(.horizontal, LBSpacing.s3)
                    .padding(.vertical, 9)
                    .background(LBColor.card.color, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(LBColor.hairline.color))
                    .onSubmit { ask(draft) }

                if canSend {
                    Button { Measure.used("support_send"); ask(draft) } label: {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(LBColor.onBrand.color)
                            .frame(width: 36, height: 36)
                            .background(LBColor.brand.color, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.return, modifiers: .command)
                    .accessibilityLabel("Send")
                    .transition(reduceMotion ? .opacity : .scale(scale: 0.4).combined(with: .opacity))
                }
            }
            .animation(spring, value: canSend)
        }
        .padding(LBSpacing.s3)
        .background(LBColor.chrome.color)
        .overlay(alignment: .top) { Rectangle().fill(LBColor.hairline.color).frame(height: 1) }
    }

    private func attachedShot(_ image: SupportImage) -> some View {
        HStack(spacing: LBSpacing.s3) {
            shot(image)
                .resizable()
                .scaledToFill()
                .frame(width: 44, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: LBRadius.xs, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: LBRadius.xs, style: .continuous).strokeBorder(LBColor.hairline.color))
            Text("Goes to the team if you ask for a reply, never to the AI. Check it first, it may show amounts.")
                .lbText(.footnote)
                .foregroundStyle(LBColor.textSecondary.color)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button {
                Measure.used("support_screenshot_remove")
                withAnimation(rise) { center.screenshotAttached = false }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(LBColor.textTertiary.color)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove the screenshot")
        }
        .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
    }

    private func shot(_ image: SupportImage) -> Image {
        #if os(iOS)
        Image(uiImage: image)
        #else
        Image(nsImage: image)
        #endif
    }

    private var canSend: Bool {
        !center.answering && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func ask(_ question: String) {
        guard !center.answering else { return }
        Task {
            let token = await auth.accessToken()
            center.send(question, token: token)
        }
        draft = ""
    }
}

/// The faces of the conversation: longbook's mark for Support, and the person's own photo,
/// or their initial, or a plain figure when nobody is signed in.
struct SupportAvatar: View {
    enum Kind { case support, person(email: String?, photo: URL?) }
    let kind: Kind
    let size: CGFloat

    var body: some View {
        Group {
            switch kind {
            case .support:
                Image("SidebarMark")
                    .resizable()
                    .scaledToFit()
                    .padding(size * 0.18)
                    .background(LBColor.chrome.color)
            case .person(let email, let photo):
                if let photo {
                    AsyncImage(url: photo) { image in image.resizable().scaledToFill() } placeholder: { initial(email) }
                } else {
                    initial(email)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(LBColor.hairline.color))
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func initial(_ email: String?) -> some View {
        ZStack {
            LBColor.brand.color.opacity(0.22)
            if let letter = email?.first(where: \.isLetter) {
                Text(String(letter).uppercased())
                    .font(.system(size: size * 0.44, weight: .semibold, design: .rounded))
                    .foregroundStyle(LBColor.brandText.color)
            } else {
                Image(systemName: "person.fill")
                    .font(.system(size: size * 0.42))
                    .foregroundStyle(LBColor.brandText.color)
            }
        }
    }
}

/// Three dots breathing in turn while the first words are on their way.
private struct TypingDots: View {
    let reduceMotion: Bool

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            HStack(spacing: 5) {
                ForEach(0..<3) { index in
                    let phase = reduceMotion ? 0.5 : (sin((t * 2 * .pi / 1.1) - Double(index) * 0.9) + 1) / 2
                    Circle()
                        .fill(LBColor.textTertiary.color)
                        .frame(width: 7, height: 7)
                        .scaleEffect(0.7 + 0.35 * phase)
                        .opacity(0.45 + 0.55 * phase)
                }
            }
        }
        .accessibilityLabel("Writing an answer")
    }
}

/// A view that rises into place a beat after the one before it.
private struct Arrive: ViewModifier {
    let delay: Double
    let reduceMotion: Bool
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 8)
            .onAppear { withAnimation(LBMotion.rise(reduceMotion: reduceMotion)?.delay(delay)) { shown = true } }
    }
}

// MARK: the button

/// The floating Support button. The dot says a conversation is recent.
struct SupportButton: View {
    /// What the press does, when Support opens in another window (the Mac's Settings).
    var action: (() -> Void)? = nil
    @ObservedObject private var center = SupportCenter.shared

    var body: some View {
        Button { Measure.used("support_button"); (action ?? center.open)() } label: {
            HStack(spacing: LBSpacing.s2) {
                Image(systemName: "bubble.left.fill")
                    .font(.system(size: 14, weight: .semibold))
                Text("Support")
                    .lbText(.label)
            }
            .foregroundStyle(LBColor.onBrand.color)
            .padding(.horizontal, LBSpacing.s4)
            .padding(.vertical, 11)
            .background(LBColor.brand.color, in: Capsule())
            .overlay(alignment: .topTrailing) {
                if center.active {
                    Circle().fill(LBColor.urgent.color)
                        .frame(width: 11, height: 11)
                        .overlay(Circle().strokeBorder(LBColor.chrome.color, lineWidth: 2))
                        .offset(x: 2, y: -2)
                        .accessibilityHidden(true)
                }
            }
            .shadow(color: .black.opacity(0.3), radius: 10, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(center.active ? "Support, conversation open" : "Support")
    }
}

/// The consent sheet before the first question, and on the phone the chat sheet itself.
struct SupportPresenter: ViewModifier {
    @ObservedObject var auth: AuthViewModel
    @ObservedObject private var center = SupportCenter.shared

    func body(content: Content) -> some View {
        content
            .measured("support_consent", .sheet, when: center.askingConsent)
            .sheet(isPresented: $center.askingConsent) {
                ConsentSheet(consent: .support, onAccept: center.accepted, onDecline: center.declined)
            }
            #if os(iOS)
            .measured("support_chat", .sheet, when: center.presented)
            .sheet(isPresented: Binding(get: { center.presented }, set: { if !$0 { center.close() } })) {
                SupportScreen(auth: auth)
            }
            #endif
    }
}

// MARK: Help & about

/// Support's rows in What leaves this device: the fact, Allow Support, Clear support history.
struct SupportPrivacyRows: View {
    @AppStorage(AIConsent.support.key) private var allowed = false
    @State private var cleared = false

    var body: some View {
        VStack(alignment: .leading, spacing: LBSpacing.s3) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Support")
                    .lbText(.body)
                    .foregroundStyle(LBColor.textPrimary.color)
                Text("Your questions go through our server, which keeps none of them, to Anthropic's Claude, which answers from our help articles. A screenshot goes only to the team, when you ask for a reply by email.")
                    .lbText(.bodySM)
                    .foregroundStyle(LBColor.textSecondary.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // Withdrawing is turning this off: the next time Support opens, it asks again.
            Toggle(isOn: $allowed.measured("allow_support")) {
                Text("Allow Support")
                    .lbText(.bodySM)
                    .foregroundStyle(LBColor.textPrimary.color)
            }
            .tint(LBColor.brand.color)
            Button {
                Measure.used("clear_support_history")
                SupportCenter.shared.clearHistory()
                cleared = true
            } label: {
                Text(cleared ? "Support history cleared" : "Clear support history")
                    .lbText(.bodySM)
                    .foregroundStyle(cleared ? LBColor.textTertiary.color : LBColor.brandText.color)
            }
            .buttonStyle(.plain)
            .disabled(cleared)
        }
    }
}
