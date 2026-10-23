// The bundled prompt catalogue decodes whole and agrees with the contract set it ships in.
// prompts.json is generated from packages/core/src/prompts.ts by scripts/gen-vault-contract.mts.
import XCTest
@testable import LongbookCore

final class PromptCatalogTests: XCTestCase {
    func testTheCatalogueDecodesEveryPromptAndGroup() throws {
        XCTAssertNotNil(PromptCatalog.file, "prompts.json is missing or no longer decodes")
        XCTAssertEqual(PromptCatalog.all.count, 27)
        XCTAssertEqual(PromptCatalog.groups.count, 6)
    }

    func testIdsAreUnique() {
        let ids = PromptCatalog.all.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
        let groupIds = PromptCatalog.groups.map(\.id)
        XCTAssertEqual(Set(groupIds).count, groupIds.count)
    }

    func testEveryPromptHasAPhraseAResultAndAProcedure() {
        for prompt in PromptCatalog.all {
            XCTAssertFalse(prompt.phrases.isEmpty, "\(prompt.id) has no phrase")
            XCTAssertFalse(prompt.phrases.contains { $0.trimmingCharacters(in: .whitespaces).isEmpty }, "\(prompt.id) has a blank phrase")
            XCTAssertFalse(prompt.result.isEmpty, "\(prompt.id) has no result")
            XCTAssertFalse(prompt.procedure.isEmpty, "\(prompt.id) has no procedure")
        }
    }

    /// A list grouped by group title would drop a prompt whose group is not listed.
    func testEveryPromptBelongsToAListedGroup() {
        let listed = Set(PromptCatalog.groups.map(\.id))
        for prompt in PromptCatalog.all {
            XCTAssertTrue(listed.contains(prompt.group), "\(prompt.id) is in an unlisted group \(prompt.group)")
        }
        XCTAssertEqual(PromptCatalog.groups.reduce(0) { $0 + PromptCatalog.prompts(in: $1).count }, PromptCatalog.all.count)
    }

    func testTheRevisionMatchesTheBundledGuide() throws {
        let revision = try XCTUnwrap(PromptCatalog.revision)
        let llms = String(decoding: try XCTUnwrap(VaultContract.bundledFiles()[VaultReader.llmsFile]), as: UTF8.self)
        XCTAssertTrue(llms.contains("contract revision \(revision)."), "llms.txt names another revision than prompts.json")
    }

    func testTheMonthReportPhraseNamesTheMonth() throws {
        let prompt = try XCTUnwrap(PromptCatalog.prompt(id: "add-a-month-report-in-my-longbook"))
        XCTAssertNotNil(prompt.template)
        XCTAssertEqual(PromptCatalog.phrase(for: prompt, month: "October"), "Add October month report in my longbook")
        XCTAssertEqual(PromptCatalog.phrase(for: prompt), prompt.phrases.first)
        XCTAssertFalse(PromptCatalog.phrase(for: prompt, month: "October").contains("{month}"))
    }

    /// Without a template the month is ignored: the first phrase is what gets copied.
    func testAPromptWithoutATemplateKeepsItsFirstPhrase() throws {
        let prompt = try XCTUnwrap(PromptCatalog.prompt(id: "create-a-report-in-my-longbook"))
        XCTAssertNil(prompt.template)
        XCTAssertEqual(PromptCatalog.phrase(for: prompt, month: "October"), "Create a report in my longbook")
    }

    /// The ids the app copies from: Step 3, the own-AI help, Reports and the morning card.
    func testThePromptsTheAppNamesExist() throws {
        let setup = try XCTUnwrap(PromptCatalog.prompt(id: "set-up-my-longbook"))
        XCTAssertEqual(setup.group, "setup")
        for id in ["add-my-statement", "create-a-report-in-my-longbook", "set-up-a-daily-longbook-email-round"] {
            XCTAssertNotNil(PromptCatalog.prompt(id: id), "\(id) is missing from the catalogue")
        }
        XCTAssertEqual(PromptCatalog.phrase(id: "no-such-prompt"), "no-such-prompt")
    }

