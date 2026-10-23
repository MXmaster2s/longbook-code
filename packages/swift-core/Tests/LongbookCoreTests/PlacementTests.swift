// What a picked folder means — the rules that keep one vault from becoming two.
//
// Run against a real temp directory, not a mocked FileManager: the thing tested IS
// filesystem shape. A mock could agree with a wrong model and pass anyway.
import XCTest
@testable import LongbookCore

final class PlacementTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("placement-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func makeVault(at dir: URL) throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: dir.appendingPathComponent(VaultReader.dataFile))
    }

    /// An empty folder — the first-run case. The vault goes in `longbook/`, NOT in the picked folder
    /// itself — picking iCloud Drive must not leave a bare financial_memory.json at its root.
    func testEmptyFolderCreatesNestedLongbook() {
        let out = VaultPlacement.resolve(picked: root)
        XCTAssertEqual(out, .create(root.appendingPathComponent("longbook", isDirectory: true)))
    }

    /// They navigated into `longbook` and picked it. The most natural thing to do, and it must adopt —
    /// creating `longbook/longbook/` would be absurd, and a second vault.
    func testPickingTheVaultItselfAdoptsIt() throws {
        try makeVault(at: root)
        XCTAssertEqual(VaultPlacement.resolve(picked: root), .adopt(root))
    }

    /// The second-app-finds-it case: they picked iCloud Drive, the Mac already made a vault inside.
    func testPickingTheParentAdoptsTheNestedVault() throws {
        let nested = root.appendingPathComponent("longbook", isDirectory: true)
        try makeVault(at: nested)
        XCTAssertEqual(VaultPlacement.resolve(picked: root), .adopt(nested))
    }

    /// A `longbook/` folder exists but holds no memory — half-made, or made by hand. Complete it in
    /// place; do not step around it with a differently-named folder.
    func testEmptyLongbookFolderIsCompletedInPlace() throws {
        let nested = root.appendingPathComponent("longbook", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        XCTAssertEqual(VaultPlacement.resolve(picked: root), .create(nested))
    }

    /// THE RULE. When a vault is present, every outcome is `.adopt`, never a second
    /// vault beside it. Two vaults is the failure that looks like success: the phone
    /// writes to one, the Mac reads the other, and nobody finds out until a payment is missing.
    func testNeverCreatesASecondVaultBesideAnExistingOne() throws {
        for site in [root!, root.appendingPathComponent("longbook", isDirectory: true)] {
            let fresh = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: fresh, withIntermediateDirectories: true)
            let target = site == root ? fresh : fresh.appendingPathComponent("longbook", isDirectory: true)
            try makeVault(at: target)

            let out = VaultPlacement.resolve(picked: fresh)
            guard case .adopt(let adopted) = out else {
                return XCTFail("a vault at \(target.lastPathComponent) produced \(out), not .adopt")
            }
            XCTAssertEqual(adopted.standardizedFileURL, target.standardizedFileURL)
        }
    }

    /// The picked folder wins over a nested one when both are vaults. Pathological, but the order has
    /// to be decided somewhere rather than by whichever check ran first: the user pointed AT this
    /// folder, so that is what they meant.
    func testThePickedFolderWinsWhenBothAreVaults() throws {
        try makeVault(at: root)
        try makeVault(at: root.appendingPathComponent("longbook", isDirectory: true))
        XCTAssertEqual(VaultPlacement.resolve(picked: root), .adopt(root))
    }

    /// The folder name must stay exactly what the desktop constructs and scans for. A rename here is a
    /// vault the Mac cannot find unaided, which is the whole bug this file exists to close.
    func testFolderNameMatchesTheDesktop() {
        XCTAssertEqual(VaultPlacement.folderName, "longbook")
    }
}
