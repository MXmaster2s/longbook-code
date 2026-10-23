// Moving a vault from this device into iCloud. It's a MOVE: leaving the original
// behind produces two vaults, the one outcome this product must never produce.
// Needs no picker — the destination is the app's own published iCloud container.
// THE ORDER IS THE SAFETY: copy, VERIFY, only then remove the original.
import Foundation

public enum VaultMigration {
    public enum Failure: LocalizedError {
        case iCloudUnavailable
        case destinationOccupied
        case copyFailed(String)
        case verifyFailed
        case sourceNotDownloaded

        public var errorDescription: String? {
            switch self {
            case .iCloudUnavailable:
                return "iCloud isn’t available on this device. Check that you’re signed in to iCloud and that iCloud Drive is on."
            case .destinationOccupied:
                // Refusing rather than merging or overwriting. Two vaults exist and only their owner
                // can say which is the real one; guessing here would destroy the wrong one silently.
                return "There’s already a longbook in your iCloud. Open that one instead, or move it aside first. This device’s copy has been left exactly as it was."
            case .copyFailed(let why):
                return "Couldn’t copy your longbook to iCloud: \(why). Nothing was changed on this device."
            case .verifyFailed:
                return "The copy in iCloud didn’t read back correctly, so nothing was moved. Your longbook is still on this device."
            case .sourceNotDownloaded:
                return "Some of your longbook is still stored online and hasn’t come down to this device yet. Open it once on Wi-Fi so everything is here, then move it. Nothing has been changed."
            }
        }
    }

    /// Every file that makes up a vault, as it sits on disk right now.
    ///
    /// Read from the folder rather than assumed, so anything an outside tool added travels with the
    /// move instead of being left behind by a hardcoded list.
    public static func files(in folder: URL, fileManager: FileManager = .default) -> [URL] {
        let names = (try? fileManager.contentsOfDirectory(atPath: folder.path)) ?? []
        return names
            .filter { !$0.hasPrefix(".") }   // .DS_Store and friends are not the owner's memory
            .sorted()
            .map { folder.appendingPathComponent($0) }
    }

    /// Anything in the vault that this device holds by name only. A move copies bytes and then
    /// deletes the original, so a file still living online would be deleted rather than moved.
    /// The whole tree, not the top level: documents/ is where an evicted statement hides.
    public static func awaitingDownload(in folder: URL, fileManager: FileManager = .default) -> [String] {
        var pending: [String] = []
        // The placeholder is a sibling dot-file, so the listing must include what files(in:)
        // deliberately drops — that filter is about .DS_Store, not about evicted content.
        let all = fileManager.enumerator(at: folder, includingPropertiesForKeys: nil)
        while let url = all?.nextObject() as? URL {
            let name = url.lastPathComponent
            if name.hasPrefix(".") && name.hasSuffix(".icloud") {
                pending.append(String(name.dropFirst().dropLast(".icloud".count)))
            } else if VaultReader.awaitingDownload(url) {
                pending.append(name)
            }
        }
        return pending.sorted()
    }

    /// Total size on disk, for telling someone how small this actually is before they commit to it.
    public static func totalBytes(in folder: URL, fileManager: FileManager = .default) -> Int {
        files(in: folder, fileManager: fileManager).reduce(0) { sum, url in
            sum + ((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
    }

    /// Move the vault at `source` into the app's iCloud container. Returns the new folder.
    public static func moveToICloud(from source: URL, fileManager: FileManager = .default) throws -> URL {
        let destination: URL
        switch VaultContainer.probe() {
        case .unavailable:
            throw Failure.iCloudUnavailable
        case .hasVault:
            throw Failure.destinationOccupied
        case .empty(let dir):
            destination = dir
        }

        // 0. Everything must be here first. files(in:) skips dot-names, so an evicted file
        // would never be copied — and step 3 deletes the original either way.
        guard awaitingDownload(in: source, fileManager: fileManager).isEmpty else {
            throw Failure.sourceNotDownloaded
        }

        // 1. COPY. Nothing on the phone is touched yet, so any failure here is harmless.
        var copied: [URL] = []
        do {
            for src in files(in: source, fileManager: fileManager) {
                let dst = destination.appendingPathComponent(src.lastPathComponent)
                if fileManager.fileExists(atPath: dst.path) { try fileManager.removeItem(at: dst) }
                try fileManager.copyItem(at: src, to: dst)
                copied.append(dst)
            }
        } catch {
            // Roll the partial copy back so a retry doesn't meet its own leftovers.
            for url in copied { try? fileManager.removeItem(at: url) }
            throw Failure.copyFailed(error.localizedDescription)
        }

        // 2. VERIFY, before anything is deleted. A copy that cannot be read back is not a vault, and
        // trusting the filesystem to have said so is how people lose things.
        guard (try? VaultReader.load(from: destination)) != nil else {
            for url in copied { try? fileManager.removeItem(at: url) }
            throw Failure.verifyFailed
        }

        // 3. REMOVE the original. Best-effort: the iCloud copy is already verified, so a
        // file refusing to delete leaves inert leftovers, not a second live vault.
        for src in files(in: source, fileManager: fileManager) {
            try? fileManager.removeItem(at: src)
        }

        return destination
    }
}
