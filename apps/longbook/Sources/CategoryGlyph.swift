import DesignSystem
import Foundation

/// The icon that names what a colour marks — a second signal, never the only one.
/// One mapping, so a category wears the same glyph on every screen. The fallback is
/// the filled form of the shared category glyph.
enum CategoryGlyph {
    static func symbol(_ name: String) -> String {
        let key = name.lowercased()
        if key.contains("help") || key.contains("staff") { return "bag.fill" }
        if key.contains("home") || key.contains("rent") || key.contains("house") { return "house.fill" }
        if key.contains("insurance") { return "shield.fill" }
        if key.contains("travel") || key.contains("flight") { return "airplane" }
        if key.contains("social") { return "bubble.left.fill" }
        if key.contains("stream") { return "play.tv" }
        if key.contains("subscription") { return "arrow.triangle.2.circlepath" }
        if key.contains("ai") { return "sparkles" }
        if key.contains("software") || key.contains("dev") { return "chevron.left.forwardslash.chevron.right" }
        if key.contains("tech") { return "laptopcomputer" }
        if key.contains("comms") || key.contains("phone") || key.contains("broadband") { return "antenna.radiowaves.left.and.right" }
        if key.contains("health") || key.contains("fitness") { return "heart.fill" }
        if key.contains("storage") || key.contains("cloud") { return "externaldrive.fill" }
        if key.contains("education") || key.contains("school") { return "book.fill" }
        return LBGlyph.categoryFilled
    }
}
