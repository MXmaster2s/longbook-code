// The report format holds to the vault's own conventions — snake_case, ISO days,
// amounts wearing their currency — and never drops what it doesn't understand.
// Every fixture is SYNTHETIC; this repo is public.
import XCTest
@testable import LongbookCore

final class ReportTests: XCTestCase {
    private let fixture = """
    {
      "version": 1,
      "id": "rpt-demo",
      "title": "july in review",
      "created_at": "2026-08-01",
      "currency": "INR",
      "modules": [
        { "type": "stats", "stats": [
          { "label": "total spent", "amount": 161420, "currency": "INR", "delta_pct": 8.4, "delta_is_good": false },
          { "label": "active commitments", "value": "32" }
        ]},
        { "type": "prose", "text": "spending held steady." },
        { "type": "donut", "title": "by category", "slices": [
          { "label": "home", "amount": 40000, "currency": "INR" },
          { "label": "claude", "amount": 100, "currency": "USD" }
        ]},
        { "type": "bars", "bars": [ { "label": "jun", "amount": 1000 }, { "label": "jul", "amount": 1200 } ]},
        { "type": "transactions", "comment": "the rent looks high", "rows": [
          { "name": "home rent", "date": "2026-07-01", "amount": 40000, "currency": "INR", "tag": "Home" }
        ]},
        { "type": "hologram", "beams": 12 }
      ]
    }
    """

    func testDecodesEveryModuleAndKeepsTheStrangerAsUnknown() throws {
        let report = try JSONDecoder().decode(Report.self, from: Data(fixture.utf8))
        XCTAssertEqual(report.title, "july in review")
        XCTAssertEqual(report.modules.count, 6)

        guard case .stats(let stats) = report.modules[0] else { return XCTFail("stats first") }
        XCTAssertEqual(stats.stats[0].deltaPct, 8.4)
        XCTAssertEqual(stats.stats[0].deltaIsGood, false, "a rising spend points up but is not good news")
        XCTAssertEqual(stats.stats[1].value, "32")

        guard case .donut(let donut) = report.modules[2] else { return XCTFail("donut third") }
        XCTAssertEqual(donut.slices[1].currency, "USD", "a foreign slice keeps its own currency")

        guard case .transactions(let list) = report.modules[4] else { return XCTFail("transactions fifth") }
        XCTAssertEqual(list.comment, "the rent looks high", "a module carries its annotation")

        guard case .unknown(let type, let fields) = report.modules[5] else { return XCTFail("stranger last") }
        XCTAssertEqual(type, "hologram", "an unknown module is named, never dropped")
        guard case .integer(let beams) = fields["beams"] else { return XCTFail("its data rides along") }
        XCTAssertEqual(beams, 12, "the data still belongs to the user and still shows")
    }

    func testUnknownModuleRoundTripsItsFields() throws {
        let report = try JSONDecoder().decode(Report.self, from: Data(fixture.utf8))
        let encoded = try JSONEncoder().encode(report)
        let again = try JSONDecoder().decode(Report.self, from: encoded)
        guard case .unknown(let type, let fields) = again.modules[5] else { return XCTFail("stranger survives") }
        XCTAssertEqual(type, "hologram")
        guard case .integer(let beams) = fields["beams"] else { return XCTFail("field survives") }
        XCTAssertEqual(beams, 12, "a write must not shed what this version doesn't understand")
    }

    func testBigIntegersKeepEveryDigitThroughTheRoundTrip() throws {
        // 2^53 + 1 — the first integer a Double silently corrupts. An id or timestamp
        // in an unknown module must survive exactly.
        let body = #"{"version":1,"id":"r","title":"t","modules":[{"type":"x","stamp":9007199254740993}]}"#
        let report = try JSONDecoder().decode(Report.self, from: Data(body.utf8))
        guard case .unknown(_, let fields) = report.modules[0],
              case .integer(let stamp) = fields["stamp"] else { return XCTFail("integer case") }
        XCTAssertEqual(stamp, 9_007_199_254_740_993)

        let again = try JSONDecoder().decode(Report.self, from: JSONEncoder().encode(report))
        guard case .unknown(_, let survived) = again.modules[0],
              case .integer(let value) = survived["stamp"] else { return XCTFail("survives encode") }
        XCTAssertEqual(value, 9_007_199_254_740_993, "boxed as Double this would end ...992")
    }

