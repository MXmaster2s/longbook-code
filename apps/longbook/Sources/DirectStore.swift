import LongbookCore
import SwiftUI
#if os(macOS)
import AppKit
#endif

/// The longbook.app door, for the direct Mac build: Polar sells the licence on the website,
/// and its webhook writes the entitlement, so the app opens checkout in the browser, takes a
/// licence key, and re-reads the entitlement. StoreKit is never touched here.
@MainActor
final class DirectStore: ObservableObject {
    static let shared = DirectStore()
    private static let checkoutURL = URL(string: "https://xbrnijgctmovoqbbmgmb.supabase.co/functions/v1/polar-checkout")!
    private static let claimURL = URL(string: "https://xbrnijgctmovoqbbmgmb.supabase.co/functions/v1/polar-claim")!

    @Published private(set) var busy = false
    @Published var failure: String?
    /// Checkout is open in the browser; the activate screen says so until the licence lands.
    @Published var waitingOnBrowser = false

    private init() {}

    /// Asks for a checkout page for this account and opens it in the browser.
    func buy(auth: AuthViewModel) async {
        if await open(action: "checkout", auth: auth) { waitingOnBrowser = true }
    }

    /// Opens Polar's customer portal: receipts, the order and its invoice.
    func managePurchase(auth: AuthViewModel) async {
        await open(action: "portal", auth: auth)
    }

    /// Asks the server again, as the app does on coming forward.
    func checkAgain(entitlement: EntitlementStore) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        await entitlement.refresh()
        if entitlement.state.hasLicence { waitingOnBrowser = false }
    }

    /// Binds a licence key to the signed-in account. Nil on success, otherwise the reason to show.
    func claim(key: String, auth: AuthViewModel, entitlement: EntitlementStore) async -> String? {
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return "Licence key is empty." }
        guard !busy else { return "Activation is already in progress." }
        busy = true
        defer { busy = false }
        do {
            let (data, status) = try await post(Self.claimURL, body: ["key": key], auth: auth)
            guard (200..<300).contains(status) else {
                return Self.why(data) ?? "The licence key could not be activated (\(status))."
            }
            await entitlement.refresh()
            waitingOnBrowser = false
            return nil
        } catch {
            Telemetry.shared.failed(.purchase, error)
            return Self.words(error)
        }
    }

    /// True once the page is open in the browser.
    @discardableResult
    private func open(action: String, auth: AuthViewModel) async -> Bool {
        guard !busy else { return false }
        busy = true
        failure = nil
        defer { busy = false }
        do {
            let (data, status) = try await post(Self.checkoutURL, body: ["action": action], auth: auth)
            guard (200..<300).contains(status),
                  let found = try? JSONDecoder().decode(Page.self, from: data),
                  let url = URL(string: found.url), url.scheme == "https" else {
                failure = Self.why(data) ?? "longbook.app could not open the page (\(status)). Try again in a moment."
                return false
            }
            #if os(macOS)
            NSWorkspace.shared.open(url)
            #endif
            return true
        } catch {
            Telemetry.shared.failed(.purchase, error)
            failure = Self.words(error)
            return false
        }
    }

    private func post(_ url: URL, body: [String: String], auth: AuthViewModel) async throws -> (Data, Int) {
        guard let token = await auth.accessToken() else { throw DirectError.signedOut }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await URLSession.shared.data(for: request)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }

    private struct Page: Decodable { let url: String }
    private struct Why: Decodable { let why: String? }

    private static func why(_ data: Data) -> String? {
        guard let why = (try? JSONDecoder().decode(Why.self, from: data))?.why, !why.isEmpty else { return nil }
        return why
    }

    private static func words(_ error: Error) -> String {
        if case DirectError.signedOut = error { return "Sign in first, then buy." }
        return error is URLError ? "longbook.app could not be reached. Check the connection, then try again." : error.localizedDescription
    }

    enum DirectError: Error { case signedOut }
}
