import Foundation

/// longbook Support's server: the conversation goes up, the answer streams back as it is
/// written, then the articles it used. It also rates an answer, emails a code that proves
/// an address, and sends the conversation to the team. Signed out, a random id is counted.
public enum SupportCloud {
    public struct Turn: Codable, Sendable, Equatable {
        public let role: String
        public let content: String
        public init(role: String, content: String) {
            self.role = role
            self.content = content
        }
    }

    public struct Source: Codable, Sendable, Hashable {
        public let slug: String
        public let title: String
    }

    public enum Event: Sendable {
        case text(String)
        case done(id: Int?, sources: [Source], email: Bool)
    }

    public enum Failure: Error, Sendable {
        /// The day's questions are used: the words say so and offer email.
        case limit(String)
        case busy(String)

        public var message: String {
            switch self {
            case .limit(let words), .busy(let words): words
            }
        }
    }

    private struct Line: Decodable {
        let text: String?
        let done: Bool?
        let id: Int?
        let articles: [Source]?
        let email: Bool?
        let error: String?
        let code: String?
    }

    private struct Reply: Decodable {
        let sent: Bool?
        let email: String?
        let error: String?
        let code: String?
    }

    /// One plain call: the action and its fields up, the answer or its refusal back.
    private static func post(_ fields: [String: Any], askerId: String, token: String?) async throws -> Reply {
        var request = URLRequest(url: SUPABASE_URL.appendingPathComponent("functions/v1/support"))
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("Bearer \(token ?? SUPABASE_ANON_KEY)", forHTTPHeaderField: "Authorization")
        request.setValue(SUPABASE_ANON_KEY, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: fields.merging(["install_id": askerId]) { a, _ in a })
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw Failure.busy("Support can't be reached. Check your connection and try again.")
        }
        let reply = (try? JSONDecoder().decode(Reply.self, from: data)) ?? Reply(sent: nil, email: nil, error: nil, code: nil)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            let words = reply.error ?? "That didn't go through. Try again in a minute."
            throw reply.code == "limit" ? Failure.limit(words) : Failure.busy(words)
        }
        return reply
    }

    /// A thumbs up or down on one answer. Best effort: a lost rating is not worth an error.
    public static func rate(answer id: Int, up: Bool, askerId: String, token: String?) async {
        _ = try? await post(["action": "feedback", "answer_id": id, "rating": up ? "up" : "down"], askerId: askerId, token: token)
    }

    /// A six-digit code to the address, so the team's reply can go there.
    public static func requestCode(email: String, askerId: String, token: String?) async throws {
        _ = try await post(["action": "code", "email": email], askerId: askerId, token: token)
    }

    /// The conversation to the team: `reply` to a proven address (or the signed-in account's),
    /// `review` with no address at all. Answers the address the reply will go to.
    @discardableResult
    public static func send(
        _ turns: [Turn], review: Bool, email: String?, code: String?, rating: Bool?, app: String,
        screenshotPNG: Data?, askerId: String, token: String?
    ) async throws -> String? {
        var fields: [String: Any] = [
            "action": "send", "kind": review ? "review" : "reply", "app": app,
            "messages": turns.map { ["role": $0.role, "content": $0.content] },
        ]
        if let email { fields["email"] = email }
        if let code { fields["code"] = code }
        if let rating { fields["rating"] = rating ? "up" : "down" }
        if let screenshotPNG { fields["screenshot"] = screenshotPNG.base64EncodedString() }
        return try await post(fields, askerId: askerId, token: token).email
    }

    public static func ask(_ turns: [Turn], askerId: String, token: String?) -> AsyncThrowingStream<Event, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var request = URLRequest(url: SUPABASE_URL.appendingPathComponent("functions/v1/support"))
                    request.httpMethod = "POST"
                    request.timeoutInterval = 60
                    request.setValue("Bearer \(token ?? SUPABASE_ANON_KEY)", forHTTPHeaderField: "Authorization")
                    request.setValue(SUPABASE_ANON_KEY, forHTTPHeaderField: "apikey")
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.httpBody = try JSONSerialization.data(withJSONObject: [
                        "messages": turns.map { ["role": $0.role, "content": $0.content] },
                        "install_id": askerId,
                    ])
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                    guard status == 200 else {
                        var data = Data()
                        for try await byte in bytes { data.append(byte) }
                        let said = try? JSONDecoder().decode(Line.self, from: data)
                        let words = said?.error ?? "Support couldn't answer just now. Try again in a minute, or tap Email us."
                        throw said?.code == "limit" ? Failure.limit(words) : Failure.busy(words)
                    }
                    for try await line in bytes.lines where line.hasPrefix("data: ") {
                        guard let event = try? JSONDecoder().decode(Line.self, from: Data(line.dropFirst(6).utf8)) else { continue }
                        if let words = event.error { throw Failure.busy(words) }
                        if let text = event.text { continuation.yield(.text(text)) }
                        if event.done == true { continuation.yield(.done(id: event.id, sources: event.articles ?? [], email: event.email ?? false)) }
                    }
                    continuation.finish()
                } catch let failure as Failure {
                    continuation.finish(throwing: failure)
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: Failure.busy("Support can't be reached. Check your connection, or tap Email us."))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
