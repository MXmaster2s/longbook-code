// Reorganising in parts: every part asked in turn under one run, each retried once, what
// one part chose sent on to the next, and the parts' proposals combined into one answer.
import XCTest
@testable import LongbookCore

final class ReorganiseCloudTests: XCTestCase {
    /// What the fake server was asked, and what it answers, part by part.
    private final class Server: @unchecked Sendable {
        private let lock = NSLock()
        private(set) var asked: [[String: Any]] = []
        /// Failures still to give, by part.
        var failures: [Int: Int] = [:]
        var failStatus = 504
        var failBody: [String: Any] = ["error": "Your longbook could not be reorganised right now. Try again in a minute."]
        let parts: Int

        init(parts: Int) { self.parts = parts }

        func answer(_ data: Data) -> (status: Int, body: Data) {
            lock.lock(); defer { lock.unlock() }
            let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
            asked.append(body)
            let part = body["part"] as? Int ?? -1
            if let left = failures[part], left > 0 {
                failures[part] = left - 1
                return (failStatus, try! JSONSerialization.data(withJSONObject: failBody))
            }
            let id = String(format: "s-%03d", part * 40)
            var proposals: [[String: Any]] = [
                ["kind": "update_commitment", "payload": ["id": id, "set": ["name": "Netflix", "tag": "Streaming"]], "why": "plain name"],
                // Every part adds the same person; the pass keeps it once.
                ["kind": "add_person", "payload": ["name": "Sunita"], "why": "paid monthly"],
            ]
            if part == 0 { proposals.append(["kind": "rename_tag", "payload": ["kind": "commitment", "from": "OTT", "to": "Streaming"], "why": "one tag"]) }
            let reply: [String: Any] = [
                "proposals": proposals, "dropped": 1, "summary": "Part \(part + 1).",
                "part": part, "parts": parts, "carry": ["people": ["Sunita"], "names": ["Netflix \(part)"]],
            ]
            return (200, try! JSONSerialization.data(withJSONObject: reply))
        }
    }

    /// A book shaped like a long-kept one: 318 commitments.
    private func bookText(_ count: Int = 318) -> String {
        let rows: [[String: Any]] = (0..<count).map { i in
            ["id": String(format: "s-%03d", i), "name": "ACH DEBIT PAYEE \(i)", "amount": 100.0 + Double(i), "currency": "INR",
             "billing_cycle": "monthly", "status": "active"]
        }
        let data = try! JSONSerialization.data(withJSONObject: ["app": "longbook", "version": 3, "commitments": rows])
        return String(decoding: data, as: UTF8.self)
    }

    @MainActor
    private final class Progress {
        var lines: [String] = []
    }

    func testPartCountFollowsTheServersRule() {
        XCTAssertEqual(ReorganiseCloud.partCount(vaultText: bookText()), 8)
        XCTAssertEqual(ReorganiseCloud.partCount(vaultText: bookText(40)), 1)
        XCTAssertEqual(ReorganiseCloud.partCount(vaultText: bookText(0)), 1)
        XCTAssertEqual(ReorganiseCloud.partCount(vaultText: "not json"), 1)
    }

    @MainActor
    func testEveryPartInTurnUnderOneRunWithTheCarry() async throws {
        let server = Server(parts: 8)
        let progress = Progress()
        let answer = try await ReorganiseCloud.runParts(vaultText: bookText(), runId: "run-12345678",
                                                        send: { server.answer($0) },
                                                        progress: { part, of in progress.lines.append("\(part) of \(of)") })
        XCTAssertEqual(server.asked.map { $0["part"] as? Int }, Array(0..<8))
        XCTAssertEqual(Set(server.asked.compactMap { $0["run_id"] as? String }), ["run-12345678"])
        XCTAssertNil(server.asked[0]["carry"])
        XCTAssertEqual((server.asked[3]["carry"] as? [String: Any])?["names"] as? [String], ["Netflix 2"])
        XCTAssertEqual(progress.lines, (1...8).map { "\($0) of 8" })
        // Eight renames, one person, one tag merge: the same person added eight times is one change.
        XCTAssertEqual(answer.proposals.count, 10)
        XCTAssertEqual(answer.proposals.filter { $0.kind == "add_person" }.count, 1)
        XCTAssertEqual(answer.proposals.first?.kind, "update_commitment")
        XCTAssertEqual(answer.dropped, 8)
        XCTAssertEqual(answer.summary, "Read in 8 parts: 8 names made plain, 8 commitments categorised, 1 tag merged and 1 person added.")
    }

    @MainActor
    func testAFailingPartIsAskedAgainOnce() async throws {
        let server = Server(parts: 8)
        server.failures = [3: 1]
        let answer = try await ReorganiseCloud.runParts(vaultText: bookText(), runId: "run-12345678",
                                                        send: { server.answer($0) }, progress: { _, _ in })
        XCTAssertEqual(server.asked.map { $0["part"] as? Int }, [0, 1, 2, 3, 3, 4, 5, 6, 7])
        XCTAssertEqual(answer.proposals.filter { $0.kind == "update_commitment" }.count, 8)
    }

    @MainActor
    func testAPartThatFailsTwiceFailsThePassAndAsksNoFurther() async {
        let server = Server(parts: 8)
        server.failures = [5: 2]
        do {
            _ = try await ReorganiseCloud.runParts(vaultText: bookText(), runId: "run-12345678",
                                                   send: { server.answer($0) }, progress: { _, _ in })
            XCTFail("the pass should fail")
        } catch {
            XCTAssertEqual(error.localizedDescription, "Your longbook could not be reorganised right now. Try again in a minute.")
        }
        XCTAssertEqual(server.asked.map { $0["part"] as? Int }, [0, 1, 2, 3, 4, 5, 5])
    }

    @MainActor
    func testASpentShareIsNotAskedAgain() async {
        let server = Server(parts: 8)
        server.failures = [0: 2]
        server.failStatus = 429
        server.failBody = ["error": "spent", "code": "share_spent"]
        do {
            _ = try await ReorganiseCloud.runParts(vaultText: bookText(), runId: "run-12345678",
                                                   send: { server.answer($0) }, progress: { _, _ in })
            XCTFail("the pass should fail")
        } catch {
            guard case ReorganiseCloud.CloudError.shareSpent = error else { return XCTFail("\(error)") }
        }
        XCTAssertEqual(server.asked.count, 1)
    }

    @MainActor
    func testTheServersCountWinsOverTheEstimate() async throws {
        let server = Server(parts: 2)
        let progress = Progress()
        _ = try await ReorganiseCloud.runParts(vaultText: bookText(), runId: "run-12345678",
                                               send: { server.answer($0) },
                                               progress: { part, of in progress.lines.append("\(part) of \(of)") })
        XCTAssertEqual(server.asked.count, 2)
        XCTAssertEqual(progress.lines, ["1 of 8", "2 of 2"])
    }

    func testAOnePartPassKeepsTheModelsSummary() {
        let one = ReorganiseCloud.PartAnswer(proposals: [], dropped: 0, summary: "Renamed Netflix.", parts: 1, carry: nil)
        XCTAssertEqual(ReorganiseCloud.combine([one]).summary, "Renamed Netflix.")
        let empty = ReorganiseCloud.combine([one, one])
        XCTAssertEqual(empty.summary, "")
        XCTAssertTrue(empty.proposals.isEmpty)
    }
}
