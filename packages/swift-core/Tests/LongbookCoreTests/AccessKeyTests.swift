import XCTest
@testable import LongbookCore

/// The key's shape is a contract with the server: lbk_ prefix, base64url body, and a
/// 64-hex SHA-256 the redemption function matches byte for byte.
final class AccessKeyTests: XCTestCase {
    func testMintedKeysWearTheContractShape() {
        let a = HostedMemory.mintKeyMaterial()
        let b = HostedMemory.mintKeyMaterial()
        XCTAssertTrue(a.key.hasPrefix("lbk_"))
        XCTAssertEqual(a.key.count, 4 + 43)
        XCTAssertNil(a.key.dropFirst(4).rangeOfCharacter(from: CharacterSet(charactersIn: "+/=")))
        XCTAssertTrue(a.hash.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil)
        XCTAssertNotEqual(a.key, b.key, "two mints must never collide")
        XCTAssertNotEqual(a.hash, b.hash)
    }
}
