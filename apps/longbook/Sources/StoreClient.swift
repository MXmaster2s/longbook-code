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
    /// Whether the two products have come from the App Store. Every price on screen waits
    /// for them: there is no price of longbook's own to stand in.
    @Published private(set) var loadState: LoadState = .loading
    @Published private(set) var busy = false
    @Published var failure: String?
    /// A restore that found and recorded a purchase says so; a buy or a new restore clears it.
    @Published var notice: String?
    /// A refund or a stopped Family Sharing seen on this device, said once in an alert.
    @Published var ended: String?
    private var updates: Task<Void, Never>?

    enum LoadState { case loading, loaded, failed }

    /// False when Screen Time or a device restriction turns In-App Purchases off: no screen
    /// then offers a Buy button that cannot work.
    var canMakePayments: Bool { AppStore.canMakePayments }

    /// Apple's own subscriptions page, for the Mac, which has no in-app sheet for it.
    static let subscriptionsURL = URL(string: "https://apps.apple.com/account/subscriptions")!

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

    /// Asks the App Store for both products until it has them; a failed ask is said on screen
    /// with Try Again, which calls this once more.
    func load() async {
        guard product == nil || cloudProduct == nil else {
            loadState = .loaded
            return
        }
        loadState = .loading
        let found = (try? await Product.products(for: [Self.productId, Self.cloudProductId])) ?? []
        product = product ?? found.first { $0.id == Self.productId }
        cloudProduct = cloudProduct ?? found.first { $0.id == Self.cloudProductId }
        loadState = product != nil && cloudProduct != nil ? .loaded : .failed
    }

    static let pricesFailedWords = "The App Store prices could not be loaded. Check your connection, then try again."
    static let purchasesOffTitle = "Purchases are turned off on this device"
    static let purchasesOffWords = "Screen Time or a device restriction blocks In-App Purchases here. Ask whoever manages this device, such as your family organiser, to allow them, or buy on another device and use Restore Purchase here."

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
            failure = Self.pricesFailedWords
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
            failure = Self.pricesFailedWords
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

    /// Starts listening, once for the app's life, to what the App Store delivers on its own: a
    /// purchase approved by a parent, a renewal, a refund, a Family Sharing copy arriving or
    /// stopping. Each reaches the server, then is finished. Later calls do nothing.
    func start(auth: AuthViewModel, entitlement: EntitlementStore) {
        guard updates == nil else { return }
        updates = Task { [weak self] in
            for await result in Transaction.updates {
                guard let self, case .verified(let transaction) = result, Self.sells(transaction.productID) else { continue }
                self.sayIfEnded(transaction)
                try? await self.record(jws: result.jwsRepresentation, auth: auth, auto: true)
                await transaction.finish()
                await entitlement.refresh()
            }
        }
    }

    /// At launch and at each sign-in, with no tap: every licence and subscription this Apple
    /// Account holds, a family member's copy included, and the latest of each that was
    /// revoked, told to the server. An automatic record never takes a purchase from another
    /// longbook account; Restore Purchase does.
    func sync(auth: AuthViewModel, entitlement: EntitlementStore) async {
        guard await auth.accessToken() != nil else { return }
        var told = false
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result, Self.sells(transaction.productID) else { continue }
            if (try? await record(jws: result.jwsRepresentation, auth: auth, auto: true)) != nil { told = true }
        }
        for id in [Self.productId, Self.cloudProductId] {
            guard let result = await Transaction.latest(for: id), case .verified(let transaction) = result,
                  transaction.revocationDate != nil else { continue }
            sayIfEnded(transaction)
            if (try? await record(jws: result.jwsRepresentation, auth: auth, auto: true)) != nil { told = true }
        }
        if told { await entitlement.refresh() }
    }

    /// A revocation from the last 30 days, said once per transaction, in the words its cause needs.
    private func sayIfEnded(_ transaction: StoreKit.Transaction) {
        guard let revoked = transaction.revocationDate, revoked > Date().addingTimeInterval(-30 * 86_400) else { return }
        let key = "longbook.store.endedSaid"
        var said = UserDefaults.standard.stringArray(forKey: key) ?? []
        let id = String(transaction.id)
        guard !said.contains(id) else { return }
        said.append(id)
        UserDefaults.standard.set(Array(said.suffix(20)), forKey: key)
        ended = Self.endedWords(productID: transaction.productID, family: transaction.ownershipType == .familyShared)
    }

    /// What ended and what to do next, for a revocation this device saw.
    static func endedWords(productID: String, family: Bool) -> String {
        if productID == cloudProductId {
            return family
                ? "Family Sharing no longer shares longbook Cloud with you, so that subscription has ended on this account. Subscribe under Account to have your own."
                : "Apple refunded your longbook Cloud subscription, so it has ended on this account. Subscribe under Account to have it again."
        }
        return family
            ? "Family Sharing no longer shares longbook with you, so the licence on this account has ended. Your longbook folder and everything in it stay yours. Buy longbook to keep adding to it."
            : "Apple refunded your longbook purchase, so the licence on this account has ended. Your longbook folder and everything in it stay yours. Buy longbook again to keep adding to it."
    }

    /// The same news when only the server knows it: the licence's row says revoked.
    static let licenceEndedWords = "The licence on this account has ended: Apple refunded it, Family Sharing stopped sharing it, or it was restored to another longbook account. Your longbook folder stays yours. Buy longbook, or restore with the Apple Account that bought it."
    /// And for Cloud, whose row says revoked.
    static let cloudEndedWords = "Apple refunded this longbook Cloud subscription, or Family Sharing stopped sharing it, so the subscription has ended on this account."

    /// Whether this Apple Account's own Cloud subscription will bill again: Apple's renewal
    /// info, read on the device. A family member's copy bills the organiser, so it is not counted.
    func ownCloudRenews() async -> Bool {
        await load()
        guard let statuses = try? await cloudProduct?.subscription?.status else { return false }
        for status in statuses {
            guard case .verified(let renewal) = status.renewalInfo, case .verified(let transaction) = status.transaction,
                  transaction.ownershipType == .purchased, renewal.willAutoRenew else { continue }
            if [.subscribed, .inGracePeriod, .inBillingRetryPeriod].contains(status.state) { return true }
        }
        return false
    }

    /// Whether a transaction is one of longbook's own two products.
    private static func sells(_ productID: String) -> Bool {
        productID == productId || productID == cloudProductId
    }

    /// `auto` marks a record the app sends on its own, which the server never lets move a
    /// purchase from another account.
    private func record(jws: String, auth: AuthViewModel, auto: Bool = false) async throws {
        guard let token = await auth.accessToken() else { throw StoreError.signedOut }
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["jws": jws, "auto": auto] as [String: Any])
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

/// Says a refund or a stopped Family Sharing the moment this device sees it, rather than
/// removing access in silence. Its own view, so the root does not redraw with the store.
struct PurchaseEndedAlert: ViewModifier {
    @ObservedObject private var store = StoreClient.shared

    func body(content: Content) -> some View {
        content
            .measured("root_purchase_ended", .alert, when: store.ended != nil)
            .alert("A purchase has ended", isPresented: Binding(get: { store.ended != nil }, set: { if !$0 { store.ended = nil } })) {
                Button("OK") { Measure.used("purchase_ended_ok"); store.ended = nil }
            } message: {
                Text(store.ended ?? "")
            }
    }
}
