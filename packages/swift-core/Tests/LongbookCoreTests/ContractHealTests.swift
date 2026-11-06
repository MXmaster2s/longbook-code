// The bug these cover shipped for months: a vault kept the contract files it was born with,
// so a folder made by an old build handed every outside tool a v1 schema for v2 data.
import XCTest
@testable import LongbookCore

final class ContractHealTests: XCTestCase {
    private func folder() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("heal-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func bundled(revision: Int) -> [String: Data] {
        [
            VaultReader.schemaFile: Data(#"{"version":2}"#.utf8),
            VaultReader.llmsFile: Data("etiquette\n".utf8),
            VaultReader.libraryFile: Data(#"{"contract_revision":\#(revision),"tags":[]}"#.utf8),
            VaultReader.promptsFile: Data(#"{"contract_revision":\#(revision),"groups":[],"prompts":[]}"#.utf8),
        ]
    }

    func testStaleContractIsReplaced() throws {
        let dir = try folder()
        try Data(#"{"version":1}"#.utf8).write(to: dir.appendingPathComponent(VaultReader.schemaFile))
        let written = VaultContract.heal(in: dir, bundled: bundled(revision: 8))
        XCTAssertEqual(written.sorted(), VaultContract.files.sorted())
        let schema = try Data(contentsOf: dir.appendingPathComponent(VaultReader.schemaFile))
        XCTAssertEqual(schema, bundled(revision: 8)[VaultReader.schemaFile])
    }

    func testCurrentContractIsLeftAlone() throws {
        let dir = try folder()
        for (name, body) in bundled(revision: 8) {
            try body.write(to: dir.appendingPathComponent(name))
        }
        XCTAssertEqual(VaultContract.heal(in: dir, bundled: bundled(revision: 8)), [])
    }

    /// Two devices on different releases would otherwise rewrite each other on every open.
    func testOlderBuildDoesNotDowngradeANewerContract() throws {
        let dir = try folder()
        for (name, body) in bundled(revision: 9) {
            try body.write(to: dir.appendingPathComponent(name))
        }
        XCTAssertEqual(VaultContract.heal(in: dir, bundled: bundled(revision: 8)), [])
        let library = try Data(contentsOf: dir.appendingPathComponent(VaultReader.libraryFile))
        XCTAssertEqual(VaultContract.revision(of: library), 9)
    }

    /// A set written before prompts.json was listed is level on its revision and still lacks the
    /// file. Only the missing file is written; a level file that differs is left as found.
    func testALevelContractGainsOnlyTheFileItLacks() throws {
        let dir = try folder()
        for (name, body) in bundled(revision: 8) where name != VaultReader.promptsFile {
            try body.write(to: dir.appendingPathComponent(name))
        }
        let edited = Data("etiquette, edited by hand\n".utf8)
        try edited.write(to: dir.appendingPathComponent(VaultReader.llmsFile))

        XCTAssertEqual(VaultContract.heal(in: dir, bundled: bundled(revision: 8)), [VaultReader.promptsFile])
        XCTAssertEqual(try Data(contentsOf: dir.appendingPathComponent(VaultReader.promptsFile)),
                       bundled(revision: 8)[VaultReader.promptsFile])
        XCTAssertEqual(try Data(contentsOf: dir.appendingPathComponent(VaultReader.llmsFile)), edited)
    }

    private func stamp(_ dir: URL, revision: Int) throws {
        try Data(#"{"contract_revision":\#(revision),"tags":[]}"#.utf8)
            .write(to: dir.appendingPathComponent(VaultReader.libraryFile))
    }

    /// library.json carries the stamp: a second device that reads it must find the rest already there.
    func testTheRevisionStampIsWrittenLast() throws {
        let dir = try folder()
        var order: [String] = []
        let written = VaultContract.heal(in: dir, bundled: bundled(revision: 8), write: { data, url in
            order.append(url.lastPathComponent)
            try VaultScaffold.coordinatedWrite(data, to: url)
        })
        XCTAssertEqual(order.last, VaultReader.libraryFile)
        XCTAssertEqual(written.last, VaultReader.libraryFile)
        XCTAssertEqual(Set(order), Set(VaultContract.files))
    }

    /// A file that failed to land keeps the old stamp, so the next open tries the set again.
    func testAFailedWriteHoldsBackTheStamp() throws {
        struct Refused: Error {}
        let dir = try folder()
        try stamp(dir, revision: 7)
        let written = VaultContract.heal(in: dir, bundled: bundled(revision: 8), write: { data, url in
            if url.lastPathComponent == VaultReader.schemaFile { throw Refused() }
            try VaultScaffold.coordinatedWrite(data, to: url)
        })
        XCTAssertEqual(written, [VaultReader.llmsFile, VaultReader.promptsFile])
        let library = try Data(contentsOf: dir.appendingPathComponent(VaultReader.libraryFile))
        XCTAssertEqual(VaultContract.revision(of: library), 7)

        XCTAssertEqual(VaultContract.heal(in: dir, bundled: bundled(revision: 8)),
                       [VaultReader.schemaFile, VaultReader.libraryFile])
    }

    /// A folder someone picked may hold a prompts.json of their own; an older set heals around it.
    func testAForeignPromptsFileIsLeftAsFound() throws {
        let foreigners = [Data(#"{"prompts":["mine"]}"#.utf8), Data("my prompts, not JSON\n".utf8), Data("[1,2]".utf8)]
        for foreign in foreigners {
            for stamped in [true, false] {
                let dir = try folder()
                if stamped { try stamp(dir, revision: 7) }
                try foreign.write(to: dir.appendingPathComponent(VaultReader.promptsFile))

                let written = VaultContract.heal(in: dir, bundled: bundled(revision: 8))
                XCTAssertFalse(written.contains(VaultReader.promptsFile))
                XCTAssertEqual(written.last, VaultReader.libraryFile)
                XCTAssertEqual(try Data(contentsOf: dir.appendingPathComponent(VaultReader.promptsFile)), foreign)
                // Level now, and still left alone on the next open.
                XCTAssertEqual(VaultContract.heal(in: dir, bundled: bundled(revision: 8)), [])
            }
        }
    }

    func testAnOlderPromptsFileOfLongbooksIsReplaced() throws {
        let dir = try folder()
        try stamp(dir, revision: 7)
        try Data(#"{"contract_revision":7,"groups":[],"prompts":[]}"#.utf8)
            .write(to: dir.appendingPathComponent(VaultReader.promptsFile))
        let written = VaultContract.heal(in: dir, bundled: bundled(revision: 8))
        XCTAssertTrue(written.contains(VaultReader.promptsFile))
        XCTAssertEqual(try Data(contentsOf: dir.appendingPathComponent(VaultReader.promptsFile)),
                       bundled(revision: 8)[VaultReader.promptsFile])
    }

    /// A new vault is written in the same order: the memory first, the stamp last.
    func testANewVaultIsStampedLast() throws {
        let dir = try folder().appendingPathComponent("longbook", isDirectory: true)
        let written = try VaultScaffold.create(at: dir, contractFiles: bundled(revision: 8))
        XCTAssertEqual(written.first, VaultReader.dataFile)
        XCTAssertEqual(written.last, VaultReader.libraryFile)
        XCTAssertEqual(Set(written), Set([VaultReader.dataFile] + VaultContract.files))
    }

    func testTheDataFileIsNeverTouched() throws {
        let dir = try folder()
        let data = dir.appendingPathComponent(VaultReader.dataFile)
        let memory = Data(#"{"app":"longbook","version":3,"commitments":[]}"#.utf8)
        try memory.write(to: data)
        _ = VaultContract.heal(in: dir, bundled: bundled(revision: 8))
        XCTAssertEqual(try Data(contentsOf: data), memory)
    }

    func testAVaultWithNoContractGetsTheWholeSet() throws {
        let dir = try folder()
        XCTAssertEqual(VaultContract.heal(in: dir, bundled: bundled(revision: 8)).sorted(),
                       VaultContract.files.sorted())
    }

    /// The shipped set is what a real vault is measured against, so it has to carry a stamp.
    func testTheShippedLibraryCarriesARevision() throws {
        let files = VaultContract.bundledFiles()
        XCTAssertEqual(files.count, VaultContract.files.count)
        XCTAssertNotNil(VaultContract.revision(of: files[VaultReader.libraryFile]))
    }

    /// The v1 schema this bug left behind describes `subscriptions`; v2 data has `commitments`.
    func testTheShippedSchemaMatchesWhatTheAppWrites() throws {
        let schema = try XCTUnwrap(VaultContract.bundledSchema())
        let required = try XCTUnwrap(schema["required"] as? [String])
        let fresh = VaultScaffold.freshMemory()
        for key in required {
            XCTAssertNotNil(fresh[key], "a fresh vault is missing the schema's required \(key)")
        }
        let properties = try XCTUnwrap(schema["properties"] as? [String: Any])
        let version = try XCTUnwrap(properties["version"] as? [String: Any])
        XCTAssertEqual(version["const"] as? Int, fresh["version"] as? Int)
    }
}
