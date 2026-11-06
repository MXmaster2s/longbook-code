// History is bytes remembered, never bytes altered: content-addressed snapshots, an
// append-only log, and a prune that must not delete what a kept line still references.
// Nothing here ever waits on iCloud: a file it still holds elsewhere is answered around.
import XCTest
@testable import LongbookCore

final class HistoryTests: XCTestCase {
    private var folder: URL!
    private var mirrorRoot: URL!

    private let a = Data(#"{"v":1}"#.utf8)
    private let b = Data(#"{"v":2}"#.utf8)
    private let c = Data(#"{"v":3}"#.utf8)

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("history-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        // The device mirror lives in Application Support; a test keeps it in its own folder.
        mirrorRoot = folder.appendingPathComponent("mirror")
        VaultHistory.mirrorRoot = mirrorRoot
    }

    override func tearDownWithError() throws {
        VaultHistory.awaitingDownload = VaultReader.awaitingDownload
        try? FileManager.default.removeItem(at: folder)
    }

    // MARK: helpers

    private func shared(_ name: String) -> URL {
        folder.appendingPathComponent(".longbook/history/\(name)")
    }

    /// Records as the other device would: the shared snapshot and log line land here
    /// through iCloud, and this device's mirror has never seen the bytes.
    private func otherDeviceRecorded(_ bytes: Data) throws {
        try VaultHistory.record(bytes, source: .ours, in: folder)
        try? FileManager.default.removeItem(at: VaultHistory.mirrorDirectory(for: folder))
    }

    /// The probe answers "iCloud holds it elsewhere" for the named shared files only.
    private func holdElsewhere(_ names: Set<String>) {
        VaultHistory.awaitingDownload = { names.contains($0.lastPathComponent) }
    }

    private func mirrorNames() -> Set<String> {
        Set((try? FileManager.default.contentsOfDirectory(atPath: VaultHistory.mirrorDirectory(for: folder).path)) ?? [])
    }

    // MARK: the log and its snapshots

    func testHashIsTheWellKnownSha256Hex() {
        XCTAssertEqual(
            VaultHistory.hash(Data("abc".utf8)),
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        )
    }

    func testRecordStoresTheBytesAndLogsOneEntry() throws {
        let entry = try XCTUnwrap(VaultHistory.record(a, source: .ours, in: folder))
        XCTAssertEqual(entry.hash, VaultHistory.hash(a))
        XCTAssertEqual(entry.byteCount, a.count)
        XCTAssertEqual(entry.source, .ours)
        XCTAssertEqual(VaultHistory.snapshot(hash: entry.hash, in: folder), a)
        XCTAssertEqual(VaultHistory.entries(in: folder).count, 1)
    }

    func testAConsecutiveDuplicateIsNoiseAndRecordsNothing() throws {
        XCTAssertNotNil(try VaultHistory.record(a, source: .ours, in: folder))
        XCTAssertNil(try VaultHistory.record(a, source: .outside, in: folder), "same bytes back to back")
        XCTAssertEqual(VaultHistory.entries(in: folder).count, 1)
    }

    func testTheSameBytesReturningLaterAreARealEventAndAreKept() throws {
        try VaultHistory.record(a, source: .ours, in: folder)
        try VaultHistory.record(b, source: .outside, in: folder)
        try VaultHistory.record(a, source: .ours, in: folder)
        XCTAssertEqual(VaultHistory.entries(in: folder).count, 3, "an edit undone by hand is history too")
    }

    func testEntriesComeBackNewestFirst() throws {
        try VaultHistory.record(a, source: .ours, in: folder)
        try VaultHistory.record(b, source: .outside, in: folder)
        try VaultHistory.record(c, source: .ours, in: folder)
        XCTAssertEqual(VaultHistory.entries(in: folder).map(\.hash), [c, b, a].map(VaultHistory.hash))
    }

    func testAnUnreadableLogLineIsSkippedNotFatal() throws {
        try VaultHistory.record(a, source: .ours, in: folder)
        let log = shared("log.jsonl")
        var raw = try Data(contentsOf: log)
        raw.append(Data("not json\n".utf8))
        try raw.write(to: log)
        try VaultHistory.record(b, source: .outside, in: folder)
        XCTAssertEqual(VaultHistory.entries(in: folder).map(\.hash), [b, a].map(VaultHistory.hash))
    }

    func testPruneDropsTheOldestAndDeletesOnlyUnreferencedSnapshots() throws {
        try VaultHistory.record(a, source: .ours, in: folder)
        try VaultHistory.record(b, source: .outside, in: folder)
        try VaultHistory.record(c, source: .ours, in: folder)
        VaultHistory.prune(in: folder, keep: 2)
        XCTAssertEqual(VaultHistory.entries(in: folder).map(\.hash), [c, b].map(VaultHistory.hash))
        XCTAssertNil(VaultHistory.snapshot(hash: VaultHistory.hash(a), in: folder),
                     "no remaining line references it")
        XCTAssertEqual(VaultHistory.snapshot(hash: VaultHistory.hash(b), in: folder), b)
        XCTAssertEqual(VaultHistory.snapshot(hash: VaultHistory.hash(c), in: folder), c)
    }

    func testPruneKeepsASnapshotAKeptLineStillReferences() throws {
        try VaultHistory.record(a, source: .ours, in: folder)
        try VaultHistory.record(b, source: .outside, in: folder)
        try VaultHistory.record(a, source: .ours, in: folder)
        VaultHistory.prune(in: folder, keep: 2)
        XCTAssertEqual(VaultHistory.entries(in: folder).map(\.hash), [a, b].map(VaultHistory.hash))
        XCTAssertEqual(VaultHistory.snapshot(hash: VaultHistory.hash(a), in: folder), a,
                       "the dropped oldest line shares its hash with the kept newest")
    }

    func testSnapshotRefusesAnythingThatIsNotAHexHash() throws {
        try VaultHistory.record(a, source: .ours, in: folder)
        XCTAssertNil(VaultHistory.snapshot(hash: "../log", in: folder))
        XCTAssertNil(VaultHistory.snapshot(hash: "", in: folder))
        XCTAssertNil(VaultHistory.snapshot(hash: "ABCDEF", in: folder), "uppercase is not ours")
        XCTAssertFalse(VaultHistory.awaiting(hash: "../log", in: folder))
    }

    func testAnEmptyFolderHasNoHistoryAndPruneIsANoOp() {
        XCTAssertTrue(VaultHistory.entries(in: folder).isEmpty)
        VaultHistory.prune(in: folder)
        XCTAssertTrue(VaultHistory.entries(in: folder).isEmpty)
    }

    // MARK: files iCloud still holds elsewhere

    func testASnapshotICloudStillHoldsElsewhereAnswersNilAtOnce() throws {
        try otherDeviceRecorded(a)
        let hash = VaultHistory.hash(a)
        XCTAssertTrue(FileManager.default.fileExists(atPath: shared("\(hash).json").path), "the bytes are on disk")
        holdElsewhere(["\(hash).json"])

        let started = Date()
        XCTAssertNil(VaultHistory.snapshot(hash: hash, in: folder))
        XCTAssertLessThan(Date().timeIntervalSince(started), 0.5, "never waits")
        XCTAssertTrue(VaultHistory.awaiting(hash: hash, in: folder))
    }

    func testAPrunedSnapshotIsNotMistakenForOneArriving() throws {
        try VaultHistory.record(a, source: .ours, in: folder)
        try VaultHistory.record(b, source: .outside, in: folder)
        try VaultHistory.record(c, source: .ours, in: folder)
        VaultHistory.prune(in: folder, keep: 2)
        XCTAssertNil(VaultHistory.snapshot(hash: VaultHistory.hash(a), in: folder))
        XCTAssertFalse(VaultHistory.awaiting(hash: VaultHistory.hash(a), in: folder), "gone, not on its way")
    }

    func testRecordRefusesToAppendToALogStillArriving() throws {
        try VaultHistory.record(a, source: .ours, in: folder)
        holdElsewhere([VaultHistory.logName])

        XCTAssertThrowsError(try VaultHistory.record(b, source: .outside, in: folder)) { error in
            guard case HistoryError.notDownloaded = error else { return XCTFail("\(error)") }
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: shared("\(VaultHistory.hash(b)).json").path),
                       "no shared snapshot either")
        VaultHistory.awaitingDownload = VaultReader.awaitingDownload
        XCTAssertEqual(VaultHistory.entries(in: folder).map(\.hash), [VaultHistory.hash(a)], "the log is as it was")
        // This device still keeps what it saw: the bytes are in its own mirror.
        XCTAssertEqual(VaultHistory.snapshot(hash: VaultHistory.hash(b), in: folder), b)
    }

    func testEntriesOfAnArrivingLogAreEmptyNotAnError() throws {
        try VaultHistory.record(a, source: .ours, in: folder)
        holdElsewhere([VaultHistory.logName])
        XCTAssertTrue(VaultHistory.entries(in: folder).isEmpty)
        XCTAssertTrue(VaultHistory.awaitingLog(in: folder))
        VaultHistory.awaitingDownload = VaultReader.awaitingDownload
        XCTAssertEqual(VaultHistory.entries(in: folder).count, 1)
        XCTAssertFalse(VaultHistory.awaitingLog(in: folder))
    }

    func testPruneLeavesAnArrivingLogAlone() throws {
        try VaultHistory.record(a, source: .ours, in: folder)
        try VaultHistory.record(b, source: .outside, in: folder)
        try VaultHistory.record(c, source: .ours, in: folder)
        holdElsewhere([VaultHistory.logName])
        VaultHistory.prune(in: folder, keep: 1)
        VaultHistory.awaitingDownload = VaultReader.awaitingDownload
        XCTAssertEqual(VaultHistory.entries(in: folder).count, 3)
        for bytes in [a, b, c] {
            XCTAssertEqual(VaultHistory.snapshot(hash: VaultHistory.hash(bytes), in: folder), bytes)
        }
    }

    func testMaterializeReturnsAtOnceForAnOrdinaryLocalSnapshot() async throws {
        try otherDeviceRecorded(a)
        let started = Date()
        try await VaultHistory.materialize(hash: VaultHistory.hash(a), in: folder)
        XCTAssertLessThan(Date().timeIntervalSince(started), 0.5)
    }

    // MARK: this device's mirror

    func testAVersionRecordedHereIsReadFromTheMirrorWhateverICloudIsDoing() throws {
        try VaultHistory.record(a, source: .ours, in: folder)
        let hash = VaultHistory.hash(a)
        holdElsewhere(["\(hash).json"])
        XCTAssertEqual(VaultHistory.snapshot(hash: hash, in: folder), a)
        XCTAssertFalse(VaultHistory.awaiting(hash: hash, in: folder), "nothing to wait for")
    }

    func testAdoptingTheOtherDevicesVersionKeepsALocalCopy() throws {
        // The owner's case: the phone wrote the version, the log's newest line already
        // carries its hash, and the Mac records it on adoption — nothing shared is written,
        // but the mirror must get the bytes or the next review's base is a placeholder.
        try otherDeviceRecorded(a)
        XCTAssertNil(try VaultHistory.record(a, source: .ours, in: folder), "the shared log is left alone")
        XCTAssertEqual(VaultHistory.entries(in: folder).count, 1)
        let hash = VaultHistory.hash(a)
        holdElsewhere(["\(hash).json"])
        XCTAssertEqual(VaultHistory.snapshot(hash: hash, in: folder), a)
        XCTAssertFalse(VaultHistory.awaiting(hash: hash, in: folder))
    }

    func testAHashRecordedOnlyInTheMirrorIsReadBack() throws {
        holdElsewhere([VaultHistory.logName])
        XCTAssertThrowsError(try VaultHistory.record(a, source: .ours, in: folder))
        VaultHistory.awaitingDownload = VaultReader.awaitingDownload
        XCTAssertTrue(VaultHistory.entries(in: folder).isEmpty, "the log never saw it")
        XCTAssertEqual(VaultHistory.snapshot(hash: VaultHistory.hash(a), in: folder), a)
    }

    func testAMirrorMissFallsThroughToTheSharedSnapshot() throws {
        try otherDeviceRecorded(a)
        XCTAssertTrue(mirrorNames().isEmpty)
        XCTAssertEqual(VaultHistory.snapshot(hash: VaultHistory.hash(a), in: folder), a)
    }

    func testPruneTrimsTheMirrorToWhatTheLogStillNames() throws {
        try VaultHistory.record(a, source: .ours, in: folder)
        try VaultHistory.record(b, source: .outside, in: folder)
        try VaultHistory.record(c, source: .ours, in: folder)
        XCTAssertEqual(mirrorNames(), Set([a, b, c].map { "\(VaultHistory.hash($0)).json" }))
        VaultHistory.prune(in: folder, keep: 2)
        XCTAssertEqual(mirrorNames(), Set([b, c].map { "\(VaultHistory.hash($0)).json" }))
    }

    func testTheMirrorIsKeptOutsideTheSharedFolder() {
        let dir = VaultHistory.mirrorDirectory(for: folder)
        XCTAssertTrue(dir.path.hasPrefix(mirrorRoot.path))
        XCTAssertFalse(dir.path.contains(".longbook"))
        XCTAssertNotEqual(VaultHistory.mirrorDirectory(for: folder.appendingPathComponent("other")), dir,
                          "one directory per vault")
    }
}
