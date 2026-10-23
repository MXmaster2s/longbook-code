// Viewer comments landing in the report file, and surviving the next draw. The rules:
// keyed by module id with the viewer's positional fallback, idempotent on re-pull,
// untouched fields stay put, and a redraw carries what the stored file holds by id, then
// title, then position.
import XCTest
@testable import LongbookCore

final class ReportMergeTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("report-merge-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: folder.appendingPathComponent(ReportReader.folderName), withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    private func writeReport(_ json: String, named name: String = "july.json") throws -> URL {
        let url = folder.appendingPathComponent(ReportReader.folderName).appendingPathComponent(name)
        try Data(json.utf8).write(to: url)
        return url
    }

    private func modules(at url: URL) throws -> [[String: Any]] {
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        return object?["modules"] as? [[String: Any]] ?? []
    }

    func testFileFindsAReportByItsIdNotItsFilename() throws {
        _ = try writeReport(#"{"version":1,"id":"july-2026","title":"July","modules":[]}"#)
        let found = try XCTUnwrap(ReportReader.file(id: "july-2026", in: folder))
        XCTAssertEqual(found.url.lastPathComponent, "july.json")
        XCTAssertNil(ReportReader.file(id: "nothing", in: folder))
    }

    func testACommentLandsUnderItsModuleId() throws {
        let url = try writeReport(
            #"{"version":1,"id":"r","title":"t","modules":[{"id":"m1","type":"stats","stats":[]},{"id":"m2","type":"prose","text":"hello"}]}"#)
        let added = try ReportReader.mergeViewerComments([(module: "m2", line: "asha — nice")], intoReportAt: url)
        XCTAssertEqual(added, 1)
        let mods = try modules(at: url)
        XCTAssertNil(mods[0]["comment"])
        XCTAssertEqual(mods[1]["comment"] as? String, "asha — nice")
        XCTAssertEqual(mods[1]["text"] as? String, "hello", "untouched fields stay put")
    }

    func testTheViewersPositionalFallbackReachesTheRightModule() throws {
        let url = try writeReport(
            #"{"version":1,"id":"r","title":"t","modules":[{"type":"stats","stats":[]},{"type":"prose","text":"x"}]}"#)
        let added = try ReportReader.mergeViewerComments([(module: "module-1", line: "someone — hm")], intoReportAt: url)
        XCTAssertEqual(added, 1)
        XCTAssertEqual(try modules(at: url)[1]["comment"] as? String, "someone — hm")
    }

    func testPullingTwiceNeverDoublesALine() throws {
        let url = try writeReport(
            #"{"version":1,"id":"r","title":"t","modules":[{"id":"m1","type":"prose","text":"x"}]}"#)
        _ = try ReportReader.mergeViewerComments([(module: "m1", line: "asha — nice")], intoReportAt: url)
        let again = try ReportReader.mergeViewerComments([(module: "m1", line: "asha — nice")], intoReportAt: url)
        XCTAssertEqual(again, 0)
        XCTAssertEqual(try modules(at: url)[0]["comment"] as? String, "asha — nice")
    }

    func testANewLineAppendsUnderTheAIsOwnComment() throws {
        let url = try writeReport(
            #"{"version":1,"id":"r","title":"t","modules":[{"id":"m1","type":"prose","text":"x","comment":"the AI's note"}]}"#)
        _ = try ReportReader.mergeViewerComments([(module: "m1", line: "asha — nice")], intoReportAt: url)
        XCTAssertEqual(try modules(at: url)[0]["comment"] as? String, "the AI's note\nasha — nice")
    }

    func testACommentForAModuleThatIsNotThereIsDroppedNotMisfiled() throws {
        let url = try writeReport(
            #"{"version":1,"id":"r","title":"t","modules":[{"id":"m1","type":"prose","text":"x"}]}"#)
        let added = try ReportReader.mergeViewerComments(
            [(module: "m9", line: "lost"), (module: "module-7", line: "lost too")], intoReportAt: url)
        XCTAssertEqual(added, 0)
        XCTAssertNil(try modules(at: url)[0]["comment"])
    }

    // ---- the next draw ----------------------------------------------------------

    private func decoded(_ json: String) throws -> Report {
        try JSONDecoder().decode(Report.self, from: Data(json.utf8))
    }

    /// Three modules, the shape a draw once wrote for a month whose charges shared one tag.
    private let stored = #"""
    {"version":1,"id":"july-2026","title":"July in review","subtitle":"Drawn by longbook",
     "period":"2026-07","currency":"INR","modules":[
      {"type":"stats","title":"Total expenses","stats":[]},
      {"type":"donut","title":"Accounts","currency":"INR","slices":[]},
      {"type":"transactions","title":"All charges","rows":[]}]}
    """#

    /// The same month drawn now: the categories ring stands, so every later module moves.
    private let fresh = #"""
    {"version":1,"id":"july-2026","title":"July in review","subtitle":"Drawn by longbook",
     "period":"2026-07","currency":"INR","modules":[
      {"type":"stats","title":"Total expenses","stats":[]},
      {"type":"donut","title":"Accounts","currency":"INR","slices":[]},
      {"type":"donut","title":"Categories","currency":"INR","slices":[]},
      {"type":"transactions","title":"All charges","rows":[]}]}
    """#

    func testARedrawKeepsTheWordsAViewerWroteUnderTheirOwnHeading() throws {
        let url = try writeReport(stored, named: "july-2026.json")
        let line = "asha — the rent looks high"
        XCTAssertEqual(try ReportReader.mergeViewerComments([(module: "module-2", line: line)], intoReportAt: url), 1)
        let kept = try JSONDecoder().decode(Report.self, from: Data(contentsOf: url))
        let redrawn = try decoded(fresh).carryingComments(from: kept)
        XCTAssertEqual(redrawn.modules.compactMap(\.comment), [line],
                       "a share expires in 72 hours; a draw that dropped this could not ask for it again")
        XCTAssertEqual(redrawn.modules[3].title, "All charges")
        XCTAssertEqual(redrawn.modules[3].comment, line, "the charge list it was written about, moved to position 3")
        XCTAssertNil(redrawn.modules[2].comment, "not the ring that took its old place")
        XCTAssertTrue(String(data: try JSONEncoder().encode(redrawn), encoding: .utf8)?.contains(line) == true,
                      "and it is in the bytes a redraw writes")
    }

    func testWithoutAnIdOrATitleThePositionStillCarries() throws {
        let stored = try decoded(
            #"{"version":1,"id":"r","title":"t","modules":[{"type":"prose","text":"x","comment":"asha — hm"}]}"#)
        let fresh = try decoded(
            #"{"version":1,"id":"r","title":"t","modules":[{"type":"prose","text":"y"},{"type":"stats","stats":[]}]}"#)
        XCTAssertEqual(fresh.carryingComments(from: stored).modules[0].comment, "asha — hm")
    }

    func testATitleMatchBeatsThePositionEvenWhereBothWouldLand() throws {
        let stored = try decoded(
            #"{"version":1,"id":"r","title":"t","modules":[{"type":"stats","title":"Total expenses","stats":[],"comment":"asha — steep"},{"type":"prose","title":"Note","text":"x","comment":"asha — hm"}]}"#)
        let fresh = try decoded(
            #"{"version":1,"id":"r","title":"t","modules":[{"type":"prose","title":"Note","text":"x"},{"type":"stats","title":"Total expenses","stats":[]}]}"#)
        let redrawn = fresh.carryingComments(from: stored)
        XCTAssertEqual(redrawn.modules[0].comment, "asha — hm", "the note, by its heading")
        XCTAssertEqual(redrawn.modules[1].comment, "asha — steep", "the total, by its heading; neither took the other's")
    }

    func testAnIdOnBothSidesBeatsThePosition() throws {
        let stored = try decoded(
            #"{"version":1,"id":"r","title":"t","modules":[{"id":"m9","type":"prose","text":"x","comment":"mine"}]}"#)
        let fresh = try decoded(
            #"{"version":1,"id":"r","title":"t","modules":[{"type":"stats","stats":[]},{"id":"m9","type":"prose","text":"x"}]}"#)
        let redrawn = fresh.carryingComments(from: stored)
        XCTAssertNil(redrawn.modules[0].comment, "not the module standing where the old one stood")
        XCTAssertEqual(redrawn.modules[1].comment, "mine")
    }

    func testAModuleNothingMatchesKeepsNoCommentAndTheBytesDoNotMove() throws {
        let fresh = try decoded(self.fresh)
        let redrawn = fresh.carryingComments(from: try decoded(stored))
        XCTAssertEqual(redrawn.modules.compactMap(\.comment), [], "nothing to carry, nothing gained")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        XCTAssertEqual(try encoder.encode(redrawn), try encoder.encode(fresh),
                       "so a redraw that changes nothing still writes nothing")
    }

    func testAnUnknownModuleCarriesItsCommentToo() throws {
        let stored = try decoded(
            #"{"version":1,"id":"r","title":"t","modules":[{"type":"gauge","reading":3,"comment":"asha — hm"}]}"#)
        let fresh = try decoded(#"{"version":1,"id":"r","title":"t","modules":[{"type":"gauge","reading":4}]}"#)
        let redrawn = fresh.carryingComments(from: stored)
        XCTAssertEqual(redrawn.modules[0].comment, "asha — hm", "a kind this version can't draw still holds words")
        let object = try JSONSerialization.jsonObject(with: try JSONEncoder().encode(redrawn)) as? [String: Any]
        let modules = object?["modules"] as? [[String: Any]] ?? []
        XCTAssertEqual(modules.first?["reading"] as? Double, 4, "its own fields ride along")
    }
}
