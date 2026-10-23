// Licence and Cloud status — the iOS mirror of electron/entitlement.ts. Cached in
// UserDefaults (status, not a credential) so a launch offline honours whatever was last known.
// PostgREST is hit directly over URLSession, the raw-fetch style the store client uses too.
import Foundation
import Supabase

public let TRIAL_DAYS = 3
private let CACHE_KEY = "longbook.entitlement.v2"

public struct EntitlementState: Codable, Equatable {
    public var signedIn: Bool
    public var trialEndsAt: Date?
    public var hasLicence: Bool
    public var readOnly: Bool
    /// longbook Cloud: a subscription in good standing, or the trial, which covers it.
    /// Every server feature the app offers asks this first.
    public var hasCloud: Bool
    /// The subscription's status as the server holds it; nil when the account has no row.
    public var cloudStatus: String?
    /// When the paid period ends, or ended. Nil without a row.
    public var cloudExpiresAt: Date?
    /// Whether Apple charges again at cloudExpiresAt.
    public var cloudAutoRenew: Bool

    public init(
        signedIn: Bool, trialEndsAt: Date?, hasLicence: Bool, readOnly: Bool,
        hasCloud: Bool = false, cloudStatus: String? = nil, cloudExpiresAt: Date? = nil, cloudAutoRenew: Bool = false
    ) {
        self.signedIn = signedIn
        self.trialEndsAt = trialEndsAt
        self.hasLicence = hasLicence
        self.readOnly = readOnly
        self.hasCloud = hasCloud
        self.cloudStatus = cloudStatus
        self.cloudExpiresAt = cloudExpiresAt
        self.cloudAutoRenew = cloudAutoRenew
    }

    public static let signedOut = EntitlementState(signedIn: false, trialEndsAt: nil, hasLicence: false, readOnly: false)

    /// Cloud as the server rules it in has_cloud, read from what the client can see: a
    /// subscription active or in its grace period with time left, or a live trial. A
    /// hand-made grant is the server's alone, so this stands in only when it cannot answer.
    public static func cloud(status: String?, expiresAt: Date?, trialEndsAt: Date?, now: Date = Date()) -> Bool {
        let subscribed = ["active", "grace"].contains(status ?? "") && (expiresAt.map { $0 > now } ?? false)
        let trialLive = trialEndsAt.map { now < $0 } ?? false
        return subscribed || trialLive
    }

    /// Whole days left, rounded up, or nil when there's no trial clock to count. Read-only is
    /// its own fact — a lapsed trial reports zero, never a negative countdown.
    public func trialDaysLeft(_ now: Date = Date()) -> Int? {
        guard let trialEndsAt, !hasLicence else { return nil }
        return max(0, Int(ceil(trialEndsAt.timeIntervalSince(now) / 86_400)))
    }
}

@MainActor
public final class EntitlementStore: ObservableObject {
    @Published public private(set) var state: EntitlementState = .signedOut
    /// True once this launch has asked the server, or found a cached answer: the purchase
    /// screen waits for it rather than flashing in front of a licensed owner.
    @Published public private(set) var known = false

    public init() {
        if let data = UserDefaults.standard.data(forKey: CACHE_KEY),
           let cached = try? JSONDecoder().decode(EntitlementState.self, from: data) {
            state = cached
            known = cached.signedIn
        }
    }

    private func write(_ next: EntitlementState) {
        state = next
        if let data = try? JSONEncoder().encode(next) {
            UserDefaults.standard.set(data, forKey: CACHE_KEY)
        }
    }

    public func clear() {
        write(.signedOut)
        known = false
    }

