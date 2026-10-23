// Reading a vault iCloud has not delivered yet. The file exists by name and holds no
// bytes, so a reader that does not ask reports a broken vault instead of a slow one.
import XCTest
@testable import LongbookCore

final class PlaceholderReadTests: XCTestCase {
    private func tempFolder() throws -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("placeholder-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func testAnOrdinaryLocalFileIsNeverAwaitingDownload() throws {
        let dir = try tempFolder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent(VaultReader.dataFile)
        try Data(#"{"app":"longbook","version":3,"commitments":[]}"#.utf8).write(to: file)

        XCTAssertFalse(VaultReader.awaitingDownload(file))
        XCTAssertNoThrow(try VaultReader.load(from: dir), "a local vault opens without waiting")
    }

    func testAMissingFileIsNotMistakenForAPlaceholder() throws {
        let dir = try tempFolder()
        defer { try? FileManager.default.removeItem(at: dir) }
        // Nothing to wait for: the answer is that this is not a vault, not that iCloud is slow.
        XCTAssertFalse(VaultReader.awaitingDownload(dir.appendingPathComponent(VaultReader.dataFile)))
        XCTAssertThrowsError(try VaultReader.load(from: dir)) { error in
            if case .notDownloaded = (error as? VaultReader.ReadError) {
                XCTFail("a folder with no data file is not a vault that is still arriving")
            }
        }
    }

    func testTheWaitingMessageNamesICloudRatherThanBlamingTheFile() {
        let message = VaultReader.ReadError.notDownloaded.errorDescription ?? ""
        XCTAssertTrue(message.contains("iCloud"))
        XCTAssertFalse(message.lowercased().contains("didn't open"))
    }
}

/// A move copies and then deletes the original, so it has to see everything first.
final class MigrationPresenceTests: XCTestCase {
    private func vault() throws -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("move-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: dir.appendingPathComponent("documents"), withIntermediateDirectories: true)
        try Data(#"{"app":"longbook","version":3,"commitments":[]}"#.utf8)
            .write(to: dir.appendingPathComponent(VaultReader.dataFile))
        return dir
    }

    func testAFullyPresentVaultHasNothingPending() throws {
        let dir = try vault()
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data("a statement".utf8).write(to: dir.appendingPathComponent("documents/aug.pdf"))

        XCTAssertEqual(VaultMigration.awaitingDownload(in: dir), [])
    }

    func testAnEvictedStatementIsFoundAndNamed() throws {
        let dir = try vault()
        defer { try? FileManager.default.removeItem(at: dir) }
        // How the filesystem shows a file iCloud is holding elsewhere: a dot-name stub.
        try Data().write(to: dir.appendingPathComponent("documents/.aug.pdf.icloud"))

        XCTAssertEqual(VaultMigration.awaitingDownload(in: dir), ["aug.pdf"])
        // files(in:) is why this check exists: the stub is invisible to the copier.
        XCTAssertFalse(VaultMigration.files(in: dir).contains { $0.lastPathComponent.contains("aug") })
    }

    func testDotFilesThatAreNotPlaceholdersAreIgnored() throws {
        let dir = try vault()
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data().write(to: dir.appendingPathComponent(".DS_Store"))

        XCTAssertEqual(VaultMigration.awaitingDownload(in: dir), [])
    }
}
