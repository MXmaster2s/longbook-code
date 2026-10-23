// Sign-in: identity and licence status only, never the financial memory — same split as the
// desktop's electron/auth.ts, same Supabase project. PKCE via the official SDK, completed
// through the longbook://auth/callback deep link (see LongbookApp's onOpenURL). The session
// itself lives in the Keychain: that is the SDK's own default on Apple platforms.
import AuthenticationServices
import Foundation
import Supabase

/// The server's own wording for a stale or over-fast code request — backend dialect at
/// the reader's most anxious moment. Everything else passes through unchanged: an
/// unmapped error is a server message a human wrote, not code we should second-guess.
private func friendlyAuthMessage(_ error: Error) -> String {
    guard case .api(_, let code, _, _) = error as? AuthError else { return error.localizedDescription }
    switch code {
    case .otpExpired:
        return "That code has expired. Send another and enter it within a few minutes."
    case .overEmailSendRateLimit, .overRequestRateLimit:
        return "Too many codes requested. Wait a moment, then try again."
    default:
        return error.localizedDescription
    }
}

/// The hourly cap on codes is the server's own sentence, with the minutes to wait. Auth's own
/// limits keep their words above; this one is flagged so the screen can add a way to write to us.
private func isHourlyLimit(_ error: Error) -> Bool {
    guard case .api(_, let code, _, let response) = error as? AuthError else { return false }
    return response.statusCode == 429 && code != .overEmailSendRateLimit && code != .overRequestRateLimit
}

/// A sign-in failure in fixed words, for the app's error count: who refused it and its code
/// ("apple" 1000, "auth" otp_expired). Never the message, never the address.
public struct AuthFailure: Sendable, Equatable {
    public let source: String
    public let code: String

    public init(source: String, code: String) {
        self.source = source
        self.code = code
    }

    public init(_ error: Error) {
        let ns = error as NSError
        if let apple = error as? ASAuthorizationError {
            self.init(source: "apple", code: String(apple.code.rawValue))
        } else if case .api(_, let code, _, let response) = error as? AuthError {
            self.init(source: "auth", code: code.rawValue.isEmpty ? String(response.statusCode) : code.rawValue)
        } else if error is AuthError {
            self.init(source: "auth", code: "client")
        } else if let url = error as? URLError {
            self.init(source: "network", code: String(url.code.rawValue))
        } else if ns.domain == "com.google.GIDSignIn" {
            self.init(source: "google", code: String(ns.code))
        } else {
            self.init(source: "other", code: "\(ns.domain) \(ns.code)")
        }
    }
}

/// Why a code could not be sent, in a sentence to show, and whether it was the hourly cap.
public struct CodeRequestFailure: Sendable {
    public let message: String
    public let hourlyLimit: Bool
}

// Public by design — an anon key is meant to ship in client code; RLS is the real boundary.
let SUPABASE_URL = URL(string: "https://xbrnijgctmovoqbbmgmb.supabase.co")!
let SUPABASE_ANON_KEY =
    "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inhicm5pamdjdG1vdm9xYmJtZ21iIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODU3NzQ0NDQsImV4cCI6MjEwMTM1MDQ0NH0.ZamrPyf3UmAmbqzzAcce_Ocb1bKNq19wVxTtaC32a-g"
let AUTH_CALLBACK_URL = URL(string: "longbook://auth/callback")!
/// App Review's account. No code is emailed to it: its eight-digit code is a password that
/// scripts/review-account.mts sets before each submission and App Store Connect hands the reviewer.
let REVIEW_EMAIL = "appreview@longbook.app"

public func isReviewAccount(_ email: String) -> Bool {
    email.trimmingCharacters(in: .whitespaces).lowercased() == REVIEW_EMAIL
}

// The same client backs both auth and the entitlement queries in EntitlementStore — one
// project, one client, matching how the desktop and website both use a single supabase-js
// instance for the same two purposes.
let supabase = SupabaseClient(
    supabaseURL: SUPABASE_URL,
    supabaseKey: SUPABASE_ANON_KEY,
    options: .init(auth: .init(storage: AuthKeychain()), global: .init(headers: ["User-Agent": appUserAgent]))
)

/// What the server records for a session when it signs in: the build, the device and the
/// system ("longbook/18 (iPhone; iOS 27.0)"), so the sign-out screen can name each session.
/// The hardware model comes from sysctl, which any thread may ask, rather than from UIDevice.
let appUserAgent: String = {
    let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    let os = ProcessInfo.processInfo.operatingSystemVersion
    let version = "\(os.majorVersion).\(os.minorVersion)"
    #if os(macOS)
    return "longbook/\(build) (Mac; macOS \(version))"
    #else
    var size = 0
    sysctlbyname("hw.machine", nil, &size, nil, 0)
    var bytes = [CChar](repeating: 0, count: max(size, 1))
    sysctlbyname("hw.machine", &bytes, &size, nil, 0)
    // On the simulator hw.machine is the Mac's; it names the simulated model in the environment.
    let model = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] ?? String(cString: bytes)
    let device = model.hasPrefix("iPad") ? "iPad" : "iPhone"
    return "longbook/\(build) (\(device); \(device == "iPad" ? "iPadOS" : "iOS") \(version))"
    #endif
}()

