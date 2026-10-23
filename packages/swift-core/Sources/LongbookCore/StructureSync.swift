// The structure store: the vault's tag DEFINITIONS — kind, name, icon — kept in the owner's
// account row. Values never travel: no commitment names, amounts, dates, notes or details,
// and no template. `payload(from:)` is the whole boundary; StructureSyncTests holds it.
import Foundation
import Supabase

public enum StructureSync {
    /// One synced definition. These fields plus the owner's id are the ENTIRE vocabulary of
    /// the structure store — nothing else leaves the device.
    public struct Row: Codable, Equatable {
        public let kind: String
        public let name: String
        public let name_key: String
        public let icon: String?
        public let source: String
    }

    /// The definitions worth syncing, straight from the registry. Library-seeded entries
    /// sync as provenance "library"; everything else is the owner's own vocabulary.
    public static func payload(from vault: Vault) -> [Row] {
        (vault.tags ?? []).map { def in
            Row(
                kind: def.kind,
                name: def.name,
                name_key: def.nameKey,
                icon: def.icon,
                source: (def.isDefault ?? false) ? "library" : "user"
            )
        }
    }

    private struct Upsert: Encodable {
        let user_id: UUID
        let kind: String
        let name_key: String
        let name: String
        let icon: String?
        let source: String
        let updated_at: Date
    }

    /// Mirror the registry into the owner's rows. Quiet by design — a failed sync never
    /// interrupts the owner; the next save tries again.
    @discardableResult
    public static func push(_ rows: [Row]) async -> Bool {
        guard !rows.isEmpty else { return true }
        do {
            let session = try await supabase.auth.session
            let now = Date()
            let upserts = rows.map { row in
                Upsert(
                    user_id: session.user.id, kind: row.kind, name_key: row.name_key,
                    name: row.name, icon: row.icon, source: row.source, updated_at: now
                )
            }
            try await supabase.from("structures")
                .upsert(upserts, onConflict: "user_id,kind,name_key").execute()
            return true
        } catch {
            return false
        }
    }
}
