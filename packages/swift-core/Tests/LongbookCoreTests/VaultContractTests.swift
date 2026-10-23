// The bundled contract files must exist and byte-match packages/core's copy — see
// scripts/gen-vault-contract.mts, which writes both from one source.
import XCTest
@testable import LongbookCore

final class VaultContractTests: XCTestCase {
    func testBundledFilesArePresentAndNonEmpty() {
        let files = VaultContract.bundledFiles()
        // Off the list, not a copy of it: a fourth contract file must not need this test edited.
        XCTAssertEqual(Set(files.keys), Set(VaultContract.files))
        for (name, data) in files {
            XCTAssertGreaterThan(data.count, 0, "\(name) should not be empty")
        }
    }

    func testBundledSchemaIsValidJSON() throws {
        let files = VaultContract.bundledFiles()
        let schema = try XCTUnwrap(files[VaultReader.schemaFile])
        XCTAssertNoThrow(try JSONSerialization.jsonObject(with: schema))
    }

    func testBundledLlmsDoesNotClaimIOSIsFreeForever() throws {
        let files = VaultContract.bundledFiles()
        let llms = try XCTUnwrap(files[VaultReader.llmsFile])
        let text = String(decoding: llms, as: UTF8.self)
        XCTAssertFalse(text.contains("free, always"), "the corrected paid-model contract must not claim this")
    }

    /// library.json is the only file parsed for a revision, but every file is stamped by one
    /// generator run. A set that disagrees with itself would heal on the strength of a number
    /// the other files contradict.
    func testEveryBundledFileNamesTheSameRevision() throws {
        let files = VaultContract.bundledFiles()
        let revision = try XCTUnwrap(VaultContract.revision(of: files[VaultReader.libraryFile]))
        let schema = String(decoding: try XCTUnwrap(files[VaultReader.schemaFile]), as: UTF8.self)
        let llms = String(decoding: try XCTUnwrap(files[VaultReader.llmsFile]), as: UTF8.self)
        XCTAssertTrue(schema.contains("contract revision \(revision)"), "the schema names another revision")
        XCTAssertTrue(llms.contains("contract revision \(revision)"), "llms.txt names another revision")
        XCTAssertEqual(VaultContract.revision(of: files[VaultReader.promptsFile]), revision,
                       "prompts.json names another revision")
        XCTAssertNil(VaultContract.revision(of: Data("Hello. If you are an AI reading this…".utf8)))
    }

    /// A vault made before documents/ existed gets one on open — the readers that list
    /// statements need somewhere to look, whatever the contract revision says.
    func testHealingMakesTheDocumentsFolderForAnOlderVault() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("heal-docs-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let memory = Data(#"{"app":"longbook","version":2,"commitments":[]}"#.utf8)
        try memory.write(to: root.appendingPathComponent(VaultReader.dataFile))

        _ = VaultContract.heal(in: root)

        var isDir: ObjCBool = false
        let made = FileManager.default.fileExists(
            atPath: root.appendingPathComponent("documents").path, isDirectory: &isDir)
        XCTAssertTrue(made && isDir.boolValue)
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent(VaultReader.dataFile)), memory)
    }

    func testBundledFilesByteMatchTheSharedCoreCopy() throws {
        let corePath = sharedFixturesDirectory(from: #filePath)
            .deletingLastPathComponent() // .../core/tests/
            .deletingLastPathComponent() // .../core/
            .appendingPathComponent("contract")
        let files = VaultContract.bundledFiles()
        for (name, bundled) in files {
            let coreCopy = try Data(contentsOf: corePath.appendingPathComponent(name))
            XCTAssertEqual(bundled, coreCopy, "\(name) must be byte-identical to packages/core/contract")
        }
    }
}
