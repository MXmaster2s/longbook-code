// The reading screen's bar and its lines. Pure, so the promise holds under test: it keeps rising,
// it slows near the end, and nothing but the end of the reading fills it.
import Foundation

/// The bar on the reading screen. It rises the whole time and slows as it goes, helped along
/// by what has really come back; only `finish` fills it, so a full bar always means done.
public struct ReadingBar: Equatable, Sendable {
    /// What the reading screen says, in order, each from its share of the bar on.
    public static let lines: [(kind: StatementTour.Kind, words: String, from: Double)] = [
        (.charge, "Importing Past Expenses", 0),
        (.people, "Identifying People", 0.14),
        (.account, "Looking for Accounts", 0.3),
        (.commitment, "Thinking on your Commitments", 0.46),
        (.transfer, "Finding Internal Transfers", 0.62),
        (.earning, "Searching your Earnings", 0.8),
    ]

    /// Measured on real statements for a file read by its lines.
    public static let linesSeconds = 23.0

    /// The seconds a batch should take: its slowest file, since files read side by side.
    public static func expected(lineFiles: Int, pieces: [Int]) -> Double {
        let documents = pieces.map { 20 + 30 * (Double($0) / 3).rounded(.up) }
        return max(lineFiles > 0 ? linesSeconds : 0, documents.max() ?? 0, 1)
    }

    /// What returned answers may carry the bar to, and what the clock alone may.
    private static let knownCeiling = 0.85
    private static let curveCeiling = 0.99
    /// The least it rises each second, so it never reads as stopped.
    private static let leastRise = 0.0008

    public private(set) var share = 0.0
    private var clock = 0.0

    public init() {}

    /// Time has passed. `done` is the share of answers back, which may fall when a file
    /// changes path; the bar never does.
    public mutating func advance(to elapsed: Double, expected: Double, done: Double) {
        guard share < 1 else { return }
        let step = max(0, elapsed - clock)
        clock = max(clock, elapsed)
        let known = min(max(done, 0), 1) * Self.knownCeiling
        let pace = max(expected, 1) * 0.4
        let curve = known + (Self.curveCeiling - known) * clock / (clock + pace)
        let room = 1 - share
        share = min(max(curve, share + min(Self.leastRise, room * 0.02) * step), 1 - room * 0.5)
    }

    /// Reading is done.
    public mutating func finish() { share = 1 }

    public var isFull: Bool { share >= 1 }

    /// Which line the bar has reached.
    public var line: Int {
        Self.lines.lastIndex { share >= $0.from } ?? 0
    }
}
