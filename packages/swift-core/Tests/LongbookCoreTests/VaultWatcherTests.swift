// The watcher's one promise: a write made by anyone else reaches onChange within a second.
// And the stamp a tick compares tells one write from the next without reading the file.
// Plain temp folders throughout — nothing here touches iCloud.
import XCTest
@testable import LongbookCore

@MainActor
final class VaultWatcherTests: XCTestCase {
    private var folder: URL!
    private var file: URL { folder.appendingPathComponent(VaultReader.dataFile) }

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("watcher-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(#"{"v":1}"#.utf8).write(to: file)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    func testAnAtomicReplaceReachesOnChangeWithinASecond() async throws {
        let heard = expectation(description: "onChange after the replace")
        heard.assertForOverFulfill = false
        let watcher = VaultWatcher(folder: folder, insideContainer: false) { heard.fulfill() }
        watcher.resume()
        // The same replace every writer does: a temp file renamed over the old inode.
        try Data(#"{"v":2}"#.utf8).write(to: file, options: .atomic)
        await fulfillment(of: [heard], timeout: 1)
        watcher.stop()
    }

    func testAStoppedWatcherSaysNothing() async throws {
        var heard = 0
        let watcher = VaultWatcher(folder: folder, insideContainer: false) { heard += 1 }
        watcher.resume()
        watcher.stop()
        try Data(#"{"v":2}"#.utf8).write(to: file, options: .atomic)
        try await Task.sleep(for: .milliseconds(600))
        XCTAssertEqual(heard, 0)
    }

    func testStampMovesWithTheFileAndIsNilWithoutIt() throws {
        let first = try XCTUnwrap(VaultReader.stamp(folder))
        XCTAssertEqual(first, VaultReader.stamp(folder))
        XCTAssertEqual(first.size, 7)

        // More bytes: the size moves, whatever the clock did.
        try Data(#"{"v":22}"#.utf8).write(to: file, options: .atomic)
        let second = try XCTUnwrap(VaultReader.stamp(folder))
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(second.size, 8)

        // The same bytes written later: the date alone tells them apart.
        let later = second.modified.addingTimeInterval(60)
        try FileManager.default.setAttributes([.modificationDate: later], ofItemAtPath: file.path)
        let third = try XCTUnwrap(VaultReader.stamp(folder))
        XCTAssertNotEqual(second, third)
        XCTAssertEqual(third.size, second.size)

        try FileManager.default.removeItem(at: file)
        XCTAssertNil(VaultReader.stamp(folder))
    }
}