@MainActor
public final class AuthViewModel: ObservableObject {
    /// Who is signed in, in the only facts a screen needs. The session itself stays in
    /// here so no view layer ever imports Supabase.
    @Published public private(set) var isSignedIn = false
    @Published public private(set) var email: String?
    /// The picture a Google sign-in carries; Apple and email sign-ins carry none. Read
    /// from the session, never stored anywhere else.
    @Published public private(set) var avatarURL: URL?
    /// Whether this account existed before the sign-in that opened this session — the
    /// vault chooser asks a returning reader a different question from a new one.
    @Published public private(set) var returningAccount = false
    /// Whether Apple opened this account, which deleting it then has to tell Apple.
    @Published public private(set) var signedInWithApple = false
    /// False until the first answer arrives; the app's gate (see RootView) waits on this so a
    /// signed-out flash never appears for someone who already is.
    @Published public private(set) var checked = false
    /// The last sign-in that failed, in fixed words; cleared when the next one starts.
    public private(set) var lastFailure: AuthFailure?

    private var session: Session? {
        didSet {
            isSignedIn = session != nil
            email = session?.user.email
            avatarURL = Self.avatar(of: session?.user)
            returningAccount = Self.isReturning(session?.user)
            signedInWithApple = session?.user.identities?.contains { $0.provider == "apple" } ?? false
        }
    }

    /// Google names the picture `avatar_url`, and `picture` beside it. Only an https
    /// address is passed on: the view loads whatever this returns.
    private static func avatar(of user: User?) -> URL? {
        guard let metadata = user?.userMetadata else { return nil }
        for key in ["avatar_url", "picture"] {
            if let text = metadata[key]?.stringValue, let url = URL(string: text), url.scheme == "https" {
                return url
            }
        }
        return nil
    }

    /// The email flow creates the account when the code is requested and stamps the sign-in
    /// when it is entered, so `createdAt` alone reads a slow typist as a returning reader.
    /// Confirmation and the first sign-in land in one request; a real return never does.
    private static func isReturning(_ user: User?) -> Bool {
        guard let user, let lastSignIn = user.lastSignInAt else { return false }
        let firstSeen = user.confirmedAt ?? user.createdAt
        return lastSignIn.timeIntervalSince(firstSeen) > 300
    }
    private var watcher: Task<Void, Never>?

    public init() {}

    public func start() {
        guard watcher == nil else { return }
        watcher = Task { [weak self] in
            guard let self else { return }
            for await state in supabase.auth.authStateChanges {
                self.session = state.session
                self.checked = true
            }
        }
    }

    /// Sends a one-time sign-in code by email. A NEW address gets a confirmation email
    /// instead of a bare code — the server's own choice, not this app's — so redirectTo
    /// is set here too: without it, that email's link dead-ends at the project's default
    /// site URL instead of coming back through longbook://auth/callback.
    public func signInWithEmail(_ email: String) async -> CodeRequestFailure? {
        lastFailure = nil
        if isReviewAccount(email) { return nil }
        do {
            try await supabase.auth.signInWithOTP(email: email, redirectTo: AUTH_CALLBACK_URL)
            return nil
        } catch {
            lastFailure = AuthFailure(error)
            return CodeRequestFailure(message: friendlyAuthMessage(error), hourlyLimit: isHourlyLimit(error))
        }
    }

    /// Verifies the code from that email and completes sign-in. Length is the
    /// project's own setting, not this app's — never assumed here or in its copy.
    public func verifyEmailOTP(_ email: String, token: String) async -> String? {
        lastFailure = nil
        do {
            if isReviewAccount(email) {
                try await supabase.auth.signIn(email: REVIEW_EMAIL, password: token)
            } else {
                try await supabase.auth.verifyOTP(email: email, token: token, type: .email)
            }
            return nil
        } catch {
            lastFailure = AuthFailure(error)
            return friendlyAuthMessage(error)
        }
    }

    /// The same two providers the desktop offers, named without exposing the SDK's own enum.
    public enum Provider: String {
        case apple, google
    }

    private let apple = AppleSignInCoordinator()

    /// Native Sign in with Apple: the system sheet asks, Apple issues an identity token,
    /// and Supabase verifies it directly — no browser session, no project domain shown.
    public func signInWithApple() async -> String? {
        lastFailure = nil
        do {
            let (idToken, nonce) = try await apple.requestIDToken()
            try await supabase.auth.signInWithIdToken(
                credentials: .init(provider: .apple, idToken: idToken, nonce: nonce)
            )
            return nil
        } catch let error as ASAuthorizationError {
            // Closing the sheet is a decision, not a failure; saying so in red would be wrong.
            // Every other ASAuthorization code surfaces as opaque system dialect
            // ("error 1000"), so those get the product's own words instead.
            if error.code == .canceled { return nil }
            lastFailure = AuthFailure(error)
            return "Apple couldn't finish signing you in on this device. Try again, or continue with email."
        } catch {
            return friendlyAuthMessage(error)
        }
    }