    /// Any failure — offline, a rate limit, an RLS hiccup — leaves the cache exactly as it was,
    /// same rule as the desktop: losing the network must never flip anyone to read-only.
    public func refresh() async {
        defer { known = true }
        guard let session = try? await supabase.auth.session else {
            write(.signedOut)
            return
        }
        let userId = session.user.id.uuidString
        let headers = [
            "apikey": SUPABASE_ANON_KEY_FOR_REST,
            "Authorization": "Bearer \(session.accessToken)",
        ]
        guard
            let entitlement: [EntitlementRow] = try? await getJSON(
                path: "entitlements", query: "user_id=eq.\(userId)&select=status", headers: headers)
        else { return }
        // Read apart from the licence: an empty answer means no subscription, while a
        // failed one keeps whatever was last known, by the same offline rule.
        let cloud: [CloudRow]? = try? await getJSON(
            path: "cloud_subscriptions", query: "user_id=eq.\(userId)&select=status,expires_at,auto_renew", headers: headers)

        // A licence is for life: every later version, major ones included.
        let hasLicence = entitlement.first?.status == "active"
        // longbook is bought before it is used, with a 7-day refund in place of a trial, so
        // there is no trial clock: an account without a licence meets the purchase screen.
        let trialEndsAt: Date? = nil
        let readOnly = !hasLicence
        let subscription = cloud.map { rows in
            (status: rows.first?.status, expiresAt: rows.first?.expires_at, autoRenew: rows.first?.auto_renew ?? false)
        } ?? (status: state.cloudStatus, expiresAt: state.cloudExpiresAt, autoRenew: state.cloudAutoRenew)
        // The one rule, asked of the server for the account the token names, since a grant
        // shows nowhere else. Unanswered, offline or before the rule is installed, the
        // local reading of the same rule stands in.
        let hasCloud = await serverHasCloud(headers: headers)
            ?? EntitlementState.cloud(status: subscription.status, expiresAt: subscription.expiresAt, trialEndsAt: trialEndsAt)
        write(EntitlementState(
            signedIn: true, trialEndsAt: trialEndsAt, hasLicence: hasLicence, readOnly: readOnly,
            hasCloud: hasCloud, cloudStatus: subscription.status, cloudExpiresAt: subscription.expiresAt,
            cloudAutoRenew: subscription.autoRenew
        ))
    }

    // MARK: - raw PostgREST

    private struct EntitlementRow: Decodable { let status: String }
    private struct CloudRow: Decodable { let status: String; let expires_at: Date?; let auto_renew: Bool? }

    /// has_cloud() as the server answers it for the token's own account: a bare JSON
    /// boolean. Nil for anything else, so the caller falls back rather than flips.
    private func serverHasCloud(headers: [String: String]) async -> Bool? {
        var req = URLRequest(url: URL(string: "https://xbrnijgctmovoqbbmgmb.supabase.co/rest/v1/rpc/has_cloud")!)
        req.httpMethod = "POST"
        req.httpBody = Data("{}".utf8)
        headers.forEach { req.setValue($1, forHTTPHeaderField: $0) }
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        guard let (data, response) = try? await URLSession.shared.data(for: req),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        switch String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines) {
        case "true": return true
        case "false": return false
        default: return nil
        }
    }

    private func getJSON<T: Decodable>(path: String, query: String, headers: [String: String]) async throws -> T {
        var url = URL(string: "https://xbrnijgctmovoqbbmgmb.supabase.co/rest/v1/\(path)")!
        url.append(percentEncodedQuery: query)
        var req = URLRequest(url: url)
        headers.forEach { req.setValue($1, forHTTPHeaderField: $0) }
        let (data, _) = try await URLSession.shared.data(for: req)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601WithFractionalSeconds
        return try decoder.decode(T.self, from: data)
    }
}

// Mirrors AuthClient.swift's constant — kept local so this file has no compile-time dependency
// on that one beyond the shared `supabase` client.
private let SUPABASE_ANON_KEY_FOR_REST =
    "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inhicm5pamdjdG1vdm9xYmJtZ21iIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODU3NzQ0NDQsImV4cCI6MjEwMTM1MDQ0NH0.ZamrPyf3UmAmbqzzAcce_Ocb1bKNq19wVxTtaC32a-g"

private extension URL {
    mutating func append(percentEncodedQuery query: String) {
        self = URL(string: absoluteString + "?" + query) ?? self
    }
}

private extension JSONDecoder.DateDecodingStrategy {
    static var iso8601WithFractionalSeconds: JSONDecoder.DateDecodingStrategy {
        .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = f.date(from: raw) { return date }
            f.formatOptions = [.withInternetDateTime]
            if let date = f.date(from: raw) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "bad date: \(raw)")
        }
    }
}
