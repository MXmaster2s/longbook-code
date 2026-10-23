// What a picked folder actually MEANS. iOS can't name the desktop's canonical
// `<iCloudDrive>/longbook` path, so it treats the picked folder as the vault's PARENT,
// creating `longbook/` inside it to converge with the Mac's path.
//
// THE ONE RULE: never end up with two vaults. When present, this ADOPTS it.
import Foundation

enum VaultPlacement {
    /// The folder name the desktop uses, and therefore the only name it will find unaided.
    static let folderName = "longbook"

    enum Outcome: Equatable {
        /// A vault is already here. Use it — do not write a new one anywhere.
        case adopt(URL)
        /// No vault anywhere in the picked folder. One may be created here, if the caller allows it.
        case create(URL)

        var url: URL {
            switch self {
            case .adopt(let u), .create(let u): return u
            }
        }
    }

    /// Decide what `picked` means, most specific reading first:
    ///
    ///   1. **The picked folder IS a vault** → adopt it directly.
    ///   2. **`picked/longbook` is a vault** → adopt that (the Mac already made one inside).
    ///   3. **Otherwise** → `picked/longbook` is where a new one goes.
    static func resolve(picked: URL, fileManager: FileManager = .default) -> Outcome {
        let hasVault = { (dir: URL) -> Bool in
            fileManager.fileExists(atPath: dir.appendingPathComponent(VaultReader.dataFile).path)
        }
        if hasVault(picked) { return .adopt(picked) }
        let nested = picked.appendingPathComponent(folderName, isDirectory: true)
        if hasVault(nested) { return .adopt(nested) }
        return .create(nested)
    }
}
