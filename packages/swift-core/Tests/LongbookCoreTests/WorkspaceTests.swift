// The sidecar's one hard rule: saving a preference must never delete a preference this build
// has no field for — the Mac writes keys the phone doesn't model, into the same folder.
import XCTest
@testable import LongbookCore

final class WorkspaceTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("workspace-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    private func writeRaw(_ json: String) throws {
        try Data(json.utf8).write(to: folder.appendingPathComponent(WorkspaceStore.fileName))
    }

    func testAMissingSidecarReadsAsNoPreferences() {
        let workspace = WorkspaceStore.read(in: folder)
        XCTAssertNil(workspace.homeCurrency)
        XCTAssertTrue(workspace.customCurrencies.isEmpty)
        XCTAssertTrue(workspace.bookmarks.isEmpty)
    }

    func testAnUnreadableSidecarIsTreatedAsAbsentRatherThanFatal() throws {
        try writeRaw("{ not json")
        XCTAssertNil(WorkspaceStore.read(in: folder).homeCurrency)
    }

    func testSavingOneFieldKeepsFieldsThisBuildDoesNotModel() throws {
        try writeRaw(#"{"trayDetail": false, "somethingNewer": {"a": 1}}"#)
        try WorkspaceStore.update(in: folder) { $0.homeCurrency = "USD" }

        let reread = WorkspaceStore.read(in: folder)
        XCTAssertEqual(reread.homeCurrency, "USD")
        XCTAssertEqual(reread.raw["trayDetail"] as? Bool, false)
        XCTAssertNotNil(reread.raw["somethingNewer"])
    }

    func testClearingTheHomeCurrencyGoesBackToDerivingIt() throws {
        try WorkspaceStore.update(in: folder) { $0.homeCurrency = "INR" }
        try WorkspaceStore.update(in: folder) { $0.homeCurrency = nil }
        XCTAssertNil(WorkspaceStore.read(in: folder).homeCurrency)
    }

    func testCustomCurrencyCodesDedupeWithoutRegardToCase() throws {
        try WorkspaceStore.update(in: folder) { $0.customCurrencies = ["AED", " aed ", "SGD"] }
        XCTAssertEqual(WorkspaceStore.read(in: folder).customCurrencies, ["AED", "SGD"])
    }

    func testBookmarksKeepTheirOrderAndNeverRepeat() throws {
        try WorkspaceStore.update(in: folder) { $0.bookmarks = ["b", "a", "b"] }
        XCTAssertEqual(WorkspaceStore.read(in: folder).bookmarks, ["b", "a"])
    }

    func testShareDetailsSitBesideTheShareMapAndLeaveItsShapeAlone() throws {
        try writeRaw(#"{"reportShares": {"rpt-1": "share-1"}}"#)
        try WorkspaceStore.update(in: folder) {
            $0.reportShareDetails = ["rpt-1": ["url": "https://x/?id=share-1", "with": "Priya"]]
        }
        let reread = WorkspaceStore.read(in: folder)
        XCTAssertEqual(reread.reportShares, ["rpt-1": "share-1"])
        XCTAssertEqual(reread.reportShareDetails["rpt-1"]?["with"], "Priya")
        XCTAssertEqual((reread.raw["reportShares"] as? [String: String])?["rpt-1"], "share-1")
    }
}
