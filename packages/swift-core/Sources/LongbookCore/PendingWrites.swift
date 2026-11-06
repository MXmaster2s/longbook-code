// Writes proposed from the cloud, waiting for this app.
//
// A scheduled agent files a proposal in `mcp_pending_writes`; nothing out there touches the
// memory. This app fetches what waits, applies it through the outside-change door — so it
// stands in Changes — and stamps the row. Applying itself is pure: see `PendingApply`.
import Foundation
import Supabase

public struct PendingWrite: Identifiable, @unchecked Sendable {
    public let id: UUID
    /// The write tool proposed: add_commitments, update_commitment, mark_paid, add_charges,
    /// remove_charges, cancel_commitment, promote_to_recurring, leave_insight, update_account,
    /// update_person, update_charge, set_planned_count, add_member, add_account, rename_tag,
    /// delete_tag, delete_commitment, create_report.
    public let kind: String
    /// The tool's own arguments, exactly as the shared validator accepted them. `Any`
    /// because a payload is arbitrary JSON — read-only once made, hence @unchecked.
    public let payload: [String: Any]
    /// Where the data came from — "gmail:18c2…" — carried into _provenance.source.
    public let sourceRef: String?
    /// The key's name, so the review says who proposed it.
    public let keyName: String?
    /// Which door it came through: a named key, or a signed-in web session.
    public let origin: String
    /// The AI as its requests named it, when the door could tell.
    public let client: String?
    public let createdAt: Date?
    /// Set on a proposal this app could not apply, with the reason in the owner's words.
    public let failure: String?

    public init(
        id: UUID, kind: String, payload: [String: Any],
        sourceRef: String? = nil, keyName: String? = nil, origin: String = "key",
        client: String? = nil, createdAt: Date? = nil, failure: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.payload = payload
        self.sourceRef = sourceRef
        self.keyName = keyName
        self.origin = origin
        self.client = client
        self.createdAt = createdAt
        self.failure = failure
    }

    /// Who to sign the rows as: the key's own name, so Changes reads "· claude-daily-brief";
    /// a signed-in AI by the name it gave; failing both, the door it came through. A name
    /// the app signs with is the app's alone: worn by a key or client, it reads as the door.
    public var author: String {
        let name = (keyName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let agent = (client ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let chosen = name.isEmpty ? agent : name
        guard !chosen.isEmpty, !OwnEdit.appNames.contains(chosen.lowercased()) else {
            return origin == "oauth" ? "Your AI" : "mcp"
        }
        return chosen
    }
}

public enum PendingWrites {
    /// Everything waiting for this owner, oldest first — one network read, empty on any
    /// failure. A proposal that cannot be fetched is not lost; it waits for the next open.
    public static func waiting() async -> [PendingWrite] {
        await fetch(waiting: true)
    }

    /// Proposals this app tried and could not apply, newest first. They are the ones the
    /// owner most needs to see: nothing else in the system will ever mention them again.
    public static func unapplied() async -> [PendingWrite] {
        await fetch(waiting: false)
    }

    private static func fetch(waiting: Bool) async -> [PendingWrite] {
        struct Row: Decodable {
            let id: UUID
            let kind: String
            let payload: AnyJSON
            let source_ref: String?
            let created_at: String?
            let origin: String?
            let client: String?
            let failure: String?
            let access_keys: KeyName?
            struct KeyName: Decodable { let name: String? }
        }
        var query = supabase
            .from("mcp_pending_writes")
            .select("id,kind,payload,source_ref,created_at,origin,client,failure,access_keys(name)")
        query = waiting
            ? query.is("applied_at", value: nil).is("failed_at", value: nil)
            : query.not("failed_at", operator: .is, value: AnyJSON.null)
        guard let rows: [Row] = try? await query
            .order("created_at", ascending: waiting)
            .limit(200)
            .execute().value
        else { return [] }

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        return rows.compactMap { row in
            guard let data = try? JSONEncoder().encode(row.payload),
                  let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { return nil }
            return PendingWrite(
                id: row.id,
                kind: row.kind,
                payload: payload,
                sourceRef: row.source_ref,
                keyName: row.access_keys?.name,
                origin: row.origin ?? "key",
                client: row.client,
                createdAt: row.created_at.flatMap { iso.date(from: $0) ?? plain.date(from: $0) },
                failure: row.failure
            )
        }
    }

    /// Stamped applied, so no other device applies it again.
    @discardableResult
    public static func markApplied(_ id: UUID) async -> Bool {
        await stamp(id, ["applied_at": ISO8601DateFormatter().string(from: Date())])
    }

    /// Stamped failed WITH its reason: a proposal the app cannot apply must say why,
    /// where the owner can see it, rather than being retried forever or silently dropped.
    @discardableResult
    public static func markFailed(_ id: UUID, reason: String) async -> Bool {
        await stamp(id, [
            "failed_at": ISO8601DateFormatter().string(from: Date()),
            "failure": String(reason.prefix(400)),
        ])
    }

    /// The owner has seen a failure and does not need to see it again.
    @discardableResult
    public static func dismissFailed(_ id: UUID) async -> Bool {
        do {
            try await supabase.from("mcp_pending_writes").delete().eq("id", value: id).execute()
            return true
        } catch {
            return false
        }
    }

    private static func stamp(_ id: UUID, _ values: [String: String]) async -> Bool {
        do {
            try await supabase.from("mcp_pending_writes")
                .update(values)
                .eq("id", value: id)
                .execute()
            return true
        } catch {
            return false
        }
    }
}
