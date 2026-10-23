// Writing a NEW vault: the folder, the memory, the contract files beside it. Split
// out of VaultStore so it's testable — the picker can't be driven in the Simulator.
// Contract files arrive as BYTES from the caller, not read here — synthetic-testable.
import Foundation

public enum VaultScaffold {
    /// A contract-valid empty vault: the three fields the v2 schema requires, nothing invented.
    public static func freshMemory() -> [String: Any] {
        [
            "app": "longbook",
            "version": VAULT_FORMAT_VERSION,
            "commitments": [],
        ]
    }

    /// Create the folder, write the memory plus every contract file given.
    ///
    /// Memory FIRST, failure fatal; library.json, the revision stamp, LAST. A contract file
    /// failing is not fatal: `VaultContract.heal(in:)` writes it on a later open.
    ///
    /// Returns names actually written, so a caller can tell complete from memory-only.
    @discardableResult
    public static func create(
        at folder: URL,
        contractFiles: [String: Data],
        fileManager: FileManager = .default
    ) throws -> [String] {
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)

        let memory = try JSONSerialization.data(
            withJSONObject: freshMemory(),
            options: [.prettyPrinted, .sortedKeys]
        )
        try coordinatedWrite(memory, to: folder.appendingPathComponent(VaultReader.dataFile))

        // The drop zone for statements and source files — named so the folder invites them.
        try? fileManager.createDirectory(
            at: folder.appendingPathComponent("documents"), withIntermediateDirectories: true
        )

        var written = [VaultReader.dataFile]
        for name in VaultContract.writeOrder(contractFiles.keys) {
            guard let body = contractFiles[name] else { continue }
            do {
                try coordinatedWrite(body, to: folder.appendingPathComponent(name))
                written.append(name)
            } catch {
                continue
            }
        }
        return written
    }

    /// One coordinated, atomic write. Coordinated because the Mac writes this same folder and iCloud
    /// syncs it; atomic so a half-written contract file can never be read as a whole one.
    public static func coordinatedWrite(_ data: Data, to file: URL) throws {
        var coordError: NSError?
        var writeError: Error?
        NSFileCoordinator().coordinate(writingItemAt: file, options: .forReplacing, error: &coordError) { url in
            do { try data.write(to: url, options: .atomic) } catch { writeError = error }
        }
        if let coordError { throw coordError }
        if let writeError { throw writeError }
    }
}
