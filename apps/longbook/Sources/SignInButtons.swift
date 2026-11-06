import AuthenticationServices
import DesignSystem
import SwiftUI

/// The three doors on the welcome share one size and shape. 44 points is the height Apple's
/// HIG recommends for its button; a capsule is a shape both Apple's and Google's guidelines allow.
enum SignInDoor {
    static let height: CGFloat = 44
    /// Google's button is drawn at 40 points; its logo and padding scale with the height.
    static let scale = height / 40
    /// The size Apple's own button draws its title at 44 points, so all three labels read alike.
    static let labelSize: CGFloat = 16
}

/// The doors' press and disabled states. No hover wash: each fill stays exactly its brand's
/// colour at rest. Pressed dims a little; disabled is 40% on the Mac and 50% on the phone.
struct SignInDoorStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        SignInDoorFace(configuration: configuration)
    }
}

private struct SignInDoorFace: View {
    let configuration: ButtonStyleConfiguration
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        #if os(macOS)
        configuration.label
            .opacity(configuration.isPressed ? 0.85 : 1)
            .opacity(isEnabled ? 1 : 0.4)
            .lbLinkPointer()
        #else
        OnboardingPressStyle().makeBody(configuration: configuration)
            .opacity(isEnabled ? 1 : 0.5)
        #endif
    }
}

// MARK: Apple

/// Sign in with Apple drawn as the HIG's custom button: black with white on a light screen,
/// white with black on a dark one, the system font, the title Sign in with Apple, and the
/// logo and title centred as Apple's own button sets them.
struct AppleSignInLabel: View {
    let dark: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            // SF Symbols marks apple.logo "may only be used to refer to Sign in with Apple".
            Image(systemName: "apple.logo")
                .font(.system(size: SignInDoor.labelSize, weight: .medium))
                .accessibilityHidden(true)
            Text("Sign in with Apple")
                .font(.system(size: SignInDoor.labelSize, weight: .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(dark ? Color.black : Color.white)
        .padding(.horizontal, 16 * SignInDoor.scale)
        .frame(maxWidth: .infinity)
        .frame(height: SignInDoor.height)
        .background(dark ? Color.white : Color.black, in: Capsule())
        .contentShape(Capsule())
    }
}

/// Runs Apple's request as Apple's own button does: one Apple ID request, Apple's sheet over
/// the window in front, the answer handed back once.
@MainActor
final class AppleSignInRunner: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    private var finish: ((Result<ASAuthorization, Error>) -> Void)?
    /// Held while Apple's sheet is up; the controller does not keep itself.
    private var controller: ASAuthorizationController?

    func run(prepare: (ASAuthorizationAppleIDRequest) -> Void, finish: @escaping (Result<ASAuthorization, Error>) -> Void) {
        let request = ASAuthorizationAppleIDProvider().createRequest()
        prepare(request)
        self.finish = finish
        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        self.controller = controller
        controller.performRequests()
    }

    nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        MainActor.assumeIsolated { done(.success(authorization)) }
    }

    nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        MainActor.assumeIsolated { done(.failure(error)) }
    }

    private func done(_ result: Result<ASAuthorization, Error>) {
        let finish = finish
        self.finish = nil
        controller = nil
        finish?(result)
    }

    nonisolated func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            #if os(macOS)
            NSApp.keyWindow ?? NSApp.mainWindow ?? ASPresentationAnchor()
            #else
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows)
                .first(where: \.isKeyWindow) ?? ASPresentationAnchor()
            #endif
        }
    }
}

// MARK: Google

/// Sign in with Google as Google's branding guidelines draw a custom button: the standard
/// colour G from Google's own artwork, the light or dark theme's fill, stroke and ink, and
/// the iOS padding of 16, 12 and 16, all at the door's scale. No shadow: the guidelines give none.
struct GoogleSignInLabel: View {
    let dark: Bool

    var body: some View {
        HStack(spacing: 12 * SignInDoor.scale) {
            Image("GoogleMark")
                .resizable()
                .scaledToFit()
                .frame(width: 20 * SignInDoor.scale, height: 20 * SignInDoor.scale)
                .accessibilityHidden(true)
            Text("Sign in with Google")
                .font(.system(size: SignInDoor.labelSize, weight: .medium))
                .foregroundStyle(ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 16 * SignInDoor.scale)
        .frame(maxWidth: .infinity)
        .frame(height: SignInDoor.height)
        .background(fill, in: Capsule())
        .overlay(Capsule().strokeBorder(stroke, lineWidth: 1))
        .contentShape(Capsule())
    }

    // The guidelines' light theme is #FFFFFF, #747775 and #1F1F1F; the dark is #131314,
    // #8E918F and #E3E3E3. Google's colours, so they stay out of the design tokens.
    private var fill: Color { dark ? Self.rgb(0x13, 0x13, 0x14) : Self.rgb(0xFF, 0xFF, 0xFF) }
    private var stroke: Color { dark ? Self.rgb(0x8E, 0x91, 0x8F) : Self.rgb(0x74, 0x77, 0x75) }
    private var ink: Color { dark ? Self.rgb(0xE3, 0xE3, 0xE3) : Self.rgb(0x1F, 0x1F, 0x1F) }

    private static func rgb(_ red: Int, _ green: Int, _ blue: Int) -> Color {
        Color(.sRGB, red: Double(red) / 255, green: Double(green) / 255, blue: Double(blue) / 255)
    }
}