    /// The confirmation Apple asks for before an Apple account is deleted: the sheet once
    /// more, answering the code the server ends the link with. Nil when the reader closes it.
    public func appleDeletionCode() async throws -> String? {
        do {
            return try await apple.requestAuthorizationCode()
        } catch let error as ASAuthorizationError where error.code == .canceled {
            return nil
        }
    }

    /// Completes a native Google sign-in: GoogleNative in the app layer runs Google's
    /// sheet — the SDK stays out of this package so the widget never carries it. The
    /// nonce is the one the sheet was opened with; Supabase refuses a token whose
    /// claim doesn't pair with it.
    public func signIn(googleIdToken: String, accessToken: String?, nonce: String?) async -> String? {
        do {
            try await supabase.auth.signInWithIdToken(
                credentials: .init(
                    provider: .google, idToken: googleIdToken, accessToken: accessToken, nonce: nonce
                )
            )
            return nil
        } catch {
            lastFailure = AuthFailure(error)
            return friendlyAuthMessage(error)
        }
    }

    /// Google's sheet fails in the app layer, before this model is asked; it reports here.
    public func noteFailure(_ failure: AuthFailure?) {
        lastFailure = failure
    }

    /// Handed the deep link from `onOpenURL`. Errors are swallowed here — a stray or expired
    /// link should leave the sign-in screen exactly as it was, not throw up an alert.
    public func handle(_ url: URL) {
        Task { try? await supabase.auth.session(from: url) }
    }

    /// Ends this device's session only. The library's default scope is global, which also
    /// revokes every other session of the account, an AI connector's included.
    public func signOut() async {
        try? await supabase.auth.signOut(scope: .local)
    }

    /// Ends every session of the account, each connected AI's included. The library forgets
    /// this device first and ignores a failed request, so a dead network looks like success; here
    /// the server is asked first, and a failure leaves this device signed in. Nil on success.
    public func signOutEverywhere() async -> String? {
        let token: String
        do {
            token = try await supabase.auth.session.accessToken
        } catch is AuthError {
            // No live session, or a refused refresh: the server has nothing of this device's to end.
            await signOut()
            return nil
        } catch {
            return "Could not reach the server. Check your connection and try again."
        }
        var address = URLComponents(url: SUPABASE_URL.appendingPathComponent("auth/v1/logout"), resolvingAgainstBaseURL: false)!
        address.queryItems = [URLQueryItem(name: "scope", value: "global")]
        var request = URLRequest(url: address.url!)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(SUPABASE_ANON_KEY, forHTTPHeaderField: "apikey")
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            // A refused token means the session is already gone on the server: the aim is met.
            guard (200..<300).contains(status) || [401, 403, 404].contains(status) else {
                return "Could not sign out all sessions. Try again shortly."
            }
            await signOut()
            return nil
        } catch {
            return "Could not reach the server. Check your connection and try again."
        }
    }

    /// The account's active sessions, this device first, described by the server. Nil when they
    /// could not be read: signed out, offline, or the function not answering.
    public func activeSessions() async -> ActiveSessionList? {
        guard let token = await accessToken() else { return nil }
        var request = URLRequest(url: SUPABASE_URL.appendingPathComponent("functions/v1/sessions"))
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(SUPABASE_ANON_KEY, forHTTPHeaderField: "apikey")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return ActiveSessionList.decode(data)
    }

    /// Deletes the account and everything the server holds, then signs out; the folder is
    /// never touched. `appleCode` is an Apple account's confirmation from `appleDeletionCode`;
    /// `beforeSignOut` runs once the server confirms. Nil on success, else a sentence to show.
    public func deleteAccount(appleCode: String? = nil, beforeSignOut: () -> Void = {}) async -> String? {
        guard let token = await accessToken() else { return "You are not signed in." }
        var request = URLRequest(url: SUPABASE_URL.appendingPathComponent("functions/v1/delete-account"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(SUPABASE_ANON_KEY, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: String] = appleCode.map { ["apple_code": $0] } ?? [:]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                let said = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
                return said?["error"] as? String ?? "The account could not be deleted. Try again shortly."
            }
        } catch {
            return "The account could not be deleted. Check your connection and try again."
        }
        // Only after the server has confirmed: signing out first would leave no token to
        // delete with, and an account nobody can reach is worse than one still there.
        beforeSignOut()
        await signOut()
        return nil
    }

    /// The bearer token an authenticated server call carries. Nil when signed out — the
    /// caller shows sign-in, it never sends an empty header.
    public func accessToken() async -> String? {
        try? await supabase.auth.session.accessToken
    }

    /// The account's id, which a subscription purchase carries as its app account token
    /// so Apple's receipt names the account it belongs to. Nil when signed out.
    public func userId() async -> UUID? {
        try? await supabase.auth.session.user.id
    }
}
