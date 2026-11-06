import Foundation
import LongbookCore

/// The share-report Edge Function's client. One report at a time, always by the owner's
/// hand — the server never sees the vault, only the document being shared.
enum ShareReportClient {
    static let endpoint = URL(string: "https://xbrnijgctmovoqbbmgmb.supabase.co/functions/v1/share-report")!
    /// Where a viewer opens a share: the site's own address, proxied to the function.
    static let viewerBase = "https://longbook.app/r/"

    /// The link a viewer opens, named the way the server names it.
    static func viewerURL(id: String) -> String {
        viewerBase + id
    }

    struct Created: Decodable {
        let id: String
        let password: String
        let url: String
        let expiresAt: String

        enum CodingKeys: String, CodingKey {
            case id, password, url
            case expiresAt = "expires_at"
        }
    }

    struct Comment: Decodable {
        /// The server's id for it, which deleting one names.
        let id: String?
        let moduleId: String
        let author: String?
        let body: String
        let createdAt: String

        enum CodingKeys: String, CodingKey {
            case id
            case moduleId = "module_id"
            case author, body
            case createdAt = "created_at"
        }

        /// The line a comment becomes in the report file: "Asha — The rent looks high".
        var line: String {
            let name = author?.trimmingCharacters(in: .whitespaces) ?? ""
            return "\(name.isEmpty ? "Someone" : name) — \(body)"
        }
    }

    /// What came back from a comments call: the lines, and how long the link still has.
    struct Comments {
        let comments: [Comment]
        let expiresAt: String?
    }

    enum ShareError: LocalizedError {
        case server(String, status: Int)

        var errorDescription: String? {
            if case .server(let why, _) = self { return why }
            return nil
        }

        /// The server no longer has this share: revoked from another device, or expired.
        var shareIsGone: Bool {
            if case .server(_, let status) = self { return status == 404 || status == 410 }
            return false
        }
    }

    private struct Failure: Decodable {
        let error: String?
    }

    static func create(reportJSON: Data, hours: Int, token: String) async throws -> Created {
        guard let report = try JSONSerialization.jsonObject(with: reportJSON) as? [String: Any] else {
            throw ShareError.server("That report file couldn’t be read as a report.", status: 0)
        }
        let body: [String: Any] = ["action": "create", "report": report, "hours": hours]
        return try await call(body, token: token)
    }

    static func comments(id: String, token: String) async throws -> Comments {
        struct Reply: Decodable {
            let comments: [Comment]
            let expiresAt: String?

            enum CodingKeys: String, CodingKey {
                case comments
                case expiresAt = "expires_at"
            }
        }
        let reply: Reply = try await call(["action": "comments", "id": id], token: token)
        return Comments(comments: reply.comments, expiresAt: reply.expiresAt)
    }

    static func revoke(id: String, token: String) async throws {
        struct Reply: Decodable { let ok: Bool }
        let _: Reply = try await call(["action": "revoke", "id": id], token: token)
    }

    static func deleteComment(shareId: String, commentId: String, token: String) async throws {
        struct Reply: Decodable { let ok: Bool }
        let _: Reply = try await call(["action": "delete_comment", "id": shareId, "comment_id": commentId], token: token)
    }

    /// Deletes one comment line from a report: first from the server while its link lives, so
    /// the next Pull comments cannot bring it back, then from the file. Nil when it is gone.
    @MainActor
    static func deleteLine(_ line: String, moduleAt index: Int, reportId: String, model: DashboardModel, auth: AuthViewModel?) async -> String? {
        if let shareId = model.shareId(forReport: reportId) {
            guard let token = await auth?.accessToken() else { return "Sign in again to delete this comment." }
            do {
                let live = try await comments(id: shareId, token: token)
                for comment in live.comments where comment.line == line {
                    if let id = comment.id { try await deleteComment(shareId: shareId, commentId: id, token: token) }
                }
            } catch let failure as ShareError where failure.shareIsGone {
                // The link has ended, and its comments went with it.
            } catch {
                Telemetry.shared.failed(.reportShare, error)
                return error.friendlyDescription
            }
        }
        return model.removeCommentLine(line, moduleAt: index, report: reportId) ? nil : model.saveError
    }

    /// One POST shape for every action. Errors surface the server's own sentence when it
    /// sent one; anything else gets an honest generic line.
    private static func call<T: Decodable>(_ body: [String: Any], token: String) async throws -> T {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let why = (try? JSONDecoder().decode(Failure.self, from: data))?.error
            throw ShareError.server(why ?? "The share server answered \(status). Try again in a moment.", status: status)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}
