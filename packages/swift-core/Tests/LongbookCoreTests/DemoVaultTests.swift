import XCTest
@testable import LongbookCore

/// The demo household: readable by the app's own reader, dated around the day asked for,
/// and never written over a folder it did not make.
final class DemoVaultTests: XCTestCase {
    private func scratch() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("demo-\(UUID().uuidString)", isDirectory: true)
    }

    func testWritesAHouseholdTheReaderAccepts() throws {
        let folder = scratch()
        defer { try? FileManager.default.removeItem(at: folder) }
        let counts = try DemoVault.write(into: folder, today: LB.day(2026, 10, 3))
        let loaded = try VaultReader.load(from: folder)

        XCTAssertEqual(counts.commitments, 24)
        XCTAssertEqual(counts.members, 5)
        XCTAssertEqual(counts.accounts, 3)
        XCTAssertEqual(loaded.vault.subscriptions.count, counts.commitments)
        XCTAssertEqual(loaded.vault.familyMembers.count, counts.members)
        XCTAssertEqual(loaded.vault.paymentMethods.count, counts.accounts)
        XCTAssertEqual(loaded.vault.charges.count, counts.charges)
        XCTAssertGreaterThan(counts.charges, 300)

        // A year back, and ahead as far as each line plans (the yearly ones two years); every
        // past row confirmed but this month's electricity.
        XCTAssertTrue(loaded.vault.charges.allSatisfy { $0.date >= "2025-09-01" && $0.date <= "2028-12-31" })
        XCTAssertTrue(loaded.vault.charges.contains { $0.commitmentId == "c-rent" && $0.date == "2027-09-01" })
        let past = loaded.vault.charges.filter { $0.date <= "2026-10-03" }
        XCTAssertEqual(past.filter { !$0.paid }.map(\.commitmentId), ["c-power"])
        XCTAssertTrue(past.filter(\.paid).allSatisfy { $0.basis != "plan" && $0.paidOn == $0.date })
        XCTAssertTrue(loaded.vault.charges.filter { $0.date > "2026-10-03" }.allSatisfy { !$0.paid && $0.basis == "plan" })

        // The rows wear library tags the file explains, and the household's words sit beside them.
        let tags = loaded.vault.tags ?? []
        XCTAssertTrue(tags.contains { $0.kind == "commitment" && $0.name == "rent" })
        XCTAssertTrue(tags.contains { $0.kind == "account" && $0.name == "credit card" })
        XCTAssertEqual(WorkspaceStore.read(in: folder).homeCurrency, "INR")
        XCTAssertTrue(WorkspaceStore.read(in: folder).commitmentsAsked)
        XCTAssertEqual(InsightsReader.byModule(in: folder).count, 5)
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent(DemoVault.marker).path))
    }

    func testWritesAgainOverItsOwnFolderOnly() throws {
        let folder = scratch()
        defer { try? FileManager.default.removeItem(at: folder) }
        try DemoVault.write(into: folder, today: LB.day(2026, 10, 3))
        XCTAssertNoThrow(try DemoVault.write(into: folder, today: LB.day(2026, 11, 3)))

        let real = scratch()
        defer { try? FileManager.default.removeItem(at: real) }
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        try "{}".write(to: real.appendingPathComponent(VaultReader.dataFile), atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try DemoVault.write(into: real, today: LB.day(2026, 10, 3)))
    }

    func testFollowsTheDayItIsWrittenFor() throws {
        let folder = scratch()
        defer { try? FileManager.default.removeItem(at: folder) }
        try DemoVault.write(into: folder, today: LB.day(2027, 2, 14))
        let charges = try VaultReader.load(from: folder).vault.charges
        XCTAssertTrue(charges.contains { $0.date == "2027-02-01" && $0.commitmentId == "c-rent" && $0.paid })
        XCTAssertTrue(charges.contains { $0.date == "2027-03-01" && $0.commitmentId == "c-rent" && !$0.paid })
    }
}
