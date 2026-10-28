import LongbookCore
import StoreKit
import SwiftUI

/// The App Store door: one non-consumable licence and one Cloud subscription, bought here
/// and recorded on the server, which verifies Apple's signed transaction and writes the
/// row a web purchase would — so one purchase unlocks every platform.
@MainActor
final class StoreClient: ObservableObject {
    static let shared = StoreClient()
    /// The product App Store Connect sells; scripts/asc-iap.mts carries the same literal.
    static let productId = "app.longbook.licence"
    /// longbook Cloud, a month at a time; the server's apple-purchase names it too.
    static let cloudProductId = "app.longbook.cloud.monthly"
    static let endpoint = URL(string: "https://xbrnijgctmovoqbbmgmb.supabase.co/functions/v1/apple-purchase")!

    @Published private(set) var product: Product?
    @Published private(set) var cloudProduct: Product?
    @Published private(set) var busy = false
    @Published var failure: String?
    /// A restore that found and recorded a purchase says so; a buy or a new restore clears it.
    @Published var notice: String?

    /// The price the store shows, in the reader's own currency, or nil until it loads.
    var displayPrice: String? { product?.displayPrice }
    /// Cloud's price per period, as the store states it, or nil until it loads.
    var cloudDisplayPrice: String? { cloudProduct?.displayPrice }

    /// "a month" — the period as the store states it, so no screen guesses it.
    var cloudPeriodWords: String {
        let period = cloudPeriod
        return period.value == 1 ? "a \(period.unit)" : "\(period.value) \(period.unit)s"
    }

    /// "every month" — the same period, as a renewal reads.
    var cloudEveryWords: String {
        let period = cloudPeriod
        return period.value == 1 ? "every \(period.unit)" : "every \(period.value) \(period.unit)s"
    }

    private var cloudPeriod: (value: Int, unit: String) {
        guard let period = cloudProduct?.subscription?.subscriptionPeriod else { return (1, "month") }
        switch period.unit {
        case .day: return (period.value, "day")
        case .week: return (period.value, "week")
        case .month: return (period.value, "month")
        case .year: return (period.value, "year")
        @unknown default: return (1, "month")
        }
    }

    func load() async {
        guard product == nil || cloudProduct == nil else { return }
        let found = (try? await Product.products(for: [Self.productId, Self.cloudProductId])) ?? []
        product = product ?? found.first { $0.id == Self.productId }
        cloudProduct = cloudProduct ?? found.first { $0.id == Self.cloudProductId }
    }

    /// Buys, tells the server, finishes the transaction, then re-reads the entitlement.
    /// The server is told before the finish, so a purchase is never lost between the two.
    func buy(auth: AuthViewModel, entitlement: EntitlementStore) async {
        guard !busy else { return }
        busy = true
        failure = nil
        notice = nil
        defer { busy = false }
        await load()
        guard let product else {
            failure = "The App Store has no price for longbook yet. Try again in a moment."
            return
        }
        do {
            switch try await product.purchase() {
            case .success(let verification):
                guard case .verified(let transaction) = verification else {
                    failure = "The App Store’s receipt could not be verified."
                    return
                }
                Telemetry.shared.send("app.licence_purchased")
                try await record(jws: verification.jwsRepresentation, auth: auth)
                await transaction.finish()
                await entitlement.refresh()
            case .userCancelled:
                break
            case .pending:
                failure = "The purchase is waiting for approval."
            @unknown default:
                break
            }
        } catch {
            Telemetry.shared.failed(.purchase, error)
            failure = error.localizedDescription
        }
    }

    /// Starts the Cloud subscription the same way. The receipt carries the account's id
    /// as its app account token, so the server binds it to the account that bought it.
    /// True once the server has the purchase.
    @discardableResult
    func subscribe(auth: AuthViewModel, entitlement: EntitlementStore) async -> Bool {
        guard !busy else { return false }
        busy = true
        failure = nil
        notice = nil
        defer { busy = false }
        await load()
        guard let cloudProduct else {
            failure = "The App Store has no price for longbook Cloud yet. Try again in a moment."
            return false
        }
        guard let userId = await auth.userId() else {
            failure = StoreError.signedOut.errorDescription
            return false
        }
        do {
            switch try await cloudProduct.purchase(options: [.appAccountToken(userId)]) {
            case .success(let verification):
                guard case .verified(let transaction) = verification else {
                    failure = "The App Store’s receipt could not be verified."
                    return false
                }
                Telemetry.shared.send("app.cloud_subscribed")
                try await record(jws: verification.jwsRepresentation, auth: auth)
                await transaction.finish()
                await entitlement.refresh()
                return true
            case .userCancelled:
                break
            case .pending:
                failure = "The purchase is waiting for approval."
            @unknown default:
                break
            }
        } catch {
            Telemetry.shared.failed(.purchase, error)
            failure = error.localizedDescription
        }
        return false
    }

