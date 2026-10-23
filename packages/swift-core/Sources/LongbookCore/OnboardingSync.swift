// The first run's position, mirrored on the account the moment a step ends, so a second
// device opens on the Waiting screen and resumes where the first one stopped. One row per
// account, the owner's alone; a failed call changes nothing in the app.
import Foundation
import Supabase

public enum OnboardingSync {
    public struct Progress: Decodable, Sendable {
        public let stage: String
        public let device: String
        public let updated_at: Date
    }

    private struct Row: Encodable {
        let user_id: UUID
        let stage: String
        let device: String
        let updated_at: Date
    }

    /// Writes the stage under the signed-in account. Silent on failure: the sidecar in the
    /// vault folder is the record that must hold; this is the fast path between devices.
    public static func push(stage: String, device: String) async {
        guard let session = try? await supabase.auth.session else { return }
        let row = Row(user_id: session.user.id, stage: stage, device: device, updated_at: Date())
        _ = try? await supabase.from("onboarding_progress").upsert(row).execute()
    }

    /// The account's row, or nil when there is none or nothing answers.
    public static func pull() async -> Progress? {
        let rows: [Progress]? = try? await supabase
            .from("onboarding_progress").select("stage,device,updated_at").execute().value
        return rows?.first
    }
}
