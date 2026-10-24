import DesignSystem
import LongbookCore
import SwiftUI
#if os(iOS)
import MessageUI
import UIKit
typealias SupportImage = UIImage
#else
import AppKit
typealias SupportImage = NSImage
#endif

/// Support: longbook's AI answering from the help articles, asked about once (the consent
/// sheet), opened from Settings and Help & about, and from every screen while a conversation
/// is recent. Email reaches a person. The conversation lives only on this device.
@MainActor
final class SupportCenter: ObservableObject {
    static let shared = SupportCenter()

    private static let conversationKey = "longbook.support.conversation"
    private static let askerKey = "longbook.support.askerId"
    /// A conversation counts as open for a day after its last message.
    private static let openFor: TimeInterval = 24 * 60 * 60

    @Published var presented = false
    @Published var askingConsent = false
    @Published private(set) var messages: [SupportMessage] = []
    @Published private(set) var answering = false
    /// The screen behind Support, taken the moment it opened, and whether it goes with the email.
    @Published private(set) var behind: SupportImage?
    @Published var screenshotAttached = false
    @Published var mailNote: String?
    #if os(iOS)
    @Published var composingMail = false
    #endif
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
        mailNote = nil
    }

    /// A random id for counting questions when signed out, apart from usage data's install id.
    private var askerId: String {
        if let id = UserDefaults.standard.string(forKey: Self.askerKey) { return id }
        let id = UUID().uuidString
        UserDefaults.standard.set(id, forKey: Self.askerKey)
        return id
    }

    func send(_ text: String, token: String?) {
        let question = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !answering else { return }
        messages.append(SupportMessage(role: .user, text: question))
        let turns = messages.filter { !$0.failed && !$0.text.isEmpty }.map {
            SupportCloud.Turn(role: $0.role == .user ? "user" : "assistant", content: $0.text)
        }
        let answer = SupportMessage(role: .assistant, text: "")
        messages.append(answer)
        answering = true
        asking = Task {
            do {
                for try await event in SupportCloud.ask(turns, askerId: askerId, token: token) {
                    switch event {
                    case .text(let words): update(answer.id) { $0.text += words }
                    case .done(let sources, let email):
                        // An answer that points to Email us gets the button, whatever the server said.
                        update(answer.id) { $0.sources = sources; $0.offerEmail = email || $0.text.contains("Email us") }
                    }
                }
            } catch {
                let words = (error as? SupportCloud.Failure)?.message ?? "Support couldn't answer just now. Try again in a minute, or tap Email us."
                update(answer.id) { $0.text = words; $0.failed = true; $0.offerEmail = true }
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
        UserDefaults.standard.removeObject(forKey: Self.conversationKey)
        UserDefaults.standard.removeObject(forKey: Self.askerKey)
    }

    // MARK: email

    static let address = "contact@longbook.app"
    static let subject = "longbook Support"

    /// The conversation so far, for the person who answers the email.
    var mailBody: String {
        let said = messages.filter { !$0.failed }.map { "\($0.role == .user ? "Me" : "longbook Support"): \($0.text)" }
        let conversation = said.isEmpty ? "" : "\n\n— The conversation so far —\n\n\(said.joined(separator: "\n\n"))"
        return "\n\(conversation)\n\n\(AppVersion.line)"
    }

    var attachment: SupportImage? { screenshotAttached ? behind : nil }

    /// A draft to a person: the phone's Mail sheet, or the Mac's mail app, with the screenshot
    /// when attached; without a mail account, a plain mailto and the screenshot on the clipboard.
    func emailUs(openURL: OpenURLAction) {
        #if os(iOS)
        if MFMailComposeViewController.canSendMail() {
            composingMail = true
            return
        }
        if let image = attachment {
            UIPasteboard.general.image = image
            mailNote = "The screenshot is copied. In your email, touch and hold and tap Paste."
        }
        if let url = FeedbackMail.url(subject: Self.subject, body: mailBody) { openURL(url) }
        #else
        var items: [Any] = [mailBody]
        if let image = attachment, let file = SupportScreenshot.save(image) { items.append(file) }
        if let service = NSSharingService(named: .composeEmail) {
            service.recipients = [Self.address]
            service.subject = Self.subject
            if service.canPerform(withItems: items) {
                service.perform(withItems: items)
                return
            }
        }
        if let url = FeedbackMail.url(subject: Self.subject, body: mailBody) { openURL(url) }
        #endif
    }
}

struct SupportMessage: Codable, Identifiable, Equatable {
    enum Role: String, Codable { case user, assistant }
    var id = UUID()
    let role: Role
    var text: String
    var at = Date()
    var sources: [SupportCloud.Source] = []
    var offerEmail = false
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

    #if os(macOS)
    /// The screenshot as a file, for the mail app to attach.
    static func save(_ image: NSImage) -> URL? {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("longbook-support", isDirectory: true)
        let file = folder.appendingPathComponent("longbook screenshot.png")
        guard let data = png(image),
              (try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)) != nil,
              (try? data.write(to: file)) != nil else { return nil }
        return file
    }
    #endif
}

