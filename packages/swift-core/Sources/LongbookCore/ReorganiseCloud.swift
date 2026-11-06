// "Reorganise my longbook": the book goes to longbook's server one part at a time, Claude
// reads each part with the guide's chapter, and the parts' proposals come back as one list
// the app applies as one change. The server keeps nothing of the book; a run is one share.
import Foundation

public enum ReorganiseCloud {
    public enum CloudError: LocalizedError {
        case notSignedIn
        case tooLarge
        case server(String)
        case unreachable
        /// The account's share of runs is spent for now; the words never say how many.
        case shareSpent

        public var errorDescription: String? {
            switch self {
            case .notSignedIn: return "Sign in first — your longbook is reorganised by your own account."
            case .tooLarge: return "This longbook is larger than the server reorganises. Ask your own AI with the “Reorganise my longbook” prompt instead."
            case .server(let said): return said
            case .unreachable: return "longbook's server could not be reached. Check the connection and try again."
            case .shareSpent:
                return "longbook's server has reorganised your longbook as often as it can for now. Try again next month, or ask your own AI with the “Reorganise my longbook” prompt."
            }
        }

        /// A failure asking again cannot mend.
        var isFinal: Bool {
            switch self {
            case .notSignedIn, .tooLarge, .shareSpent: return true
            case .server, .unreachable: return false
            }
        }
    }

    /// One change the server proposes: a write tool's name and its arguments, already held
    /// to the shared validator there, and the reason in a few words.
    public struct Proposal: @unchecked Sendable {
        public let kind: String
        public let payload: [String: Any]
        public let why: String

        public init(kind: String, payload: [String: Any], why: String) {
            self.kind = kind
            self.payload = payload
            self.why = why
        }
    }

    public struct Answer: @unchecked Sendable {
        public let proposals: [Proposal]
        /// Answers the server's sieve dropped: counted, never named.
        public let dropped: Int
        public let summary: String
    }

    /// One part's answer: its proposals, where it sits, and what it chose, for the next part.
    public struct PartAnswer: @unchecked Sendable {
        public let proposals: [Proposal]
        public let dropped: Int
        public let summary: String
        public let parts: Int
        public let carry: Any?

        public init(proposals: [Proposal], dropped: Int, summary: String, parts: Int, carry: Any?) {
            self.proposals = proposals
            self.dropped = dropped
            self.summary = summary
            self.parts = parts
            self.carry = carry
        }
    }

    /// One request's body to the server, and its status and body back.
    public typealias Send = @Sendable (Data) async throws -> (status: Int, body: Data)

    /// The most the app sends: the file's own bytes, as the server caps them.
    public static let maxVaultBytes = 2_000_000
    /// Commitments the server reads in one part; the server's own count wins once it answers.
    public static let partSize = 40

    public static func newRunId() -> String { UUID().uuidString.lowercased() }

    /// How many parts the server will read this book in, for the progress line before it says.
    public static func partCount(vaultText: String) -> Int {
        let root = (try? JSONSerialization.jsonObject(with: Data(vaultText.utf8))) as? [String: Any]
        let count = (root?["commitments"] as? [Any])?.count ?? 0
        return max(1, (count + partSize - 1) / partSize)
    }

    /// The file's text to the server, part by part, and every part's proposals back as one.
    public static func run(vaultText: String, token: String?,
                           progress: @escaping @MainActor @Sendable (_ part: Int, _ of: Int) -> Void = { _, _ in }) async throws -> Answer {
        guard let token, !token.isEmpty else { throw CloudError.notSignedIn }
        guard vaultText.utf8.count <= maxVaultBytes else { throw CloudError.tooLarge }
        let send: Send = { body in
            var request = URLRequest(url: SUPABASE_URL.appendingPathComponent("functions/v1/reorganise"))
            request.httpMethod = "POST"
            request.timeoutInterval = 150
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue(SUPABASE_ANON_KEY, forHTTPHeaderField: "apikey")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
            let (data, response) = try await URLSession.shared.data(for: request)
            return ((response as? HTTPURLResponse)?.statusCode ?? 0, data)
        }
        return try await runParts(vaultText: vaultText, runId: newRunId(), send: send, progress: progress)
    }

    /// Every part in turn under one run id, each asked again once when it fails. A part that
    /// fails twice fails the pass, and nothing of it is kept.
    public static func runParts(vaultText: String, runId: String, send: Send,
                                progress: @escaping @MainActor @Sendable (_ part: Int, _ of: Int) -> Void) async throws -> Answer {
        var total = partCount(vaultText: vaultText)
        var answers: [PartAnswer] = []
        var carry: Any?
        var index = 0
        while index < total {
            await progress(index + 1, total)
            var body: [String: Any] = ["run_id": runId, "vault": vaultText, "part": index]
            if let carry { body["carry"] = carry }
            let data = try JSONSerialization.data(withJSONObject: body)
            let answer = try await askTwice(data, send: send)
            answers.append(answer)
            carry = answer.carry
            total = max(answer.parts, index + 1)
            index += 1
        }
        return combine(answers)
    }

