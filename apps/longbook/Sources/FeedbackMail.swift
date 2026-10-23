import Foundation
import LongbookCore

/// A mail to the support address with the subject filled in. The body ends with the build and
/// the system, and carries nothing else about the sender.
enum FeedbackMail {
    static func url(subject: String) -> URL? {
        let safe = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        func encoded(_ text: String) -> String { text.addingPercentEncoding(withAllowedCharacters: safe) ?? "" }
        return URL(string: "mailto:contact@longbook.app?subject=\(encoded(subject))&body=\(encoded("\n\n\(AppVersion.line)"))")
    }

    /// Offered on the sign-in screen when the hourly cap on codes is reached.
    static var signInLimit: URL? { url(subject: "longbook sign-in limit") }

    /// Offered when the server has read its share of statements: the install id lets us
    /// see what the account did before reading more for it. Without sharing, it says so.
    static func statementShare(installId: String?) -> URL? {
        url(subject: "longbook statement reading", body: installId.map { "Install ID: \($0)" } ?? "Share usage and crash data is off, so there is no install ID.")
    }

    static func url(subject: String, body: String) -> URL? {
        let safe = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        func encoded(_ text: String) -> String { text.addingPercentEncoding(withAllowedCharacters: safe) ?? "" }
        return URL(string: "mailto:contact@longbook.app?subject=\(encoded(subject))&body=\(encoded("\(body)\n\n\(AppVersion.line)"))")
    }
}
