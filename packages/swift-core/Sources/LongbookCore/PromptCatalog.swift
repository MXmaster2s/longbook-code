// The prompts an owner gives their AI, read from the bundled prompts.json: the same bytes
// packages/core/contract ships, generated from packages/core/src/prompts.ts. Screens that show
// or copy a prompt read it here, so the app, the site and the MCP servers use one wording.
import Foundation

public enum PromptCatalog {
    /// One prompt: what the owner says, what it does, and the steps their AI follows.
    public struct Prompt: Decodable, Identifiable, Hashable, Sendable {
        /// Stable name: the MCP prompt's name and a read_guide key.
        public let id: String
        public let title: String
        /// A `Group.id`.
        public let group: String
        /// What the owner says. The first is what a Copy button copies.
        public let phrases: [String]
        /// The first phrase with `{month}` where the owner names a month.
        public let template: String?
        /// Other words for the same prompt: matched by the servers, never shown.
        public let aliases: [String]?
        public let attachments: String
        /// What the prompt does, said to the owner in a line or two.
        public let result: String
        /// Whether following it can write to the longbook.
        public let writes: Bool
        /// What the owner's AI needs besides longbook: "mail", "scheduler".
        public let needs: [String]?
        /// The llms.txt chapter holding the method in full.
        public let chapter: String?
        /// The steps, one per line; a sub-step is indented three spaces.
        public let procedure: [String]
    }

    public struct Group: Decodable, Identifiable, Hashable, Sendable {
        public let id: String
        public let title: String
    }

    struct File: Decodable {
        let contractRevision: Int?
        let groups: [Group]
        let prompts: [Prompt]

        enum CodingKeys: String, CodingKey {
            case contractRevision = "contract_revision"
            case groups, prompts
        }

        /// Per element: one malformed prompt or group is dropped, never the whole catalogue.
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            contractRevision = try? c.decodeIfPresent(Int.self, forKey: .contractRevision)
            groups = (try? c.decodeIfPresent([Lossy<Group>].self, forKey: .groups))?.compactMap(\.value) ?? []
            prompts = (try? c.decodeIfPresent([Lossy<Prompt>].self, forKey: .prompts))?.compactMap(\.value) ?? []
        }
    }

    /// The decoded file, loaded once; the bundle never changes mid-run. Nil if it is missing
    /// or unreadable, which leaves every list empty rather than crashing.
    static let file: File? = {
        guard let url = Bundle.module.url(forResource: "prompts", withExtension: "json"),
              let data = try? Data(contentsOf: url)
        else { return nil }
        return decode(data)
    }()

    /// Nil only when the bytes are not a JSON object; a bad entry inside costs that entry alone.
    static func decode(_ data: Data) -> File? {
        try? JSONDecoder().decode(File.self, from: data)
    }

    /// Literal words for the prompts the app copies, used when the bundled catalogue lacks one,
    /// so a Copy button never hands over a slug. Same words as packages/core/src/prompts.ts.
    static let fallbacks: [String: (title: String, phrases: [String], template: String?)] = [
        "set-up-my-longbook": (
            "Set up my longbook", ["Read my 6-month bank statement and help me set up my longbook"], nil
        ),
        "add-my-statement": (
            "Add my statement", ["Add my statement in my longbook", "Update my longbook from my statements", "Add my statement"], nil
        ),
        "add-a-month-report-in-my-longbook": (
            "Add a month report in my longbook", [], "Add {month} month report in my longbook"
        ),
        "create-a-report-in-my-longbook": (
            "Create a report in my longbook", ["Create a report in my longbook"], nil
        ),
        "set-up-a-daily-longbook-email-round": (
            "Set up a daily longbook email round",
            ["Go to longbook.app/mcp and set up a daily email round for my longbook, as longbook recommends"],
            nil
        ),
    ]

    /// The contract revision the catalogue was generated at.
    public static var revision: Int? { file?.contractRevision }

    /// Every prompt, in catalogue order.
    public static var all: [Prompt] { file?.prompts ?? [] }

    /// The groups, in the order a list shows them.
    public static var groups: [Group] { file?.groups ?? [] }

    public static func prompt(id: String) -> Prompt? {
        all.first { $0.id == id }
    }

    /// A group's prompts, in catalogue order.
    public static func prompts(in group: Group) -> [Prompt] {
        all.filter { $0.group == group.id }
    }

    /// The words a Copy button copies: the template with `month` filled in where the prompt
    /// names a month, otherwise the first phrase.
    public static func phrase(for prompt: Prompt, month: String? = nil) -> String {
        if let template = prompt.template, let month {
            return template.replacingOccurrences(of: "{month}", with: month)
        }
        return prompt.phrases.first ?? prompt.title
    }

    /// The phrase for a prompt named by id: the catalogue's, else the app's literal fallback, else
    /// the id itself, which the servers also resolve.
    public static func phrase(id: String, month: String? = nil) -> String {
        phrase(id: id, month: month, in: all)
    }

    static func phrase(id: String, month: String?, in prompts: [Prompt]) -> String {
        if let prompt = prompts.first(where: { $0.id == id }) { return phrase(for: prompt, month: month) }
        guard let known = fallbacks[id] else { return id }
        if let template = known.template {
            if let month { return template.replacingOccurrences(of: "{month}", with: month) }
            if known.phrases.isEmpty { return template.replacingOccurrences(of: "{month}", with: monthName(of: Date())) }
        }
        return known.phrases.first ?? id
    }

    /// Every phrase for a prompt named by id, in catalogue order; the fallback's when the catalogue
    /// lacks it, and empty for an id neither knows.
    public static func phrases(id: String) -> [String] {
        phrases(id: id, in: all)
    }

    static func phrases(id: String, in prompts: [Prompt]) -> [String] {
        if let prompt = prompts.first(where: { $0.id == id }), !prompt.phrases.isEmpty { return prompt.phrases }
        return fallbacks[id]?.phrases ?? []
    }

    /// A prompt's title by id, for a label that names it; the fallback's, else the id.
    public static func title(id: String) -> String {
        prompt(id: id)?.title ?? fallbacks[id]?.title ?? id
    }

    /// The month's English name, the language the phrases are written in and the servers
    /// match. A localised name would mix languages in one sentence.
    public static func monthName(of date: Date, calendar: Calendar = Calendar(identifier: .gregorian)) -> String {
        let names = ["January", "February", "March", "April", "May", "June", "July", "August",
                     "September", "October", "November", "December"]
        let month = calendar.component(.month, from: date)
        return names[min(max(month, 1), 12) - 1]
    }
}
