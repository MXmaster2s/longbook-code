// "Reorganise my longbook": the whole book goes once to longbook's server, Claude reads it
// with the guide's chapter, and what comes back is a list of proposals the app applies as
// one change. The server keeps nothing of the book; a run counts against a monthly share.
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
    }

    /// One change the server proposes: a write tool's name and its arguments, already held
    /// to the shared validator there, and the reason in a few words.
    public struct Proposal: @unchecked Sendable {
        public let kind: String
        public let payload: [String: Any]
        public let why: String
    }

    public struct Answer: @unchecked Sendable {
        public let proposals: [Proposal]
        /// Answers the server's sieve dropped: counted, never named.
        public let dropped: Int
        public let summary: String
    }

    /// The most the app sends: the file's own bytes, as the server caps them.
    public static let maxVaultBytes = 2_000_000

    public static func newRunId() -> String { UUID().uuidString.lowercased() }

    /// The file's text to the server, and the proposals back.
    public static func run(vaultText: String, token: String?) async throws -> Answer {
        guard let token, !token.isEmpty else { throw CloudError.notSignedIn }
        guard vaultText.utf8.count <= maxVaultBytes else { throw CloudError.tooLarge }
        var request = URLRequest(url: SUPABASE_URL.appendingPathComponent("functions/v1/reorganise"))
        request.httpMethod = "POST"
        request.timeoutInterval = 300
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(SUPABASE_ANON_KEY, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["run_id": newRunId(), "vault": vaultText])
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw CloudError.unreachable
        }
        let said = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            if said?["code"] as? String == "share_spent" { throw CloudError.shareSpent }
            if (response as? HTTPURLResponse)?.statusCode == 413 { throw CloudError.tooLarge }
            throw CloudError.server(said?["error"] as? String ?? "Your longbook could not be reorganised right now. Try again in a minute.")
        }
        guard let said else { throw CloudError.server("The server's answer could not be read.") }
        let proposals = (said["proposals"] as? [[String: Any]] ?? []).compactMap { one -> Proposal? in
            guard let kind = one["kind"] as? String, let payload = one["payload"] as? [String: Any] else { return nil }
            return Proposal(kind: kind, payload: payload, why: one["why"] as? String ?? "")
        }
        return Answer(proposals: proposals, dropped: (said["dropped"] as? NSNumber)?.intValue ?? 0, summary: said["summary"] as? String ?? "")
    }
}
