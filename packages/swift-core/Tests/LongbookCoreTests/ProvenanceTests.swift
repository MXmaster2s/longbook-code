// A pill that says where a figure came from must never say more than the file does.
import XCTest
@testable import LongbookCore

final class ProvenanceTests: XCTestCase {
    private func vault(_ provenance: Any) -> [String: Any] {
        ["app": "longbook", "version": 1, "_provenance": provenance]
    }

    func testASignedRecordCarriesWhoAndWhatTheyRead() throws {
        let map = ProvenanceReader.map(in: vault([
            "s1": ["edited_by": "claude", "edited_at": "2026-07-20T10:00:00Z", "source": "bank statement"],
        ]))
        let entry = try XCTUnwrap(map["s1"])
        XCTAssertEqual(entry.editedBy, "claude")
        XCTAssertEqual(entry.source, "bank statement")
        XCTAssertNotNil(entry.editedAt)
        XCTAssertFalse(entry.isOurs)
        XCTAssertEqual(entry.word, "claude · bank statement")
    }

    func testOurOwnWritesAreNamedAsTheOwnersOwn() throws {
        let map = ProvenanceReader.map(in: vault(["s1": ["edited_by": "longbook-phone"]]))
        let entry = try XCTUnwrap(map["s1"])
        XCTAssertTrue(entry.isOurs)
        XCTAssertEqual(entry.word, "You")
    }

    func testAnUnsignedRecordIsAbsentRatherThanInvented() {
        let map = ProvenanceReader.map(in: vault([
            "s1": ["edited_at": "2026-07-20T10:00:00Z"],
            "s2": ["edited_by": "   "],
            "s3": "not an object",
        ]))
        XCTAssertTrue(map.isEmpty)
    }

    func testAVaultWithNoProvenanceReadsAsNoneSigned() {
        XCTAssertTrue(ProvenanceReader.map(in: ["app": "longbook"]).isEmpty)
    }

    func testAnUnparseableTimestampStillNamesTheEditor() throws {
        let map = ProvenanceReader.map(in: vault(["s1": ["edited_by": "chatgpt", "edited_at": "whenever"]]))
        let entry = try XCTUnwrap(map["s1"])
        XCTAssertNil(entry.editedAt)
        XCTAssertEqual(entry.editedBy, "chatgpt")
    }

    func testAReviewMarkIsReadBesideTheSignatureAndNeverChangesTheWord() throws {
        let map = ProvenanceReader.map(in: vault([
            "s1": ["edited_by": "claude", "edited_at": "2026-07-20T10:00:00Z",
                   "reviewed_by": "longbook-phone", "reviewed_at": "2026-07-21T09:00:00Z"],
        ]))
        let entry = try XCTUnwrap(map["s1"])
        XCTAssertEqual(entry.reviewedBy, "longbook-phone")
        XCTAssertEqual(entry.reviewedAt, "2026-07-21T09:00:00Z")
        XCTAssertEqual(entry.word, "claude", "kept is not written; the pill still names the writer")
        XCTAssertFalse(entry.isOurs)
    }

    func testAReviewMarkAloneKeepsTheEntryWithNobodyNamed() throws {
        let map = ProvenanceReader.map(in: vault(["s1": ["reviewed_by": "longbook-phone", "reviewed_at": "2026-07-21T09:00:00Z"]]))
        let entry = try XCTUnwrap(map["s1"])
        XCTAssertEqual(entry.editedBy, "")
        XCTAssertEqual(entry.reviewedBy, "longbook-phone")
        XCTAssertNil(ProvenanceReader.map(in: vault(["s2": ["reviewed_by": "  "]]))["s2"], "a blank mark names nobody")
    }
}
