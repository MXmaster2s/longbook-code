import GoogleSignIn
import LongbookCore
import SwiftUI

/// Native Google sign-in: Google's own SDK runs the consent step, and the ID token it
/// issues goes to Supabase through AuthViewModel. The dependency lives here in the app
/// target — never in swift-core, which the widget also carries. Configuration comes
/// from Info.plist (GIDClientID + the reversed-client-id URL scheme in project.yml).
enum GoogleNative {
    @MainActor
    static func signIn(auth: AuthViewModel) async -> String? {
        // Our own nonce, not the SDK's internal one: the SDK never reveals what it sent,
        // and Supabase can only verify the token's claim against a value it is handed.
        let nonce = AuthNonce.random()
        auth.noteFailure(nil)
        do {
            #if os(iOS)
            guard let presenter = topViewController() else {
                auth.noteFailure(AuthFailure(source: "google", code: "no_presenter"))
                return "Couldn’t open the Google sign-in sheet. Try again."
            }
            let result = try await GIDSignIn.sharedInstance.signIn(
                withPresenting: presenter, hint: nil, additionalScopes: nil, nonce: nonce
            )
            #else
            guard let window = NSApplication.shared.keyWindow ?? NSApplication.shared.windows.first else {
                auth.noteFailure(AuthFailure(source: "google", code: "no_presenter"))
                return "Couldn’t open the Google sign-in window. Try again."
            }
            let result = try await GIDSignIn.sharedInstance.signIn(
                withPresenting: window, hint: nil, additionalScopes: nil, nonce: nonce
            )
            #endif
            guard let idToken = result.user.idToken?.tokenString else {
                auth.noteFailure(AuthFailure(source: "google", code: "no_id_token"))
                return "Google didn’t return an identity token. Try again."
            }
            return await auth.signIn(
                googleIdToken: idToken, accessToken: result.user.accessToken.tokenString, nonce: nonce
            )
        } catch {
            // Closing the sheet is a decision, not a failure; saying so in red would be wrong.
            let failure = error as NSError
            if failure.domain == kGIDSignInErrorDomain, failure.code == GIDSignInError.canceled.rawValue {
                return nil
            }
            auth.noteFailure(AuthFailure(error))
            return failure.localizedDescription
        }
    }

    /// The redirect back from Google's browser round trip on the Mac; iOS returns
    /// through the same scheme. True when the SDK consumed the URL.
    static func handle(_ url: URL) -> Bool {
        GIDSignIn.sharedInstance.handle(url)
    }

    #if os(iOS)
    /// The sheet needs a view controller to stand on; SwiftUI doesn't hand one out, so
    /// this walks to the frontmost presented controller of the key window.
    @MainActor
    private static func topViewController() -> UIViewController? {
        let root = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first?.rootViewController
        var top = root
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
    }
    #endif
}
