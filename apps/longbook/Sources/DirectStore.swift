import LongbookCore
import SwiftUI
#if os(macOS)
import AppKit
#endif

/// The longbook.app door, for the direct Mac build: Polar sells the licence on the website,
/// and its webhook writes the entitlement, so the app opens checkout in the browser and
/// re-reads the entitlement. Keys are claimed by LicenceKeyClaim. StoreKit is never touched here.
@MainActor
final class DirectStore: ObservableObject {
    static let shared = DirectStore()
    private static let checkoutURL = URL(string: "https://xbrnijgctmovoqbbmgmb.supabase.co/functions/v1/polar-checkout")!

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

    /// True once the page is open in the browser.
    @discardableResult
    private func open(action: String, auth: AuthViewModel) async -> Bool {
        guard !busy else { return false }
        busy = true
        failure = nil
        defer { busy = false }
        do {
            let (data, status) = try await PolarFunctions.post(Self.checkoutURL, body: ["action": action], auth: auth)
            guard (200..<300).contains(status),
                  let found = try? JSONDecoder().decode(Page.self, from: data),
                  let url = URL(string: found.url), url.scheme == "https" else {
                failure = PolarFunctions.why(data) ?? "longbook.app could not open the page (\(status)). Try again in a moment."
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

    private struct Page: Decodable { let url: String }

    private static func words(_ error: Error) -> String {
        if case PolarFunctions.Failure.signedOut = error { return "Sign in first, then buy." }
        return error is URLError ? "longbook.app could not be reached. Check the connection, then try again." : error.localizedDescription
    }
}
