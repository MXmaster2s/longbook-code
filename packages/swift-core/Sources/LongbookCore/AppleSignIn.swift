// Native Sign in with Apple: the system sheet, no browser session and no third-party
// domain in the consent dialog. Produces the identity token and the raw nonce that
// AuthViewModel hands to Supabase's signInWithIdToken. Below it, the web session for a
// build signed without that capability.
import AuthenticationServices
import CryptoKit
import Foundation

/// One replay-protection nonce per sign-in attempt, shared by both providers: Apple's
/// request carries its SHA-256, Google's SDK sends it verbatim, and Supabase gets the
/// raw value either way to compare against the issued token's claim.
public enum AuthNonce {
    public static func random(length: Int = 32) -> String {
        var bytes = [UInt8](repeating: 0, count: length)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        // Random bytes only ever fail on a broken system; a predictable nonce must not
        // silently stand in, so a constant that can never verify is safer than a guess.
        guard status == errSecSuccess else { return "nonce-entropy-unavailable" }
        let charset = Array("0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ-._")
        return String(bytes.map { charset[Int($0) % charset.count] })
    }

    static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

@MainActor
final class AppleSignInCoordinator: NSObject {
    private var continuation: CheckedContinuation<ASAuthorization, Error>?

    /// Runs the system sheet and returns the identity token with the raw nonce.
    func requestIDToken() async throws -> (idToken: String, nonce: String) {
        let rawNonce = AuthNonce.random()
        let credential = try await authorize(scopes: [.email], nonce: AuthNonce.sha256(rawNonce))
        guard let tokenBytes = credential.identityToken,
              let idToken = String(data: tokenBytes, encoding: .utf8)
        else {
            throw ASAuthorizationError(.invalidResponse)
        }
        return (idToken, rawNonce)
    }

    /// A fresh authorization code: the server swaps it for the token Apple revokes when the
    /// account is deleted. The sheet asks for nothing but the confirmation.
    func requestAuthorizationCode() async throws -> String {
        let credential = try await authorize(scopes: nil, nonce: nil)
        guard let bytes = credential.authorizationCode, let code = String(data: bytes, encoding: .utf8) else {
            throw ASAuthorizationError(.invalidResponse)
        }
        return code
    }

    private func authorize(scopes: [ASAuthorization.Scope]?, nonce: String?) async throws -> ASAuthorizationAppleIDCredential {
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = scopes
        request.nonce = nonce

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        let authorization = try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            controller.performRequests()
        }
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            throw ASAuthorizationError(.invalidResponse)
        }
        return credential
    }
}

extension AppleSignInCoordinator: ASAuthorizationControllerDelegate {
    nonisolated func authorizationController(
        controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        Task { @MainActor in
            continuation?.resume(returning: authorization)
            continuation = nil
        }
    }

    nonisolated func authorizationController(
        controller: ASAuthorizationController, didCompleteWithError error: Error
    ) {
        Task { @MainActor in
            continuation?.resume(throwing: error)
            continuation = nil
        }
    }
}

extension AppleSignInCoordinator: ASAuthorizationControllerPresentationContextProviding {
    nonisolated func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        MainActor.assumeIsolated { signInAnchor() }
    }
}

/// The window a sign-in sheet or web session hangs from.
@MainActor
private func signInAnchor() -> ASPresentationAnchor {
    #if os(macOS)
    NSApplication.shared.keyWindow ?? NSApplication.shared.windows.first ?? ASPresentationAnchor()
    #else
    UIApplication.shared.connectedScenes
        .compactMap { ($0 as? UIWindowScene)?.keyWindow }
        .first ?? ASPresentationAnchor()
    #endif
}

/// A sign-in page in the system's web session, which hands back the URL it redirects to.
@MainActor
final class BrowserSignInSession: NSObject {
    private var continuation: CheckedContinuation<URL?, Error>?
    private var session: ASWebAuthenticationSession?

    /// The callback URL, or nil when the reader closes the window.
    func open(_ page: URL, callbackScheme: String) async throws -> URL? {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let session = ASWebAuthenticationSession(url: page, callbackURLScheme: callbackScheme) { [weak self] callback, error in
                Task { @MainActor in self?.finish(callback, error) }
            }
            session.presentationContextProvider = self
            self.session = session
            if !session.start() { finish(nil, ASWebAuthenticationSessionError(.presentationContextInvalid)) }
        }
    }

    /// Runs once: a session that failed to start may still report through its handler.
    private func finish(_ callback: URL?, _ error: Error?) {
        guard let continuation else { return }
        self.continuation = nil
        session = nil
        if let error {
            if (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin {
                continuation.resume(returning: nil)
            } else {
                continuation.resume(throwing: error)
            }
        } else {
            continuation.resume(returning: callback)
        }
    }

    /// Whether a callback carries a refusal because the reader cancelled on the provider's page.
    nonisolated static func cancelled(_ callback: URL) -> Bool {
        let parts = URLComponents(url: callback, resolvingAgainstBaseURL: false)
        var fragment = URLComponents()
        fragment.percentEncodedQuery = parts?.percentEncodedFragment
        let items = (parts?.queryItems ?? []) + (fragment.queryItems ?? [])
        return items.contains { ["error", "error_code", "error_description"].contains($0.name) && ($0.value ?? "").lowercased().contains("cancel") }
    }
}

extension BrowserSignInSession: ASWebAuthenticationPresentationContextProviding {
    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated { signInAnchor() }
    }
}
