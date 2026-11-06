// A vault written by the MCP server's write tools, and a report the MCP server's reports
// tool reads, decoded by THIS implementation — shared fixtures, so the two readers of one
// file cannot silently drift apart.
import XCTest
@testable import LongbookCore

final class McpWriteConformanceTests: XCTestCase {
    private func fixtureData(_ name: String) throws -> Data {
        let url = sharedFixturesDirectory(from: #filePath).appendingPathComponent(name)
        return try Data(contentsOf: url)
    }

    func testMcpWrittenVaultDecodesWhole() throws {
        let vault = try JSONDecoder().decode(Vault.self, from: fixtureData("mcp-written-vault.json"))

        XCTAssertEqual(vault.subscriptions.count, 3)
        let insurance = try XCTUnwrap(vault.subscriptions.first { $0.name == "Car insurance" })
        XCTAssertEqual(insurance.tag, "insurance")
        XCTAssertNotNil(insurance.details?["insurer"])
        XCTAssertEqual(charges(of: insurance, in: vault).first?.row.date, "2024-03-12", "history is the rows the writer wrote")
        XCTAssertEqual(vault.subscriptions.first { $0.name == "Airport taxi" }?.status, .cancelled)

        // The registry the writer built: seeded tags with their icons, the invented one bare.
        // This file's tags still hold templates, as an older writer left them; they read as
        // none, and the TypeScript reader says the same of this file.
        let tags = try XCTUnwrap(vault.tags)
        let seeded = try XCTUnwrap(tags.first { $0.nameKey == "insurance" })
        XCTAssertEqual(seeded.icon, "shield.checkered")
        XCTAssertEqual(seeded.isDefault, true)
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(tags), as: UTF8.self).contains("template"))
        let invented = try XCTUnwrap(tags.first { $0.nameKey == "colony kitty" })
        XCTAssertNil(invented.icon)
        XCTAssertEqual(invented.isDefault, false)

        let paid = try XCTUnwrap(vault.charges.first { $0.paid })
        XCTAssertEqual(paid.date, "2026-08-30")
        XCTAssertFalse(paid.writtenAt?.isEmpty ?? true)

        // Entities the writer ensured are the app's own placeholder shape.
        XCTAssertEqual(vault.familyMembers.first?.name, "Rohit")
        XCTAssertEqual(vault.paymentMethods.first?.isIncomplete, true)
    }

    /// The vault a whole year of statements produces, decoded by the app that must draw
    /// it: every line a row, the repeats promoted with their facts intact, the tags
    /// carrying their icons.
    func testImportedYearDecodesAndCarriesEveryKind() throws {
        let vault = try JSONDecoder().decode(Vault.self, from: fixtureData("import-golden-vault.json"))

        XCTAssertFalse(vault.subscriptions.isEmpty)
        XCTAssertFalse(vault.charges.isEmpty)
        for sub in vault.subscriptions where sub.billingCycle == .once {
            XCTAssertEqual(charges(of: sub, in: vault).count, 1, "\(sub.name): a one-time commitment is one charge")
        }
        let netflix = try XCTUnwrap(vault.subscriptions.first { $0.name == "Netflix" })
        let rows = charges(of: netflix, in: vault)
        XCTAssertEqual(rows.first?.row.date, "2025-09-05", "history is the first charge the statement showed")
        XCTAssertTrue(rows.contains { $0.paid && $0.row.basis == "statement" }, "what the statement proved is proved")
        XCTAssertTrue(rows.contains { !$0.paid && $0.row.basis == "plan" }, "and the plan continues from it")

        // Members were never invented: the statement named no one the owner named.
        XCTAssertTrue(vault.familyMembers.isEmpty)
        XCTAssertEqual(vault.paymentMethods.count, 2)

        let tags = try XCTUnwrap(vault.tags)
        let insurance = try XCTUnwrap(tags.first { $0.nameKey == "insurance" })
        XCTAssertEqual(insurance.icon, "shield.checkered")
        XCTAssertTrue(tags.allSatisfy { $0.isDefault == true }, "every tag came from the library")
    }

    /// The four modules a drawn report holds, in their drawn order, then the kinds an older
    /// file may still carry — one fixture, read by both decoders.
    func testGoldenReportDecodesModuleForModule() throws {
        let report = try JSONDecoder().decode(Report.self, from: fixtureData("report-golden.json"))

        XCTAssertEqual(report.version, 1)
        XCTAssertEqual(report.id, "august-2026")
        XCTAssertEqual(report.createdAt, "2026-08-20")
        XCTAssertEqual(report.periodKey, "2026-08")
        XCTAssertEqual(report.modules.count, 7)

        guard case .stats(let stats) = report.modules[0] else { return XCTFail("stats first") }
        XCTAssertEqual(stats.title, MonthlyReport.Titles.total)
        XCTAssertEqual(stats.stats.first?.deltaPct, 8.4)
        XCTAssertEqual(stats.stats.last?.label, "Money in")

        guard case .donut(let accounts) = report.modules[1] else { return XCTFail("accounts second") }
        XCTAssertEqual(accounts.title, MonthlyReport.Titles.accounts)
        XCTAssertEqual(accounts.slices.count, 3)
        XCTAssertEqual(accounts.slices.last?.label, "Amex 1007", "slices are biggest first")

        guard case .donut(let categories) = report.modules[2] else { return XCTFail("categories third") }
        XCTAssertEqual(categories.title, MonthlyReport.Titles.categories)
        XCTAssertEqual(categories.comment, "The rent is the whole of it.")
        XCTAssertEqual(categories.slices.first?.label, "rent", "a tag is stored as the owner typed it")
        // A draw derives both rings from one currency, so a drawn donut carries only that one.
        XCTAssertTrue(categories.slices.allSatisfy { $0.currency == "INR" })

        guard case .transactions(let charges) = report.modules[3] else { return XCTFail("charges fourth") }
        XCTAssertEqual(charges.title, MonthlyReport.Titles.charges)
        XCTAssertEqual(charges.rows.count, 4)
        XCTAssertEqual(charges.rows.first?.name, "House rent")
        XCTAssertNil(charges.rows[1].category, "a commitment with no tag writes no category")
        XCTAssertEqual(charges.rows.last?.currency, "USD", "the charge list is every currency")

        // Past the four: kinds no draw produces, which a file may still hold. The donut here
        // is not a drawn one — it is titled otherwise and mixes currencies, which is what
        // holds the "listed beside the ring, never in it" rule under test.
        guard case .donut(let written) = report.modules[4] else { return XCTFail("a written donut fifth") }
        XCTAssertNotEqual(written.title, MonthlyReport.Titles.categories)
        XCTAssertEqual(written.slices.last?.currency, "USD")
        guard case .prose = report.modules[5] else { return XCTFail("prose sixth") }
        guard case .bars(let bars) = report.modules[6] else { return XCTFail("bars seventh") }
        XCTAssertEqual(bars.bars.last?.amount, 46528)
    }
}
