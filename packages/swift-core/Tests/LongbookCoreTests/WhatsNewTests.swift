import XCTest
@testable import LongbookCore

final class WhatsNewTests: XCTestCase {
    func testAVersionsBuildsMergeNewestFirstWithEachLineOnce() {
        let releases = [
            Release(version: "1.5.0", build: 52, date: "2026-10-27", changes: ["Shared. Twice over.", "Newest."]),
            Release(version: "1.5.0", build: 51, date: "2026-10-23", changes: ["Older.", "Shared. Twice over."]),
            Release(version: "1.4.1", build: 50, date: "2026-10-22", changes: ["Another version."]),
            Release(version: "1.5.0", build: 53, date: "2026-10-28", changes: ["Nothing you will see changes."]),
        ]
        let changes = WhatsNew.changes(for: "1.5.0", in: releases)
        XCTAssertEqual(changes.map(\.lead), ["Shared.", "Newest.", "Older."])
        XCTAssertEqual(changes.first?.rest, "Twice over.")
        XCTAssertTrue(WhatsNew.changes(for: "9.9.9", in: releases).isEmpty)
    }

    func testALineThatFixesSomethingIsBadgedFixed() {
        XCTAssertEqual(WhatsNew.kind(of: "Fixed a crash when importing."), .fixed)
        XCTAssertEqual(WhatsNew.kind(of: "Fixes the menu."), .fixed)
        XCTAssertEqual(WhatsNew.kind(of: "Star a person to keep it at the top."), .new)
        XCTAssertEqual(WhatsNew.Kind.fixed.label, "Fixed")
        XCTAssertEqual(WhatsNew.Kind.new.label, "New")
    }

    func testTheFirstSentenceKeepsVersionNumbersAndMenuPathsWhole() {
        XCTAssertEqual(WhatsNew.firstSentence("Version 1.3.6 is out. More here."), "Version 1.3.6 is out.")
        XCTAssertEqual(WhatsNew.firstSentence("Replay them in Settings > Tutorials."), "Replay them in Settings > Tutorials.")
    }

    func testItIsDueOnceForEachNewerVersion() {
        XCTAssertTrue(WhatsNew.isDue(current: "1.5.0", seen: nil), "a copy from before What's New")
        XCTAssertTrue(WhatsNew.isDue(current: "1.5.0", seen: "1.4.1"))
        XCTAssertTrue(WhatsNew.isDue(current: "1.10.0", seen: "1.9.2"))
        XCTAssertFalse(WhatsNew.isDue(current: "1.5.0", seen: "1.5.0"), "already shown")
        XCTAssertFalse(WhatsNew.isDue(current: "1.4.1", seen: "1.5.0"), "a downgrade shows nothing")
        XCTAssertFalse(WhatsNew.isDue(current: "1.5", seen: "1.5.0"))
    }
}
