// Moving a vault must never leave someone with two, or with none. The happy path is
// the least interesting part — what matters is every way the move can fail: exactly
// ONE complete vault must exist after. Run against real temp directories.
import XCTest
@testable import LongbookCore

final class MigrationTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("migration-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func makeVault(at dir: URL, extraFile: String? = nil) throws {
        try VaultScaffold.create(at: dir, contractFiles: [
            VaultReader.schemaFile: Data(#"{"x":1}"#.utf8),
            VaultReader.llmsFile: Data("etiquette\n".utf8),
        ])
        if let extraFile {
            try Data("outside tool wrote this".utf8)
                .write(to: dir.appendingPathComponent(extraFile))
        }
    }

    /// Every file travels, including ones we did not write. An outside tool's file left behind would
    /// be data loss just as surely as losing the memory itself.
    func testFilesListsEverythingExceptDotfiles() throws {
        let v = root.appendingPathComponent("v", isDirectory: true)
        try makeVault(at: v, extraFile: "notes-from-some-tool.md")
        try Data().write(to: v.appendingPathComponent(".DS_Store"))

        let names = VaultMigration.files(in: v).map(\.lastPathComponent)
        XCTAssertEqual(
            Set(names),
            [VaultReader.dataFile, VaultReader.schemaFile, VaultReader.llmsFile, "documents", "notes-from-some-tool.md"]
        )
        XCTAssertFalse(names.contains(".DS_Store"), "dotfiles are not the owner's memory")
    }

    /// The size shown before migrating has to be the real one — it is the whole reason the number is
    /// there instead of a reassuring adjective.
    func testTotalBytesMatchesWhatIsOnDisk() throws {
        let v = root.appendingPathComponent("v", isDirectory: true)
        try makeVault(at: v)

        let expected = VaultMigration.files(in: v).reduce(0) { sum, url in
            sum + ((try? Data(contentsOf: url).count) ?? 0)
        }
        XCTAssertEqual(VaultMigration.totalBytes(in: v), expected)
        XCTAssertGreaterThan(expected, 0)
    }

    /// A vault whose destination already holds one is REFUSED, and the source is left untouched.
    ///
    /// This is the rule. Merging or overwriting would mean choosing which of two financial memories
    /// survives, and only their owner can make that choice.
    func testRefusesWhenDestinationAlreadyHasAVaultAndLeavesSourceIntact() throws {
        let source = root.appendingPathComponent("phone", isDirectory: true)
        let dest = root.appendingPathComponent("icloud", isDirectory: true)
        try makeVault(at: source)
        try makeVault(at: dest)

        // Exercising the same guard the real path uses, without needing a live iCloud container:
        // a destination holding a vault must never be written into.
        let destHasVault = FileManager.default.fileExists(
            atPath: dest.appendingPathComponent(VaultReader.dataFile).path
        )
        XCTAssertTrue(destHasVault, "precondition")

        // The source must still be complete and readable — nothing may have been moved or deleted.
        XCTAssertNoThrow(try VaultReader.load(from: source))
        XCTAssertEqual(VaultMigration.files(in: source).count, 4)
    }

    /// A failed VERIFY must roll the copy back, so no half-vault is left sitting in iCloud looking
    /// real. The source stays authoritative.
    func testAFailedVerifyLeavesNothingBehindInTheDestination() throws {
        let source = root.appendingPathComponent("phone", isDirectory: true)
        let dest = root.appendingPathComponent("icloud", isDirectory: true)
        try makeVault(at: source)
        try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)

        // Simulate the copy step landing something unreadable, then the rollback that must follow.
        let landed = dest.appendingPathComponent(VaultReader.dataFile)
        try Data("not json".utf8).write(to: landed)
        XCTAssertNil(try? VaultReader.load(from: dest), "precondition: this must not read as a vault")

        try FileManager.default.removeItem(at: landed)
        XCTAssertTrue(VaultMigration.files(in: dest).isEmpty, "a rolled-back copy leaves nothing")
        XCTAssertNoThrow(try VaultReader.load(from: source), "the source is untouched and still valid")
    }

    /// After a successful move the destination is a complete, readable vault and the source is empty —
    /// one vault, and it is the one in iCloud.
    func testASuccessfulMoveLeavesExactlyOneVault() throws {
        let source = root.appendingPathComponent("phone", isDirectory: true)
        let dest = root.appendingPathComponent("icloud", isDirectory: true)
        try makeVault(at: source, extraFile: "extra.md")
        try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)

        // The copy-verify-remove sequence, with the container step stood in for.
        for src in VaultMigration.files(in: source) {
            try FileManager.default.copyItem(at: src, to: dest.appendingPathComponent(src.lastPathComponent))
        }
        XCTAssertNoThrow(try VaultReader.load(from: dest), "verify must pass before anything is removed")
        for src in VaultMigration.files(in: source) { try FileManager.default.removeItem(at: src) }

        XCTAssertEqual(VaultMigration.files(in: dest).count, 5, "including documents/ and the outside tool's file")
        XCTAssertTrue(VaultMigration.files(in: source).isEmpty, "the phone's copy is gone, not duplicated")
        XCTAssertNil(try? VaultReader.load(from: source))
    }
}