    /// One malformed prompt or group costs that entry, never the catalogue.
    func testABadEntryIsSkippedAndTheRestDecode() throws {
        let json = #"""
        {"contract_revision":35,
         "groups":[{"id":"setup","title":"Set up"},{"id":7}],
         "prompts":[
          {"id":"a","title":"A","group":"setup","phrases":["Do a"],"attachments":"none.","result":"A done.","writes":true,"procedure":["1. a"]},
          {"id":"b","title":"B","group":"setup","phrases":"not a list","attachments":"none.","result":"B done.","writes":false,"procedure":["1. b"]},
          {"id":"c","title":"C","group":"setup","phrases":["Do c"],"attachments":"none.","result":"C done.","writes":"yes","procedure":["1. c"]},
          {"id":"d","title":"D","group":"setup","phrases":["Do d"],"attachments":"none.","result":"D done.","writes":false,"procedure":["1. d"],"needs":["mail"]}
         ]}
        """#
        let file = try XCTUnwrap(PromptCatalog.decode(Data(json.utf8)))
        XCTAssertEqual(file.contractRevision, 35)
        XCTAssertEqual(file.groups.map(\.id), ["setup"])
        XCTAssertEqual(file.prompts.map(\.id), ["a", "d"])
        XCTAssertEqual(file.prompts.last?.needs, ["mail"])
    }

    func testBytesThatAreNotACatalogueDecodeToNothing() {
        XCTAssertNil(PromptCatalog.decode(Data("not json".utf8)))
        XCTAssertEqual(PromptCatalog.decode(Data("{}".utf8))?.prompts.count, 0)
        XCTAssertEqual(PromptCatalog.decode(Data(#"{"prompts":"none"}"#.utf8))?.prompts.count, 0)
    }

    /// The ids the app copies never come out as a slug, even with no catalogue at all.
    func testWithoutACatalogueTheAppStillCopiesWords() {
        XCTAssertEqual(Set(PromptCatalog.fallbacks.keys), [
            "set-up-my-longbook", "add-my-statement", "add-a-month-report-in-my-longbook",
            "create-a-report-in-my-longbook", "set-up-a-daily-longbook-email-round",
        ])
        for id in PromptCatalog.fallbacks.keys {
            let phrase = PromptCatalog.phrase(id: id, month: nil, in: [])
            XCTAssertNotEqual(phrase, id)
            XCTAssertFalse(phrase.contains("{month}"), id)
        }
        XCTAssertEqual(PromptCatalog.phrase(id: "set-up-my-longbook", month: nil, in: []),
                       "Read my 12-month bank statement and help me set up my longbook")
        XCTAssertEqual(PromptCatalog.phrases(id: "add-my-statement", in: []),
                       ["Add my statement in my longbook", "Update my longbook from my statements", "Add my statement"])
        XCTAssertEqual(PromptCatalog.phrase(id: "add-a-month-report-in-my-longbook", month: "October", in: []),
                       "Add October month report in my longbook")
        XCTAssertEqual(PromptCatalog.phrase(id: "set-up-a-daily-longbook-email-round", month: nil, in: []),
                       "Go to longbook.app/mcp and set up a daily email round for my longbook, as longbook recommends")
        XCTAssertEqual(PromptCatalog.phrase(id: "no-such-prompt", month: nil, in: []), "no-such-prompt")
        XCTAssertEqual(PromptCatalog.phrases(id: "no-such-prompt", in: []), [])
    }

    /// The fallbacks are copies of the catalogue's words; this fails the day they drift apart.
    func testTheFallbacksMatchTheCatalogue() throws {
        for (id, known) in PromptCatalog.fallbacks {
            let prompt = try XCTUnwrap(PromptCatalog.prompt(id: id), "\(id) is missing from the catalogue")
            XCTAssertEqual(prompt.title, known.title, id)
            XCTAssertEqual(PromptCatalog.title(id: id), known.title, id)
            XCTAssertEqual(Array(prompt.phrases.prefix(known.phrases.count)), known.phrases, id)
            XCTAssertEqual(prompt.template, known.template, id)
        }
    }

    /// The statement prompt the own-AI help copies outside setup is the one that names longbook.
    func testTheStatementPromptsSecondPhraseNamesLongbook() {
        XCTAssertEqual(PromptCatalog.phrases(id: "add-my-statement").dropFirst().first,
                       "Update my longbook from my statements")
    }

    func testTheMonthNameIsEnglishWhateverTheLocale() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let day = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 5)))
        XCTAssertEqual(PromptCatalog.monthName(of: day, calendar: calendar), "October")
    }
}
