// The folder remembers whose account opened it. A second device reads that before anyone
// signs in, so typing another address cannot quietly start an empty longbook instead.
import XCTest
@testable import LongbookCore

final class AccountEmailTests: XCTestCase {
    private func folder() throws -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("account-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func testAFolderNobodyHasOpenedNamesNoAccount() throws {
        let dir = try folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        XCTAssertNil(WorkspaceStore.read(in: dir).accountEmail)
    }

    func testTheAccountSurvivesAReadBack() throws {
        let dir = try folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        _ = try WorkspaceStore.update(in: dir) { $0.accountEmail = "  rohit@example.com  " }
        XCTAssertEqual(WorkspaceStore.read(in: dir).accountEmail, "rohit@example.com")
    }

    func testItLivesBesideTheVaultAndNeverInsideIt() throws {
        let dir = try folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let memory = Data(#"{"app":"longbook","version":3,"commitments":[]}"#.utf8)
        try memory.write(to: dir.appendingPathComponent(VaultReader.dataFile))

        _ = try WorkspaceStore.update(in: dir) { $0.accountEmail = "rohit@example.com" }

        XCTAssertEqual(try Data(contentsOf: dir.appendingPathComponent(VaultReader.dataFile)), memory,
                       "an address is not the owner's financial memory and never enters it")
    }

    func testClearingItLeavesNoAddressBehind() throws {
        let dir = try folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        _ = try WorkspaceStore.update(in: dir) { $0.accountEmail = "rohit@example.com" }
        _ = try WorkspaceStore.update(in: dir) { $0.accountEmail = nil }
        XCTAssertNil(WorkspaceStore.read(in: dir).accountEmail)
    }

    func testTheSidecarsOtherPreferencesAreUntouched() throws {
        let dir = try folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        _ = try WorkspaceStore.update(in: dir) {
            $0.homeCurrency = "INR"
            $0.bookmarks = ["s-rent"]
        }
        _ = try WorkspaceStore.update(in: dir) { $0.accountEmail = "rohit@example.com" }

        let after = WorkspaceStore.read(in: dir)
        XCTAssertEqual(after.homeCurrency, "INR")
        XCTAssertEqual(after.bookmarks, ["s-rent"])
        XCTAssertEqual(after.accountEmail, "rohit@example.com")
    }
}
