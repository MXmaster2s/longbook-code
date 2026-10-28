// A signed-in reader must never land somewhere with nowhere to save. `decide` is the
// whole policy, kept separate from `ensureICloudVault` so it's testable without a real
// iCloud container: pass it an already-probed Availability and it never touches
// FileManager's ubiquity API itself.
import Foundation

public enum VaultProvisioner {
    public enum Result: Equatable {
        /// A vault exists at this folder now. `found` is true when it was already there:
        /// the reader asked for a new one and got the one they already had, and only this
        /// flag can tell them so — both arms land here.
        case ready(URL, found: Bool)
        /// iCloud can't be used on this device right now. The message is for the reader.
        case unavailable(String)
    }

    /// One wording for "iCloud can't be used here", wherever it is found — the chooser
    /// now probes for it before the reader taps anything, and both routes must agree.
    public static let iCloudOffMessage =
        "Keep your longbook on this device."

    /// Ask the real container, then act. Blocking — call it off the main actor, the same
    /// rule `VaultContainer.probeBeforeCreating()` documents for itself.
    public static func ensureICloudVault() -> Result {
        decide(VaultContainer.probeBeforeCreating())
    }

    static func decide(
        _ availability: VaultContainer.Availability,
        contractFiles: [String: Data] = VaultContract.bundledFiles()
    ) -> Result {
        switch availability {
        case .hasVault(let folder):
            // Someone else got here first — another device, or a re-run of this same
            // call. Adopt, never overwrite: the one rule every vault-placement path shares.
            return .ready(folder, found: true)
        case .empty(let folder):
            do {
                try VaultScaffold.create(at: folder, contractFiles: contractFiles)
                return .ready(folder, found: false)
            } catch {
                return .unavailable(error.friendlyDescription)
            }
        case .unavailable:
            return .unavailable(iCloudOffMessage)
        }
    }
}
