// Shared conformance vectors — the SAME JSON fixtures drive this suite and
// packages/core's conformance.test.ts. See RenewalConformanceTests.swift for the shared
// fixtures-directory resolution, and packages/core/tests/fixtures/data-policy-vectors.json.
import XCTest
@testable import LongbookCore

struct DataPolicyVector: Decodable {
    let name: String
    let text: String
    let expectKind: String?

    enum CodingKeys: String, CodingKey {
        case name, text
        case expectKind = "expect_kind"
    }
}

final class DataPolicyConformanceTests: XCTestCase {
    private func loadVectors() throws -> [DataPolicyVector] {
        let url = sharedFixturesDirectory(from: #filePath).appendingPathComponent("data-policy-vectors.json")
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode([DataPolicyVector].self, from: data)
    }

    func testDataPolicyConformanceVectorsMatchScanText() throws {
        let vectors = try loadVectors()
        XCTAssertGreaterThan(vectors.count, 0, "fixture file must not be empty")
        for v in vectors {
            let hit = scanText(v.text)
            XCTAssertEqual(hit?.kind.rawValue, v.expectKind, v.name)
        }
    }
}