    func testInsightsReaderKeepsTheLatestNotePerModule() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("insight-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        let body = """
        {"version":1,"insights":[
          {"module":"dashboard.this_month","text":"older note","created_at":"2026-08-01"},
          {"module":"dashboard.this_month","text":"newer note","created_at":"2026-08-07"},
          {"module":"account.m1","text":"one card note"}
        ]}
        """
        try Data(body.utf8).write(to: vault.appendingPathComponent(InsightsReader.fileName))

        let notes = InsightsReader.byModule(in: vault)
        XCTAssertEqual(notes.count, 2)
        XCTAssertEqual(notes["dashboard.this_month"]?.text, "newer note", "a later entry wins — append, never edit")
        XCTAssertEqual(notes["account.m1"]?.text, "one card note")
        XCTAssertTrue(InsightsReader.byModule(in: vault.appendingPathComponent("nowhere")).isEmpty)
    }

    /// A temporary vault carrying an empty reports folder. The caller removes it.
    private func makeVault() throws -> (vault: URL, folder: URL) {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("report-tests-\(UUID().uuidString)", isDirectory: true)
        let folder = vault.appendingPathComponent(ReportReader.folderName, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return (vault, folder)
    }

    func testReaderListsNewestFirstAndCountsTheUnreadable() throws {
        let (vault, folder) = try makeVault()
        defer { try? FileManager.default.removeItem(at: vault) }

        func write(_ name: String, id: String, created: String) throws {
            let body = #"{"version":1,"id":"\#(id)","title":"t","created_at":"\#(created)","modules":[]}"#
            try Data(body.utf8).write(to: folder.appendingPathComponent(name))
        }
        try write("a.json", id: "older", created: "2026-06-01")
        try write("b.json", id: "newer", created: "2026-08-01")
        // Report-shaped and undecodable: modules is a list, never a string.
        try Data(#"{"version":1,"id":"bad","title":"t","modules":"nope"}"#.utf8)
            .write(to: folder.appendingPathComponent("broken.json"))

        let listed = ReportReader.list(in: vault)
        XCTAssertEqual(listed.reports.map(\.id), ["newer", "older"], "newest first")
        XCTAssertEqual(listed.unreadable, 1, "a report that won't decode is counted, not silently gone")
    }

    func testAFileThatIsNotAReportIsNotABrokenReport() throws {
        let (vault, folder) = try makeVault()
        defer { try? FileManager.default.removeItem(at: vault) }

        // The ledger's own top-level shape: no id, no title, no modules. A copy of it
        // parked in reports/ is a different file, not a report the app failed to read.
        let ledger = #"{"version":2,"app":"longbook","commitments":[],"accounts":[],"tags":[]}"#
        try Data(ledger.utf8).write(to: folder.appendingPathComponent("financial_memory.json"))
        try Data("plain text, not JSON".utf8).write(to: folder.appendingPathComponent("notes.json"))

        let listed = ReportReader.list(in: vault)
        XCTAssertTrue(listed.reports.isEmpty)
        XCTAssertEqual(listed.unreadable, 0, "nothing here claims to be a report")
    }

    func testTwelveReportsFromOneRunListInMonthOrder() throws {
        let (vault, folder) = try makeVault()
        defer { try? FileManager.default.removeItem(at: vault) }

        // One sitting, one created_at. Filenames ascend with the month, so a filename
        // pre-sort would hand back the reverse of what the page wants.
        for month in 1...12 {
            let key = String(format: "2026-%02d", month)
            let body = """
            {"version":1,"id":"rpt-\(key)","title":"t","created_at":"2026-12-31","modules":[
              {"type":"transactions","rows":[
                {"name":"a row","date":"\(key)-05","amount":1,"currency":"INR"},
                {"name":"a row","date":"\(key)-19","amount":2,"currency":"INR"}
              ]}
            ]}
            """
            try Data(body.utf8).write(to: folder.appendingPathComponent("\(key).json"))
        }

        let listed = ReportReader.list(in: vault)
        XCTAssertEqual(
            listed.reports.map(\.id),
            (1...12).reversed().map { String(format: "rpt-2026-%02d", $0) },
            "twelve months, newest first — the covered month orders them, not the timestamp"
        )
    }

    func testTheMonthComesFromPeriodThenTheTransactionsThenNothing() throws {
        func decode(_ json: String) throws -> Report {
            try JSONDecoder().decode(Report.self, from: Data(json.utf8))
        }
        let july = #"{"name":"a row","date":"2026-07-04","amount":1,"currency":"INR"}"#
        let august = #"{"name":"a row","date":"2026-08-04","amount":1,"currency":"INR"}"#
        let julyRows = #"{"type":"transactions","rows":[\#(july)]}"#

        let stated = try decode(
            #"{"version":1,"id":"r","title":"t","period":"2026-05","modules":[\#(julyRows)]}"#)
        XCTAssertEqual(stated.periodKey, "2026-05", "the file's own period is the first answer")

        let derived = try decode(
            #"{"version":1,"id":"r","title":"t","created_at":"2026-08-31","modules":[\#(julyRows)]}"#)
        XCTAssertEqual(derived.periodKey, "2026-07", "every dated row falls in one month")
        XCTAssertEqual(derived.periodName, LB.monthYear(LB.day(2026, 7, 1)))
        XCTAssertNotEqual(derived.periodName, LB.monthYear(LB.day(2026, 8, 1)), "written in August, about July")

        let spread = try decode(
            #"{"version":1,"id":"r","title":"t","created_at":"2026-08-31","modules":[{"type":"transactions","rows":[\#(july),\#(august)]}]}"#)
        XCTAssertNil(spread.periodKey, "two months settle nothing")
        XCTAssertNil(spread.periodName)
        XCTAssertEqual(
            spread.writtenNote, "Written " + LB.longDate(LB.day(2026, 8, 31)),
            "with no month, the authoring day is given as the authoring day"
        )

        for bad in ["2026-13", "2026-7", "26-07", "2026-07-01", "later"] {
            let report = try decode(#"{"version":1,"id":"r","title":"t","period":"\#(bad)","modules":[]}"#)
            XCTAssertNil(report.periodKey, "\(bad) is not a calendar month")
        }
    }
}
