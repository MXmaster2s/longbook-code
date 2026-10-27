// The check Settings runs on a picked folder before switching to it, against real temp
// directories: a folder that opens, one with no data file, and one in another format.
import XCTest
@testable import LongbookCore

final class VaultFolderCheckTests: XCTestCase {
    private var root: URL!

    /// The minimal file the open-any-folder blog post shows, byte for byte in shape.
    static let minimalVault = """
    {
      "app": "longbook",
      "version": 3,
      "commitments": [
        {
          "id": "9f6c1b52-3d1e-4a8b-9c47-2f0e6a1d5b83",
          "name": "Netflix",
          "amount": 649,
          "currency": "INR",
          "billing_cycle": "monthly",
          "status": "active"
        }
      ],
      "charges": [
        {
          "commitment_id": "9f6c1b52-3d1e-4a8b-9c47-2f0e6a1d5b83",
          "date": "2026-11-05",
          "amount": 649,
          "paid": false,
          "basis": "plan"
        }
      ]
    }
    """

    override func setUpWithError() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("folder-check-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func write(_ text: String) throws {
        try Data(text.utf8).write(to: root.appendingPathComponent(VaultReader.dataFile))
    }

    private func snapshot() throws -> [String: Data] {
        let names = try FileManager.default.contentsOfDirectory(atPath: root.path)
        return try Dictionary(uniqueKeysWithValues: names.map { ($0, try Data(contentsOf: root.appendingPathComponent($0))) })
    }

    func testAValidFolderOpens() throws {
        try write(Self.minimalVault)
        XCTAssertEqual(VaultFolderCheck.check(root), .opens)
        let loaded = try VaultReader.load(from: root)
        XCTAssertEqual(loaded.vault.subscriptions.map(\.name), ["Netflix"])
        XCTAssertEqual(loaded.vault.charges.count, 1)
    }

    func testAFolderWithoutTheFileIsRefused() throws {
        try Data("hello".utf8).write(to: root.appendingPathComponent("notes.txt"))
        XCTAssertEqual(VaultFolderCheck.check(root), .noDataFile)
    }

    func testAFileInAnotherFormatIsRefused() throws {
        for text in ["not json at all", "{\"transactions\": []}", "{\"app\": \"longbook\", \"version\": 2, \"commitments\": []}",
                     Self.minimalVault.replacingOccurrences(of: "\"monthly\"", with: "\"weekly\"")] {
            try write(text)
            XCTAssertEqual(VaultFolderCheck.check(root), .notLongbookFormat, text)
        }
    }

    func testAMissingFolderIsUnreadable() {
        XCTAssertEqual(VaultFolderCheck.check(root.appendingPathComponent("gone")), .unreadable)
    }

    /// Checking reads only: the folder holds the same files, byte for byte, afterwards.
    func testCheckingWritesNothing() throws {
        for text in [Self.minimalVault, "{\"transactions\": []}"] {
            try write(text)
            let before = try snapshot()
            _ = VaultFolderCheck.check(root)
            XCTAssertEqual(try snapshot(), before)
        }
    }

    func testDownloadingCheckAnswersALocalFolderAtOnce() async throws {
        try write(Self.minimalVault)
        let verdict = await VaultFolderCheck.checkDownloading(root, timeout: 1)
        XCTAssertEqual(verdict, .opens)
    }
}
