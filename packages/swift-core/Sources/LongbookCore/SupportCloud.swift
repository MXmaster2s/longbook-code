import Foundation

/// longbook Support's server: the conversation goes up, the answer streams back as it is
/// written, then the articles it used, and a rating on one answer goes up later. Signed out,
/// a support-only random id is counted.
public enum SupportCloud {
    public struct Turn: Codable, Sendable, Equatable {
        public let role: String
        public let content: String
        public init(role: String, content: String) {
            self.role = role
            self.content = content
        }
    }

    /// A screenshot sent with the last message, read by Claude alongside it.
    public struct Attachment: Sendable {
        public let mediaType: String
        public let data: Data
        public init(mediaType: String, data: Data) {
            self.mediaType = mediaType
            self.data = data
        }
    }

    public struct Source: Codable, Sendable, Hashable {
        public let slug: String
        public let title: String
    }

    public enum Event: Sendable {
        case text(String)
        case done(id: Int?, key: String?, sources: [Source], email: Bool)
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
        let key: String?
        let articles: [Source]?
        let email: Bool?
        let error: String?
        let code: String?
    }

    private struct Reply: Decodable {
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
        let reply = (try? JSONDecoder().decode(Reply.self, from: data)) ?? Reply(error: nil, code: nil)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            let words = reply.error ?? "That didn't go through. Try again in a minute."
            throw reply.code == "limit" ? Failure.limit(words) : Failure.busy(words)
        }
        return reply
    }

    /// A thumbs up or down on one answer. Best effort: a lost rating is not worth an error.
    public static func rate(answer id: Int, key: String, up: Bool, askerId: String, token: String?) async {
        _ = try? await post(["action": "feedback", "answer_id": id, "key": key, "rating": up ? "up" : "down"], askerId: askerId, token: token)
    }

    public static func ask(_ turns: [Turn], attachment: Attachment? = nil, askerId: String, token: String?) -> AsyncThrowingStream<Event, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var request = URLRequest(url: SUPABASE_URL.appendingPathComponent("functions/v1/support"))
                    request.httpMethod = "POST"
                    request.timeoutInterval = 60
                    request.setValue("Bearer \(token ?? SUPABASE_ANON_KEY)", forHTTPHeaderField: "Authorization")
                    request.setValue(SUPABASE_ANON_KEY, forHTTPHeaderField: "apikey")
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    var fields: [String: Any] = [
                        "messages": turns.map { ["role": $0.role, "content": $0.content] },
                        "install_id": askerId,
                    ]
                    if let attachment { fields["image"] = ["media_type": attachment.mediaType, "data": attachment.data.base64EncodedString()] }
                    request.httpBody = try JSONSerialization.data(withJSONObject: fields)
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                    guard status == 200 else {
                        var data = Data()
                        for try await byte in bytes { data.append(byte) }
                        let said = try? JSONDecoder().decode(Line.self, from: data)
                        let words = said?.error ?? "Support couldn't answer just now. Try again in a minute, or email the team."
                        throw said?.code == "limit" ? Failure.limit(words) : Failure.busy(words)
                    }
                    for try await line in bytes.lines where line.hasPrefix("data: ") {
                        guard let event = try? JSONDecoder().decode(Line.self, from: Data(line.dropFirst(6).utf8)) else { continue }
                        if let words = event.error { throw Failure.busy(words) }
                        if let text = event.text { continuation.yield(.text(text)) }
                        if event.done == true { continuation.yield(.done(id: event.id, key: event.key, sources: event.articles ?? [], email: event.email ?? false)) }
                    }
                    continuation.finish()
                } catch let failure as Failure {
                    continuation.finish(throwing: failure)
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: Failure.busy("Support can't be reached. Check your connection, or email the team."))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
