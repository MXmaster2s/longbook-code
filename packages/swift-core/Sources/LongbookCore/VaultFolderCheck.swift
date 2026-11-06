// Whether a folder someone picked holds a longbook this build opens, asked before the app
// switches to it. Reads only: the folder is never written, so a refused folder is left as found.
import Foundation

public enum VaultFolderCheck {
    public enum Verdict: Equatable {
        /// A financial_memory.json that longbook's own decoder reads.
        case opens
        /// No financial_memory.json in the folder itself.
        case noDataFile
        /// The file is there and readable, but it is not longbook's format.
        case notLongbookFormat
        /// The file is in iCloud and not on this device yet.
        case notDownloaded
        /// The file could not be read at all.
        case unreadable
    }

    /// One look at the folder, with the same reader the app opens a longbook with, so a
    /// folder that passes here is one `VaultReader.load` opens.
    public static func check(_ folder: URL, fileManager: FileManager = .default) -> Verdict {
        let scoped = folder.startAccessingSecurityScopedResource()
        defer { if scoped { folder.stopAccessingSecurityScopedResource() } }
        guard let names = try? fileManager.contentsOfDirectory(atPath: folder.path) else { return .unreadable }
        let placeholder = ".\(VaultReader.dataFile).icloud"
        guard names.contains(VaultReader.dataFile) || names.contains(placeholder) else { return .noDataFile }
        do {
            _ = try VaultReader.load(from: folder)
            return .opens
        } catch VaultReader.ReadError.notAVault {
            return .notLongbookFormat
        } catch VaultReader.ReadError.notDownloaded {
            return .notDownloaded
        } catch {
            return .unreadable
        }
    }

    /// The same look, after waiting for an iCloud file to come down to this device.
    public static func checkDownloading(_ folder: URL, timeout: TimeInterval = 30) async -> Verdict {
        let first = check(folder)
        guard first == .notDownloaded else { return first }
        let scoped = folder.startAccessingSecurityScopedResource()
        defer { if scoped { folder.stopAccessingSecurityScopedResource() } }
        do {
            try await VaultReader.materialize(folder.appendingPathComponent(VaultReader.dataFile), timeout: timeout)
        } catch {
            return .notDownloaded
        }
        return check(folder)
    }
}
