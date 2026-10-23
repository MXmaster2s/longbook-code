import Foundation
import LongbookCore

/// A card's chips as the region sees them. The cards themselves now carry the region's
/// words (OnboardingCards.accounts reads the device region), so every chip shows.
enum OnboardingRegion {
    static func chips(of card: OnboardingCard, region: String? = Locale.current.region?.identifier) -> [String] {
        card.chips
    }
}