#if os(iOS)
/// The phone's Mail sheet, addressed and filled, with the screenshot when attached.
private struct SupportMailView: UIViewControllerRepresentable {
    let body: String
    let screenshot: UIImage?
    let onDone: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onDone: onDone) }

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let mail = MFMailComposeViewController()
        mail.mailComposeDelegate = context.coordinator
        mail.setToRecipients([SupportCenter.address])
        mail.setSubject(SupportCenter.subject)
        mail.setMessageBody(body, isHTML: false)
        if let screenshot, let data = SupportScreenshot.png(screenshot) {
            mail.addAttachmentData(data, mimeType: "image/png", fileName: "longbook screenshot.png")
        }
        return mail
    }

    func updateUIViewController(_ controller: MFMailComposeViewController, context: Context) {}

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let onDone: () -> Void
        init(onDone: @escaping () -> Void) { self.onDone = onDone }
        func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
            onDone()
        }
    }
}
#endif

// MARK: the sheet, the panel

/// What Support shows: a bar, the conversation (or a greeting with starter questions), and the
/// composer. Answers stream in; the articles they used sit under them; Email us reaches a person.
struct SupportScreen: View {
    @ObservedObject var auth: AuthViewModel
    @ObservedObject private var center = SupportCenter.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openURL) private var openURL
    @State private var draft = ""
    @State private var reading: HelpArticle?
    @FocusState private var typing: Bool

    private static let starters = [
        "How do I import a bank statement?",
        "How do I connect Claude or ChatGPT?",
        "How do I get a refund?",
        "Where is my data kept?",
    ]

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
        .measured("support_mail", .sheet, when: center.composingMail)
        .sheet(isPresented: $center.composingMail) {
            SupportMailView(body: center.mailBody, screenshot: center.attachment) { center.composingMail = false }
                .ignoresSafeArea()
        }
        .presentationDetents([.large])
        .presentationBackground(LBColor.canvas.color)
        #endif
    }

    private var rise: Animation? { LBMotion.rise(reduceMotion: reduceMotion) }

    private var bar: some View {
        HStack(spacing: LBSpacing.s3) {
            VStack(alignment: .leading, spacing: 1) {
                Text("longbook Support")
                    .lbText(.headline)
                    .foregroundStyle(LBColor.textPrimary.color)
                    .accessibilityAddTraits(.isHeader)
                Text("AI · answers from our help articles")
                    .lbText(.footnote)
                    .foregroundStyle(LBColor.textTertiary.color)
            }
            Spacer(minLength: LBSpacing.s3)
            Button { Measure.used("support_email"); center.emailUs(openURL: openURL) } label: {
                Image(systemName: "envelope")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(LBColor.textSecondary.color)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Email us")
            .accessibilityLabel("Email us")
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
                LazyVStack(alignment: .leading, spacing: LBSpacing.s4) {
                    greeting
                    if center.messages.isEmpty { starters }
                    ForEach(center.messages) { message in
                        bubble(message)
                            .id(message.id)
                            .transition(reduceMotion ? .opacity : .asymmetric(
                                insertion: .move(edge: .bottom).combined(with: .opacity),
                                removal: .opacity))
                    }
                    Color.clear.frame(height: 1).id("end")
                }
                .padding(LBSpacing.s4)
                .animation(rise, value: center.messages.count)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: center.messages.last?.text) { _, _ in
                withAnimation(rise) { scroller.scrollTo("end", anchor: .bottom) }
            }
            .onChange(of: center.messages.count) { _, _ in
                withAnimation(rise) { scroller.scrollTo("end", anchor: .bottom) }
            }
            .onAppear { scroller.scrollTo("end", anchor: .bottom) }
        }
    }

    private var greeting: some View {
        answerBubble("Hi, I'm longbook's AI. Ask me anything about longbook and I'll answer from our help articles. Please don't share amounts, or account or card numbers. Tap the envelope any time to email a person.")
    }

    private var starters: some View {
        VStack(alignment: .leading, spacing: LBSpacing.s2) {
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

    @ViewBuilder
    private func bubble(_ message: SupportMessage) -> some View {
        if message.role == .user {
            Text(message.text)
                .lbText(.bodySM)
                .foregroundStyle(LBColor.textPrimary.color)
                .padding(.horizontal, LBSpacing.s3)
                .padding(.vertical, LBSpacing.s2 + 2)
                .background(LBColor.chrome.color, in: RoundedRectangle(cornerRadius: LBRadius.lg, style: .continuous))
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.leading, LBSpacing.s8)
                .textSelection(.enabled)
        } else {
            VStack(alignment: .leading, spacing: LBSpacing.s2) {
                if message.text.isEmpty {
                    TypingDots(reduceMotion: reduceMotion)
                        .padding(.horizontal, LBSpacing.s3)
                        .padding(.vertical, LBSpacing.s3)
                        .background(LBColor.card.color, in: RoundedRectangle(cornerRadius: LBRadius.lg, style: .continuous))
                } else {
                    answerBubble(message.text, failed: message.failed)
                }
                if !message.sources.isEmpty { sources(message.sources) }
                if message.offerEmail && !center.answering || message.failed { emailOffer }
            }
            .padding(.trailing, LBSpacing.s8)
        }
    }

    private func answerBubble(_ text: String, failed: Bool = false) -> some View {
        Text((try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text))
            .lbText(.bodySM)
            .foregroundStyle(failed ? LBColor.textSecondary.color : LBColor.textPrimary.color)
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
                .transition(.opacity)
            }
        }
    }

    private var emailOffer: some View {
        VStack(alignment: .leading, spacing: LBSpacing.s1) {
            Button { Measure.used("support_email_offer"); center.emailUs(openURL: openURL) } label: {
                Label("Email us", systemImage: "envelope.fill")
                    .lbText(.label)
                    .foregroundStyle(LBColor.onBrand.color)
                    .padding(.horizontal, LBSpacing.s3)
                    .padding(.vertical, 8)
                    .background(LBColor.brand.color, in: Capsule())
            }
            .buttonStyle(.plain)
            if let note = center.mailNote {
                Text(note)
                    .lbText(.footnote)
                    .foregroundStyle(LBColor.textTertiary.color)
            }
        }
        .transition(.scale(scale: 0.9, anchor: .leading).combined(with: .opacity))
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
                .help("Attach a screenshot to your email")
                .accessibilityLabel(center.screenshotAttached ? "Remove the screenshot" : "Attach a screenshot to your email")

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
            .animation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.72), value: canSend)
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
            Text("Goes with your email, never to the AI. Check it first, it may show amounts.")
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
                Text("Your questions go through our server, which keeps none of them, to Anthropic's Claude, which answers from our help articles. A screenshot goes only in an email you choose to send.")
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
