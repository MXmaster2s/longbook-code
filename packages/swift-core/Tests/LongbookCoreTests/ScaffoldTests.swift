// Creating a vault: does the folder on disk look like one? A real defect: "create in
// iCloud" produced a lone `financial_memory.json`, invisible to tests since only the
// picker reaches it and it can't be driven in the Simulator. Moved into VaultScaffold.
import XCTest
@testable import LongbookCore

final class ScaffoldTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("scaffold-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private let contract = [
        VaultReader.schemaFile: Data(#"{"$schema":"synthetic"}"#.utf8),
        VaultReader.llmsFile: Data("synthetic etiquette\n".utf8),
    ]

    /// The whole regression: a created vault carries the memory AND both contract files — not the
    /// memory alone, which is what shipped.
    func testCreatesAllThreeFiles() throws {
        let vault = root.appendingPathComponent("longbook", isDirectory: true)
        let written = try VaultScaffold.create(at: vault, contractFiles: contract)

        XCTAssertEqual(Set(written), [VaultReader.dataFile, VaultReader.schemaFile, VaultReader.llmsFile])
        for name in written {
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: vault.appendingPathComponent(name).path),
                "\(name) was reported written but is not on disk"
            )
        }
    }

    /// A vault made with this build's own contract carries every contract file, prompts.json
    /// included, so an outside AI finds the prompt catalogue beside llms.txt.
    func testCreatesEveryBundledContractFile() throws {
        let vault = root.appendingPathComponent("longbook", isDirectory: true)
        let written = try VaultScaffold.create(at: vault, contractFiles: VaultContract.bundledFiles())

        XCTAssertEqual(Set(written), Set([VaultReader.dataFile] + VaultContract.files))
        XCTAssertTrue(VaultContract.files.contains(VaultReader.promptsFile))
        let prompts = try Data(contentsOf: vault.appendingPathComponent(VaultReader.promptsFile))
        XCTAssertEqual(prompts, VaultContract.bundledFiles()[VaultReader.promptsFile])
    }

    /// It creates the folder it was given, rather than requiring one to exist. The picker hands back a
    /// parent; `longbook/` inside it will not be there yet.
    func testCreatesTheDocumentsFolder() throws {
        let folder = root.appendingPathComponent("docs-vault", isDirectory: true)
        try VaultScaffold.create(at: folder, contractFiles: [:])
        var isDir: ObjCBool = false
        let there = FileManager.default.fileExists(
            atPath: folder.appendingPathComponent("documents").path, isDirectory: &isDir
        )
        XCTAssertTrue(there && isDir.boolValue, "the statements drop zone exists from day one")
    }

    func testCreatesTheFolderItself() throws {
        let vault = root.appendingPathComponent("nested/deep/longbook", isDirectory: true)
        try VaultScaffold.create(at: vault, contractFiles: [:])
        XCTAssertTrue(FileManager.default.fileExists(atPath: vault.appendingPathComponent(VaultReader.dataFile).path))
    }

    /// The memory must satisfy the five fields the contract requires, and invent nothing — a vault the
    /// desktop would reject is worse than no vault.
    func testMemoryIsContractValidAndDecodable() throws {
        let vault = root.appendingPathComponent("longbook", isDirectory: true)
        try VaultScaffold.create(at: vault, contractFiles: contract)

        let bytes = try Data(contentsOf: vault.appendingPathComponent(VaultReader.dataFile))
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        XCTAssertEqual(json["app"] as? String, "longbook")
        XCTAssertEqual(json["version"] as? Int, VAULT_FORMAT_VERSION)
        XCTAssertEqual((json["commitments"] as? [Any])?.count, 0, "commitments should exist and be empty")
        XCTAssertEqual(Set(json.keys), ["app", "version", "commitments"])
        // And it must decode as a Vault — the app has to be able to read what it just wrote.
        XCTAssertNoThrow(try JSONDecoder().decode(Vault.self, from: bytes))
    }

    /// Contract bytes go in untouched. They are generated from the desktop's vault.ts, so re-encoding
    /// or reformatting them here would be this app quietly inventing a second contract.
    func testContractFilesAreCopiedVerbatim() throws {
        let vault = root.appendingPathComponent("longbook", isDirectory: true)
        try VaultScaffold.create(at: vault, contractFiles: contract)
        for (name, expected) in contract {
            XCTAssertEqual(try Data(contentsOf: vault.appendingPathComponent(name)), expected, name)
        }
    }

    /// A missing contract resource must NOT sink the vault. The memory is what matters, and the desktop
    /// writes any absent contract file the next time it opens the folder — losing someone's vault to
    /// protect a self-healing file would be the wrong way round.
    func testMissingContractFilesStillProduceAUsableVault() throws {
        let vault = root.appendingPathComponent("longbook", isDirectory: true)
        let written = try VaultScaffold.create(at: vault, contractFiles: [:])
        XCTAssertEqual(written, [VaultReader.dataFile])
        XCTAssertNoThrow(try VaultReader.load(from: vault))
    }

    /// `longbook.workspace.json` is the desktop's display-prefs sidecar, and its own note says an
    /// absent one is never an error. The phone must not invent one.
    func testDoesNotWriteTheWorkspaceSidecar() throws {
        let vault = root.appendingPathComponent("longbook", isDirectory: true)
        try VaultScaffold.create(at: vault, contractFiles: contract)
        let names = try FileManager.default.contentsOfDirectory(atPath: vault.path)
        XCTAssertFalse(names.contains { $0.contains("workspace") }, "found \(names)")
    }

    /// End to end, the way it actually happens: resolve a picked folder, then create at what it says.
    /// Picking a folder must leave `longbook/` inside it — never a bare memory file at the top, which
    /// is exactly what landed in the owner's iCloud Drive.
    func testPickedFolderEndsUpWithANestedCompleteVault() throws {
        guard case .create(let target) = VaultPlacement.resolve(picked: root) else {
            return XCTFail("an empty picked folder should resolve to .create")
        }
        try VaultScaffold.create(at: target, contractFiles: contract)

        XCTAssertFalse(
            FileManager.default.fileExists(atPath: root.appendingPathComponent(VaultReader.dataFile).path),
            "the memory must NOT be written at the top of the picked folder"
        )
        XCTAssertEqual(target.lastPathComponent, "longbook")
        XCTAssertNoThrow(try VaultReader.load(from: target))
        // And re-picking the same parent now finds it instead of making a second one.
        XCTAssertEqual(VaultPlacement.resolve(picked: root), .adopt(target))
    }
    /// A second scaffold over a folder that already has one writes nothing: the memory stays
    /// as found, and no file gets a twin.
    func testNeverWritesOverAnExistingVault() throws {
        let vault = root.appendingPathComponent("longbook", isDirectory: true)
        try VaultScaffold.create(at: vault, contractFiles: contract)
        let memory = Data(#"{"app":"longbook","version":3,"commitments":[{"id":"kept"}]}"#.utf8)
        try memory.write(to: vault.appendingPathComponent(VaultReader.dataFile))

        let again = try VaultScaffold.create(at: vault, contractFiles: contract)

        XCTAssertEqual(again, [])
        XCTAssertEqual(try Data(contentsOf: vault.appendingPathComponent(VaultReader.dataFile)), memory)
        let names = try FileManager.default.contentsOfDirectory(atPath: vault.path)
        XCTAssertFalse(names.contains { $0.contains(" 2") }, "\(names)")
    }

    /// A file iCloud has not sent yet lists as a dot-name. Writing the real name beside it is
    /// how iCloud ends up keeping both, so the scaffold leaves that name to the download.
    func testLeavesNamesStillComingFromICloud() throws {
        let vault = root.appendingPathComponent("longbook", isDirectory: true)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        try Data().write(to: vault.appendingPathComponent(".\(VaultReader.dataFile).icloud"))
        try Data().write(to: vault.appendingPathComponent(".\(VaultReader.llmsFile).icloud"))

        let written = try VaultScaffold.create(at: vault, contractFiles: contract)

        XCTAssertEqual(written, [VaultReader.schemaFile])
        XCTAssertFalse(FileManager.default.fileExists(atPath: vault.appendingPathComponent(VaultReader.dataFile).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: vault.appendingPathComponent(VaultReader.llmsFile).path))
    }
}
