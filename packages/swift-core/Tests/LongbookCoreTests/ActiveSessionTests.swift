import XCTest
@testable import LongbookCore

final class ActiveSessionTests: XCTestCase {
    private func body(_ rows: String) -> Data { Data(#"{"sessions": [\#(rows)]}"#.utf8) }

    func testARowReadsIntoItsWordsAndItsMicrosecondDates() throws {
        let data = body(#"""
        {"id": "s-1", "kind": "app", "label": "iPhone", "detail": "longbook 18 · iOS 27.0",
         "signed_in_at": "2026-09-20T08:00:00.123456+00:00", "last_active_at": "2026-09-29T10:00:00+00:00", "this_device": true}
        """#)
        let session = try XCTUnwrap(ActiveSession.decode(data)?.first)
        XCTAssertEqual(session.id, "s-1")
        XCTAssertEqual(session.kind, .app)
        XCTAssertEqual(session.label, "iPhone")
        XCTAssertEqual(session.detail, "longbook 18 · iOS 27.0")
        XCTAssertTrue(session.isThisDevice)
        XCTAssertNotNil(session.signedInAt, "a date with microseconds reads")
        XCTAssertNotNil(session.lastActiveAt, "a date with none reads too")
        XCTAssertLessThan(try XCTUnwrap(session.signedInAt), try XCTUnwrap(session.lastActiveAt))
    }

    func testAnUnknownKindIsOtherAndAMissingFlagIsNotThisDevice() throws {
        let data = body(#"{"id": "s-2", "kind": "toaster", "label": "Claude", "signed_in_at": "2026-09-20T08:00:00Z"}"#)
        let session = try XCTUnwrap(ActiveSession.decode(data)?.first)
        XCTAssertEqual(session.kind, .other)
        XCTAssertFalse(session.isThisDevice)
        XCTAssertEqual(session.detail, "")
        XCTAssertNil(session.lastActiveAt)
    }

    func testARowWithoutAnIdOrALabelIsDroppedNotShownBlank() throws {
        let data = body(#"{"kind": "app", "label": "Mac"}, {"id": "s-3", "kind": "app"}, {"id": "s-4", "kind": "app", "label": "Mac"}"#)
        XCTAssertEqual(try XCTUnwrap(ActiveSession.decode(data)).map(\.id), ["s-4"])
    }

    func testABodyThatIsNotTheListIsNil() {
        XCTAssertNil(ActiveSession.decode(Data(#"{"error": "That session is no longer valid."}"#.utf8)))
        XCTAssertNil(ActiveSession.decode(Data("not json".utf8)))
        XCTAssertEqual(ActiveSession.decode(Data(#"{"sessions": []}"#.utf8))?.count, 0)
    }

    func testTheListCarriesTheTotalAndNeverLessThanItShows() throws {
        let rows = #"{"id": "a", "kind": "app", "label": "Mac"}, {"id": "b", "kind": "app", "label": "iPhone"}"#
        let more = try XCTUnwrap(ActiveSessionList.decode(Data(#"{"sessions": [\#(rows)], "total": 73}"#.utf8)))
        XCTAssertEqual(more.sessions.count, 2)
        XCTAssertEqual(more.total, 73)
        let none = try XCTUnwrap(ActiveSessionList.decode(Data(#"{"sessions": [\#(rows)]}"#.utf8)))
        XCTAssertEqual(none.total, 2, "no total means what it carries")
        XCTAssertEqual(ActiveSessionList(sessions: more.sessions, total: 1).total, 2, "never fewer than shown")
        XCTAssertNil(ActiveSessionList.decode(Data("{}".utf8)))
    }

    /// The server reads the device out of this string with a fixed pattern; the two must agree.
    func testTheAppsUserAgentIsInTheShapeTheServerReads() {
        let pattern = #"^longbook/\d{1,6} \((iPhone|iPad|Mac); (iOS|iPadOS|macOS) [\d.]{1,12}\)$"#
        XCTAssertNotNil(appUserAgent.range(of: pattern, options: .regularExpression), appUserAgent)
    }

    func testLastUsedReadsInWordsAndJustNowUnderAMinute() {
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        func session(secondsAgo: TimeInterval) -> ActiveSession {
            ActiveSession(id: "x", kind: .app, label: "Mac", detail: "", signedInAt: nil,
                          lastActiveAt: now.addingTimeInterval(-secondsAgo), isThisDevice: false)
        }
        XCTAssertEqual(session(secondsAgo: 20).lastUsedWords(now: now), "just now")
        XCTAssertNotNil(session(secondsAgo: 3 * 3600).lastUsedWords(now: now))
        XCTAssertNil(ActiveSession(id: "x", kind: .app, label: "Mac", detail: "", signedInAt: nil, lastActiveAt: nil,
                                   isThisDevice: false).lastUsedWords(now: now))
    }
}
