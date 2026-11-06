import XCTest
@testable import LongbookCore

final class ReleaseNotesTests: XCTestCase {
    private let repo = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()

    func testReleasesReadNewestFirstAndAnEmptyOneIsDropped() throws {
        let data = Data("""
        [{"version": "1.3.3", "build": 18, "date": "2026-09-24", "changes": ["a"]},
         {"version": "1.3.4", "build": 19, "date": "2026-09-30", "changes": ["b", "c"]},
         {"version": "1.3.5", "build": 20, "changes": []},
         {"build": 21, "changes": ["no version"]}]
        """.utf8)
        let releases = try XCTUnwrap(ReleaseNotes.decode(data))
        XCTAssertEqual(releases.map(\.version), ["1.3.4", "1.3.3"])
        XCTAssertEqual(releases.first?.changes, ["b", "c"])
        XCTAssertEqual(ReleaseNotes.current(in: releases, version: "1.3.3")?.build, 18)
        XCTAssertEqual(ReleaseNotes.current(in: releases, version: "9.9")?.build, 19, "no match reads the newest")
        XCTAssertNil(ReleaseNotes.decode(Data("{}".utf8)))
    }

    /// The file the app ships must name the version the project builds, or the screen would
    /// describe another release.
    func testTheShippedChangelogNamesTheProjectsVersionAndBuild() throws {
        let json = try Data(contentsOf: repo.appendingPathComponent("apps/longbook/Resources/changelog.json"))
        let newest = try XCTUnwrap(ReleaseNotes.decode(json)?.first)
        let project = try String(contentsOf: repo.appendingPathComponent("apps/longbook/project.yml"), encoding: .utf8)
        let version = try XCTUnwrap(project.firstMatch(of: #/MARKETING_VERSION: "([^"]+)"/#)?.1)
        let build = try XCTUnwrap(project.firstMatch(of: #/CURRENT_PROJECT_VERSION: "(\d+)"/#)?.1)
        XCTAssertEqual(newest.version, String(version))
        XCTAssertEqual(newest.build, Int(build))
        XCTAssertFalse(newest.changes.isEmpty)
        XCTAssertNotNil(newest.date.firstMatch(of: #/^\d{4}-\d{2}-\d{2}$/#))
    }
}
