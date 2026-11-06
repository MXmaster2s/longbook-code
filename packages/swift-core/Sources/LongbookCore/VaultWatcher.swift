// Hearing a write made somewhere else — another device through iCloud, an agent — so the
// screen re-reads instead of waiting for a timer. Three ears, since none hears everything:
// a kqueue on the folder, a metadata query that knows a newer version is still upstream,
// and on iOS a file presenter.
import Foundation

@MainActor
public final class VaultWatcher {
    public let folder: URL
    private let file: URL
    private let onChange: @MainActor () -> Void
    private var source: DispatchSourceFileSystemObject?
    private let query: NSMetadataQuery
    private var queryObservers: [NSObjectProtocol] = []
    private var pending: Task<Void, Never>?
    private var suspended = true
    private var stopped = false
    #if os(iOS)
    private let presenter: FolderPresenter
    #endif

    /// Whether a folder sits inside the app's own iCloud container, which decides what the
    /// metadata query may search. Touches disk once; call it when a folder is opened.
    public static func insideContainer(_ folder: URL) -> Bool {
        guard let container = VaultContainer.vaultURL() else { return false }
        return folder.standardizedFileURL.path.hasPrefix(container.standardizedFileURL.path)
    }

    /// Made quiet: nothing is heard until `resume()`. The folder is watched, never the file —
    /// every writer here replaces the file atomically, and the old inode goes with it.
    public init(folder: URL, insideContainer: Bool, onChange: @escaping @MainActor () -> Void) {
        self.folder = folder
        self.file = folder.appendingPathComponent(VaultReader.dataFile)
        self.onChange = onChange

        // A picked folder is reachable only while its scope is held, so the kqueue holds it
        // for its own life and gives it back when it is cancelled.
        let scoped = folder.startAccessingSecurityScopedResource()
        let fd = open(folder.path, O_EVTONLY)
        if fd >= 0 {
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: fd, eventMask: [.write, .rename, .delete, .attrib, .extend], queue: .main
            )
            source.setCancelHandler {
                close(fd)
                if scoped { folder.stopAccessingSecurityScopedResource() }
            }
            source.activate()
            source.suspend()
            self.source = source
        } else if scoped {
            folder.stopAccessingSecurityScopedResource()
        }

        // The one signal that says a newer version exists and is not here yet. The container
        // is searchable as documents; a folder picked elsewhere only as an external document.
        let query = NSMetadataQuery()
        query.searchScopes = insideContainer
            ? [NSMetadataQueryUbiquitousDocumentsScope]
            : [NSMetadataQueryAccessibleUbiquitousExternalDocumentsScope]
        query.predicate = NSPredicate(format: "%K == %@", NSMetadataItemFSNameKey, VaultReader.dataFile)
        query.notificationBatchingInterval = 0.5
        self.query = query

        #if os(iOS)
        presenter = FolderPresenter(folder: folder)
        #endif

        source?.setEventHandler { [weak self] in
            guard let self else { return }
            MainActor.assumeIsolated { self.bump() }
        }
        for name in [Notification.Name.NSMetadataQueryDidFinishGathering, .NSMetadataQueryDidUpdate] {
            let observer = NotificationCenter.default.addObserver(forName: name, object: query, queue: .main) { [weak self] _ in
                guard let self else { return }
                MainActor.assumeIsolated { self.queryChanged() }
            }
            queryObservers.append(observer)
        }
        #if os(iOS)
        presenter.changed = { [weak self] in
            Task { @MainActor in self?.bump() }
        }
        #endif
    }

    deinit {
        MainActor.assumeIsolated { stop() }
    }

    /// Start listening, or listen again after `suspend()`.
    public func resume() {
        guard suspended, !stopped else { return }
        suspended = false
        source?.resume()
        query.start()
        #if os(iOS)
        NSFileCoordinator.addFilePresenter(presenter)
        #endif
    }

    /// Go quiet while nobody is looking. The kqueue and its scope stay open, so coming back
    /// costs nothing.
    public func suspend() {
        guard !suspended, !stopped else { return }
        suspended = true
        source?.suspend()
        query.stop()
        #if os(iOS)
        NSFileCoordinator.removeFilePresenter(presenter)
        #endif
        pending?.cancel()
    }

    /// Done for good: the descriptor and the scope are released. A suspended source cannot
    /// be released, so it is woken to be cancelled.
    public func stop() {
        guard !stopped else { return }
        if !suspended { suspend() }
        stopped = true
        source?.resume()
        source?.cancel()
        source = nil
        for observer in queryObservers { NotificationCenter.default.removeObserver(observer) }
        queryObservers = []
    }

    /// bird touches a folder several times for one download — a temp file, the swap into
    /// place, the attributes — and so does our own atomic write. One word after the last touch.
    private func bump() {
        guard !stopped else { return }
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled, let self, !self.stopped else { return }
            self.onChange()
        }
    }

    /// The query's word on the vault file alone. Not current means iCloud has a newer
    /// version than this device: ask for it, and the kqueue hears it land.
    private func queryChanged() {
        guard !stopped else { return }
        query.disableUpdates()
        defer { query.enableUpdates() }
        let wanted = file.standardizedFileURL.resolvingSymlinksInPath().path
        for case let item as NSMetadataItem in query.results {
            guard let url = item.value(forAttribute: NSMetadataItemURLKey) as? URL,
                  url.standardizedFileURL.resolvingSymlinksInPath().path == wanted else { continue }
            let status = item.value(forAttribute: NSMetadataUbiquitousItemDownloadingStatusKey) as? String
            if status == NSMetadataUbiquitousItemDownloadingStatusCurrent {
                bump()
            } else {
                VaultReader.requestDownload(file)
            }
            return
        }
    }
}

#if os(iOS)
/// On the phone a picked iCloud Drive folder may give the kqueue nothing until bird is
/// done, and bird writes under coordination — which a presenter on the folder hears.
private final class FolderPresenter: NSObject, NSFilePresenter {
    let presentedItemURL: URL?
    let presentedItemOperationQueue = OperationQueue()
    var changed: (@Sendable () -> Void)?

    init(folder: URL) {
        presentedItemURL = folder
        presentedItemOperationQueue.maxConcurrentOperationCount = 1
    }

    func presentedItemDidChange() { changed?() }
    func presentedSubitemDidChange(at url: URL) { changed?() }
}
#endif
