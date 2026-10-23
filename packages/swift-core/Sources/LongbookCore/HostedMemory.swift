// The hosted copy of the memory: pushed by this app on the owner's explicit choice,
// read by the hosted MCP server with the same account, deleted the moment they revoke.
// One row per user; the owner's JWT is the only door — see the hosted_memories policies.
import CryptoKit
import Foundation
import Supabase

public enum HostedMemory {
    /// Where an MCP client reaches the hosted copy — the public longbook address,
    /// which fronts the function. Shown in settings for connecting.
    public static let endpoint = URL(string: "https://longbook.app/mcp")!

    // The same public pair AuthClient ships; auth REST calls here carry them directly.
    private static let authBase = URL(string: "https://xbrnijgctmovoqbbmgmb.supabase.co/auth/v1")!
    private static let anonKey =
        "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inhicm5pamdjdG1vdm9xYmJtZ21iIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODU3NzQ0NDQsImV4cCI6MjEwMTM1MDQ0NH0.ZamrPyf3UmAmbqzzAcce_Ocb1bKNq19wVxTtaC32a-g"

    /// One AI the owner has let in — the consent GoTrue remembers for a client.
    public struct AIGrant: Identifiable, Sendable {
        public let clientId: String
        public let name: String
        public let grantedAt: Date?
        public var id: String { clientId }
    }

    private struct GrantRow: Decodable {
        struct Client: Decodable {
            let id: String
            let name: String?
        }
        let client: Client
        let granted_at: String?
    }

