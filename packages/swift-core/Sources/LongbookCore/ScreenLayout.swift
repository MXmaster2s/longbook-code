import Foundation

/// The row a list screen last opened, per screen. Kept on the device, never in the vault.
public struct RememberedRows: Codable, Equatable, Sendable {
    private var rows: [String: String]

    public init() { rows = [:] }

    public func row(on screen: String) -> String? { rows[screen] }

    public mutating func remember(_ row: String, on screen: String) { rows[screen] = row }

    public mutating func forget(on screen: String) { rows[screen] = nil }

    /// The row to open on arriving at a screen: the one remembered, while the list still holds it.
    public func arrival(on screen: String, holds: (String) -> Bool) -> String? {
        rows[screen].flatMap { holds($0) ? $0 : nil }
    }
}

/// A table's column widths by column title: one set while the side panel is open and one while
/// it is closed. A set nothing has been dragged in is nil, and the table lays itself out.
public struct ColumnSets: Codable, Equatable, Sendable {
    /// Below this a column cannot show its header.
    public static let narrowest = 40.0

    public private(set) var open: [String: Double]?
    public private(set) var closed: [String: Double]?

    public init(open: [String: Double]? = nil, closed: [String: Double]? = nil) {
        self.open = open
        self.closed = closed
    }

    public var isEmpty: Bool { open == nil && closed == nil }

    /// The set the panel's state puts in force.
    public func inForce(panelOpen: Bool) -> [String: Double]? {
        panelOpen ? open : closed
    }

    /// A drag's widths go into the set in force and leave the other as it stands.
    public mutating func record(_ widths: [String: Double], panelOpen: Bool) {
        let kept = widths.mapValues { max($0, Self.narrowest) }
        if panelOpen { open = kept } else { closed = kept }
    }
}