    private static func askTwice(_ data: Data, send: Send) async throws -> PartAnswer {
        do {
            return try await askOnce(data, send: send)
        } catch let error as CloudError where error.isFinal {
            throw error
        } catch {
            return try await askOnce(data, send: send)
        }
    }

    private static func askOnce(_ data: Data, send: Send) async throws -> PartAnswer {
        let reply: (status: Int, body: Data)
        do {
            reply = try await send(data)
        } catch {
            throw CloudError.unreachable
        }
        return try readPart(status: reply.status, data: reply.body)
    }

    /// One part's reply read: an error in the owner's words, or its proposals.
    public static func readPart(status: Int, data: Data) throws -> PartAnswer {
        let said = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        guard status == 200 else {
            if said?["code"] as? String == "share_spent" { throw CloudError.shareSpent }
            if status == 413 { throw CloudError.tooLarge }
            throw CloudError.server(said?["error"] as? String ?? "Your longbook could not be reorganised right now. Try again in a minute.")
        }
        guard let said else { throw CloudError.server("The server's answer could not be read.") }
        let proposals = (said["proposals"] as? [[String: Any]] ?? []).compactMap { one -> Proposal? in
            guard let kind = one["kind"] as? String, let payload = one["payload"] as? [String: Any] else { return nil }
            return Proposal(kind: kind, payload: payload, why: one["why"] as? String ?? "")
        }
        return PartAnswer(proposals: proposals, dropped: (said["dropped"] as? NSNumber)?.intValue ?? 0,
                          summary: said["summary"] as? String ?? "",
                          parts: (said["parts"] as? NSNumber)?.intValue ?? 1, carry: said["carry"])
    }

    /// The parts as one answer: proposals in part order, a change two parts both proposed
    /// kept once, and one summary. A one-part pass keeps the model's own words.
    public static func combine(_ parts: [PartAnswer]) -> Answer {
        var seen = Set<String>()
        var proposals: [Proposal] = []
        for part in parts {
            for proposal in part.proposals {
                let body = (try? JSONSerialization.data(withJSONObject: proposal.payload, options: [.sortedKeys])) ?? Data()
                let key = proposal.kind + " " + String(decoding: body, as: UTF8.self)
                if seen.insert(key).inserted { proposals.append(proposal) }
            }
        }
        let dropped = parts.reduce(0) { $0 + $1.dropped }
        let summary = parts.count == 1 ? parts[0].summary : counted(proposals, parts: parts.count)
        return Answer(proposals: proposals, dropped: dropped, summary: summary)
    }

    /// What a pass of several parts did, counted by kind of change.
    static func counted(_ proposals: [Proposal], parts: Int) -> String {
        var renamed = 0, categorised = 0, linked = 0, merged = 0, removedTags = 0
        var people = 0, accounts = 0, updated = 0, charges = 0
        for p in proposals {
            let set = p.payload["set"] as? [String: Any] ?? [:]
            switch p.kind {
            case "update_commitment":
                if set["name"] != nil { renamed += 1 }
                if set["tag"] != nil { categorised += 1 }
                if set["member"] != nil || set["account"] != nil { linked += 1 }
            case "rename_tag": merged += 1
            case "delete_tag": removedTags += 1
            case "add_person": people += 1
            case "add_account": accounts += 1
            case "update_account", "update_person": updated += 1
            case "remove_charges": charges += (p.payload["dates"] as? [Any])?.count ?? 1
            default: break
            }
        }
        let say = { (n: Int, one: String, many: String) -> String? in n == 0 ? nil : n == 1 ? "1 \(one)" : "\(n) \(many)" }
        let clauses = [
            say(renamed, "name made plain", "names made plain"),
            say(categorised, "commitment categorised", "commitments categorised"),
            say(linked, "commitment linked to a person or an account", "commitments linked to a person or an account"),
            say(merged, "tag merged", "tags merged"),
            say(removedTags, "tag removed", "tags removed"),
            say(people, "person added", "people added"),
            say(accounts, "account added", "accounts added"),
            say(updated, "account or person tidied", "accounts and people tidied"),
            say(charges, "doubled charge removed", "doubled charges removed"),
        ].compactMap { $0 }
        guard !clauses.isEmpty else { return "" }
        let list = clauses.count == 1 ? clauses[0] : clauses.dropLast().joined(separator: ", ") + " and " + clauses.last!
        return "Read in \(parts) parts: \(list)."
    }
}
