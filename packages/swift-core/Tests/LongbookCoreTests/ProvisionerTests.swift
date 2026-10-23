// The provisioning DECISION, exercised without a real iCloud container: `decide` takes
// an already-probed Availability, so every branch is synthetic-testable against a temp
// directory the same way ScaffoldTests drives VaultScaffold directly.
import XCTest
@testable import LongbookCore

final class ProvisionerTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("provisioner-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private let contract = [
        VaultReader.schemaFile: Data(#"{"$schema":"synthetic"}"#.utf8),
        VaultReader.llmsFile: Data("synthetic etiquette\n".utf8),
    ]

    /// A vault already in the container is adopted, never touched — the one rule every
    /// placement path shares. Pre-seed a marker so a wrongful re-create would be caught.
    func testHasVaultIsAdoptedUntouched() throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let marker = Data("pre-existing".utf8)
        try marker.write(to: root.appendingPathComponent(VaultReader.dataFile))

        let result = VaultProvisioner.decide(.hasVault(root), contractFiles: contract)

        XCTAssertEqual(result, .ready(root, found: true))
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent(VaultReader.dataFile)), marker)
    }

    /// An empty container gets a real vault: memory plus both contract files, exactly what
    /// a manually-picked folder would produce.
    func testEmptyContainerIsProvisioned() throws {
        let result = VaultProvisioner.decide(.empty(root), contractFiles: contract)

        guard case .ready(let folder, let found) = result else {
            return XCTFail("expected .ready, got \(result)")
        }
        XCTAssertEqual(folder, root)
        // Provisioned here and now, so the reader is not to be told we found it.
        XCTAssertFalse(found)
        XCTAssertNoThrow(try VaultReader.load(from: root))
        for name in [VaultReader.dataFile, VaultReader.schemaFile, VaultReader.llmsFile] {
            XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent(name).path), name)
        }
    }

    /// iCloud reporting unavailable never crashes or throws — it is a Result the caller
    /// can show plainly, same voice as VaultContainer.createInICloud's own copy.
    func testUnavailableReportsPlainly() {
        let result = VaultProvisioner.decide(.unavailable, contractFiles: contract)

        guard case .unavailable(let message) = result else {
            return XCTFail("expected .unavailable, got \(result)")
        }
        XCTAssertTrue(message.contains("this device"), message)
    }

    /// A folder that genuinely can't be written to — a file sitting where the vault's
    /// directory needs to be created — degrades to .unavailable rather than throwing out
    /// of `decide`. The caller never has to catch anything.
    func testCreateFailureDegradesToUnavailable() throws {
        let blocked = root.appendingPathComponent("blocked")
        try Data().write(to: blocked) // a FILE, so creating a directory of the same name fails
        let target = blocked.appendingPathComponent("longbook", isDirectory: true)

        let result = VaultProvisioner.decide(.empty(target), contractFiles: contract)

        guard case .unavailable = result else {
            return XCTFail("expected .unavailable, got \(result)")
        }
    }

    /// The reader taps one button for both outcomes, so the result is the only place the
    /// difference survives. Without this the app cannot say "we found the one you had".
    func testAdoptedAndCreatedAreToldApart() throws {
        let existing = root.appendingPathComponent("had-one")
        try FileManager.default.createDirectory(at: existing, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: existing.appendingPathComponent(VaultReader.dataFile))

        let adopted = VaultProvisioner.decide(.hasVault(existing), contractFiles: contract)
        let created = VaultProvisioner.decide(.empty(root), contractFiles: contract)

        guard case .ready(_, let wasFound) = adopted, case .ready(_, let wasMade) = created else {
            return XCTFail("expected both to be ready, got \(adopted) and \(created)")
        }
        XCTAssertTrue(wasFound)
        XCTAssertFalse(wasMade)
    }

    /// End to end through the real entry point's signature — contractFiles defaults to the
    /// app's bundled resources, so a caller passing none still gets a usable vault.
    func testDecideUsesBundledContractFilesByDefault() throws {
        let result = VaultProvisioner.decide(.empty(root))

        guard case .ready = result else {
            return XCTFail("expected .ready, got \(result)")
        }
        XCTAssertNoThrow(try VaultReader.load(from: root))
    }
}
