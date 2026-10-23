// The widget's copy of the vault, written against a temp directory — a unit test
// can't stand up an extension to read the real App Group container.
// Pins down what can silently go wrong: exact bytes, no old tail, never mistaken for a vault.
import XCTest
@testable import LongbookCore

final class MirrorTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("mirror-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    /// Byte-for-byte, because the widget decodes this with the same decoder the app uses on the real
    /// file. Anything less than an exact copy is a vault that reads differently on the Home Screen.
    func testWriteThenReadReturnsTheExactBytes() {
        let bytes = Data(#"{"app":"longbook","version":1}"#.utf8)
        XCTAssertTrue(VaultMirror.write(bytes, in: dir))
        XCTAssertEqual(VaultMirror.read(in: dir), bytes)
    }

    /// A shorter vault must not leave the tail of a longer one behind — that would decode as valid
    /// JSON's worth of nonsense, or worse, as an older set of commitments.
    func testOverwritingWithShorterBytesLeavesNoTail() {
        VaultMirror.write(Data(String(repeating: "x", count: 5000).utf8), in: dir)
        let short = Data(#"{"app":"longbook"}"#.utf8)
        VaultMirror.write(short, in: dir)
        XCTAssertEqual(VaultMirror.read(in: dir), short)
    }

    /// Nothing there is not an error. It is the ordinary state on a phone whose vault has never been
    /// opened, and the widget answers it with its own words.
    func testReadingAnEmptyDirectoryReturnsNil() {
        XCTAssertNil(VaultMirror.read(in: dir))
    }

    /// The return value drives whether WidgetKit gets nudged, so it has to mean "the widget would see
    /// something different" — not "a write happened". The app re-reads its own vault every 20s and
    /// almost always finds it unchanged.
    func testWriteReportsWhetherTheCopyActuallyChanged() {
        let bytes = Data(#"{"app":"longbook","version":1}"#.utf8)
        XCTAssertTrue(VaultMirror.write(bytes, in: dir), "first write is a change")
        XCTAssertFalse(VaultMirror.write(bytes, in: dir), "identical bytes are not a change")
        XCTAssertTrue(VaultMirror.write(Data(#"{"app":"longbook","version":1,"x":2}"#.utf8), in: dir))
    }

    func testClearRemovesTheCopy() {
        VaultMirror.write(Data("{}".utf8), in: dir)
        VaultMirror.clear(in: dir)
        XCTAssertNil(VaultMirror.read(in: dir))
        XCTAssertNoThrow(VaultMirror.clear(in: dir), "clearing twice is not an error")
    }

    /// The copy is NOT named like the data file, and a folder holding only a copy is
    /// not a vault. A derived copy wearing the vault's name would eventually be opened
    /// as one by outside code looking in the group container.
    func testTheCopyCannotBeMistakenForAVault() {
        XCTAssertNotEqual(VaultMirror.fileName, VaultReader.dataFile)
        VaultMirror.write(Data(#"{"app":"longbook","version":1,"commitments":[]}"#.utf8), in: dir)
        XCTAssertNil(try? VaultReader.load(from: dir), "a directory holding only the copy is not a vault")
    }
}
