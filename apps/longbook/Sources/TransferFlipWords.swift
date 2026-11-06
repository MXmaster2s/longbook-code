import Foundation

/// What the popup says before an edit changes charges into Transfers or back.
enum TransferFlipWords {
    typealias Flips = (intoTransfers: Int, intoCharges: Int)

    static func isZero(_ flips: Flips) -> Bool { flips.intoTransfers == 0 && flips.intoCharges == 0 }

    static func message(_ flips: Flips) -> String {
        var sentences: [String] = []
        if flips.intoTransfers > 0 {
            let noun = flips.intoTransfers == 1 ? "1 charge" : "\(flips.intoTransfers) charges"
            sentences.append("This will change \(noun) into Transfers. Transfers don't count as spending.")
        }
        if flips.intoCharges > 0 {
            let noun = flips.intoCharges == 1 ? "1 Transfer" : "\(flips.intoCharges) Transfers"
            sentences.append("This will change \(noun) back into charges.")
        }
        return sentences.joined(separator: " ")
    }
}
