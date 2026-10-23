// Insights.swift — notes the user's AI leaves about the app's own modules, read from
// `insights.json` beside the data file. The app never generates one: an icon where a
// note exists, the words when asked. Replaces a computed engine (owner, 2026-08-07).

import Foundation

public struct Insight: Codable {
    public init(module: String, text: String, createdAt: String? = nil) {
        self.module = module
        self.text = text
        self.createdAt = createdAt
    }

    /// The module the note belongs to — stable ids listed in docs/insights-format.md.
    public var module: String
    public var text: String
    public var createdAt: String?      // ISO YYYY-MM-DD

    enum CodingKeys: String, CodingKey {
        case module, text
        case createdAt = "created_at"
    }
}

private struct InsightsFile: Codable {
    var version: Int
    var insights: [Insight]
}

public enum InsightsReader {
    public static let fileName = "insights.json"

    /// The latest note per module — a later entry for the same module wins, so the AI
    /// can append without editing history.
    public static func byModule(in vaultFolder: URL) -> [String: Insight] {
        let file = vaultFolder.appendingPathComponent(fileName)
        try? FileManager.default.startDownloadingUbiquitousItem(at: file)
        guard let bytes = try? VaultReader.coordinatedRead(file),
              let decoded = try? JSONDecoder().decode(InsightsFile.self, from: bytes)
        else { return [:] }
        var out: [String: Insight] = [:]
        for insight in decoded.insights {
            out[insight.module] = insight
        }
        return out
    }
}

/// The two writes this app makes to insights.json. Appending, for an AI proposal being
/// applied: append-only, as the contract asks — the last note per module wins, and an
/// unreadable file starts fresh. Removing, on the owner's click: every note for that module
/// goes, so no earlier one resurfaces.
public enum InsightsWriter {
    public static func append(module: String, text: String, in vaultFolder: URL, now: Date = Date()) throws {
        let day = ISO8601DateFormatter()
        day.formatOptions = [.withInternetDateTime]
        try rewrite(in: vaultFolder) { $0 + [Insight(module: module, text: text, createdAt: day.string(from: now))] }
    }

    public static func remove(module: String, in vaultFolder: URL) throws {
        try rewrite(in: vaultFolder) { $0.filter { $0.module != module } }
    }

    private static func rewrite(in vaultFolder: URL, _ change: ([Insight]) -> [Insight]) throws {
        let file = vaultFolder.appendingPathComponent(InsightsReader.fileName)
        var existing: [Insight] = []
        if let bytes = try? VaultReader.coordinatedRead(file),
           let decoded = try? JSONDecoder().decode(InsightsFile.self, from: bytes) {
            existing = decoded.insights
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let bytes = try encoder.encode(InsightsFile(version: 1, insights: change(existing)))
        try VaultScaffold.coordinatedWrite(bytes, to: file)
    }
}