    /// The line under every Restore Purchase button. AppStore.sync shows Apple's own sign-in
    /// sheet, which asks for the Apple Account's password; a longbook account has none.
    static let restoreWords = "Apple may ask for your Apple Account, the one you use for the App Store. It isn't your longbook sign-in."

    /// Every licence and subscription this Apple Account holds, told to the server again —
    /// the way back after a reinstall, on a second device, or for a purchase the server never
    /// heard about. AppStore.sync is Apple's sheet, never longbook's sign-in.
    func restore(auth: AuthViewModel, entitlement: EntitlementStore) async {
        guard !busy else { return }
        busy = true
        failure = nil
        notice = nil
        defer { busy = false }
        do {
            try await AppStore.sync()
        } catch StoreKitError.userCancelled {
            // Apple's sheet was dismissed: nothing was checked, so nothing is reported.
            return
        } catch {
            // The device's own record of its purchases is still read below.
        }
        var found = false
        var recorded = false
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result, Self.sells(transaction.productID) else { continue }
            found = true
            do {
                try await record(jws: result.jwsRepresentation, auth: auth)
                recorded = true
            } catch {
                Telemetry.shared.failed(.purchase, error)
                failure = Self.restoreFailureWords(error)
            }
        }
        if !found {
            failure = "No longbook purchase is on this Apple Account. Restore with the Apple Account you bought with."
        } else if recorded, failure == nil {
            notice = "Purchase restored."
        }
        await entitlement.refresh()
    }

    /// A restore failure names the purchase as found, so it never reads as a longbook sign-in
    /// refused. A lapsed longbook session is the one case that asks for longbook's sign-in.
    private static func restoreFailureWords(_ error: Error) -> String {
        if case StoreError.signedOut = error { return "Your purchase was found. Sign in to longbook again, then restore." }
        return "Your purchase was found, but could not be recorded: \(error.localizedDescription). Try again in a moment."
    }

    /// Days after buying in which longbook backs a refund request, as the terms say.
    static let refundDays = 7

    /// The licence this Apple ID bought itself, while it is young enough to refund: its id
    /// and the day the window closes. A family copy is the buyer's to refund, so it never shows.
    func refundable(now: Date = Date()) async -> (id: UInt64, closes: Date)? {
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result, transaction.productID == Self.productId,
                  transaction.ownershipType == .purchased, transaction.revocationDate == nil else { continue }
            let closes = transaction.purchaseDate.addingTimeInterval(Double(Self.refundDays) * 86_400)
            return closes > now ? (transaction.id, closes) : nil
        }
        return nil
    }

    /// Transactions the App Store delivers on its own — a purchase finished elsewhere, a
    /// renewal, a refund — reach the server too. Runs for the life of the view that starts it.
    func listen(auth: AuthViewModel, entitlement: EntitlementStore) async {
        for await result in Transaction.updates {
            guard case .verified(let transaction) = result, Self.sells(transaction.productID) else { continue }
            try? await record(jws: result.jwsRepresentation, auth: auth)
            await transaction.finish()
            await entitlement.refresh()
        }
    }

    /// Whether a transaction is one of longbook's own two products.
    private static func sells(_ productID: String) -> Bool {
        productID == productId || productID == cloudProductId
    }

    private func record(jws: String, auth: AuthViewModel) async throws {
        guard let token = await auth.accessToken() else { throw StoreError.signedOut }
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["jws": jws])
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let why = (try? JSONDecoder().decode(Failure.self, from: data))?.error
            throw StoreError.server(why ?? "The purchase could not be recorded (\(status)). Restore purchases to try again.")
        }
    }

    private struct Failure: Decodable { let error: String? }

    enum StoreError: LocalizedError {
        case signedOut
        case server(String)

        var errorDescription: String? {
            switch self {
            case .signedOut: "Sign in first, then buy."
            case .server(let why): why
            }
        }
    }
}
