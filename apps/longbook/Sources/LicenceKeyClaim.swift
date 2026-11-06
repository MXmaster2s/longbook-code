import Foundation
import LongbookCore

#if DIRECT
/// Binds a licence key from a purchase email to the signed-in account: the polar-claim
/// function checks the key and writes the entitlement, then the app re-reads it. Only the
/// website Mac app has it.
@MainActor
final class LicenceKeyClaim: ObservableObject {
    static let shared = LicenceKeyClaim()
    private static let claimURL = URL(string: "https://xbrnijgctmovoqbbmgmb.supabase.co/functions/v1/polar-claim")!

    @Published private(set) var busy = false

    private init() {}

    /// Nil on success, otherwise the reason to show under the field.
    func claim(key: String, auth: AuthViewModel, entitlement: EntitlementStore) async -> String? {
        let key = LicenceKeyWords.trimmed(key)
        guard !key.isEmpty else { return "Licence key is empty." }
        guard !busy else { return "Activation is already in progress." }
        busy = true
        defer { busy = false }
        do {
            let (data, status) = try await PolarFunctions.post(Self.claimURL, body: ["key": key], auth: auth)
            guard (200..<300).contains(status) else {
                return LicenceKeyWords.refusal(why: PolarFunctions.why(data), status: status)
            }
            await entitlement.refresh()
            DirectStore.shared.waitingOnBrowser = false
            return nil
        } catch {
            Telemetry.shared.failed(.purchase, error)
            if case PolarFunctions.Failure.signedOut = error { return "Sign in first, then activate." }
            return error is URLError ? LicenceKeyWords.unreachable : error.localizedDescription
        }
    }
}
#endif

/// The signed-in POST the polar functions take, and the `why` they give with a refusal.
enum PolarFunctions {
    enum Failure: Error { case signedOut }

    @MainActor
    static func post(_ url: URL, body: [String: String], auth: AuthViewModel) async throws -> (Data, Int) {
        guard let token = await auth.accessToken() else { throw Failure.signedOut }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await URLSession.shared.data(for: request)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }

    private struct Why: Decodable { let why: String? }

    static func why(_ data: Data) -> String? {
        guard let why = (try? JSONDecoder().decode(Why.self, from: data))?.why, !why.isEmpty else { return nil }
        return why
    }
}