    private static func authRequest(_ method: String, path: String, query: [URLQueryItem] = []) async throws -> URLRequest {
        let session = try await supabase.auth.session
        var components = URLComponents(url: authBase.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        return request
    }

    // MARK: access keys — the OAuth fallback for clients without a browser flow

    /// What a key may do. Never a write scope: nothing in the cloud rewrites the memory —
    /// a proposing key files suggestions the app applies, where they stand for review.
    public enum KeyScope: String, Sendable, CaseIterable {
        case read
        case propose

        /// The words the app shows, and the words the server stores.
        public var label: String { self == .read ? "Read only" : "Read and suggest changes" }
        public var explanation: String {
            self == .read
                ? "It can read your memory and answer questions about it."
                : "It can also suggest changes, which wait for your review in Changes the next time you open longbook."
        }
        var stored: [String] { self == .read ? ["memory:read"] : ["memory:read", "memory:propose"] }
    }

    public struct AccessKey: Identifiable, Sendable {
        public let id: UUID
        public let name: String
        public let scope: KeyScope
        public let createdAt: Date?
        public let lastUsedAt: Date?
        public let expiresAt: Date?
    }

    private struct KeyRow: Decodable {
        let id: UUID
        let name: String
        let scopes: [String]?
        let created_at: String
        let last_used_at: String?
        let expires_at: String?
    }

    private struct NewKeyRow: Encodable {
        let user_id: UUID
        let name: String
        let key_hash: String
        let scopes: [String]
        let expires_at: String?
    }

    /// A fresh key and its hash. The key is shown once and never stored anywhere —
    /// the server keeps only the hash, so a lost key is replaced, never recovered.
    public static func mintKeyMaterial() -> (key: String, hash: String) {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let body = Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        let key = "lbk_\(body)"
        let hash = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        return (key, hash)
    }

    /// Active keys, newest first. Empty on any failure — informational, like grants.
    public static func accessKeys() async -> [AccessKey] {
        guard let rows: [KeyRow] = try? await supabase
            .from("access_keys")
            .select("id,name,scopes,created_at,last_used_at,expires_at")
            .is("revoked_at", value: nil)
            .order("created_at", ascending: false)
            .execute().value
        else { return [] }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        func date(_ raw: String?) -> Date? {
            raw.flatMap { iso.date(from: $0) ?? plain.date(from: $0) }
        }
        return rows.map {
            AccessKey(
                id: $0.id,
                name: $0.name,
                scope: ($0.scopes ?? []).contains("memory:propose") ? .propose : .read,
                createdAt: date($0.created_at),
                lastUsedAt: date($0.last_used_at),
                expiresAt: date($0.expires_at)
            )
        }
    }

    /// Creates a named key and answers the one showing of it, or nil on failure.
    public static func createAccessKey(name: String, scope: KeyScope = .read, expires: Date? = nil) async -> String? {
        let material = mintKeyMaterial()
        do {
            let session = try await supabase.auth.session
            try await supabase.from("access_keys")
                .insert(NewKeyRow(
                    user_id: session.user.id,
                    name: name,
                    key_hash: material.hash,
                    scopes: scope.stored,
                    expires_at: expires.map { ISO8601DateFormatter().string(from: $0) }
                ))
                .execute()
            return material.key
        } catch {
            return nil
        }
    }

    /// Revoking stamps the row; the key stops answering on its next use.
    @discardableResult
    public static func revokeAccessKey(id: UUID) async -> Bool {
        do {
            // returning: .minimal on purpose — the default asks PostgREST for the whole
            // row back, which needs SELECT on key_hash, and that column is deliberately
            // unreadable by any client: the hash IS the credential the server redeems.
            try await supabase.from("access_keys")
                .update(["revoked_at": ISO8601DateFormatter().string(from: Date())], returning: .minimal)
                .eq("id", value: id)
                .execute()
            return true
        } catch {
            return false
        }
    }

    /// The AIs connected right now. Empty on any failure — the list is informational,
    /// and a scary error would outrank what it explains.
    public static func grants() async -> [AIGrant] {
        guard let request = try? await authRequest("GET", path: "user/oauth/grants"),
              let (data, _) = try? await URLSession.shared.data(for: request),
              let rows = try? JSONDecoder().decode([GrantRow].self, from: data)
        else { return [] }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return rows.map { row in
            AIGrant(
                clientId: row.client.id,
                name: row.client.name?.isEmpty == false ? row.client.name! : "An AI",
                grantedAt: row.granted_at.flatMap { iso.date(from: $0) }
            )
        }
    }

    /// Disconnects one AI: it must ask again. The hosted copy itself is untouched.
    public static func revokeGrant(clientId: String) async -> String? {
        do {
            let request = try await authRequest(
                "DELETE", path: "user/oauth/grants",
                query: [URLQueryItem(name: "client_id", value: clientId)]
            )
            let (_, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            return (200...299).contains(status) ? nil : "That connection couldn't be removed. Try again in a moment."
        } catch {
            return "That connection couldn't be removed. Check your connection and try again."
        }
    }

    private struct HostedRow: Encodable {
        let user_id: UUID
        let memory: AnyJSON
        let pushed_at: Date
    }

    private struct StatusRow: Decodable {
        let pushed_at: Date
        let web_propose: Bool?
    }

    /// When the hosted copy was last pushed, or nil when none exists (or nothing answers).
    public static func pushedAt() async -> Date? {
        await status()?.pushed_at
    }

    private static func status() async -> StatusRow? {
        let rows: [StatusRow]? = try? await supabase
            .from("hosted_memories").select("pushed_at,web_propose").execute().value
        return rows?.first
    }

    /// Whether an AI the owner is signed into may suggest changes. Off until they say so;
    /// the database enforces the same answer, so this only reflects it.
    public static func webProposeAllowed() async -> Bool {
        await status()?.web_propose ?? false
    }

    /// The owner's switch. Nil on success, a sentence on failure.
    public static func setWebPropose(_ on: Bool) async -> String? {
        do {
            let session = try await supabase.auth.session
            try await supabase.from("hosted_memories")
                .update(["web_propose": on])
                .eq("user_id", value: session.user.id)
                .execute()
            return nil
        } catch {
            return "That couldn't be changed. Check your connection and try again."
        }
    }

    /// Replaces the hosted copy with the memory as it stands. The bytes are the vault
    /// file's own — no derivation, the data policy already minimized at write time.
    public static func push(memoryData: Data) async -> String? {
        do {
            let session = try await supabase.auth.session
            let memory = try JSONDecoder().decode(AnyJSON.self, from: memoryData)
            let row = HostedRow(user_id: session.user.id, memory: memory, pushed_at: Date())
            try await supabase.from("hosted_memories").upsert(row).execute()
            return nil
        } catch {
            return "The hosted copy couldn't be updated. Check your connection and try again."
        }
    }

    /// Tells the server the app is still in use, so the copy's ninety days start again: at
    /// most once a day per account, stamped only when the server has heard. An update,
    /// never an insert, so a copy switched off elsewhere stays gone.
    @discardableResult
    public static func touchIfDue(now: Date = Date()) async -> Bool {
        do {
            let session = try await supabase.auth.session
            let key = "longbook.hostedCopyTouchedAt." + session.user.id.uuidString
            guard now.timeIntervalSince1970 - UserDefaults.standard.double(forKey: key) > 24 * 60 * 60 else { return false }
            try await supabase.from("hosted_memories")
                .update(["pushed_at": ISO8601DateFormatter().string(from: now)])
                .eq("user_id", value: session.user.id).execute()
            UserDefaults.standard.set(now.timeIntervalSince1970, forKey: key)
            return true
        } catch {
            return false
        }
    }

    /// Revoke is a delete, not a lapse: the row is gone before this returns.
    public static func revoke() async -> String? {
        do {
            let session = try await supabase.auth.session
            try await supabase.from("hosted_memories")
                .delete().eq("user_id", value: session.user.id).execute()
            return nil
        } catch {
            return "The hosted copy couldn't be removed. Check your connection and try again."
        }
    }
}
