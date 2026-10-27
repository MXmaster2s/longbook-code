// The first run's rules: how a tap is named, which tag it wears, where the stage word
// round-trips, and what the dashboard waits for.
import XCTest
@testable import LongbookCore

final class OnboardingTests: XCTestCase {
    private var people: OnboardingCard { OnboardingCards.commitments[0] }
    private var cards: OnboardingCard { OnboardingCards.accounts[1] }
    private var wallets: OnboardingCard { OnboardingCards.accounts[2] }

    func testAPersonOnTheFirstCardBecomesASalaryOrAFeeAndAMember() {
        XCTAssertEqual(OnboardingCards.commitmentName("Maid", on: people), "Maid salary")
        XCTAssertEqual(OnboardingCards.commitmentName("Accountant", on: people), "Accountant fees")
        XCTAssertEqual(OnboardingCards.memberRole("Maid", on: people), "Maid")
        XCTAssertNil(OnboardingCards.memberRole("Home rent", on: OnboardingCards.commitments[1]))
        XCTAssertEqual(OnboardingCards.commitmentName("Home rent", on: OnboardingCards.commitments[1]), "Home rent")
    }

    func testAPlaceholderCarriesTheCardsQuestionAndTag() {
        let placeholder = OnboardingCards.placeholder("Netflix", on: OnboardingCards.commitments[4])
        XCTAssertEqual(placeholder.name, "Netflix")
        XCTAssertEqual(placeholder.group, "Personal subscriptions?")
        XCTAssertEqual(placeholder.tag, "subscription")
    }

    func testAnAccountChipWearsTheCardsTagUnlessItSaysOtherwise() {
        XCTAssertEqual(OnboardingCards.accountTag("Savings account", on: OnboardingCards.accounts[0]), "bank account")
        XCTAssertEqual(OnboardingCards.accountTag("Credit card", on: cards), "credit card")
        XCTAssertEqual(OnboardingCards.accountTag("Debit card", on: cards), "debit card")
        XCTAssertEqual(OnboardingCards.accountTag("UPI", on: wallets), "upi")
        XCTAssertEqual(OnboardingCards.accountTag("PayPal", on: wallets), "wallet")
        XCTAssertEqual(OnboardingCards.accountTag("Cash", on: OnboardingCards.accounts[3]), "cash")
    }

    func testEveryChipIsUniqueWithinItsStep() {
        for step in [OnboardingCards.commitments, OnboardingCards.accounts] {
            let chips = step.flatMap(\.chips).map { $0.lowercased() }
            XCTAssertEqual(chips.count, Set(chips).count)
        }
    }

    func testTheStageWordRoundTripsAndRefusesWhatIsNotACard() {
        let stages: [OnboardingStage] = [.commitments(card: 0), .commitments(card: 6), .commitmentsDone, .accounts(card: 3),
                                         .accountsDone(empty: false), .accountsDone(empty: true), .finish, .done]
        for stage in stages {
            XCTAssertEqual(OnboardingStage(raw: stage.raw), stage, stage.raw)
        }
        XCTAssertEqual(OnboardingStage.commitments(card: 0).raw, "s1c1")
        XCTAssertNil(OnboardingStage(raw: "s1c8"))
        XCTAssertNil(OnboardingStage(raw: "s2c5"))
        XCTAssertNil(OnboardingStage(raw: "later"))
        XCTAssertEqual(OnboardingStage.accounts(card: 1).step, 2)
        XCTAssertEqual(OnboardingStage.finish.step, 3)
    }

    func testTheDashboardWaitsForTheMinimums() {
        XCTAssertTrue(OnboardingCards.dashboardAllowed(commitments: 3, charges: 10, accounts: 1, members: 1))
        XCTAssertFalse(OnboardingCards.dashboardAllowed(commitments: 2, charges: 10, accounts: 1, members: 1))
        XCTAssertFalse(OnboardingCards.dashboardAllowed(commitments: 3, charges: 9, accounts: 1, members: 1))
        XCTAssertFalse(OnboardingCards.dashboardAllowed(commitments: 3, charges: 10, accounts: 0, members: 1))
        XCTAssertFalse(OnboardingCards.dashboardAllowed(commitments: 3, charges: 10, accounts: 1, members: 0))
    }

    func testTheSidecarKeepsTheStageAndTheDeviceAndClearsThemWithNil() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("onboarding-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try WorkspaceStore.update(in: folder) { $0.onboardingStage = "s1c3"; $0.onboardingDevice = "iPhone" }
        var read = WorkspaceStore.read(in: folder)
        XCTAssertEqual(read.onboardingStage, "s1c3")
        XCTAssertEqual(read.onboardingDevice, "iPhone")
        try WorkspaceStore.update(in: folder) { $0.onboardingStage = nil }
        read = WorkspaceStore.read(in: folder)
        XCTAssertNil(read.onboardingStage)
        XCTAssertEqual(read.onboardingDevice, "iPhone")
    }

    func testTheAccountNameExampleFollowsTheRegion() {
        XCTAssertEqual(Regional.accountNameExample(for: "IN"), "HDFC savings")
        XCTAssertEqual(Regional.accountNameExample(for: "US"), "Chase checking")
        XCTAssertEqual(Regional.accountNameExample(for: "DE"), "Current account")
        XCTAssertEqual(Regional.accountNameExample(for: "BR"), "Everyday savings")
        XCTAssertEqual(Regional.accountNameExample(for: nil), "Everyday savings")
    }

    func testTheUpiTagIsOfferedOnlyInIndiaAndStaysInTheLibrary() {
        XCTAssertTrue(Regional.offersLibraryTag(kind: "account", name: "upi", region: "IN"))
        XCTAssertFalse(Regional.offersLibraryTag(kind: "account", name: "upi", region: "US"))
        XCTAssertFalse(Regional.offersLibraryTag(kind: "account", name: "UPI", region: nil))
        XCTAssertTrue(Regional.offersLibraryTag(kind: "account", name: "wallet", region: "US"))
        XCTAssertNotNil(TagLibrary.entry(kind: "account", name: "upi"))
    }
}
