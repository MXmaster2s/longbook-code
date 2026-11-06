// The vault step after purchase: when an early iCloud answer stands in for the full check,
// when a longbook is made without one, and how a second vault is recognised afterwards.
import XCTest
@testable import LongbookCore

final class VaultPrecheckTests: XCTestCase {
    private let dir = URL(fileURLWithPath: "/container/Documents", isDirectory: true)
    private let other = URL(fileURLWithPath: "/other/Documents", isDirectory: true)
    private let start = Date(timeIntervalSince1970: 1_000_000)

    private func held(_ availability: VaultContainer.Availability, account: AnyHashable? = "account-a") -> VaultPrecheck.Held {
        VaultPrecheck.Held(availability: availability, account: account, at: start)
    }

    private func reuse(
        _ held: VaultPrecheck.Held, after seconds: TimeInterval = 60, account: AnyHashable? = "account-a",
        current: VaultContainer.Availability
    ) -> VaultContainer.Availability? {
        VaultPrecheck.reusable(held, now: start.addingTimeInterval(seconds), account: account, current: current)
    }

    private func step(
        _ early: VaultPrecheck.Held?, after seconds: TimeInterval = 60, account: AnyHashable? = "account-a",
        current: VaultContainer.Availability
    ) -> VaultPrecheck.Step {
        VaultPrecheck.step(early: early, now: start.addingTimeInterval(seconds), account: account, current: current)
    }

    // MARK: reusing an early answer

    func testAVaultFoundEarlyStandsWhileItStillLists() {
        XCTAssertEqual(reuse(held(.hasVault(dir)), current: .hasVault(dir)), .hasVault(dir))
    }

    func testAVaultFoundEarlyThatNoLongerListsDoesNotStand() {
        XCTAssertNil(reuse(held(.hasVault(dir)), current: .empty(dir)))
        XCTAssertNil(reuse(held(.hasVault(dir)), current: .unavailable))
        XCTAssertNil(reuse(held(.hasVault(dir)), current: .hasVault(other)))
    }

    func testEmptyStandsWhileTheContainerStillListsEmpty() {
        XCTAssertEqual(reuse(held(.empty(dir)), current: .empty(dir)), .empty(dir))
        XCTAssertNil(reuse(held(.empty(dir)), current: .empty(other)))
    }

    func testAVaultThatArrivedSinceIsAdopted() {
        XCTAssertEqual(reuse(held(.empty(dir)), current: .hasVault(dir)), .hasVault(dir))
    }

    func testAnotherICloudAccountDoesNotStand() {
        XCTAssertNil(reuse(held(.hasVault(dir)), account: "account-b", current: .hasVault(dir)))
        XCTAssertNil(reuse(held(.empty(dir)), account: nil, current: .empty(dir)))
        XCTAssertNil(reuse(held(.empty(dir), account: nil), current: .empty(dir)))
    }

    func testAnEarlyAnswerExpires() {
        let limit = VaultPrecheck.maxAge
        XCTAssertEqual(reuse(held(.empty(dir)), after: limit, current: .empty(dir)), .empty(dir))
        XCTAssertNil(reuse(held(.empty(dir)), after: limit + 1, current: .empty(dir)))
        XCTAssertNil(reuse(held(.hasVault(dir)), after: limit + 1, current: .hasVault(dir)))
        // A clock that went backwards proves nothing about how old the answer is.
        XCTAssertNil(reuse(held(.hasVault(dir)), after: -1, current: .hasVault(dir)))
    }

    func testICloudOffEarlyIsNeverReused() {
        XCTAssertNil(reuse(held(.unavailable), current: .unavailable))
        XCTAssertNil(reuse(held(.unavailable), current: .empty(dir)))
    }

    // MARK: the step, never waiting

    func testAnEarlyFoundVaultIsAdopted() {
        XCTAssertEqual(step(held(.hasVault(dir)), current: .hasVault(dir)),
                       VaultPrecheck.Step(availability: .hasVault(dir), confirmed: true))
    }

    func testAConfirmedEmptyContainerIsMadeConfirmed() {
        XCTAssertEqual(step(held(.empty(dir)), current: .empty(dir)),
                       VaultPrecheck.Step(availability: .empty(dir), confirmed: true))
    }

    func testNoAnswerYetMakesTheVaultUnconfirmed() {
        XCTAssertEqual(step(nil, current: .empty(dir)), VaultPrecheck.Step(availability: .empty(dir), confirmed: false))
        // An answer that no longer stands counts as none.
        XCTAssertEqual(step(held(.empty(dir)), after: VaultPrecheck.maxAge + 1, current: .empty(dir)),
                       VaultPrecheck.Step(availability: .empty(dir), confirmed: false))
        XCTAssertEqual(step(held(.hasVault(dir)), current: .empty(dir)),
                       VaultPrecheck.Step(availability: .empty(dir), confirmed: false))
    }

    func testAVaultListedNowIsAdoptedWithoutAnAnswer() {
        XCTAssertEqual(step(nil, current: .hasVault(dir)), VaultPrecheck.Step(availability: .hasVault(dir), confirmed: true))
    }

    func testICloudOffNowIsSaidWhateverCameBefore() {
        XCTAssertEqual(step(nil, current: .unavailable), VaultPrecheck.Step(availability: .unavailable, confirmed: true))
        XCTAssertEqual(step(held(.empty(dir)), current: .unavailable), VaultPrecheck.Step(availability: .unavailable, confirmed: true))
    }

    // MARK: a second vault, afterwards

    func testIClouds_RenamedCopyIsFound() {
        XCTAssertEqual(VaultDuplicates.kind(listing: ["financial_memory.json", "financial_memory 2.json"], conflicts: 0), .renamedCopy)
        XCTAssertEqual(VaultDuplicates.kind(listing: ["financial_memory.json", ".financial_memory 3.json.icloud"], conflicts: 0), .renamedCopy)
    }

    func testAConflictVersionIsFound() {
        XCTAssertEqual(VaultDuplicates.kind(listing: ["financial_memory.json"], conflicts: 1), .conflict)
    }

    func testOneVaultAndItsOwnFilesAreNoDuplicate() {
        let one = ["financial_memory.json", "documents", "library.json", ".financial_memory.json.icloud", "financial_memory 2.json.bak", "notes 2.json"]
        XCTAssertNil(VaultDuplicates.kind(listing: one, conflicts: 0))
    }

    func testTheRenamedCopyOnDiskIsFoundInAFolder() throws {
        let folder = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("dupes-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try Data("{}".utf8).write(to: folder.appendingPathComponent("financial_memory.json"))
        XCTAssertNil(VaultDuplicates.find(in: folder))
        try Data("{}".utf8).write(to: folder.appendingPathComponent("financial_memory 2.json"))
        XCTAssertEqual(VaultDuplicates.find(in: folder), .renamedCopy)
    }
}
